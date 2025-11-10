import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/services/persistence/drivers/go_bridge_persistence_driver.dart';
import 'package:alist_player/services/persistence/drivers/postgres_persistence_driver.dart';
import 'package:alist_player/services/persistence/drivers/sqlite_persistence_driver.dart';

/// 所有持久化实现都需要遵守的统一接口，便于在 DatabaseHelper 内做依赖反转
abstract class PersistenceDriver {
  DatabasePersistenceType get type;

  /// 初始化底层资源，包含连接池、文件句柄或HTTP客户端
  Future<void> init(DatabaseConnectionConfig config);

  /// 执行查询并返回字典列表
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// 插入记录并返回主键ID
  Future<int> insert(String table, Map<String, dynamic> values);

  /// 根据条件更新记录并返回影响行数
  Future<int> update(
    String table,
    Map<String, dynamic> values,
    String where,
    Map<String, dynamic> whereArgs,
  );

  /// 删除记录并返回影响行数
  Future<int> delete(
    String table,
    String where,
    Map<String, dynamic> whereArgs,
  );

  /// 释放底层资源
  Future<void> close();
}

/// 工厂方法便于在运行时根据配置动态实例化对应驱动
class PersistenceDriverFactory {
  static PersistenceDriver create(DatabasePersistenceType type) {
    switch (type) {
      case DatabasePersistenceType.remotePostgres:
        return PostgresPersistenceDriver();
      case DatabasePersistenceType.localSqlite:
        return SqlitePersistenceDriver();
      case DatabasePersistenceType.localGoBridge:
        return GoBridgePersistenceDriver();
    }
  }
}
