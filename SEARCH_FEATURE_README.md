# 历史记录搜索功能

## 功能概述

为历史记录界面添加了搜索筛选功能，用户可以通过视频名称或路径快速查找历史观看记录。

## 新增功能

### 1. 搜索界面
- 在历史记录页面的AppBar中添加了搜索按钮（🔍图标）
- 点击搜索按钮进入搜索模式，标题栏变为搜索输入框
- 搜索模式下显示返回按钮，可以退出搜索模式

### 2. 搜索功能
- **实时搜索**：输入搜索关键词后，系统会自动进行搜索（500ms防抖）
- **模糊匹配**：支持按视频名称和视频路径进行模糊搜索
- **大小写不敏感**：搜索时忽略大小写
- **分页加载**：搜索结果支持分页加载，提高性能

### 3. 搜索体验优化
- 搜索结果按时间线模式显示
- 搜索模式下禁用目录模式切换
- 清空搜索内容时自动恢复正常显示
- 搜索结果为空时显示"没有找到匹配的视频"提示

## 数据库层改进

### 新增方法

1. **searchHistoricalRecords**
   ```sql
   SELECT * FROM t_historical_records 
   WHERE user_id = @userId
   AND (
     LOWER(video_name) LIKE LOWER(@searchQuery) 
     OR LOWER(video_path) LIKE LOWER(@searchQuery)
   )
   ORDER BY change_time DESC
   LIMIT @limit OFFSET @offset
   ```

2. **getSearchHistoricalRecordsCount**
   ```sql
   SELECT COUNT(*) as count
   FROM t_historical_records
   WHERE user_id = @userId
   AND (
     LOWER(video_name) LIKE LOWER(@searchQuery) 
     OR LOWER(video_path) LIKE LOWER(@searchQuery)
   )
   ```

## 界面改进

### AppBar 更新
- 搜索模式：显示搜索输入框和清空按钮
- 正常模式：显示搜索按钮和其他功能按钮
- 动态标题：根据当前状态显示不同标题

### 搜索状态管理
- `_isSearchMode`: 控制是否处于搜索模式
- `_searchQuery`: 当前搜索关键词
- `_searchResults`: 搜索结果列表
- `_searchController`: 搜索输入框控制器
- `_searchDebounceTimer`: 防抖计时器

## 使用方法

1. 在历史记录页面点击搜索按钮（🔍）
2. 在搜索框中输入关键词（视频名称或路径的一部分）
3. 系统自动显示匹配的搜索结果
4. 点击返回按钮或清空搜索内容退出搜索模式

## 技术特点

- **防抖搜索**：避免频繁查询数据库
- **分页加载**：支持大量搜索结果的分页显示
- **状态管理**：完善的搜索状态管理
- **用户体验**：流畅的搜索交互体验
- **性能优化**：高效的数据库查询和UI渲染

## 兼容性

- 与现有的时间线模式和目录模式完全兼容
- 保持原有的多选、删除等功能
- 搜索结果支持所有原有的操作（播放、删除、下载等）
