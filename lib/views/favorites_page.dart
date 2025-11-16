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

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.refreshSignal});

  /// 父级通过 ValueListenable 传入刷新信号，数值变化即代表需要重新拉取收藏数据
  final ValueListenable<int>? refreshSignal;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<FavoriteDirectory> _favorites = [];
  bool _isLoading = true;
  String? _currentUsername;
  int? _currentUserId;
  bool _isSelectMode = false;
  final Set<FavoriteDirectory> _selectedItems = {};
  late final AnimationController _controller;
  String _debugMessage = '';
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

  Future<void> _loadFavorites() async {
    if (!mounted) return;

    try {
      setState(() => _isLoading = true);
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

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedItems.clear();
      }
    });
  }

  void _toggleSelect(FavoriteDirectory directory) {
    setState(() {
      if (_selectedItems.contains(directory)) {
        _selectedItems.remove(directory);
      } else {
        _selectedItems.add(directory);
      }

      if (_selectedItems.isEmpty && _isSelectMode) {
        _isSelectMode = false;
      }
    });
  }

  Future<void> _deleteSelected() async {
    try {
      final userId = _requireUserId('批量删除收藏');
      if (userId == null) {
        return;
      }

      for (var item in _selectedItems) {
        await DatabaseHelper.instance.removeFavoriteDirectory(
          path: item.path,
          userId: userId,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除成功')),
      );

      setState(() {
        _isSelectMode = false;
        _selectedItems.clear();
      });

      _loadFavorites();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    }
  }

  void _navigateToDirectory(FavoriteDirectory directory) {
    // 使用IndexPage静态方法进行导航，保留底部导航栏
    IndexPage.navigateToHome(context, directory.path, directory.name);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectMode ? '已选择 ${_selectedItems.length} 项' : '收藏夹',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
          // 只在有内容或选择模式时显示操作按钮
          if (_favorites.isNotEmpty)
            IconButton(
              icon: Icon(_isSelectMode ? Icons.close : Icons.checklist),
              onPressed: _toggleSelectMode,
            ),
          if (_isSelectMode && _selectedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? _buildEmptyState()
              : _buildFavoritesList(),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isWide = constraints.maxWidth >= 720;
        final iconSize = isWide ? 120.0 : 88.0;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 440 : 360,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 32 : 24,
                vertical: isWide ? 48 : 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: iconSize,
                    width: iconSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.18),
                          theme.colorScheme.primary.withOpacity(0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.star_border_rounded,
                      size: isWide ? 72 : 64,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '暂无收藏目录',
                    style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.84),
                        ) ??
                        TextStyle(
                          fontSize: isWide ? 24 : 20,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.84),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '可在文件浏览页面点击星标图标收藏，管理常用目录更高效。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          height: 1.5,
                        ) ??
                        TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          height: 1.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => _refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('立即刷新'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
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
        const gridSpacing = 20.0;

        if (isListMode) {
          return ListView.separated(
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
          );
        }

        // 使用 Wrap 配合自适应卡片宽度，让内容高度自然扩展，避免固定 childAspectRatio
        // 在桌面和移动端宽度变化时出现 Column 垂直溢出。
        final totalSpacing = gridSpacing * (crossAxisCount - 1);
        final availableWidth = width - horizontalPadding * 2;
        final itemWidth = (availableWidth - totalSpacing) / crossAxisCount;

        return ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(
            // 扩展桌面端与移动端的拖拽设备，确保鼠标/触控板也能流畅滚动。
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

  Widget _buildAnimatedFavoriteCard(
    FavoriteDirectory favorite,
    int index,
    bool isCompact,
  ) {
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
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: _FavoriteTile(
          favorite: favorite,
          isCompact: isCompact,
          isSelected: _selectedItems.contains(favorite),
          isSelectMode: _isSelectMode,
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

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.isCompact,
    required this.isSelected,
    required this.isSelectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectionChanged,
  });

  final FavoriteDirectory favorite;
  final bool isCompact;
  final bool isSelected;
  final bool isSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool?> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(isCompact ? 14 : 18);
    final highlight = theme.colorScheme.primary;
    final normalizedPath = favorite.path.replaceAll('\\', '/');
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final displayFolderName =
        pathSegments.isNotEmpty ? pathSegments.last : favorite.path;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  highlight.withOpacity(0.18),
                  highlight.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSelected
            ? highlight.withOpacity(0.04)
            : theme.colorScheme.surface,
        border: Border.all(
          color: isSelected
              ? highlight.withOpacity(0.6)
              : theme.dividerColor.withOpacity(0.2),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.1 : 0.06),
            blurRadius: isCompact ? 10 : 14,
            offset: const Offset(0, 6),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          splashColor: highlight.withOpacity(0.12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 20,
              vertical: isCompact ? 14 : 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部仅保留名称与末级目录，移除图标后整体更紧凑。
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            favorite.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ) ??
                                const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayFolderName,
                            style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65),
                                  letterSpacing: 0.3,
                                ) ??
                                TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.65),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: isSelectMode ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !isSelectMode,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: onSelectionChanged,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          activeColor: highlight,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 使用 SelectableText 展示完整路径，移动端与桌面端都可滑动复制，避免任何截断。
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: highlight.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    favorite.path,
                    style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.82),
                          height: 1.3,
                        ) ??
                        TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.82),
                          height: 1.3,
                        ),
                  ),
                ),
                SizedBox(height: isCompact ? 12 : 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: highlight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
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
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 18,
                          color: highlight,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
