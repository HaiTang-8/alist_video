# Tab导航刷新问题修复

## 问题描述
用户反馈：浏览别的界面时点击底部的tab选项切换到首页和历史这两个界面时会刷新，这个体验感很不好。

## 问题原因
原来的实现在每次tab切换时都会重新创建页面widget，导致页面状态丢失和重新初始化。

## 解决方案
使用`IndexedStack`替代原来的switch-case页面切换方式，并为所有页面添加`AutomaticKeepAliveClientMixin`来保持页面状态。

## 修改内容

### 1. 修改主导航页面 (lib/views/index.dart)
- 将原来的switch-case页面切换改为使用`IndexedStack`
- 创建`_HomePageWrapper`包装器来管理HomePage的动态路径更新
- 保持所有页面实例，避免重复创建

### 2. 为所有页面添加状态保持功能
- **HomePage** (lib/views/home_page.dart): 添加`AutomaticKeepAliveClientMixin`
- **HistoryPage** (lib/views/history_page.dart): 添加`AutomaticKeepAliveClientMixin`
- **FavoritesPage** (lib/views/favorites_page.dart): 添加`AutomaticKeepAliveClientMixin`
- **DownloadsPage** (lib/views/downloads_page.dart): 添加`AutomaticKeepAliveClientMixin`
- **PersonPage** (lib/views/person_page.dart): 添加`AutomaticKeepAliveClientMixin`

### 3. 关键技术点
- 使用`IndexedStack`保持所有页面的widget树
- 实现`AutomaticKeepAliveClientMixin`并设置`wantKeepAlive = true`
- 在`build`方法中调用`super.build(context)`以保持状态
- 创建HomePage包装器支持动态路径更新

## 效果
- 切换tab时页面不再刷新
- 保持页面滚动位置和状态
- 保持用户输入和选择状态
- 提升用户体验

## 注意事项
- 所有页面会同时保持在内存中，可能会增加内存使用
- 如果页面数量很多，建议考虑使用PageView配合懒加载
- 确保页面的dispose方法正确清理资源
