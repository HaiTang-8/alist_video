import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/services/persistence/persistence_driver.dart';
import 'package:dio/dio.dart';

/// 通过本地Go程序暴露的HTTP接口读写数据，Flutter端只处理SQL转发
class GoBridgePersistenceDriver implements PersistenceDriver {
  late Dio _client;

  @override
  DatabasePersistenceType get type => DatabasePersistenceType.localGoBridge;

  @override
  Future<void> init(DatabaseConnectionConfig config) async {
    final baseUrl =
        (config.goBridgeEndpoint ?? AppConstants.defaultGoBridgeEndpoint)
            .trim();
    _client = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: AppConstants.apiConnectTimeout,
        receiveTimeout: AppConstants.apiReceiveTimeout,
        headers: {
          if ((config.goBridgeAuthToken ?? '').isNotEmpty)
            'Authorization': 'Bearer ${config.goBridgeAuthToken}',
        },
      ),
    );
    await _healthCheck();
  }

  Future<void> _healthCheck() async {
    try {
      await _client.get('/health');
    } on DioException catch (e) {
      // 大部分 Go 桥接服务都会实现 /health，用于提前发现异常
      throw Exception('Go 服务不可用: ${e.message}');
    }
  }

  Map<String, dynamic> _payload(
    String sql,
    Map<String, dynamic>? parameters,
  ) {
    return {
      'sql': sql,
      'parameters': parameters ?? const <String, dynamic>{},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/sql/query',
      data: _payload(sql, parameters),
    );
    final rows = (response.data?['rows'] as List<dynamic>? ?? [])
        .cast<Map<dynamic, dynamic>>();
    return rows
        .map(
          (raw) => raw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/sql/insert',
      data: {
        'table': table,
        'values': values,
      },
    );
    return (response.data?['lastInsertId'] as int?) ?? 0;
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/sql/update',
      data: {
        'table': table,
        'values': values,
        'where': where,
        'whereArgs': whereArgs,
      },
    );
    return (response.data?['affectedRows'] as int?) ?? 0;
  }

  @override
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/sql/delete',
      data: {
        'table': table,
        'where': where,
        'whereArgs': whereArgs,
      },
    );
    return (response.data?['affectedRows'] as int?) ?? 0;
  }

  @override
  Future<void> close() async {
    _client.close(force: true);
  }
}
