import 'dart:convert';

/// 数据库配置预设模型
class DatabaseConfigPreset {
  /// 配置ID（唯一标识）
  final String id;
  
  /// 配置名称
  final String name;
  
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
  
  /// 创建时间
  final DateTime createdAt;
  
  /// 是否为默认配置
  final bool isDefault;
  
  /// 描述信息
  final String? description;

  const DatabaseConfigPreset({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.createdAt,
    this.isDefault = false,
    this.description,
  });

  /// 从JSON创建实例
  factory DatabaseConfigPreset.fromJson(Map<String, dynamic> json) {
    return DatabaseConfigPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
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
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isDefault': isDefault,
      'description': description,
    };
  }

  /// 创建副本
  DatabaseConfigPreset copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    DateTime? createdAt,
    bool? isDefault,
    String? description,
  }) {
    return DatabaseConfigPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
    );
  }

  /// 验证配置是否有效
  bool get isValid {
    return name.trim().isNotEmpty && 
           host.trim().isNotEmpty && 
           database.trim().isNotEmpty &&
           username.trim().isNotEmpty &&
           password.trim().isNotEmpty &&
           port > 0 && port <= 65535;
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
    return '$username@$host:$port/$database';
  }

  /// 获取完整连接字符串（包含密码，用于实际连接）
  String get fullConnectionString {
    return '$username:$password@$host:$port/$database';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseConfigPreset &&
        other.id == id &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.database == database &&
        other.username == username &&
        other.password == password &&
        other.isDefault == isDefault &&
        other.description == description;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      host,
      port,
      database,
      username,
      password,
      isDefault,
      description,
    );
  }

  @override
  String toString() {
    return 'DatabaseConfigPreset(id: $id, name: $name, host: $host, port: $port, database: $database, username: $username, isDefault: $isDefault)';
  }

  /// 创建默认配置预设
  static DatabaseConfigPreset createDefault({
    required String name,
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
    String? description,
  }) {
    return DatabaseConfigPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      createdAt: DateTime.now(),
      isDefault: false,
      description: description,
    );
  }

  /// 从JSON字符串列表解析配置预设列表
  static List<DatabaseConfigPreset> fromJsonList(String jsonString) {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => DatabaseConfigPreset.fromJson(json)).toList();
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

  /// 验证主机地址格式
  static bool _isValidHost(String host) {
    if (host.trim().isEmpty) return false;
    
    // 检查是否为IP地址
    final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipRegex.hasMatch(host)) {
      // 验证IP地址范围
      final parts = host.split('.');
      for (final part in parts) {
        final num = int.tryParse(part);
        if (num == null || num < 0 || num > 255) {
          return false;
        }
      }
      return true;
    }
    
    // 检查是否为域名（简单验证）
    final domainRegex = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$');
    return domainRegex.hasMatch(host) || host == 'localhost';
  }

  /// 验证端口号
  static bool _isValidPort(int port) {
    return port > 0 && port <= 65535;
  }
}
