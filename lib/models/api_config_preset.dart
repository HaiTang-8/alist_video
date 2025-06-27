import 'dart:convert';

/// API配置预设模型
class ApiConfigPreset {
  /// 配置ID（唯一标识）
  final String id;
  
  /// 配置名称
  final String name;
  
  /// 基础URL
  final String baseUrl;
  
  /// 下载URL
  final String baseDownloadUrl;
  
  /// 创建时间
  final DateTime createdAt;
  
  /// 是否为默认配置
  final bool isDefault;
  
  /// 描述信息
  final String? description;

  const ApiConfigPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.baseDownloadUrl,
    required this.createdAt,
    this.isDefault = false,
    this.description,
  });

  /// 从JSON创建实例
  factory ApiConfigPreset.fromJson(Map<String, dynamic> json) {
    return ApiConfigPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      baseDownloadUrl: json['baseDownloadUrl'] as String,
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
      'baseUrl': baseUrl,
      'baseDownloadUrl': baseDownloadUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isDefault': isDefault,
      'description': description,
    };
  }

  /// 创建副本
  ApiConfigPreset copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? baseDownloadUrl,
    DateTime? createdAt,
    bool? isDefault,
    String? description,
  }) {
    return ApiConfigPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      baseDownloadUrl: baseDownloadUrl ?? this.baseDownloadUrl,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
    );
  }

  /// 验证配置是否有效
  bool get isValid {
    return name.trim().isNotEmpty && 
           baseUrl.trim().isNotEmpty && 
           baseDownloadUrl.trim().isNotEmpty &&
           _isValidUrl(baseUrl) &&
           _isValidUrl(baseDownloadUrl);
  }

  /// 验证URL格式
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiConfigPreset &&
        other.id == id &&
        other.name == name &&
        other.baseUrl == baseUrl &&
        other.baseDownloadUrl == baseDownloadUrl &&
        other.isDefault == isDefault &&
        other.description == description;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      baseUrl,
      baseDownloadUrl,
      isDefault,
      description,
    );
  }

  @override
  String toString() {
    return 'ApiConfigPreset(id: $id, name: $name, baseUrl: $baseUrl, baseDownloadUrl: $baseDownloadUrl, isDefault: $isDefault)';
  }

  /// 创建默认配置预设
  static ApiConfigPreset createDefault({
    required String name,
    required String baseUrl,
    required String baseDownloadUrl,
    String? description,
  }) {
    return ApiConfigPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      baseUrl: baseUrl,
      baseDownloadUrl: baseDownloadUrl,
      createdAt: DateTime.now(),
      isDefault: false,
      description: description,
    );
  }

  /// 从JSON字符串列表解析配置预设列表
  static List<ApiConfigPreset> fromJsonList(String jsonString) {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => ApiConfigPreset.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 将配置预设列表转换为JSON字符串
  static String toJsonList(List<ApiConfigPreset> presets) {
    try {
      final List<Map<String, dynamic>> jsonList = 
          presets.map((preset) => preset.toJson()).toList();
      return jsonEncode(jsonList);
    } catch (e) {
      return '[]';
    }
  }
}
