# 下载管理器迁移指南

## 概述

本指南说明如何将现有代码从旧的 `DownloadManager` 迁移到新的 `DownloadAdapter`，以支持移动端后台下载功能。

## 迁移步骤

### 1. 更新导入语句

**旧代码：**
```dart
import '../utils/download_manager.dart';
```

**新代码：**
```dart
import '../utils/download_manager.dart';
import '../utils/download_adapter.dart';
```

### 2. 替换下载管理器实例

**旧代码：**
```dart
DownloadManager().addTask(path, fileName);
```

**新代码：**
```dart
DownloadAdapter().addTask(path, fileName);
```

### 3. 具体文件修改示例

#### 3.1 home_page.dart

**批量下载功能：**

```dart
// 旧代码 (第1452行)
DownloadManager().addTask(
  currentPath.join('/'),
  file.name,
);

// 新代码
DownloadAdapter().addTask(
  currentPath.join('/'),
  file.name,
);
```

**本地文件检查：**

```dart
// 旧代码 (第97行)
final downloadManager = DownloadManager();

// 新代码 - 保持不变，因为这里需要访问具体的任务信息
final downloadManager = DownloadManager();
```

#### 3.2 history_page.dart

**历史记录下载：**

```dart
// 旧代码 (第1172行)
DownloadManager().addTask(record.videoPath, record.videoName);

// 新代码
DownloadAdapter().addTask(record.videoPath, record.videoName);
```

#### 3.3 video_player.dart

**播放器中的下载检查：**

```dart
// 旧代码 (第618行)
final downloadManager = DownloadManager();

// 新代码 - 保持不变，因为这里需要访问具体的任务信息
final downloadManager = DownloadManager();
```

#### 3.4 downloads_page.dart

**下载页面操作：**

```dart
// 旧代码 - 暂停任务
DownloadManager().pauseTask(task.path);

// 新代码
DownloadAdapter().pauseTask(task.path);

// 旧代码 - 恢复任务
DownloadManager().resumeTask(task.path);

// 新代码
DownloadAdapter().resumeTask(task.path);

// 旧代码 - 重新开始任务
DownloadManager().restartTask(task.path);

// 新代码
DownloadAdapter().restartTask(task.path);
```

## 兼容性说明

### 保持原有功能的场景

以下场景仍然使用原有的 `DownloadManager`，因为需要访问具体的任务信息：

1. **任务状态查询**：
```dart
final task = DownloadManager().findTask(path, fileName);
```

2. **本地文件检查**：
```dart
final localVideos = await DownloadManager().getLocalVideosInPath(path);
```

3. **下载页面的任务列表显示**：
```dart
ValueListenableBuilder<Map<String, DownloadTask>>(
  valueListenable: DownloadManager().tasks,
  // ...
)
```

### 需要迁移的场景

以下操作应该迁移到 `DownloadAdapter`：

1. **添加下载任务**
2. **暂停/恢复任务**
3. **删除任务**
4. **重新开始任务**

## 完整迁移示例

### home_page.dart 完整修改

```dart
// 在文件顶部添加导入
import '../utils/download_adapter.dart';

// 修改批量下载方法
TextButton.icon(
  icon: const Icon(Icons.download),
  label: const Text('批量下载'),
  onPressed: () {
    for (var file in _selectedFiles) {
      if (file.type == 2) {
        // 使用新的下载适配器
        DownloadAdapter().addTask(
          currentPath.join('/'),
          file.name,
        );
      }
    }
    setState(() {
      _isSelectMode = false;
      _selectedFiles.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到下载队列')),
    );
  },
),
```

### history_page.dart 完整修改

```dart
// 在文件顶部添加导入
import '../utils/download_adapter.dart';

// 修改下载菜单项
PopupMenuItem(
  child: const Text('下载视频'),
  onTap: () {
    // 使用新的下载适配器
    DownloadAdapter().addTask(record.videoPath, record.videoName);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到下载队列')),
    );
  },
),
```

## 测试验证

迁移完成后，请进行以下测试：

### 桌面端测试
1. 验证下载功能正常工作
2. 测试暂停/恢复功能
3. 检查下载进度显示

### 移动端测试
1. 开始下载大文件
2. 熄屏或切换应用
3. 验证下载继续进行
4. 检查系统通知

## 注意事项

1. **渐进式迁移**：可以逐步迁移，不需要一次性修改所有文件
2. **向后兼容**：新的 `DownloadAdapter` 与现有代码完全兼容
3. **平台自动检测**：`DownloadAdapter` 会自动检测平台并选择合适的下载方式
4. **错误处理**：保持原有的错误处理逻辑不变

## 迁移检查清单

- [ ] 更新 home_page.dart 中的批量下载功能
- [ ] 更新 history_page.dart 中的下载功能
- [ ] 更新其他页面中的下载调用
- [ ] 测试桌面端下载功能
- [ ] 测试移动端后台下载功能
- [ ] 验证下载进度显示正常
- [ ] 检查下载通知功能

完成迁移后，您的应用将在移动端支持真正的后台下载，解决熄屏和应用切换导致的下载中断问题。
