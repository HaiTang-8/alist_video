import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/services/persistence/persistence_driver.dart';
import 'package:postgres/postgres.dart';

/// 远程 PostgreSQL 实现，复用之前的直连能力并补充自动重连
class PostgresPersistenceDriver implements PersistenceDriver {
  Connection? _connection;
  late DatabaseConnectionConfig _config;

  @override
  DatabasePersistenceType get type => DatabasePersistenceType.remotePostgres;

  @override
  Future<void> init(DatabaseConnectionConfig config) async {
    _config = config;
    await _openConnection();
  }

  Future<void> _openConnection() async {
    final host = _config.host ?? AppConstants.defaultDbHost;
    final port = _config.port ?? AppConstants.defaultDbPort;
    final database = _config.database ?? AppConstants.defaultDbName;
    final username = _config.username ?? AppConstants.defaultDbUser;
    final password = _config.password ?? AppConstants.defaultDbPassword;

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
        connectTimeout: AppConstants.dbConnectTimeout,
        queryTimeout: AppConstants.dbQueryTimeout,
      ),
    );
  }

  Future<void> _ensureConnection() async {
    if (_connection == null) {
      await _openConnection();
      return;
    }

    try {
      await _connection!.execute('SELECT 1');
    } catch (_) {
      await close();
      await _openConnection();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureConnection();
    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters,
      timeout: AppConstants.dbQueryTimeout,
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final columns = values.keys.join(', ');
    final placeholders =
        values.keys.map((key) => '@$key').toList(growable: false).join(', ');
    final sql =
        'INSERT INTO $table ($columns) VALUES ($placeholders) RETURNING id';
    final rows = await query(sql, parameters: values);
    return (rows.first['id'] as int?) ?? 0;
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final sets = values.keys
        .map((key) => '$key = @$key')
        .toList(growable: false)
        .join(', ');
    final sql = 'UPDATE $table SET $sets WHERE $where';
    await query(sql, parameters: {...values, ...whereArgs});
    return 1;
  }

  @override
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final sql = 'DELETE FROM $table WHERE $where';
    await query(sql, parameters: whereArgs);
    return 1;
  }

  @override
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
