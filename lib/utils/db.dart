import 'dart:typed_data';

import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Connection? _connection;

  // 添加配置字段
  late String _host;
  late int _port;
  late String _database;
  late String _username;
  late String _password;

  // 单例模式
  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  DatabaseHelper._();

  /// 检查是否启用SQL日志
  Future<bool> _isSqlLoggingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppConstants.enableSqlLoggingKey) ?? AppConstants.defaultEnableSqlLogging;
    } catch (e) {
      return AppConstants.defaultEnableSqlLogging;
    }
  }

  // 初始化数据库连接
  Future<void> init({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
  }) async {
    // 保存配置以供重连使用
    _host = host;
    _port = port;
    _database = database;
    _username = username;
    _password = password;

    try {
      if (_connection != null) {
        await _connection!.close();
      }

      _connection = await Connection.open(
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
        settings: const ConnectionSettings(
          sslMode: SslMode.disable,
          // 添加连接超时
          connectTimeout: Duration(seconds: 30),
          // 添加查询超时
          queryTimeout: Duration(seconds: 30),
        ),
      );
      print('Database connected successfully to $host:$port/$database');
    } catch (e) {
      print('Database connection failed: $e');
      _connection = null;
      rethrow;
    }
  }

  // 检查并确保数据库连接
  Future<void> _ensureConnection() async {
    if (_connection == null) {
      throw Exception('Database not initialized. Please call init() first.');
    }

    try {
      // 测试连接是否有效
      await _connection!.execute('SELECT 1');
    } catch (e) {
      print('Connection test failed: $e');
      _connection = null;
      // 使用保存的配置重新连接
      await init(
        host: _host, // 需要添加这个字段
        port: _port,
        database: _database,
        username: _username,
        password: _password,
      );
    }
  }

  // 执行查询并返回结果
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    try {
      await _ensureConnection();

      // 根据设置决定是否打印SQL日志
      final enableLogging = await _isSqlLoggingEnabled();
      if (enableLogging) {
        print('Executing SQL: $sql');
        print('Parameters: $parameters');
      }

      final results = await _connection!.execute(
        Sql.named(sql),
        parameters: parameters,
        timeout: const Duration(seconds: 30),
      );

      return results.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      // 错误信息始终打印，不受设置控制
      print('Query execution failed: $e');
      print('SQL: $sql');
      print('Parameters: $parameters');
      rethrow;
    }
  }

  // 执行插入操作
  Future<int> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    final columns = values.keys.join(', ');
    final placeholders = values.keys.map((key) => '@$key').join(', ');

    final sql =
        'INSERT INTO $table ($columns) VALUES ($placeholders) RETURNING id';

    final result = await query(sql, values);
    return result.first['id'] as int;
  }

  // 执行更新操作
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final setColumns = values.keys.map((key) => '$key = @$key').join(', ');
    final sql = 'UPDATE $table SET $setColumns WHERE $where';

    final parameters = {...values, ...whereArgs};
    await query(sql, parameters);
    return 1; // 返回影响的行数
  }

  // 执行删除操作
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final sql = 'DELETE FROM $table WHERE $where';
    await query(sql, whereArgs);
    return 1; // 返回影响的行数
  }

  // 关闭数据库连接
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }

  // 查询历史记录
  Future<void> queryHistoricalRecords() async {
    try {
      final results = await query('''
        SELECT * FROM t_historical_records 
        ORDER BY change_time DESC
      ''');

      // 打印结果到控制台
      print('=== Historical Records ===');
      for (var record in results) {
        print('ID: ${record['id']}');
        print('Path: ${record['path']}');
        print('Name: ${record['name']}');
        print('Created At: ${record['created_at']}');
        print('------------------------');
      }
      print('Total records: ${results.length}');
    } catch (e) {
      print('Failed to query historical records: $e');
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
        ON CONFLICT (video_sha1) 
        DO UPDATE SET 
          video_seek = @seek,
          change_time = CURRENT_TIMESTAMP
      ''';

      await query(sql, {
        'sha1': videoSha1,
        'path': videoPath,
        'seek': videoSeek,
        'userId': userId,
        'name': videoName,
        'totalDuration': totalVideoDuration,
      });

      print('Historical record upserted successfully');
    } catch (e) {
      print('Failed to upsert historical record: $e');
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
    } catch (e) {
      print('Failed to get historical record: $e');
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
    } catch (e) {
      print('Failed to get user historical records: $e');
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

      print('Historical record deleted successfully');
    } catch (e) {
      print('Failed to delete historical record: $e');
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

      print('User historical records cleared successfully');
    } catch (e) {
      print('Failed to clear user historical records: $e');
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

      print('Video seek updated successfully');
    } catch (e) {
      print('Failed to update video seek: $e');
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
    } catch (e) {
      print('Failed to get recent historical records: $e');
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
    } catch (e) {
      print('Failed to get user historical records count: $e');
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
    } catch (e) {
      print('Failed to get historical records by path: $e');
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
    } catch (e) {
      print('Failed to get historical record by name: $e');
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
    } catch (e) {
      print('Failed to search historical records: $e');
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
    } catch (e) {
      print('Failed to get search historical records count: $e');
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
      print('开始批量更新历史记录路径，共 ${renameMap.length} 个项目');

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

            print('更新文件夹历史记录成功: $oldName -> $newName');
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

            print('更新文件历史记录成功: $oldName -> $newName');
          }

          successCount++;
        } catch (e) {
          failCount++;
          print('更新历史记录失败: $oldName -> $newName, 错误: $e');
        }
      }

      print('批量更新历史记录完成: 成功 $successCount 个, 失败 $failCount 个');
    } catch (e) {
      print('批量更新历史记录异常: $e');
      rethrow;
    }
  }

  Future<void> saveHistoricalRecord(HistoricalRecord record) async {
    try {
      if (record.screenshot != null) {
        print('Saving screenshot size: ${record.screenshot!.length} bytes');
      }

      await query('''
        INSERT INTO t_historical_records 
        (video_sha1, video_path, video_seek, user_id, change_time, video_name, total_video_duration, screenshot)
        VALUES 
        (@sha1, @path, @seek, @userId, @changeTime, @name, @duration, @screenshot)
        ON CONFLICT ON CONSTRAINT unique_video_user
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

      print('Historical record saved successfully');
    } catch (e) {
      print('Failed to save historical record: $e');
      rethrow;
    }
  }

  // 修改获取截图的方法
  Future<Uint8List?> getHistoricalRecordScreenshot({
    required String videoSha1,
    required int userId,
  }) async {
    try {
      print('Fetching screenshot for video: $videoSha1, user: $userId');

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
        print('No screenshot found');
        return null;
      }

      final bytes = results.first['screenshot'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) {
        print('Screenshot data is empty');
        return null;
      }

      print('Retrieved screenshot size: ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      print('Failed to get historical record screenshot: $e');
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
      print('Adding favorite directory - path: $path, name: $name, userId: $userId');
      
      // 先检查是否已存在
      final existingCheck = await query('''
        SELECT COUNT(*) as count FROM t_favorite_directories 
        WHERE path = @path AND user_id = @userId
      ''', {
        'path': path,
        'userId': userId,
      });
      
      final alreadyExists = (existingCheck.first['count'] as int) > 0;
      print('Directory already exists in favorites: $alreadyExists');
      
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
        print('Using existing favorite directory id: $existingId');
        return existingId;
      }
      
      const sql = '''
        INSERT INTO t_favorite_directories 
        (path, name, user_id, created_at)
        VALUES (@path, @name, @userId, CURRENT_TIMESTAMP)
        RETURNING id
      ''';

      final result = await query(sql, {
        'path': path,
        'name': name,
        'userId': userId,
      });

      final newId = result.first['id'] as int;
      print('Added favorite directory with id: $newId');
      return newId;
    } catch (e) {
      print('Failed to add favorite directory: $e');
      rethrow;
    }
  }

  // 获取用户的所有收藏目录
  Future<List<Map<String, dynamic>>> getFavoriteDirectories(int userId) async {
    try {
      print('Fetching favorite directories for userId: $userId');
      
      final results = await query('''
        SELECT * FROM t_favorite_directories 
        WHERE user_id = @userId
        ORDER BY created_at DESC
      ''', {
        'userId': userId,
      });

      print('Found ${results.length} favorite directories');
      if (results.isNotEmpty) {
        // 打印第一条记录的详细信息
        print('First record: ${results.first}');
      }

      return results;
    } catch (e) {
      print('Failed to get favorite directories: $e');
      rethrow;
    }
  }

  // 检查目录是否已收藏
  Future<bool> isFavoriteDirectory({
    required String path,
    required int userId,
  }) async {
    try {
      print('Checking if directory is favorite - path: $path, userId: $userId');
      
      final results = await query('''
        SELECT COUNT(*) as count FROM t_favorite_directories 
        WHERE path = @path AND user_id = @userId
      ''', {
        'path': path,
        'userId': userId,
      });

      final count = results.first['count'] as int;
      print('Directory favorite status: ${count > 0}');
      
      return count > 0;
    } catch (e) {
      print('Failed to check favorite directory: $e');
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
    } catch (e) {
      print('Failed to remove favorite directory: $e');
      rethrow;
    }
  }
}
