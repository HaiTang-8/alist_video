# 下载状态同步问题修复

## 问题描述
用户反馈：下载完后退出应用重新进入这个下载界面，偶尔会出现已经下载完的任务显示没下载完，也有被删除的任务又出现的问题。

## 问题原因分析
1. **缺少文件验证**：应用重启后只是简单地从SharedPreferences恢复任务状态，没有验证文件是否真的存在和完整
2. **删除操作不原子**：删除任务时可能存在异步保存的时序问题
3. **状态不一致**：已完成任务的文件完整性没有验证，重启后没有检查已完成的文件是否还存在
4. **持久化延迟**：删除任务后状态持久化可能有延迟，导致已删除的任务重新出现

## 解决方案

### 1. 添加任务验证机制 (lib/utils/download_manager.dart)

#### 新增 `_validateTask` 方法
```dart
Future<bool> _validateTask(DownloadTask task) async {
  try {
    // 检查文件路径是否有效
    if (task.filePath.isEmpty) {
      return false;
    }
    
    final file = File(task.filePath);
    
    if (task.status == '已完成') {
      // 对于已完成的任务，检查文件是否存在
      if (!await file.exists()) {
        return false;
      }
      
      // 如果有总字节数信息，验证文件大小是否匹配
      if (task.totalBytes != null && task.totalBytes! > 0) {
        final fileSize = await file.length();
        if (fileSize != task.totalBytes) {
          return false; // 文件大小不匹配
        }
      }
    } else {
      // 对于未完成的任务，检查部分下载文件
      if (await file.exists()) {
        task.receivedBytes = await file.length();
      } else {
        task.receivedBytes = 0;
        task.progress = 0;
      }
    }
    
    return true;
  } catch (e) {
    return false;
  }
}
```

#### 改进 `_loadTasks` 方法
- 在加载任务时调用验证方法
- 只保留有效的任务
- 自动清理无效任务并保存更新

### 2. 改进删除操作的原子性

#### 优化 `removeTask` 方法
```dart
Future<void> removeTask(String path, {bool deleteFile = true}) async {
  final task = _tasks[path];
  if (task != null) {
    try {
      // 1. 先取消下载任务
      task.cancelToken?.cancel('用户删除任务');
      
      // 2. 删除文件（如果需要）
      if (deleteFile && task.filePath.isNotEmpty) {
        // 删除文件逻辑
      }
      
      // 3. 从内存中移除任务
      _tasks.remove(path);
      
      // 4. 立即更新UI
      _downloadTaskController.value = Map.from(_tasks);
      
      // 5. 保存到持久化存储
      await _saveTasks();
      
    } catch (e) {
      // 如果出现错误，尝试重新加载任务以保持一致性
      await _loadTasks();
    }
  }
}
```

### 3. 添加手动刷新功能

#### 新增 `refreshTasks` 方法
```dart
Future<void> refreshTasks() async {
  await _loadTasks();
}
```

#### 在下载页面添加刷新按钮
- 用户可以手动刷新任务状态
- 自动验证和清理无效任务

### 4. 平台下载管理器同步改进

对 `lib/utils/platform_download_manager.dart` 应用相同的改进：
- 添加任务验证机制
- 改进状态恢复逻辑
- 添加刷新功能

## 修改的文件

1. **lib/utils/download_manager.dart**
   - 添加 `_validateTask` 方法
   - 改进 `_loadTasks` 方法
   - 优化 `removeTask` 方法
   - 添加 `refreshTasks` 方法

2. **lib/utils/platform_download_manager.dart**
   - 添加相同的验证和刷新机制

3. **lib/utils/download_adapter.dart**
   - 添加 `refreshTasks` 方法统一接口

4. **lib/views/downloads_page.dart**
   - 添加刷新按钮
   - 使用DownloadAdapter进行刷新

## 效果

✅ **文件完整性验证**：重启后验证已完成任务的文件是否存在和完整  
✅ **自动清理无效任务**：自动移除文件已被删除或损坏的任务  
✅ **原子删除操作**：确保删除操作的一致性，避免已删除任务重新出现  
✅ **手动刷新功能**：用户可以手动刷新任务状态  
✅ **状态同步一致性**：确保内存状态和持久化状态的一致性  

## 使用方法

1. **自动验证**：应用启动时自动验证所有任务
2. **手动刷新**：点击下载页面的刷新按钮
3. **异常恢复**：删除操作出错时自动重新加载任务

这些改进确保了下载任务状态的准确性和一致性，解决了重启后状态不同步的问题。
