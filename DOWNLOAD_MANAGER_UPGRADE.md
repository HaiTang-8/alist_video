# 下载管理器升级说明

## 概述

为了解决移动端下载文件时熄屏后或应用不在前台时导致下载失败的问题，我们实现了一个新的平台适配下载管理器。

## 主要改进

### 1. 平台检测和适配
- **移动端（Android/iOS）**：使用 `flutter_downloader` 插件，支持真正的后台下载
- **桌面端（Mac/Windows）**：继续使用 `dio` HTTP 客户端，保持原有功能

### 2. 后台下载支持
- **Android**：配置了前台服务权限和通知权限，支持熄屏下载
- **iOS**：配置了后台模式，支持应用切换到后台时继续下载

### 3. 统一接口
- 通过 `DownloadAdapter` 提供统一的下载接口
- 自动根据平台选择合适的下载方式
- 保持与现有代码的兼容性

## 技术实现

### 新增文件

1. **`lib/utils/platform_download_manager.dart`**
   - 核心的平台适配下载管理器
   - 支持移动端后台下载和桌面端 dio 下载

2. **`lib/utils/download_adapter.dart`**
   - 下载适配器，提供统一接口
   - 自动选择合适的下载方式

3. **Android 配置**
   - `android/app/src/main/AndroidManifest.xml`：添加后台下载权限
   - `android/app/src/main/res/xml/provider_paths.xml`：文件提供者配置

4. **iOS 配置**
   - `ios/Runner/Info.plist`：添加后台模式配置

### 依赖更新

在 `pubspec.yaml` 中添加了以下依赖：
```yaml
flutter_downloader: ^1.11.8
permission_handler: ^11.3.1
```

## 使用方法

### 当前下载方法显示

在下载设置页面中，现在会显示当前使用的下载方法：
- 移动端：`Flutter Downloader (支持后台下载)`
- 桌面端：`Dio HTTP Client (桌面端)`

### 自动初始化

下载管理器会在应用启动时自动初始化：
```dart
// 在 main.dart 中
await DownloadAdapter().initialize();
```

### API 兼容性

现有的下载相关代码无需修改，`DownloadAdapter` 会自动处理平台差异：
```dart
// 添加下载任务
await DownloadAdapter().addTask(path, fileName);

// 暂停任务
await DownloadAdapter().pauseTask(taskId);

// 恢复任务
await DownloadAdapter().resumeTask(taskId);
```

## 功能特性

### 移动端特性
- ✅ 支持熄屏下载
- ✅ 支持应用切换到后台时继续下载
- ✅ 系统级下载通知
- ✅ 下载进度实时更新
- ✅ 支持暂停和恢复
- ✅ 自动权限请求

### 桌面端特性
- ✅ 保持原有 dio 下载功能
- ✅ 支持断点续传
- ✅ 实时进度显示
- ✅ 支持暂停和恢复

### 通用特性
- ✅ 统一的任务管理界面
- ✅ 下载历史记录
- ✅ 文件管理功能
- ✅ 自定义下载路径
- ✅ 批量操作支持

## 权限说明

### Android 权限
```xml
<!-- 后台下载权限 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

### iOS 后台模式
```xml
<key>UIBackgroundModes</key>
<array>
    <string>background-fetch</string>
    <string>background-processing</string>
</array>
```

## 测试验证

可以通过以下方式验证后台下载功能：

1. **移动端测试**：
   - 开始下载一个大文件
   - 熄屏或切换到其他应用
   - 观察下载是否继续进行
   - 检查系统通知栏的下载进度

2. **桌面端测试**：
   - 验证原有下载功能正常工作
   - 测试断点续传功能

## 注意事项

1. **首次运行**：移动端首次使用时会请求存储和通知权限
2. **电池优化**：某些 Android 设备可能需要手动关闭应用的电池优化
3. **网络环境**：后台下载仍然依赖网络连接
4. **存储空间**：确保设备有足够的存储空间

## 故障排除

### 常见问题

1. **权限被拒绝**：
   - 检查应用权限设置
   - 重新安装应用以重新请求权限

2. **后台下载失败**：
   - 检查设备的电池优化设置
   - 确认网络连接稳定

3. **下载速度慢**：
   - 检查网络环境
   - 尝试更换网络连接

## 未来改进

1. **下载队列管理**：支持同时下载多个文件的队列管理
2. **智能重试**：网络中断时自动重试下载
3. **下载统计**：提供详细的下载统计信息
4. **云同步**：支持下载任务的云端同步

---

通过这次升级，移动端用户现在可以安心地在后台下载大文件，无需担心熄屏或切换应用导致的下载中断问题。
