class FavoriteDirectory {
  final int id;
  final String path;
  final String name;
  final int userId;
  final DateTime createdAt;

  FavoriteDirectory({
    required this.id,
    required this.path,
    required this.name,
    required this.userId,
    required this.createdAt,
  });

  factory FavoriteDirectory.fromMap(Map<String, dynamic> map) {
    print('转换记录: $map'); // 添加调试信息
    try {
      final dynamic createdAtValue = map['created_at'];
      final DateTime createdAt;
      
      if (createdAtValue is DateTime) {
        // 如果已经是DateTime类型，直接使用
        createdAt = createdAtValue;
      } else if (createdAtValue is String) {
        // 如果是字符串，尝试解析
        createdAt = DateTime.parse(createdAtValue);
      } else {
        // 如果是其他类型，使用当前时间
        createdAt = DateTime.now();
      }

      return FavoriteDirectory(
        id: map['id'] as int,
        path: map['path'] as String,
        name: map['name'] as String,
        userId: map['user_id'] as int,
        createdAt: createdAt,
      );
    } catch (e) {
      print('记录转换错误: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
    };
  }
} 