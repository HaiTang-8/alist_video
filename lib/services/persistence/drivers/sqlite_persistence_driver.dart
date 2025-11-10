import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/services/persistence/persistence_driver.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:universal_io/io.dart' as io;

/// 本地 SQLite 实现，使用 sqflite + FFI 保证移动端与桌面端一致
class SqlitePersistenceDriver implements PersistenceDriver {
  Database? _database;
  DatabaseFactory? _databaseFactory;
  late DatabaseConnectionConfig _config;

  @override
  DatabasePersistenceType get type => DatabasePersistenceType.localSqlite;

  @override
  Future<void> init(DatabaseConnectionConfig config) async {
    _databaseFactory = _resolveFactory();
    final resolvedPath = await _resolveDbPath(config.sqlitePath);
    _config = config.copyWith(sqlitePath: resolvedPath);
    _database = await _databaseFactory!.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async => _ensureSchema(db),
        onOpen: (db) async => _ensureSchema(db),
      ),
    );
  }

  DatabaseFactory _resolveFactory() {
    if (kIsWeb) {
      return databaseFactoryFfiWeb;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        sqfliteFfiInit();
        return databaseFactoryFfi;
      default:
        return sqflite.databaseFactory;
    }
  }

  Future<String> _resolveDbPath(String? customPath) async {
    if (_databaseFactory == null) {
      throw StateError('DatabaseFactory 未初始化');
    }

    if (customPath != null && customPath.trim().isNotEmpty) {
      return customPath;
    }

    final basePath = await _databaseFactory!.getDatabasesPath();
    if (!kIsWeb) {
      final dir = io.Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    return p.join(basePath, AppConstants.defaultSqliteFilename);
  }

  Future<void> _ensureSchema(DatabaseExecutor executor) async {
    // 历史记录表
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS t_historical_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_sha1 TEXT NOT NULL,
        video_path TEXT NOT NULL,
        video_seek INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        change_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        video_name TEXT NOT NULL,
        total_video_duration INTEGER NOT NULL,
        screenshot BLOB,
        UNIQUE(video_sha1, user_id)
      )
    ''');

    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_hist_video_user
      ON t_historical_records(video_sha1, user_id)
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS t_favorite_directories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(path, user_id)
      )
    ''');
  }

  Future<Database> _ensureDatabase() async {
    if (_database != null) {
      return _database!;
    }
    await init(_config);
    return _database!;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final db = await _ensureDatabase();
    final statement = _prepareStatement(sql, parameters);
    final rows = await db.rawQuery(statement.sql, statement.args);
    return rows;
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await _ensureDatabase();
    return db.insert(table, _normalizeMap(values));
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final db = await _ensureDatabase();
    final statement = _prepareStatement(where, whereArgs);
    return db.update(
      table,
      _normalizeMap(values),
      where: statement.sql,
      whereArgs: statement.args,
    );
  }

  @override
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final db = await _ensureDatabase();
    final statement = _prepareStatement(where, whereArgs);
    return db.delete(
      table,
      where: statement.sql,
      whereArgs: statement.args,
    );
  }

  _SqliteStatement _prepareStatement(
    String sql,
    Map<String, dynamic>? parameters,
  ) {
    if (parameters == null || parameters.isEmpty) {
      return _SqliteStatement(sql, const []);
    }

    final args = <Object?>[];
    final converted = sql.replaceAllMapped(
      RegExp(r'@([a-zA-Z0-9_]+)'),
      (match) {
        final key = match.group(1)!;
        if (!parameters.containsKey(key)) {
          throw ArgumentError('缺少SQL参数: $key');
        }
        args.add(_normalizeValue(parameters[key]));
        return '?';
      },
    );

    return _SqliteStatement(converted, args);
  }

  Map<String, dynamic> _normalizeMap(Map<String, dynamic> values) {
    return values.map((key, value) => MapEntry(key, _normalizeValue(value)));
  }

  Object? _normalizeValue(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value;
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

class _SqliteStatement {
  final String sql;
  final List<Object?> args;
  const _SqliteStatement(this.sql, this.args);
}
