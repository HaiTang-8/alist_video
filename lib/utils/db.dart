import 'dart:typed_data';

import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/admin_dashboard_metrics.dart';
import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/services/persistence/persistence_driver.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  PersistenceDriver? _driver;
  DatabaseConnectionConfig? _config;

  /// 数据库统一日志出口，便于跨端追踪 SQL 操作
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'DatabaseHelper',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  double _parseDouble(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  Duration _secondsToDuration(dynamic value) {
    final seconds = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return Duration(seconds: seconds);
  }

  // 单例模式
  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  DatabaseHelper._();

  DatabaseConnectionConfig? get currentConfig => _config;
  DatabasePersistenceType? get currentDriverType => _config?.type;

  /// 检查是否启用SQL日志
  Future<bool> _isSqlLoggingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppConstants.enableSqlLoggingKey) ??
          AppConstants.defaultEnableSqlLogging;
    } catch (e) {
      return AppConstants.defaultEnableSqlLogging;
    }
  }

  /// 兼容旧代码的初始化方法，默认使用远程PostgreSQL
  Future<void> init({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
  }) async {
    await initWithConfig(
      DatabaseConnectionConfig(
        type: DatabasePersistenceType.remotePostgres,
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
    );
  }

  /// 根据运行时配置初始化具体持久化驱动
  Future<void> initWithConfig(DatabaseConnectionConfig config) async {
    _config = config;
    await _driver?.close();
    _driver = PersistenceDriverFactory.create(config.type);
    await _driver!.init(config);
    _log(
      'Initialized persistence driver: ${config.type.displayName}',
      level: LogLevel.info,
    );
  }

  /// 确保底层驱动已就绪，若因异常被关闭则自动重建
  Future<PersistenceDriver> _ensureDriver() async {
    if (_driver != null) {
      return _driver!;
    }

    if (_config == null) {
      throw Exception('数据库尚未初始化，请先调用 initWithConfig');
    }

    await initWithConfig(_config!);
    return _driver!;
  }

  // 执行查询并返回结果
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    try {
      final driver = await _ensureDriver();

      // 根据设置决定是否打印SQL日志
      final enableLogging = await _isSqlLoggingEnabled();
      if (enableLogging) {
        _log(
          'Executing SQL: $sql\nParameters: $parameters',
          level: LogLevel.debug,
        );
      }

      final results =
          await driver.query(sql, parameters: parameters ?? const {});
      return results;
    } catch (e, stack) {
      // 错误信息始终记录，不受设置控制
      _log(
        'Query execution failed: $sql\nParameters: $parameters',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 执行插入操作
  Future<int> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    final driver = await _ensureDriver();
    return driver.insert(table, values);
  }

  // 执行更新操作
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final driver = await _ensureDriver();
    return driver.update(table, values, where, whereArgs);
  }

  // 执行删除操作
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final driver = await _ensureDriver();
    return driver.delete(table, where, whereArgs);
  }

  // 关闭数据库连接
  Future<void> close() async {
    await _driver?.close();
    _driver = null;
  }

  // 查询历史记录
  Future<void> queryHistoricalRecords() async {
    try {
      final results = await query('''
        SELECT * FROM t_historical_records 
        ORDER BY change_time DESC
      ''');

      // 记录调试信息
      final buffer = StringBuffer()..writeln('=== Historical Records ===');
      for (var record in results) {
        buffer
          ..writeln('ID: ${record['id']}')
          ..writeln('Path: ${record['path']}')
          ..writeln('Name: ${record['name']}')
          ..writeln('Created At: ${record['created_at']}')
          ..writeln('------------------------');
      }
      buffer.writeln('Total records: ${results.length}');
      _log(buffer.toString(), level: LogLevel.debug);
    } catch (e, stack) {
      _log(
        'Failed to query historical records',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 插入或更新历史记录
  Future<void> upsertHistoricalRecord({
    required String videoSha1,
    required String videoPath,
    required int videoSeek,
    required int userId,
    required String videoName,
    required int totalVideoDuration,
  }) async {
    try {
      const sql = '''
        INSERT INTO t_historical_records 
        (video_sha1, video_path, video_seek, user_id, change_time, video_name, total_video_duration)
        VALUES (@sha1, @path, @seek, @userId, CURRENT_TIMESTAMP, @name, @totalDuration)
        ON CONFLICT (video_sha1, user_id) 
        DO UPDATE SET 
          video_seek = @seek,
          change_time = CURRENT_TIMESTAMP,
          total_video_duration = @totalDuration
      ''';

      await query(sql, {
        'sha1': videoSha1,
        'path': videoPath,
        'seek': videoSeek,
        'userId': userId,
        'name': videoName,
        'totalDuration': totalVideoDuration,
      });

      _log('Historical record upserted successfully', level: LogLevel.debug);
    } catch (e, stack) {
      _log(
        'Failed to upsert historical record',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 查询单个历史记录
  Future<Map<String, dynamic>?> getHistoricalRecord(String videoSha1) async {
    try {
      final results = await query(
        'SELECT * FROM t_historical_records WHERE video_sha1 = @sha1',
        {'sha1': videoSha1},
      );

      return results.isNotEmpty ? results.first : null;
    } catch (e, stack) {
      _log(
        'Failed to get historical record',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 查询用户的所有历史记录
  Future<List<Map<String, dynamic>>> getUserHistoricalRecords(
    int userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final results = await query('''
        SELECT * FROM t_historical_records 
        WHERE user_id = @userId
        ORDER BY change_time DESC
        LIMIT @limit OFFSET @offset
      ''', {
        'userId': userId,
        'limit': limit,
        'offset': offset,
      });

      return results;
    } catch (e, stack) {
      _log(
        'Failed to get user historical records',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 删除单个历史记录
  Future<void> deleteHistoricalRecord(String videoSha1) async {
    try {
      await query(
        'DELETE FROM t_historical_records WHERE video_sha1 = @sha1',
        {'sha1': videoSha1},
      );

      _log('Historical record deleted successfully', level: LogLevel.debug);
    } catch (e, stack) {
      _log(
        'Failed to delete historical record',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 清空用户的所有历史记录
  Future<void> clearUserHistoricalRecords(int userId) async {
    try {
      await query(
        'DELETE FROM t_historical_records WHERE user_id = @userId',
        {'userId': userId},
      );

      _log(
        'User historical records cleared successfully',
        level: LogLevel.debug,
      );
    } catch (e, stack) {
      _log(
        'Failed to clear user historical records',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 更新视频播放进度
  Future<void> updateVideoSeek({
    required String videoSha1,
    required int videoSeek,
  }) async {
    try {
      await query('''
        UPDATE t_historical_records 
        SET video_seek = @seek, change_time = CURRENT_TIMESTAMP
        WHERE video_sha1 = @sha1
      ''', {
        'sha1': videoSha1,
        'seek': videoSeek,
      });

      _log('Video seek updated successfully', level: LogLevel.debug);
    } catch (e, stack) {
      _log(
        'Failed to update video seek',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 获取最近观看的视频记录
  Future<List<Map<String, dynamic>>> getRecentHistoricalRecords({
    required int userId,
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final results = await query('''
        SELECT
          video_sha1,
          video_path,
          video_seek,
          user_id,
          change_time,
          video_name,
          total_video_duration
        FROM t_historical_records
        WHERE user_id = @userId
        ORDER BY change_time DESC
        LIMIT @limit OFFSET @offset
      ''', {
        'userId': userId,
        'limit': limit,
        'offset': offset,
      });

      return results;
    } catch (e, stack) {
      _log(
        'Failed to get recent historical records',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 获取用户历史记录总数
  Future<int> getUserHistoricalRecordsCount(int userId) async {
    try {
      final results = await query('''
        SELECT COUNT(*) as count
        FROM t_historical_records
        WHERE user_id = @userId
      ''', {
        'userId': userId,
      });

      return results.first['count'] as int;
    } catch (e, stack) {
      _log(
        'Failed to get user historical records count',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 根据路径查询历史记录
  Future<List<HistoricalRecord>> getHistoricalRecordsByPath({
    required String path,
    required int userId,
  }) async {
    try {
      final results = await query('''
        SELECT 
          video_sha1, 
          video_path, 
          video_seek, 
          user_id, 
          change_time, 
          video_name, 
          total_video_duration
        FROM t_historical_records 
        WHERE video_path LIKE @path 
        AND user_id = @userId
        ORDER BY change_time DESC
      ''', {
        'path': '$path%',
        'userId': userId,
      });

      return results.map((record) => HistoricalRecord.fromMap(record)).toList();
    } catch (e, stack) {
      _log(
        'Failed to get historical records by path',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 根据视频名称查询历史记录
  Future<HistoricalRecord?> getHistoricalRecordByName({
    required String name,
    required int userId,
  }) async {
    try {
      final results = await query('''
        SELECT
          video_sha1,
          video_path,
          video_seek,
          user_id,
          change_time,
          video_name,
          total_video_duration
        FROM t_historical_records
        WHERE video_name = @name
        AND user_id = @userId
        ORDER BY change_time DESC
        LIMIT 1
      ''', {
        'name': name,
        'userId': userId,
      });

      return results.isNotEmpty
          ? HistoricalRecord.fromMap(results.first)
          : null;
    } catch (e, stack) {
      _log(
        'Failed to get historical record by name',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 搜索历史记录（按视频名称和路径）
  Future<List<Map<String, dynamic>>> searchHistoricalRecords({
    required int userId,
    required String searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final results = await query('''
        SELECT
          video_sha1,
          video_path,
          video_seek,
          user_id,
          change_time,
          video_name,
          total_video_duration
        FROM t_historical_records
        WHERE user_id = @userId
        AND (
          LOWER(video_name) LIKE LOWER(@searchQuery)
          OR LOWER(video_path) LIKE LOWER(@searchQuery)
        )
        ORDER BY change_time DESC
        LIMIT @limit OFFSET @offset
      ''', {
        'userId': userId,
        'searchQuery': '%$searchQuery%',
        'limit': limit,
        'offset': offset,
      });

      return results;
    } catch (e, stack) {
      _log(
        'Failed to search historical records',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 获取搜索结果总数
  Future<int> getSearchHistoricalRecordsCount({
    required int userId,
    required String searchQuery,
  }) async {
    try {
      final results = await query('''
        SELECT COUNT(*) as count
        FROM t_historical_records
        WHERE user_id = @userId
        AND (
          LOWER(video_name) LIKE LOWER(@searchQuery)
          OR LOWER(video_path) LIKE LOWER(@searchQuery)
        )
      ''', {
        'userId': userId,
        'searchQuery': '%$searchQuery%',
      });

      return results.first['count'] as int;
    } catch (e, stack) {
      _log(
        'Failed to get search historical records count',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 批量更新历史记录的文件路径和名称（用于文件重命名后同步数据库）
  Future<void> batchUpdateHistoricalRecordPaths({
    required List<Map<String, dynamic>> renameMap,
    required String basePath,
    required int userId,
  }) async {
    try {
      _log(
        '开始批量更新历史记录路径，共 ${renameMap.length} 个项目',
        level: LogLevel.info,
      );

      int successCount = 0;
      int failCount = 0;

      for (var rename in renameMap) {
        final oldName = rename['oldName'] as String;
        final newName = rename['newName'] as String;
        final fileType = rename['type'] as int; // 1=文件夹, 2=文件

        try {
          if (fileType == 1) {
            // 文件夹重命名：更新 video_path 中包含该文件夹路径的记录
            final oldFolderPath = '$basePath/$oldName';
            final newFolderPath = '$basePath/$newName';

            await query('''
              UPDATE t_historical_records
              SET video_path = REPLACE(video_path, @oldFolderPath, @newFolderPath)
              WHERE video_path LIKE @oldFolderPathPattern
              AND user_id = @userId
            ''', {
              'oldFolderPath': oldFolderPath,
              'newFolderPath': newFolderPath,
              'oldFolderPathPattern': '$oldFolderPath%',
              'userId': userId,
            });

            _log(
              '更新文件夹历史记录成功: $oldName -> $newName',
              level: LogLevel.debug,
            );
          } else if (fileType == 2) {
            // 文件重命名：更新 video_name
            await query('''
              UPDATE t_historical_records
              SET video_name = @newName
              WHERE video_path = @basePath
              AND video_name = @oldName
              AND user_id = @userId
            ''', {
              'newName': newName,
              'basePath': basePath,
              'oldName': oldName,
              'userId': userId,
            });

            _log(
              '更新文件历史记录成功: $oldName -> $newName',
              level: LogLevel.debug,
            );
          }

          successCount++;
        } catch (e, stack) {
          failCount++;
          _log(
            '更新历史记录失败: $oldName -> $newName',
            level: LogLevel.error,
            error: e,
            stackTrace: stack,
          );
        }
      }

      _log(
        '批量更新历史记录完成: 成功 $successCount 个, 失败 $failCount 个',
        level: LogLevel.info,
      );
    } catch (e, stack) {
      _log(
        '批量更新历史记录异常',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> saveHistoricalRecord(HistoricalRecord record) async {
    try {
      if (record.screenshot != null) {
        _log(
          'Saving screenshot size: ${record.screenshot!.length} bytes',
          level: LogLevel.debug,
        );
      }

      await query('''
        INSERT INTO t_historical_records 
        (video_sha1, video_path, video_seek, user_id, change_time, video_name, total_video_duration, screenshot)
        VALUES 
        (@sha1, @path, @seek, @userId, @changeTime, @name, @duration, @screenshot)
        ON CONFLICT (video_sha1, user_id)
        DO UPDATE SET 
          video_seek = EXCLUDED.video_seek,
          change_time = EXCLUDED.change_time,
          total_video_duration = EXCLUDED.total_video_duration,
          screenshot = EXCLUDED.screenshot
      ''', {
        'sha1': record.videoSha1,
        'path': record.videoPath,
        'seek': record.videoSeek,
        'userId': record.userId,
        'changeTime': record.changeTime,
        'name': record.videoName,
        'duration': record.totalVideoDuration,
        'screenshot': record.screenshot,
      });

      _log('Historical record saved successfully', level: LogLevel.debug);
    } catch (e, stack) {
      _log(
        'Failed to save historical record',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 修改获取截图的方法
  Future<Uint8List?> getHistoricalRecordScreenshot({
    required String videoSha1,
    required int userId,
  }) async {
    try {
      _log(
        'Fetching screenshot for video: $videoSha1, user: $userId',
        level: LogLevel.debug,
      );

      final results = await query('''
        SELECT screenshot  -- 直接获取二进制数据，不使用 encode
        FROM t_historical_records 
        WHERE video_sha1 = @sha1 
        AND user_id = @userId
      ''', {
        'sha1': videoSha1,
        'userId': userId,
      });

      if (results.isEmpty) {
        _log('No screenshot found', level: LogLevel.debug);
        return null;
      }

      final bytes = results.first['screenshot'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) {
        _log('Screenshot data is empty', level: LogLevel.debug);
        return null;
      }

      _log(
        'Retrieved screenshot size: ${bytes.length} bytes',
        level: LogLevel.debug,
      );
      return bytes;
    } catch (e, stack) {
      _log(
        'Failed to get historical record screenshot',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  // 添加收藏目录
  Future<int> addFavoriteDirectory({
    required String path,
    required String name,
    required int userId,
  }) async {
    try {
      _log(
        'Adding favorite directory - path: $path, name: $name, userId: $userId',
        level: LogLevel.debug,
      );

      // 先检查是否已存在
      final existingCheck = await query('''
        SELECT COUNT(*) as count FROM t_favorite_directories 
        WHERE path = @path AND user_id = @userId
      ''', {
        'path': path,
        'userId': userId,
      });

      final alreadyExists = (existingCheck.first['count'] as int) > 0;
      _log(
        'Directory already exists in favorites: $alreadyExists',
        level: LogLevel.debug,
      );

      if (alreadyExists) {
        // 如果已存在，返回现有记录的ID
        final existing = await query('''
          SELECT id FROM t_favorite_directories 
          WHERE path = @path AND user_id = @userId
          LIMIT 1
        ''', {
          'path': path,
          'userId': userId,
        });

        final existingId = existing.first['id'] as int;
        _log(
          'Using existing favorite directory id: $existingId',
          level: LogLevel.debug,
        );
        return existingId;
      }

      final newId = await insert('t_favorite_directories', {
        'path': path,
        'name': name,
        'user_id': userId,
        'created_at': DateTime.now(),
      });
      _log('Added favorite directory with id: $newId', level: LogLevel.debug);
      return newId;
    } catch (e, stack) {
      _log(
        'Failed to add favorite directory',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 获取用户的所有收藏目录
  Future<List<Map<String, dynamic>>> getFavoriteDirectories(int userId) async {
    try {
      _log(
        'Fetching favorite directories for userId: $userId',
        level: LogLevel.debug,
      );

      final results = await query('''
        SELECT * FROM t_favorite_directories 
        WHERE user_id = @userId
        ORDER BY created_at DESC
      ''', {
        'userId': userId,
      });

      _log(
        'Found ${results.length} favorite directories',
        level: LogLevel.debug,
      );
      if (results.isNotEmpty) {
        _log('First record: ${results.first}', level: LogLevel.debug);
      }

      return results;
    } catch (e, stack) {
      _log(
        'Failed to get favorite directories',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 检查目录是否已收藏
  Future<bool> isFavoriteDirectory({
    required String path,
    required int userId,
  }) async {
    try {
      _log(
        'Checking if directory is favorite - path: $path, userId: $userId',
        level: LogLevel.debug,
      );

      final results = await query('''
        SELECT COUNT(*) as count FROM t_favorite_directories 
        WHERE path = @path AND user_id = @userId
      ''', {
        'path': path,
        'userId': userId,
      });

      final count = results.first['count'] as int;
      _log(
        'Directory favorite status: ${count > 0}',
        level: LogLevel.debug,
      );

      return count > 0;
    } catch (e, stack) {
      _log(
        'Failed to check favorite directory',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // 删除收藏目录
  Future<void> removeFavoriteDirectory({
    required String path,
    required int userId,
  }) async {
    try {
      await query('''
        DELETE FROM t_favorite_directories 
        WHERE path = @path AND user_id = @userId
      ''', {
        'path': path,
        'userId': userId,
      });
    } catch (e, stack) {
      _log(
        'Failed to remove favorite directory',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 计算全局观看指标，供管理员运营面板使用。
  Future<AdminWatchSummary> getAdminWatchSummary() async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(
            const Duration(hours: 24),
          );
      final rows = await query('''
        SELECT
          COUNT(*) AS total_sessions,
          COUNT(DISTINCT user_id) AS unique_users,
          COUNT(DISTINCT video_sha1) AS unique_videos,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds,
          COALESCE(AVG(
            CASE
              WHEN total_video_duration > 0 THEN
                CASE
                  WHEN video_seek >= total_video_duration THEN 1.0
                  ELSE (1.0 * video_seek) / total_video_duration
                END
              ELSE NULL
            END
          ), 0) AS avg_completion,
          COALESCE(SUM(
            CASE WHEN change_time >= @cutoff THEN 1 ELSE 0 END
          ), 0) AS sessions_last_24h,
          MAX(change_time) AS last_activity
        FROM t_historical_records
      ''', {
        'cutoff': cutoff,
      });

      final data = rows.isEmpty ? <String, dynamic>{} : rows.first;
      return AdminWatchSummary(
        totalSessions: data['total_sessions'] as int? ?? 0,
        uniqueUsers: data['unique_users'] as int? ?? 0,
        uniqueVideos: data['unique_videos'] as int? ?? 0,
        totalWatchDuration: _secondsToDuration(data['total_watch_seconds']),
        averageCompletion: _parseDouble(data['avg_completion']),
        sessionsLast24h: data['sessions_last_24h'] as int? ?? 0,
        lastActivityAt: _parseDateTime(data['last_activity']),
      );
    } catch (e, stack) {
      _log(
        'Failed to load admin watch summary',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 聚合各用户的播放行为，按照观看时长倒序返回 TOP 列表。
  Future<List<UserActivitySummary>> getTopUserActivities({
    int limit = 6,
  }) async {
    try {
      final rows = await query('''
        SELECT
          user_id,
          COUNT(*) AS session_count,
          COUNT(DISTINCT video_sha1) AS unique_videos,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds,
          COALESCE(AVG(
            CASE
              WHEN total_video_duration > 0 THEN
                CASE
                  WHEN video_seek >= total_video_duration THEN 1.0
                  ELSE (1.0 * video_seek) / total_video_duration
                END
              ELSE NULL
            END
          ), 0) AS avg_completion,
          MAX(change_time) AS last_active_at
        FROM t_historical_records
        GROUP BY user_id
        ORDER BY total_watch_seconds DESC
        LIMIT @limit
      ''', {
        'limit': limit,
      });

      return rows.map((row) {
        final userId = row['user_id'] as int? ?? 0;
        return UserActivitySummary(
          userId: userId,
          displayName: '用户 #$userId',
          sessionCount: row['session_count'] as int? ?? 0,
          uniqueVideos: row['unique_videos'] as int? ?? 0,
          totalWatchDuration: _secondsToDuration(row['total_watch_seconds']),
          averageCompletion: _parseDouble(row['avg_completion']),
          lastActiveAt: _parseDateTime(row['last_active_at']),
        );
      }).toList();
    } catch (e, stack) {
      _log(
        'Failed to load user activities',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 聚合目录热度，帮助管理员识别最常访问的路径。
  Future<List<DirectoryHeatEntry>> getDirectoryHeatEntries({
    int limit = 6,
  }) async {
    try {
      final rows = await query('''
        SELECT
          video_path AS directory_path,
          COUNT(*) AS session_count,
          COUNT(DISTINCT user_id) AS unique_users,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds,
          COALESCE(AVG(
            CASE
              WHEN total_video_duration > 0 THEN
                CASE
                  WHEN video_seek >= total_video_duration THEN 1.0
                  ELSE (1.0 * video_seek) / total_video_duration
                END
              ELSE NULL
            END
          ), 0) AS avg_completion,
          MAX(change_time) AS last_active_at
        FROM t_historical_records
        WHERE COALESCE(video_path, '') <> ''
        GROUP BY video_path
        ORDER BY session_count DESC
        LIMIT @limit
      ''', {
        'limit': limit,
      });

      return rows.map((row) {
        return DirectoryHeatEntry(
          directoryPath: row['directory_path'] as String? ?? '/',
          sessionCount: row['session_count'] as int? ?? 0,
          uniqueUsers: row['unique_users'] as int? ?? 0,
          totalWatchDuration: _secondsToDuration(row['total_watch_seconds']),
          averageCompletion: _parseDouble(row['avg_completion']),
          lastActiveAt: _parseDateTime(row['last_active_at']),
        );
      }).toList();
    } catch (e, stack) {
      _log(
        'Failed to load directory heat map',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 获取最近若干天的活跃曲线，支撑折线/柱状图展示。
  Future<List<DailyActivityPoint>> getDailyActivityPoints({
    int days = 7,
  }) async {
    if (days <= 0) {
      return const [];
    }
    try {
      final since = DateTime.now().toUtc().subtract(
            Duration(days: days - 1),
          );
      final rows = await query('''
        SELECT
          DATE(change_time) AS activity_day,
          COUNT(*) AS session_count,
          COUNT(DISTINCT user_id) AS unique_users,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds
        FROM t_historical_records
        WHERE change_time >= @since
        GROUP BY activity_day
        ORDER BY activity_day ASC
      ''', {
        'since': since,
      });

      return rows.map((row) {
        final day = _parseDateTime(row['activity_day']) ?? DateTime.now();
        return DailyActivityPoint(
          day: day,
          sessionCount: row['session_count'] as int? ?? 0,
          uniqueUsers: row['unique_users'] as int? ?? 0,
          watchDuration: _secondsToDuration(row['total_watch_seconds']),
        );
      }).toList();
    } catch (e, stack) {
      _log(
        'Failed to load daily activity points',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 收藏操作概览，体现全局运营中“操作信息”的占比。
  Future<FavoriteStatSummary> getFavoriteStatSummary({
    int limit = 5,
  }) async {
    try {
      final overviewRows = await query('''
        SELECT
          COUNT(*) AS total_favorites,
          COUNT(DISTINCT user_id) AS unique_users,
          MAX(created_at) AS last_favorited_at
        FROM t_favorite_directories
      ''');
      final overview =
          overviewRows.isEmpty ? <String, dynamic>{} : overviewRows.first;

      final detailRows = await query('''
        SELECT
          path,
          COUNT(*) AS bookmark_count,
          COUNT(DISTINCT user_id) AS unique_users,
          MAX(created_at) AS last_favorited_at
        FROM t_favorite_directories
        GROUP BY path
        ORDER BY bookmark_count DESC
        LIMIT @limit
      ''', {
        'limit': limit,
      });

      final topDirs = detailRows
          .map(
            (row) => FavoriteDirectoryStat(
              path: row['path'] as String? ?? '/',
              bookmarkCount: row['bookmark_count'] as int? ?? 0,
              uniqueUsers: row['unique_users'] as int? ?? 0,
              lastFavoritedAt: _parseDateTime(row['last_favorited_at']),
            ),
          )
          .toList();

      return FavoriteStatSummary(
        totalFavorites: overview['total_favorites'] as int? ?? 0,
        uniqueUsers: overview['unique_users'] as int? ?? 0,
        lastFavoritedAt: _parseDateTime(overview['last_favorited_at']),
        topDirectories: topDirs,
      );
    } catch (e, stack) {
      _log(
        'Failed to load favorite stats',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// 汇总指定用户的观看与操作明细，供管理员钻取。 
  Future<UserDetailDashboardData> getUserDetailDashboard({
    required int userId,
    int recentLimit = 30,
    int directoryLimit = 6,
    int favoriteLimit = 6,
  }) async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(
        const Duration(hours: 24),
      );
      final summaryRows = await query('''
        SELECT
          COUNT(*) AS session_count,
          COUNT(DISTINCT video_sha1) AS unique_videos,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds,
          COALESCE(AVG(
            CASE
              WHEN total_video_duration > 0 THEN
                CASE
                  WHEN video_seek >= total_video_duration THEN 1.0
                  ELSE (1.0 * video_seek) / total_video_duration
                END
              ELSE NULL
            END
          ), 0) AS avg_completion,
          COALESCE(SUM(
            CASE WHEN change_time >= @cutoff THEN 1 ELSE 0 END
          ), 0) AS sessions_last_24h,
          MIN(change_time) AS first_watch_at,
          MAX(change_time) AS last_watch_at
        FROM t_historical_records
        WHERE user_id = @userId
      ''', {
        'userId': userId,
        'cutoff': cutoff,
      });

      final favoriteCountRows = await query('''
        SELECT COUNT(*) AS favorite_count
        FROM t_favorite_directories
        WHERE user_id = @userId
      ''', {'userId': userId});

      final summaryData = summaryRows.isEmpty ? <String, dynamic>{} : summaryRows.first;
      final overview = UserDetailOverview(
        userId: userId,
        displayName: '用户 #$userId',
        sessionCount: summaryData['session_count'] as int? ?? 0,
        uniqueVideos: summaryData['unique_videos'] as int? ?? 0,
        totalWatchDuration: _secondsToDuration(summaryData['total_watch_seconds']),
        averageCompletion: _parseDouble(summaryData['avg_completion']),
        sessionsLast24h: summaryData['sessions_last_24h'] as int? ?? 0,
        firstWatchAt: _parseDateTime(summaryData['first_watch_at']),
        lastWatchAt: _parseDateTime(summaryData['last_watch_at']),
        favoriteCount: favoriteCountRows.isEmpty
            ? 0
            : favoriteCountRows.first['favorite_count'] as int? ?? 0,
      );

      final directoryRows = await query('''
        SELECT
          video_path AS directory_path,
          COUNT(*) AS session_count,
          COALESCE(SUM(video_seek), 0) AS total_watch_seconds,
          MAX(change_time) AS last_active_at
        FROM t_historical_records
        WHERE user_id = @userId
          AND COALESCE(video_path, '') <> ''
        GROUP BY video_path
        ORDER BY session_count DESC
        LIMIT @limit
      ''', {
        'userId': userId,
        'limit': directoryLimit,
      });

      final directories = directoryRows
          .map(
            (row) => UserDirectoryStat(
              directoryPath: row['directory_path'] as String? ?? '/',
              sessionCount: row['session_count'] as int? ?? 0,
              totalWatchDuration:
                  _secondsToDuration(row['total_watch_seconds']),
              lastActiveAt: _parseDateTime(row['last_active_at']),
            ),
          )
          .toList();

      final favoriteRows = await query('''
        SELECT path, created_at
        FROM t_favorite_directories
        WHERE user_id = @userId
        ORDER BY created_at DESC
        LIMIT @limit
      ''', {
        'userId': userId,
        'limit': favoriteLimit,
      });

      final favorites = favoriteRows
          .map(
            (row) => UserFavoriteEntry(
              path: row['path'] as String? ?? '/',
              createdAt: _parseDateTime(row['created_at']),
            ),
          )
          .toList();

      final recordRows = await query('''
        SELECT
          video_sha1,
          video_path,
          video_seek,
          user_id,
          change_time,
          video_name,
          total_video_duration,
          screenshot
        FROM t_historical_records
        WHERE user_id = @userId
        ORDER BY change_time DESC
        LIMIT @limit
      ''', {
        'userId': userId,
        'limit': recentLimit,
      });

      final records =
          recordRows.map((row) => HistoricalRecord.fromMap(row)).toList();

      return UserDetailDashboardData(
        overview: overview,
        topDirectories: directories,
        favoriteDirectories: favorites,
        recentRecords: records,
      );
    } catch (e, stack) {
      _log(
        'Failed to load user detail dashboard for $userId',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
