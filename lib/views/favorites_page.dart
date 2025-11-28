// ignore_for_file: unused_element, unused_field

import 'dart:async';

import 'package:alist_player/models/favorite_directory.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/index.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:alist_player/utils/user_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 收藏目录页面 - 展示用户收藏的文件夹列表
/// 支持移动端列表布局和桌面端网格布局，提供优美的卡片设计和流畅的动画效果
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.refreshSignal});

  /// 父级通过 ValueListenable 传入刷新信号，数值变化即代表需要重新拉取收藏数据
  final ValueListenable<int>? refreshSignal;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // 收藏列表数据
  List<FavoriteDirectory> _favorites = [];
  // 加载状态
  bool _isLoading = true;
  // 当前登录用户名
  String? _currentUsername;
  // 当前登录用户 ID
  int? _currentUserId;
  // 是否处于多选模式
  bool _isSelectMode = false;
  // 已选中的收藏项集合
  final Set<FavoriteDirectory> _selectedItems = {};
  // 列表入场动画控制器
  late final AnimationController _controller;
  // 调试信息（开发阶段使用）
  String _debugMessage = '';
  // 上一次刷新信号的值，用于判断是否需要重新加载
  int? _lastRefreshSignalValue;

  /// 统一的收藏页日志出口，确保移动端与桌面端日志一致
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'FavoritesPage',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 初始化动画控制器，设置入场动画时长
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _setupRefreshSignalListener();
    _loadFavorites();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefreshSignal);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 refreshSignal 更换时，重新绑定监听器
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_handleExternalRefreshSignal);
      _setupRefreshSignalListener();
    }
  }

  /// 监听外部刷新信号，确保跨端切换 Tab 时能够自动刷新收藏列表
  void _setupRefreshSignalListener() {
    final signal = widget.refreshSignal;
    if (signal == null) {
      return;
    }
    _lastRefreshSignalValue = signal.value;
    signal.addListener(_handleExternalRefreshSignal);
  }

  /// 收到外部刷新信号时触发一次刷新，避免用户再手动下拉
  void _handleExternalRefreshSignal() {
    final signal = widget.refreshSignal;
    if (signal == null) {
      return;
    }
    if (_lastRefreshSignalValue == signal.value) {
      return;
    }
    _lastRefreshSignalValue = signal.value;
    _log(
      '收到外部刷新信号，开始自动刷新收藏列表',
      level: LogLevel.debug,
    );
    unawaited(_refresh());
  }

  // 收藏模块里所有增删改都依赖 userId，缺失时追加 Debug 提示。
  int? _requireUserId(String contextLabel) {
    final resolved = _currentUserId ?? _currentUsername?.hashCode;
    if (resolved == null) {
      _log('缺少用户ID，无法执行$contextLabel', level: LogLevel.warning);
      if (mounted) {
        setState(() {
          _debugMessage += '\n缺少用户ID: $contextLabel 未执行';
        });
      }
    }
    return resolved;
  }

  // 检查数据库表结构
  Future<void> _checkDatabaseSchema() async {
    try {
      // 检查表是否存在
      final tableCheck = await DatabaseHelper.instance.query('''
        SELECT EXISTS (
          SELECT FROM information_schema.tables
          WHERE table_name = 't_favorite_directories'
        ) as exists
      ''');

      final tableExists = tableCheck.first['exists'] as bool;
      setState(() {
        _debugMessage += '\n表是否存在: $tableExists';
      });

      if (tableExists) {
        // 检查表结构
        final columns = await DatabaseHelper.instance.query('''
          SELECT column_name, data_type
          FROM information_schema.columns
          WHERE table_name = 't_favorite_directories'
        ''');

        final columnInfo = columns
            .map((c) => '${c['column_name']} (${c['data_type']})')
            .join(', ');

        setState(() {
          _debugMessage += '\n表结构: $columnInfo';
        });

        // 检查表约束/索引
        final constraints = await DatabaseHelper.instance.query('''
          SELECT constraint_name, constraint_type
          FROM information_schema.table_constraints
          WHERE table_name = 't_favorite_directories'
        ''');

        final constraintInfo = constraints
            .map((c) => '${c['constraint_name']} (${c['constraint_type']})')
            .join(', ');

        setState(() {
          _debugMessage += '\n表约束: $constraintInfo';
        });
      }
    } catch (e) {
      setState(() {
        _debugMessage += '\n检查表结构出错: $e';
      });
    }
  }

  // 添加测试数据
  Future<void> _addTestData() async {
    try {
      final userId = _requireUserId('添加收藏测试数据');
      if (userId == null) {
        return;
      }
      final id = await DatabaseHelper.instance.addFavoriteDirectory(
        path: '/测试目录',
        name: '测试收藏',
        userId: userId,
      );

      setState(() {
        _debugMessage += '\n添加测试数据成功, ID: $id';
      });

      // 重新加载收藏
      await _loadFavorites();
    } catch (e) {
      setState(() {
        _debugMessage += '\n添加测试数据失败: $e';
      });
    }
  }

  /// 加载收藏列表数据
  Future<void> _loadFavorites() async {
    if (!mounted) return;

    try {
      setState(() => _isLoading = true);
      // 获取当前登录用户信息
      final identity = await UserSession.loadIdentity();
      _currentUsername = identity.username;
      _currentUserId = identity.effectiveUserId;

      setState(() {
        _debugMessage = '用户名: ${_currentUsername ?? "未找到"}';
      });

      final userId = _requireUserId('加载收藏列表');
      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _debugMessage += '\n用户ID: $userId';
      });

      // 直接查询数据库，检查表是否存在收藏记录
      try {
        final countResult = await DatabaseHelper.instance
            .query('SELECT COUNT(*) as count FROM t_favorite_directories');
        final totalCount = countResult.first['count'] as int;
        setState(() {
          _debugMessage += '\n收藏表总记录数: $totalCount';
        });
      } catch (e) {
        setState(() {
          _debugMessage += '\n查询收藏表总数出错: $e';
        });
      }

      // 获取当前用户的收藏记录
      final favorites =
          await DatabaseHelper.instance.getFavoriteDirectories(userId);

      setState(() {
        _debugMessage += '\n当前用户收藏记录数: ${favorites.length}';
      });

      if (!mounted) return;

      if (favorites.isNotEmpty) {
        // 打印第一条记录的详细信息
        final firstRecord = favorites.first;
        setState(() {
          _debugMessage += '\n第一条记录: ${firstRecord.toString()}';
        });
      }

      setState(() {
        try {
          _favorites = [];
          for (var record in favorites) {
            try {
              final favorite = FavoriteDirectory.fromMap(record);
              _favorites.add(favorite);
            } catch (e) {
              _debugMessage += '\n转换记录失败: ${record['id']}, 错误: $e';
            }
          }
          _debugMessage += '\n成功转换记录数: ${_favorites.length}';
        } catch (e) {
          _debugMessage += '\n转换记录出错: $e';
        }
        _isLoading = false;
      });
      // 启动入场动画
      _controller.forward(from: 0);
    } catch (e) {
      _log(
        '加载收藏列表失败',
        level: LogLevel.error,
        error: e,
        stackTrace: StackTrace.current,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _debugMessage += '\n加载收藏出错: $e';
      });
    }
  }

  // 刷新按钮
  Future<void> _refresh() async {
    setState(() {
      _debugMessage = '';
    });
    await _loadFavorites();
  }

  /// 切换多选模式
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedItems.clear();
      }
    });
  }

  /// 切换单个项目的选中状态
  void _toggleSelect(FavoriteDirectory directory) {
    setState(() {
      if (_selectedItems.contains(directory)) {
        _selectedItems.remove(directory);
      } else {
        _selectedItems.add(directory);
      }

      // 当取消所有选择时，自动退出多选模式
      if (_selectedItems.isEmpty && _isSelectMode) {
        _isSelectMode = false;
      }
    });
  }

  /// 批量删除选中的收藏项
  Future<void> _deleteSelected() async {
    try {
      final userId = _requireUserId('批量删除收藏');
      if (userId == null) {
        return;
      }

      final deleteCount = _selectedItems.length;

      for (var item in _selectedItems) {
        await DatabaseHelper.instance.removeFavoriteDirectory(
          path: item.path,
          userId: userId,
        );
      }

      setState(() {
        _isSelectMode = false;
        _selectedItems.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $deleteCount 个收藏'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      _loadFavorites();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 导航到收藏的目录
  void _navigateToDirectory(FavoriteDirectory directory) {
    // 使用IndexPage静态方法进行导航，保留底部导航栏
    IndexPage.navigateToHome(context, directory.path, directory.name);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    final theme = Theme.of(context);

    return Scaffold(
      // 使用自定义 AppBar 样式，增加视觉层次
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _isSelectMode ? '已选择 ${_selectedItems.length} 项' : '我的收藏',
            key: ValueKey(_isSelectMode ? 'select_${_selectedItems.length}' : 'normal'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        actions: _buildAppBarActions(theme),
      ),
      body: _isLoading
          ? _buildLoadingState(theme)
          : _favorites.isEmpty
              ? _buildEmptyState()
              : _buildFavoritesList(),
    );
  }

  /// 构建 AppBar 操作按钮
  List<Widget> _buildAppBarActions(ThemeData theme) {
    return [
      // 刷新按钮
      IconButton(
        icon: Icon(
          Icons.refresh_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: _refresh,
        tooltip: '刷新列表',
      ),
      // 多选模式切换按钮（仅在有收藏时显示）
      if (_favorites.isNotEmpty)
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isSelectMode ? Icons.close_rounded : Icons.checklist_rounded,
              key: ValueKey(_isSelectMode),
              color: _isSelectMode
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onPressed: _toggleSelectMode,
          tooltip: _isSelectMode ? '取消选择' : '多选模式',
        ),
      // 删除按钮（仅在多选模式下且有选中项时显示）
      if (_isSelectMode && _selectedItems.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Icon(
              Icons.delete_rounded,
              color: theme.colorScheme.error,
            ),
            onPressed: _deleteSelected,
            tooltip: '删除选中项',
          ),
        ),
    ];
  }

  /// 构建加载状态界面
  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '加载中...',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建空状态界面 - 优美的空态设计
  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isWide = constraints.maxWidth >= 720;
        final iconSize = isWide ? 140.0 : 100.0;

        return Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 480 : 320,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 24,
                  vertical: isWide ? 60 : 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 精美的空态图标 - 使用渐变和阴影效果
                    Container(
                      height: iconSize,
                      width: iconSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.primaryContainer.withOpacity(0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.folder_special_rounded,
                        size: isWide ? 64 : 48,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: isWide ? 32 : 24),
                    // 主标题
                    Text(
                      '还没有收藏',
                      style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ) ??
                          TextStyle(
                            fontSize: isWide ? 26 : 22,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // 副标题说明
                    Text(
                      '在文件浏览中点击星标图标\n即可将常用目录添加到收藏',
                      style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ) ??
                          TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isWide ? 40 : 32),
                    // 刷新按钮
                    FilledButton.tonalIcon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('刷新列表'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建收藏列表 - 响应式布局，移动端列表/桌面端网格
  Widget _buildFavoritesList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 根据屏幕宽度计算网格列数
        final crossAxisCount = width >= 1280
            ? 4
            : width >= 1024
                ? 3
                : width >= 720
                    ? 2
                    : 1;
        final isListMode = crossAxisCount == 1;
        final horizontalPadding = isListMode ? 16.0 : 24.0;
        final verticalPadding = isListMode ? 12.0 : 24.0;
        const gridSpacing = 16.0;

        // 移动端使用列表布局，支持下拉刷新
        if (isListMode) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: Theme.of(context).colorScheme.primary,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              itemCount: _favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final favorite = _favorites[index];
                return _buildAnimatedFavoriteCard(favorite, index, true);
              },
            ),
          );
        }

        // 桌面端使用 Wrap 布局实现网格效果
        final totalSpacing = gridSpacing * (crossAxisCount - 1);
        final availableWidth = width - horizontalPadding * 2;
        final itemWidth = (availableWidth - totalSpacing) / crossAxisCount;

        return ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(
            // 扩展桌面端与移动端的拖拽设备，确保鼠标/触控板也能流畅滚动
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.unknown,
            },
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Wrap(
              spacing: gridSpacing,
              runSpacing: gridSpacing,
              alignment: WrapAlignment.start,
              children: List.generate(_favorites.length, (index) {
                final favorite = _favorites[index];
                return SizedBox(
                  width: itemWidth,
                  child: _buildAnimatedFavoriteCard(
                    favorite,
                    index,
                    false,
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  /// 构建带动画的收藏卡片
  Widget _buildAnimatedFavoriteCard(
    FavoriteDirectory favorite,
    int index,
    bool isCompact,
  ) {
    // 计算交错动画的时间间隔
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        (0.05 * index).clamp(0.0, 0.8),
        (0.45 + 0.05 * index).clamp(0.2, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.1),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: _FavoriteTile(
          favorite: favorite,
          isCompact: isCompact,
          isSelected: _selectedItems.contains(favorite),
          isSelectMode: _isSelectMode,
          colorIndex: index,
          onTap: _isSelectMode
              ? () => _toggleSelect(favorite)
              : () => _navigateToDirectory(favorite),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _toggleSelectMode();
            _toggleSelect(favorite);
          },
          onSelectionChanged: (_) => _toggleSelect(favorite),
        ),
      ),
    );
  }
}

/// 文件夹装饰色列表 - 根据索引循环使用，使界面更加丰富多彩
const List<Color> _folderColors = [
  Color(0xFF5B8DEF), // 蓝色
  Color(0xFF7C4DFF), // 紫色
  Color(0xFF00BFA5), // 青色
  Color(0xFFFF6D00), // 橙色
  Color(0xFFE91E63), // 粉色
  Color(0xFF43A047), // 绿色
  Color(0xFFFFB300), // 金色
  Color(0xFF00ACC1), // 蓝绿色
];

/// 收藏项卡片组件 - 精美的卡片设计，支持悬停效果
class _FavoriteTile extends StatefulWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.isCompact,
    required this.isSelected,
    required this.isSelectMode,
    required this.colorIndex,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectionChanged,
  });

  final FavoriteDirectory favorite;
  final bool isCompact;
  final bool isSelected;
  final bool isSelectMode;
  final int colorIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool?> onSelectionChanged;

  @override
  State<_FavoriteTile> createState() => _FavoriteTileState();
}

class _FavoriteTileState extends State<_FavoriteTile> {
  // 悬停状态
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(widget.isCompact ? 16 : 20);
    final highlight = theme.colorScheme.primary;

    // 解析路径以获取显示用的目录名
    final normalizedPath = widget.favorite.path.replaceAll('\\', '/');
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final displayFolderName =
        pathSegments.isNotEmpty ? pathSegments.last : widget.favorite.path;

    // 根据索引获取文件夹颜色
    final folderColor = _folderColors[widget.colorIndex % _folderColors.length];

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, _isHovered ? -3.0 : 0.0),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          // 选中状态使用主题色渐变
          gradient: widget.isSelected
              ? LinearGradient(
                  colors: [
                    highlight.withOpacity(0.15),
                    highlight.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: widget.isSelected
              ? null
              : isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(_isHovered ? 0.4 : 0.25)
                  : Colors.black.withOpacity(_isHovered ? 0.1 : 0.05),
              blurRadius: _isHovered ? 24 : 12,
              offset: Offset(0, _isHovered ? 8 : 4),
              spreadRadius: 0,
            ),
            if (widget.isSelected)
              BoxShadow(
                color: highlight.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            borderRadius: borderRadius,
            splashColor: highlight.withOpacity(0.1),
            highlightColor: highlight.withOpacity(0.05),
            child: Padding(
              padding: EdgeInsets.all(widget.isCompact ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部：图标、名称和复选框
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 彩色文件夹图标
                      _buildFolderIcon(folderColor),
                      const SizedBox(width: 14),
                      // 名称和目录信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.favorite.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    color: theme.colorScheme.onSurface,
                                  ) ??
                                  TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    displayFolderName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ) ??
                                        TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 选择模式下显示复选框
                      AnimatedOpacity(
                        opacity: widget.isSelectMode ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedScale(
                          scale: widget.isSelectMode ? 1 : 0.8,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !widget.isSelectMode,
                            child: Checkbox(
                              value: widget.isSelected,
                              onChanged: widget.onSelectionChanged,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              activeColor: highlight,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: widget.isCompact ? 12 : 16),
                  // 路径显示区域
                  _buildPathContainer(theme),
                  SizedBox(height: widget.isCompact ? 12 : 16),
                  // 底部操作按钮
                  _buildActionButton(theme, highlight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建彩色文件夹图标
  Widget _buildFolderIcon(Color folderColor) {
    return Container(
      width: widget.isCompact ? 44 : 52,
      height: widget.isCompact ? 44 : 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            folderColor.withOpacity(0.2),
            folderColor.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(widget.isCompact ? 12 : 14),
      ),
      child: Icon(
        Icons.folder_rounded,
        size: widget.isCompact ? 24 : 28,
        color: folderColor,
      ),
    );
  }

  /// 构建路径显示容器
  Widget _buildPathContainer(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: widget.isCompact ? 12 : 14,
        vertical: widget.isCompact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(widget.isCompact ? 10 : 12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标容器，确保与文本首行对齐
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.link_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              widget.favorite.path,
              style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ) ??
                  TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部操作按钮
  Widget _buildActionButton(ThemeData theme, Color highlight) {
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: widget.isCompact ? 14 : 16,
          vertical: widget.isCompact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? highlight.withOpacity(0.15)
              : highlight.withOpacity(0.08),
          borderRadius: BorderRadius.circular(widget.isCompact ? 10 : 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '打开目录',
              style: theme.textTheme.labelMedium?.copyWith(
                    color: highlight,
                    fontWeight: FontWeight.w600,
                  ) ??
                  TextStyle(
                    color: highlight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: highlight,
            ),
          ],
        ),
      ),
    );
  }
}
