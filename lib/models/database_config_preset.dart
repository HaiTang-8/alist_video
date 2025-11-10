import 'dart:convert';

import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';

/// 数据库配置预设模型
class DatabaseConfigPreset {
  /// 配置ID（唯一标识）
  final String id;

  /// 配置名称
  final String name;

  /// 当前预设使用的持久化方式
  final DatabasePersistenceType driverType;

  /// 数据库主机地址
  final String host;

  /// 数据库端口
  final int port;

  /// 数据库名称
  final String database;

  /// 数据库用户名
  final String username;

  /// 数据库密码
  final String password;

  /// SQLite 文件路径
  final String? sqlitePath;

  /// Go 桥接服务地址
  final String? goBridgeEndpoint;

  /// Go 服务认证令牌
  final String? goBridgeAuthToken;

  /// 创建时间
  final DateTime createdAt;

  /// 是否为默认配置
  final bool isDefault;

  /// 描述信息
  final String? description;

  const DatabaseConfigPreset({
    required this.id,
    required this.name,
    required this.driverType,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.sqlitePath,
    this.goBridgeEndpoint,
    this.goBridgeAuthToken,
    required this.createdAt,
    this.isDefault = false,
    this.description,
  });

  /// 从JSON创建实例
  factory DatabaseConfigPreset.fromJson(Map<String, dynamic> json) {
    return DatabaseConfigPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      driverType: DatabasePersistenceTypeExtension.fromStorage(
        json['driverType'] as String?,
      ),
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      sqlitePath: json['sqlitePath'] as String?,
      goBridgeEndpoint: json['goBridgeEndpoint'] as String?,
      goBridgeAuthToken: json['goBridgeAuthToken'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      isDefault: json['isDefault'] as bool? ?? false,
      description: json['description'] as String?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'driverType': driverType.storageValue,
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'sqlitePath': sqlitePath,
      'goBridgeEndpoint': goBridgeEndpoint,
      'goBridgeAuthToken': goBridgeAuthToken,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isDefault': isDefault,
      'description': description,
    };
  }

  /// 创建副本
  DatabaseConfigPreset copyWith({
    String? id,
    String? name,
    DatabasePersistenceType? driverType,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    String? sqlitePath,
    String? goBridgeEndpoint,
    String? goBridgeAuthToken,
    DateTime? createdAt,
    bool? isDefault,
    String? description,
  }) {
    return DatabaseConfigPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      driverType: driverType ?? this.driverType,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      sqlitePath: sqlitePath ?? this.sqlitePath,
      goBridgeEndpoint: goBridgeEndpoint ?? this.goBridgeEndpoint,
      goBridgeAuthToken: goBridgeAuthToken ?? this.goBridgeAuthToken,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
    );
  }

  /// 验证配置是否有效
  bool get isValid {
    if (name.trim().isEmpty) {
      return false;
    }

    switch (driverType) {
      case DatabasePersistenceType.remotePostgres:
        return host.trim().isNotEmpty &&
            database.trim().isNotEmpty &&
            username.trim().isNotEmpty &&
            password.trim().isNotEmpty &&
            port > 0 &&
            port <= 65535;
      case DatabasePersistenceType.localSqlite:
        return true;
      case DatabasePersistenceType.localGoBridge:
        return (goBridgeEndpoint ?? '').trim().isNotEmpty;
    }
  }

  /// 获取显示名称
  String get displayName {
    if (description != null && description!.trim().isNotEmpty) {
      return '$name - ${description!}';
    }
    return name;
  }

  /// 获取连接字符串（用于显示，不包含密码）
  String get connectionString {
    switch (driverType) {
      case DatabasePersistenceType.remotePostgres:
        return '$username@$host:$port/$database';
      case DatabasePersistenceType.localSqlite:
        return sqlitePath ?? '未配置 SQLite 路径';
      case DatabasePersistenceType.localGoBridge:
        return goBridgeEndpoint ?? '未配置 Go 服务地址';
    }
  }

  /// 获取完整连接字符串（包含密码，用于实际连接）
  String get fullConnectionString {
    switch (driverType) {
      case DatabasePersistenceType.remotePostgres:
        return '$username:$password@$host:$port/$database';
      case DatabasePersistenceType.localSqlite:
        return sqlitePath ?? '未配置 SQLite 路径';
      case DatabasePersistenceType.localGoBridge:
        return goBridgeEndpoint ?? '未配置 Go 服务地址';
    }
  }

  /// 将预设转换为运行时连接配置，供数据库驱动直接使用
  DatabaseConnectionConfig toConnectionConfig() {
    return DatabaseConnectionConfig(
      type: driverType,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      sqlitePath: sqlitePath,
      goBridgeEndpoint: goBridgeEndpoint,
      goBridgeAuthToken: goBridgeAuthToken,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseConfigPreset &&
        other.id == id &&
        other.name == name &&
        other.driverType == driverType &&
        other.host == host &&
        other.port == port &&
        other.database == database &&
        other.username == username &&
        other.password == password &&
        other.sqlitePath == sqlitePath &&
        other.goBridgeEndpoint == goBridgeEndpoint &&
        other.goBridgeAuthToken == goBridgeAuthToken &&
        other.isDefault == isDefault &&
        other.description == description;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      driverType,
      host,
      port,
      database,
      username,
      password,
      sqlitePath,
      goBridgeEndpoint,
      goBridgeAuthToken,
      isDefault,
      description,
    );
  }

  @override
  String toString() {
    return 'DatabaseConfigPreset(id: $id, driver: ${driverType.name}, name: $name)';
  }

  /// 创建默认配置预设
  static DatabaseConfigPreset createDefault({
    required String name,
    DatabasePersistenceType driverType = DatabasePersistenceType.remotePostgres,
    String host = '127.0.0.1',
    int port = 5432,
    String database = 'alist_video',
    String username = 'postgres',
    String password = 'postgres',
    String? sqlitePath,
    String? goBridgeEndpoint,
    String? goBridgeAuthToken,
    String? description,
  }) {
    return DatabaseConfigPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      driverType: driverType,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      sqlitePath: sqlitePath,
      goBridgeEndpoint: goBridgeEndpoint,
      goBridgeAuthToken: goBridgeAuthToken,
      createdAt: DateTime.now(),
      isDefault: false,
      description: description,
    );
  }

  /// 从JSON字符串列表解析配置预设列表
  static List<DatabaseConfigPreset> fromJsonList(String jsonString) {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => DatabaseConfigPreset.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 将配置预设列表转换为JSON字符串
  static String toJsonList(List<DatabaseConfigPreset> presets) {
    try {
      final jsonList = presets.map((preset) => preset.toJson()).toList();
      return jsonEncode(jsonList);
    } catch (e) {
      return '[]';
    }
  }
}
