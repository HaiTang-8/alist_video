import 'package:alist_player/models/favorite_directory.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/home_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  List<FavoriteDirectory> _favorites = [];
  bool _isLoading = true;
  String? _currentUsername;
  bool _isSelectMode = false;
  final Set<FavoriteDirectory> _selectedItems = {};
  late final AnimationController _controller;
  String _debugMessage = '';

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
        
        final columnInfo = columns.map((c) => 
          '${c['column_name']} (${c['data_type']})'
        ).join(', ');
        
        setState(() {
          _debugMessage += '\n表结构: $columnInfo';
        });
        
        // 检查表约束/索引
        final constraints = await DatabaseHelper.instance.query('''
          SELECT constraint_name, constraint_type
          FROM information_schema.table_constraints
          WHERE table_name = 't_favorite_directories'
        ''');
        
        final constraintInfo = constraints.map((c) => 
          '${c['constraint_name']} (${c['constraint_type']})'
        ).join(', ');
        
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
        final countResult = await DatabaseHelper.instance.query(
          'SELECT COUNT(*) as count FROM t_favorite_directories'
        );
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
      final favorites = await DatabaseHelper.instance
          .getFavoriteDirectories(userId);
      
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
      print('Error loading favorites: $e');
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HomePage(
          initialUrl: directory.path,
          initialTitle: directory.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // 移除调试刷新按钮，只在有内容或选择模式时显示操作按钮
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '暂无收藏目录',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可在文件浏览页面点击星标图标收藏',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesList() {
    return ListView.builder(
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final favorite = _favorites[index];
        final isSelected = _selectedItems.contains(favorite);
        
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.2, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Interval(
              0.05 * index,
              0.5 + 0.05 * index,
              curve: Curves.easeOutCubic,
            ),
          )),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Interval(
                0.05 * index,
                0.5 + 0.05 * index,
              ),
            ),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected
                    ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: _isSelectMode
                    ? () => _toggleSelect(favorite)
                    : () => _navigateToDirectory(favorite),
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  _toggleSelectMode();
                  _toggleSelect(favorite);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_isSelectMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (value) => _toggleSelect(favorite),
                            activeColor: Theme.of(context).primaryColor,
                          ),
                        ),
                      Icon(
                        Icons.folder,
                        color: Theme.of(context).primaryColor,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              favorite.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              favorite.path,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
} 