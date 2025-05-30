# 下载功能测试指南

## 测试目标

通过详细的日志记录来分析移动端下载失败的具体原因。

## 测试步骤

### 1. 启动应用并检查日志初始化

1. 启动应用
2. 进入下载页面
3. 点击右上角的 🐛 (bug_report) 图标查看日志
4. 确认看到以下初始化日志：
   ```
   [INFO] [App] Application starting...
   [INFO] [App] Platform: android/ios
   [INFO] [DownloadManager] Initializing download manager...
   [INFO] [DownloadManager] Is mobile platform: true/false
   ```

### 2. 测试权限请求（仅移动端）

在移动端，查看权限请求的详细日志：
```
[INFO] [Permissions] Requesting permissions...
[INFO] [Permissions] Requesting storage permission...
[INFO] [Permissions] Storage permission status: granted/denied
[INFO] [Permissions] Requesting notification permission...
[INFO] [Permissions] Notification permission status: granted/denied
```

### 3. 测试下载任务创建

1. 在文件浏览页面选择一个视频文件
2. 点击下载
3. 立即查看日志，应该看到：
   ```
   [INFO] [DownloadTask] Adding download task: /path/filename
   [INFO] [DownloadTask] Getting download URL for: /path/filename
   [INFO] [DownloadTask] Download URL obtained: https://...
   [INFO] [DownloadTask] Download path: /storage/.../filename
   [INFO] [DownloadTask] Download directory created/verified
   [INFO] [DownloadTask] Task added to queue: /path/filename
   [INFO] [DownloadTask] Starting download: /path/filename
   ```

### 4. 测试移动端后台下载

**移动端特定测试：**
1. 开始下载一个大文件（>100MB）
2. 查看日志确认 flutter_downloader 初始化：
   ```
   [INFO] [FlutterDownloader] Starting flutter_downloader initialization
   [INFO] [FlutterDownloader] Initializing flutter_downloader...
   [INFO] [FlutterDownloader] Flutter_downloader initialized successfully
   [INFO] [FlutterDownloader] Setting up callback port...
   [INFO] [FlutterDownloader] Callback registered successfully
   ```

3. 确认下载开始：
   ```
   [INFO] [MobileDownload] Starting mobile download for: filename
   [INFO] [MobileDownload] URL: https://...
   [INFO] [MobileDownload] Save path: /storage/.../filename
   [INFO] [MobileDownload] Download directory: /storage/...
   [INFO] [MobileDownload] Flutter downloader task created: task_id
   ```

4. **关键测试：熄屏和后台切换**
   - 下载开始后，熄屏 30 秒
   - 切换到其他应用 30 秒
   - 返回应用查看下载进度
   - 检查日志中是否有错误信息

### 5. 桌面端测试

**桌面端特定测试：**
1. 确认使用 Dio 下载：
   ```
   [INFO] [DownloadManager] Using Dio for desktop platform
   ```

2. 测试断点续传功能

### 6. 错误日志分析

如果下载失败，查找以下类型的错误日志：

**权限相关错误：**
```
[ERROR] [Permissions] Failed to request permissions
[ERROR] [FlutterDownloader] Failed to initialize flutter_downloader
```

**网络相关错误：**
```
[ERROR] [DownloadTask] Failed to add download task
[ERROR] [MobileDownload] Mobile download failed for: filename
```

**文件系统错误：**
```
[ERROR] [DownloadTask] Download directory creation failed
[ERROR] [DownloadTask] File write permission denied
```

## 常见问题诊断

### 问题1：权限被拒绝
**症状：** 日志显示权限状态为 `denied`
**解决方案：**
1. 手动在设置中授予应用存储权限
2. 重新安装应用重新请求权限

### 问题2：Flutter Downloader 初始化失败
**症状：** 日志显示 flutter_downloader 初始化错误
**解决方案：**
1. 检查 Android 权限配置
2. 确认 provider_paths.xml 文件存在
3. 重新安装应用

### 问题3：后台下载中断
**症状：** 熄屏后下载停止，日志中断
**解决方案：**
1. 检查电池优化设置
2. 确认后台应用权限
3. 查看系统级下载通知

### 问题4：下载URL获取失败
**症状：** 日志显示 "获取下载地址失败"
**解决方案：**
1. 检查网络连接
2. 确认服务器配置
3. 验证文件路径正确性

## 日志导出和分享

1. 在日志查看页面点击分享按钮
2. 导出完整日志文件
3. 通过邮件或其他方式分享给开发者

## 性能监控

关注以下性能指标的日志：
- 下载速度
- 内存使用
- 电池消耗
- 网络使用情况

## 自动化测试脚本

可以编写自动化测试来验证：
1. 权限请求流程
2. 下载任务创建
3. 后台下载持续性
4. 错误恢复机制

---

通过这个详细的测试指南和日志分析，我们可以准确定位移动端下载问题的根本原因，并提供针对性的解决方案。
