import 'package:flutter/material.dart';

/// 可扩展的持久化方式列表，统一枚举便于后续新增实现
enum DatabasePersistenceType {
  remotePostgres,
  localSqlite,
  localGoBridge,
}

extension DatabasePersistenceTypeExtension on DatabasePersistenceType {
  /// 按枚举值输出持久化方式字符串，方便持久化到 SharedPreferences
  String get storageValue => name;

  /// 获取人类可读的中文名称用于 UI 展示
  String get displayName {
    switch (this) {
      case DatabasePersistenceType.remotePostgres:
        return '远程 PostgreSQL';
      case DatabasePersistenceType.localSqlite:
        return '本地 SQLite';
      case DatabasePersistenceType.localGoBridge:
        return '本地 Go 服务';
    }
  }

  /// 每种持久化方式使用不同图标，便于跨端视觉识别
  IconData get icon {
    switch (this) {
      case DatabasePersistenceType.remotePostgres:
        return Icons.cloud_outlined;
      case DatabasePersistenceType.localSqlite:
        return Icons.storage_outlined;
      case DatabasePersistenceType.localGoBridge:
        return Icons.developer_board_outlined;
    }
  }

  /// 判断是否需要传统数据库连接信息（host/port等）
  bool get requiresRemoteEndpoint =>
      this == DatabasePersistenceType.remotePostgres;

  /// 判断是否需要显式配置SQLite路径
  bool get requiresSqlitePath => this == DatabasePersistenceType.localSqlite;

  /// 判断是否使用Go进程暴露的本地API
  bool get requiresGoEndpoint => this == DatabasePersistenceType.localGoBridge;

  /// 从持久化的字符串恢复枚举值，默认回落到远程Postgres
  static DatabasePersistenceType fromStorage(String? value) {
    if (value == null || value.isEmpty) {
      return DatabasePersistenceType.remotePostgres;
    }
    return DatabasePersistenceType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => DatabasePersistenceType.remotePostgres,
    );
  }
}
