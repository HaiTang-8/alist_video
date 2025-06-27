import 'dart:io';
import 'package:flutter/foundation.dart';
import 'download_manager.dart';
import 'platform_download_manager.dart';

/// 下载适配器，用于在新旧下载管理器之间进行适配
/// 保持向后兼容性，同时提供新的后台下载功能
class DownloadAdapter {
  static final DownloadAdapter _instance = DownloadAdapter._internal();
  factory DownloadAdapter() => _instance;
  
  late final DownloadManager _legacyManager;
  late final PlatformDownloadManager _platformManager;
  
  bool _isInitialized = false;

  DownloadAdapter._internal() {
    _legacyManager = DownloadManager();
    _platformManager = PlatformDownloadManager();
  }

  // 初始化
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _platformManager.initialize();
    _isInitialized = true;
  }

  // 检查是否为移动平台
  bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  // 获取当前使用的下载管理器
  String getCurrentDownloadMethod() {
    return _platformManager.getCurrentDownloadMethod();
  }

  // 添加下载任务
  Future<void> addTask(String path, String fileName) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (isMobilePlatform) {
      // 移动端使用新的平台下载管理器
      await _platformManager.addTask(path, fileName);
    } else {
      // 桌面端继续使用原有的下载管理器
      await _legacyManager.addTask(path, fileName);
    }
  }

  // 暂停任务
  Future<void> pauseTask(String taskId) async {
    if (isMobilePlatform) {
      await _platformManager.pauseTask(taskId);
    } else {
      await _legacyManager.pauseTask(taskId);
    }
  }

  // 恢复任务
  Future<void> resumeTask(String taskId) async {
    if (isMobilePlatform) {
      await _platformManager.resumeTask(taskId);
    } else {
      await _legacyManager.resumeTask(taskId);
    }
  }

  // 删除任务
  Future<void> removeTask(String taskId, {bool deleteFile = true}) async {
    if (isMobilePlatform) {
      await _platformManager.removeTask(taskId, deleteFile: deleteFile);
    } else {
      await _legacyManager.removeTask(taskId, deleteFile: deleteFile);
    }
  }

  // 重新开始任务
  Future<void> restartTask(String taskId) async {
    if (isMobilePlatform) {
      await _platformManager.restartTask(taskId);
    } else {
      await _legacyManager.restartTask(taskId);
    }
  }

  // 获取任务流 - 根据平台返回相应的任务流
  ValueNotifier<Map<String, dynamic>> get tasks {
    if (isMobilePlatform) {
      // 将新的任务格式转换为旧的格式以保持兼容性
      return ValueNotifier(_convertToLegacyFormat(_platformManager.tasks.value));
    } else {
      return _legacyManager.tasks;
    }
  }

  // 刷新任务状态
  Future<void> refreshTasks() async {
    if (isMobilePlatform) {
      await _platformManager.refreshTasks();
    } else {
      await _legacyManager.refreshTasks();
    }
  }

  // 监听任务变化
  void addTaskListener(VoidCallback listener) {
    if (isMobilePlatform) {
      _platformManager.tasks.addListener(listener);
    } else {
      _legacyManager.tasks.addListener(listener);
    }
  }

  void removeTaskListener(VoidCallback listener) {
    if (isMobilePlatform) {
      _platformManager.tasks.removeListener(listener);
    } else {
      _legacyManager.tasks.removeListener(listener);
    }
  }

  // 将新的任务格式转换为旧的格式
  Map<String, dynamic> _convertToLegacyFormat(Map<String, UnifiedDownloadTask> newTasks) {
    final Map<String, dynamic> legacyTasks = {};
    
    for (final entry in newTasks.entries) {
      final task = entry.value;
      legacyTasks[entry.key] = DownloadTask(
        path: task.path,
        url: task.url,
        fileName: task.fileName,
        filePath: task.filePath,
      )
        ..progress = task.progress
        ..status = _convertStatus(task.status)
        ..error = task.error
        ..receivedBytes = task.receivedBytes
        ..totalBytes = task.totalBytes
        ..speed = task.speed;
    }
    
    return legacyTasks;
  }

  // 状态转换
  String _convertStatus(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.waiting:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.failed:
        return '错误';
      case DownloadStatus.canceled:
        return '已取消';
    }
  }

  // 获取下载路径相关方法
  static Future<String> getDownloadPath() async {
    return await PlatformDownloadManager.getDownloadPath();
  }

  static Future<String> getCustomDownloadPath() async {
    return await DownloadManager.getCustomDownloadPath();
  }

  static Future<bool> setCustomDownloadPath(String path) async {
    return await DownloadManager.setCustomDownloadPath(path);
  }

  static Future<void> resetToDefaultDownloadPath() async {
    await DownloadManager.resetToDefaultDownloadPath();
  }

  static Future<void> openFolder(String path) async {
    await DownloadManager.openFolder(path);
  }

  // 扫描下载文件夹
  Future<int> scanDownloadFolder() async {
    if (isMobilePlatform) {
      // 移动端暂时使用旧的扫描逻辑
      return await _legacyManager.scanDownloadFolder();
    } else {
      return await _legacyManager.scanDownloadFolder();
    }
  }

  // 打开文件
  Future<void> openFile(String filePath) async {
    await _legacyManager.openFile(filePath);
  }

  // 重命名任务
  Future<void> renameTask(String taskId, String newFileName) async {
    if (isMobilePlatform) {
      // 移动端暂时使用旧的重命名逻辑
      await _legacyManager.renameTask(taskId, newFileName);
    } else {
      await _legacyManager.renameTask(taskId, newFileName);
    }
  }

  // 释放资源
  void dispose() {
    _platformManager.dispose();
  }
}
