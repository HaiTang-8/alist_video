# SQL日志功能使用说明

## 功能概述

在设置界面添加了一个开关，用于控制是否在控制台打印SQL查询语句。这个功能主要用于调试和开发目的。

## 实现位置

### 1. 常量定义
在 `lib/constants/app_constants.dart` 中添加了：
```dart
// SQL日志设置
static const String enableSqlLoggingKey = 'enable_sql_logging'; // 是否启用SQL日志打印
static const bool defaultEnableSqlLogging = false; // 默认不启用SQL日志
```

### 2. 数据库工具类修改
在 `lib/utils/db.dart` 中：
- 添加了 `_isSqlLoggingEnabled()` 方法来检查设置
- 修改了 `query()` 方法，根据设置决定是否打印SQL语句
- 错误信息仍然会打印，不受设置控制

### 3. 设置界面
在 `lib/views/settings/database_preset_settings_dialog.dart` 中：
- 添加了SQL日志开关的状态变量
- 在自定义配置标签页中添加了"调试设置"部分
- 包含一个开关来控制SQL日志的启用/禁用

## 使用方法

1. 打开应用
2. 进入"个人"页面
3. 点击"数据库设置"
4. 在自定义配置标签页中找到"调试设置"部分
5. 切换"启用SQL日志"开关

## 功能特点

- **默认关闭**：为了避免生产环境中的性能影响，默认不启用SQL日志
- **实时生效**：设置更改后立即生效，无需重启应用
- **错误日志保留**：即使关闭SQL日志，错误信息仍会打印
- **用户友好**：提供清晰的开关说明和反馈

## 技术细节

### 设置存储
使用 SharedPreferences 存储用户的选择：
```dart
await prefs.setBool(AppConstants.enableSqlLoggingKey, _enableSqlLogging);
```

### 日志控制
在每次SQL查询前检查设置：
```dart
final enableLogging = await _isSqlLoggingEnabled();
if (enableLogging) {
  print('Executing SQL: $sql');
  print('Parameters: $parameters');
}
```

### UI组件
使用 SwitchListTile 提供直观的开关界面：
```dart
SwitchListTile(
  title: const Text('启用SQL日志'),
  subtitle: const Text('在控制台打印数据库SQL查询语句'),
  value: _enableSqlLogging,
  onChanged: (bool value) {
    setState(() {
      _enableSqlLogging = value;
    });
    _saveSqlLoggingSetting();
  },
)
```

## 注意事项

1. **性能影响**：启用SQL日志可能会影响应用性能，建议仅在调试时使用
2. **日志量**：频繁的数据库操作会产生大量日志输出
3. **隐私考虑**：SQL参数可能包含敏感信息，请谨慎在生产环境中使用
