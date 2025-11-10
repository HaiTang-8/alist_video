import 'package:alist_player/models/database_persistence_type.dart';

/// 统一封装数据库/本地持久化的连接配置，确保跨端配置字段一致
class DatabaseConnectionConfig {
  final DatabasePersistenceType type;
  final String? host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final String? sqlitePath;
  final String? goBridgeEndpoint;
  final String? goBridgeAuthToken;

  const DatabaseConnectionConfig({
    required this.type,
    this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.sqlitePath,
    this.goBridgeEndpoint,
    this.goBridgeAuthToken,
  });

  /// 便于根据当前配置生成新的变体
  DatabaseConnectionConfig copyWith({
    DatabasePersistenceType? type,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    String? sqlitePath,
    String? goBridgeEndpoint,
    String? goBridgeAuthToken,
  }) {
    return DatabaseConnectionConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      sqlitePath: sqlitePath ?? this.sqlitePath,
      goBridgeEndpoint: goBridgeEndpoint ?? this.goBridgeEndpoint,
      goBridgeAuthToken: goBridgeAuthToken ?? this.goBridgeAuthToken,
    );
  }

  /// 将配置序列化，便于调试输出或未来持久化
  Map<String, dynamic> toMap() {
    return {
      'type': type.storageValue,
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'sqlitePath': sqlitePath,
      'goBridgeEndpoint': goBridgeEndpoint,
    };
  }
}
