# 搜索功能Bug修复

## 问题描述

在文件夹模式下进行搜索后，点击文件夹进入目录详情，然后点击后退按钮会出现以下错误：

```
_TypeError (Null check operator used on a null value)
```

错误发生在 `_buildDirectoryTimeline` 方法中的这行代码：
```dart
final records = _groupedRecords[dirPath]!;
```

## 问题原因

1. **数据结构不匹配**：搜索模式下的 `_groupedRecords` 是按时间线分组的，而文件夹模式下是按目录路径分组的
2. **状态管理混乱**：在搜索模式下点击文件夹会设置 `_selectedDirectory`，但搜索结果中没有对应的目录数据
3. **模式切换逻辑缺陷**：搜索模式和目录模式之间的状态切换没有正确处理

## 修复方案

### 1. 修复 `_buildDirectoryTimeline` 方法

```dart
Widget _buildDirectoryTimeline(String dirPath) {
  // 检查是否在搜索模式下，如果是则返回到正常模式
  if (_searchQuery.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedDirectory = null;
      });
    });
    return const Center(child: CircularProgressIndicator());
  }

  final records = _groupedRecords[dirPath];
  if (records == null || records.isEmpty) {
    // 如果找不到对应的目录记录，返回到目录列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedDirectory = null;
      });
    });
    return const Center(child: Text('目录不存在或已被删除'));
  }
  
  // ... 其余逻辑保持不变
}
```

### 2. 修复 `_buildContent` 方法

```dart
Widget _buildContent() {
  // 在搜索模式下，始终显示时间线视图
  if (_searchQuery.isNotEmpty) {
    return _buildTimelineView();
  }
  
  // ... 其余逻辑保持不变
}
```

### 3. 修复 `_toggleSearchMode` 方法

```dart
void _toggleSearchMode() {
  setState(() {
    _isSearchMode = !_isSearchMode;
    if (!_isSearchMode) {
      _searchController.clear();
      _searchQuery = '';
      _searchResults.clear();
      _searchFocusNode.unfocus();
      // 退出搜索模式时，如果在目录模式下且选择了目录，需要重置
      if (!_isTimelineMode && _selectedDirectory != null) {
        _selectedDirectory = null;
      }
      _loadHistory(); // 恢复正常显示
    } else {
      // ... 其余逻辑保持不变
    }
  });
}
```

### 4. 修复目录点击逻辑

```dart
onTap: () {
  // 在搜索模式下不允许进入目录详情
  if (_searchQuery.isEmpty) {
    setState(() => _selectedDirectory = dirPath);
  }
},
```

## 修复效果

1. **防止空指针异常**：在访问 `_groupedRecords[dirPath]` 前进行 null 检查
2. **状态一致性**：确保搜索模式下不会进入目录详情页面
3. **用户体验优化**：在异常情况下自动返回到安全状态
4. **错误恢复**：当数据不一致时提供友好的错误提示

## 测试场景

修复后应该测试以下场景：

1. ✅ 在文件夹模式下进行搜索
2. ✅ 搜索模式下点击文件夹（应该无效果）
3. ✅ 退出搜索模式后正常使用文件夹功能
4. ✅ 在目录详情页面时切换到搜索模式
5. ✅ 各种边界情况的错误恢复

## 技术要点

- 使用 `WidgetsBinding.instance.addPostFrameCallback` 确保状态更新在下一帧执行
- 添加 null 安全检查避免运行时异常
- 明确区分搜索模式和目录模式的数据结构
- 提供用户友好的错误处理和状态恢复机制
