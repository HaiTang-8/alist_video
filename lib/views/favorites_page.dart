// ignore_for_file: unused_element, unused_field

import 'package:alist_player/models/favorite_directory.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/index.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:alist_player/utils/logger.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<FavoriteDirectory> _favorites = [];
  bool _isLoading = true;
  String? _currentUsername;
  bool _isSelectMode = false;
  final Set<FavoriteDirectory> _selectedItems = {};
  late final AnimationController _controller;
  String _debugMessage = '';

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
    _loadFavorites();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      if (_currentUsername == null) {
        setState(() {
          _debugMessage += '\n无法添加测试数据: 未找到当前用户';
        });
        return;
      }

      final userId = _currentUsername!.hashCode;
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
      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('current_username');

      setState(() {
        _debugMessage = '用户名: ${_currentUsername ?? "未找到"}';
      });

      if (_currentUsername == null) {
        setState(() {
          _isLoading = false;
          _debugMessage = '错误: 未找到当前用户信息';
        });
        return;
      }

      final userId = _currentUsername!.hashCode;
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
      final userId = _currentUsername!.hashCode;

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

        return GridView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: gridSpacing,
            childAspectRatio: () {
              final availableWidth = width -
                  horizontalPadding * 2 -
                  gridSpacing * (crossAxisCount - 1);
              final itemWidth = availableWidth / crossAxisCount;
              final targetHeight = width >= 1440
                  ? 220.0
                  : width >= 1024
                      ? 230.0
                      : 250.0;
              return itemWidth / targetHeight;
            }(),
          ),
          itemCount: _favorites.length,
          itemBuilder: (context, index) {
            final favorite = _favorites[index];
            return _buildAnimatedFavoriteCard(favorite, index, false);
          },
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
    final borderRadius = BorderRadius.circular(isCompact ? 16 : 20);
    final highlight = theme.colorScheme.primary;

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
            color: Colors.black.withOpacity(isSelected ? 0.12 : 0.08),
            blurRadius: isCompact ? 12 : 18,
            offset: const Offset(0, 8),
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
            padding: EdgeInsets.all(isCompact ? 18 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: highlight.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        color: highlight,
                        size: isCompact ? 26 : 28,
                      ),
                    ),
                    const Spacer(),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 10),
                Tooltip(
                  message: favorite.path,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: highlight.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.drive_file_move_rounded,
                          size: 18,
                          color: highlight,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            favorite.path,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.74),
                                ) ??
                                TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.74),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: isCompact ? 16 : 24),
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
