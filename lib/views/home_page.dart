import 'dart:ui';

import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/download_manager.dart';
import 'package:alist_player/views/video_player.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

class HomePage extends StatefulWidget {
  final String? initialUrl;
  final String? initialTitle;

  const HomePage({
    super.key,
    this.initialUrl,
    this.initialTitle,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  List<FileItem> files = [];
  List<String> currentPath = ['/'];
  int _sortColumnIndex = 0;
  bool _isAscending = true;
  late AnimationController _animationController;
  bool _isSelectMode = false;
  final Set<FileItem> _selectedFiles = {};
  bool _isSearchMode = false;
  String _searchKeyword = '';
  int _searchScope = 0;
  String? _currentUsername;
  bool _isFavorite = false;
  
  // 添加一个映射来跟踪哪些文件已下载
  final Set<String> _localFiles = {};

  Future<void> _getList({bool refresh = false}) async {
    if (refresh) {
      await _animationController.reverse();
    }

    try {
      var res = await FsApi.list(
          path: currentPath.join('/'),
          password: '',
          page: 1,
          perPage: 0,
          refresh: refresh);
      if (res.code == 200) {
        setState(() {
          files = res.data?.content
                  ?.where((data) => data.type == 1 || data.type == 2)
                  .map((data) => FileItem(
                        type: data.type ?? -1,
                        sha1: data.hashInfo?.sha1 ?? '',
                        name: data.name ?? '',
                        size: data.size ?? 0,
                        modified: DateTime.tryParse(data.modified ?? '') ??
                            DateTime.now(),
                        parent: data.parent ?? currentPath.join('/'),
                      ))
                  .toList() ??
              [];
          _sort((file) => file.name.toLowerCase(), 0, true);
        });
        
        // 检查当前目录是否已收藏
        _checkFavoriteStatus();
        
        // 检查哪些文件已下载到本地
        _checkLocalFiles();
        
        // 加载视频文件的播放历史记录
        _loadVideoHistoryRecords();
      } else {
        _handleError(res.message ?? '获取文件失败');
      }

      if (refresh) {
        await _animationController.forward();
      }
    } catch (e) {
      _handleError('操作失败,请检查日志');
    }
  }

  // 新增方法：检查哪些文件已下载到本地
  Future<void> _checkLocalFiles() async {
    final downloadManager = DownloadManager();
    
    try {
      // 使用新方法获取当前路径下的本地视频列表
      final localVideos = await downloadManager.getLocalVideosInPath(currentPath.join('/'));
      
      setState(() {
        _localFiles.clear();
        _localFiles.addAll(localVideos);
      });
      
      print("Found ${_localFiles.length} local videos in current directory");
    } catch (e) {
      print("Error checking local files: $e");
    }
  }
  
  // 新增方法：加载视频文件的播放历史记录
  Future<void> _loadVideoHistoryRecords() async {
    if (_currentUsername == null) return;
    
    try {
      // 获取当前目录下所有视频文件的历史记录
      final currentDirectory = currentPath.join('/');
      final historyRecords = await DatabaseHelper.instance.getHistoricalRecordsByPath(
        path: currentDirectory,
        userId: _currentUsername!.hashCode,
      );
      
      if (historyRecords.isEmpty) return;
      
      // 将历史记录关联到对应的文件项
      setState(() {
        for (var file in files) {
          if (file.type == 2) { // 只处理视频文件
            // 查找匹配的历史记录
            try {
              final record = historyRecords.firstWhere(
                (record) => record.videoName == file.name,
              );
              file.historyRecord = record;
            } catch (e) {
              // 如果没有找到匹配的记录，不做任何操作
            }
          }
        }
      });
      
      print("Found ${historyRecords.length} history records for current directory");
    } catch (e) {
      print("Error loading video history records: $e");
    }
  }

  // 检查当前目录是否已收藏
  Future<void> _checkFavoriteStatus() async {
    if (_currentUsername == null) return;
    
    try {
      final currentDirectory = currentPath.join('/');
      final isFavorite = await DatabaseHelper.instance.isFavoriteDirectory(
        path: currentDirectory,
        userId: _currentUsername!.hashCode,
      );
      
      setState(() {
        _isFavorite = isFavorite;
      });
    } catch (e) {
      print('Failed to check favorite status: $e');
    }
  }

  // 收藏/取消收藏当前目录
  Future<void> _toggleFavorite() async {
    if (_currentUsername == null) return;
    
    final currentDirectory = currentPath.join('/');
    final directoryName = currentPath.last == '/' ? '主目录' : currentPath.last;
    
    try {
      if (_isFavorite) {
        // 取消收藏
        await DatabaseHelper.instance.removeFavoriteDirectory(
          path: currentDirectory,
          userId: _currentUsername!.hashCode,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消收藏')),
        );
      } else {
        // 添加收藏
        await DatabaseHelper.instance.addFavoriteDirectory(
          path: currentDirectory,
          name: directoryName,
          userId: _currentUsername!.hashCode,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到收藏夹')),
        );
      }
      
      setState(() {
        _isFavorite = !_isFavorite;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  void _handleError(String message) {
    setState(() {
      currentPath.removeLast();
      if (currentPath.isEmpty) {
        currentPath.add('/');
      }
    });
    toastification.show(
      style: ToastificationStyle.flat,
      type: ToastificationType.error,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  void _sort<T>(
    Comparable<T> Function(FileItem file) getField,
    int columnIndex,
    bool ascending,
  ) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;
      files.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        return ascending
            ? Comparable.compare(aValue, bValue)
            : Comparable.compare(bValue, aValue);
      });
    });
  }

  void _gotoVideo(FileItem file) {
    print("path: ${currentPath.join('/')}");
    print("name: ${file.name}");
    print("file: ${file}");
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => VideoPlayer(
              path: currentPath.join('/'),
              name: file.name,
            )));
  }
  

  
  // 获取中文星期几
  String _getChineseWeekday(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
  }
  
  // 构建带有不同颜色的播放进度文本
  List<TextSpan> _buildWatchProgressText(HistoricalRecord record) {
    // 计算进度百分比
    final progressPercent = (record.progressValue * 100).toStringAsFixed(0);
    
    // 格式化观看进度时间（分:秒）
    int minutes = 0;
    int seconds = 0;
    
    // 确保videoSeek有效
    if (record.videoSeek > 0) {
      // videoSeek是总秒数，直接计算分钟和剩余秒数
      minutes = (record.videoSeek / 60).floor();
      seconds = (record.videoSeek % 60).floor();
    }
    
    final progressTime = "$minutes分$seconds秒";
    
    // 格式化观看日期时间
    final now = DateTime.now();
    final changeTime = record.changeTime;
    final isSameYear = now.year == changeTime.year;
    
    // 获取星期几
    final weekday = _getChineseWeekday(changeTime.weekday);
    
    // 格式化日期，如果是今年则不显示年份
    final dateFormat = isSameYear 
        ? DateFormat('MM-dd $weekday HH:mm')
        : DateFormat('yyyy-MM-dd $weekday HH:mm');
    final formattedDate = dateFormat.format(changeTime);
    
    // 返回带有不同颜色的TextSpan列表
    return [
      const TextSpan(
        text: "观看至",
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue,
          height: 1.2,
        ),
      ),
      TextSpan(
        text: "$progressPercent%（$progressTime）$formattedDate 观看",
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
          height: 1.2,
        ),
      ),
    ];
  }

  // 执行搜索
  Future<void> _performSearch(
      StateSetter setState, List<FileItem> searchResults) async {
    if (_searchKeyword.trim().isEmpty) {
      setState(() {
        searchResults.clear();
      });
      return;
    }

    try {
      print('Searching with scope: $_searchScope');
      var res = await FsApi.search(
        keyword: _searchKeyword,
        parent: currentPath.join('/'),
        scope: _searchScope,
        page: 1,
        per_page: 100,
        password: '',
      );
      if (res.code == 200) {
        setState(() {
          searchResults.clear();
          searchResults.addAll(
            res.data?.content
                    ?.map((data) => FileItem(
                          type: data.type ?? -1,
                          sha1: data.hashInfo?.sha1 ?? '',
                          name: data.name ?? '',
                          size: data.size ?? 0,
                          modified: DateTime.tryParse(data.modified ?? '') ??
                              DateTime.now(),
                          parent: data.parent ?? currentPath.join('/'),
                        ))
                    .toList() ??
                [],
          );
        });
      } else {
        _handleError(res.message ?? '搜索失败');
      }
    } catch (e) {
      _handleError('搜索失败,请检查网络连接');
    }
  }

  void _showSearchDialog() {
    // 创建一个临时的搜索结果列表，改为类成员变量
    List<FileItem> dialogSearchResults = [];

    showDialog(
      context: context,
      builder: (context) {
        // 获取屏幕尺寸
        final size = MediaQuery.of(context).size;
        final dialogWidth = size.width * 0.8;
        final dialogHeight = size.height * 0.8;

        return Dialog(
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(24),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '请输入搜索关键词',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _searchKeyword = value;
                      if (value.trim().isNotEmpty) {
                        _performSearch(setState, dialogSearchResults);
                      } else {
                        setState(() {
                          dialogSearchResults.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildFilterOption(
                            context,
                            (value) {
                              setState(() {
                                _searchScope = value;
                                if (_searchKeyword.trim().isNotEmpty) {
                                  _performSearch(setState, dialogSearchResults);
                                }
                              });
                            },
                            0,
                            '全部',
                            Icons.apps,
                          ),
                        ),
                        Expanded(
                          child: _buildFilterOption(
                            context,
                            (value) {
                              setState(() {
                                _searchScope = value;
                                if (_searchKeyword.trim().isNotEmpty) {
                                  _performSearch(setState, dialogSearchResults);
                                }
                              });
                            },
                            1,
                            '文件夹',
                            Icons.folder,
                          ),
                        ),
                        Expanded(
                          child: _buildFilterOption(
                            context,
                            (value) {
                              setState(() {
                                _searchScope = value;
                                if (_searchKeyword.trim().isNotEmpty) {
                                  _performSearch(setState, dialogSearchResults);
                                }
                              });
                            },
                            2,
                            '文件',
                            Icons.insert_drive_file,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (dialogSearchResults.isNotEmpty) ...[
                    Text(
                      '搜索结果 (${dialogSearchResults.length})',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: dialogSearchResults.isEmpty
                        ? Center(
                            child: Text(
                              _searchKeyword.isEmpty ? '请输入搜索关键词' : '无搜索结果',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: dialogSearchResults.length,
                            itemBuilder: (context, index) {
                              final file = dialogSearchResults[index];
                              return _buildSearchResultItem(
                                context,
                                file,
                                _searchKeyword,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 构建搜索结果项
  Widget _buildSearchResultItem(
    BuildContext context,
    FileItem file,
    String keyword,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          if (file.type == 1) {
            // 构建完整路径
            List<String> newPath = ['/'];
            if (file.parent.isNotEmpty) {
              newPath.addAll(file.parent.split('/').where((e) => e.isNotEmpty));
            }
            newPath.add(file.name);

            setState(() {
              currentPath = newPath;
            });
            _getList();
          } else if (file.type == 2) {
            // 构建视频路径
            List<String> videoPath = ['/'];
            if (file.parent.isNotEmpty) {
              videoPath
                  .addAll(file.parent.split('/').where((e) => e.isNotEmpty));
            }

            print("Video path: ${videoPath.join('/')}");
            print("Video name: ${file.name}");

            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => VideoPlayer(
                path: videoPath.join('/'),
                name: file.name,
              ),
            ));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    file.type == 1 ? Icons.folder : Icons.insert_drive_file,
                    size: 20,
                    color: file.type == 1 ? Colors.blue : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHighlightedText(file.name, keyword),
                  ),
                  if (file.type == 2) ...[
                    const SizedBox(width: 12),
                    Text(
                      _formatSize(file.size),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                file.parent,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建高亮文本
  Widget _buildHighlightedText(String text, String keyword) {
    if (keyword.isEmpty) {
      return Text(text);
    }

    List<TextSpan> spans = [];
    int start = 0;
    String lowerText = text.toLowerCase();
    String lowerKeyword = keyword.toLowerCase();

    while (true) {
      int index = lowerText.indexOf(lowerKeyword, start);
      if (index == -1) {
        spans.add(TextSpan(
          text: text.substring(start),
          style: const TextStyle(fontSize: 14),
        ));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: const TextStyle(fontSize: 14),
        ));
      }

      spans.add(TextSpan(
        text: text.substring(index, index + keyword.length),
        style: const TextStyle(
          fontSize: 14,
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0x1A2196F3), // 浅蓝色背景
        ),
      ));

      start = index + keyword.length;
    }

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildFilterOption(
    BuildContext context,
    Function(int) onValueChanged,
    int value,
    String label,
    IconData icon,
  ) {
    final isSelected = _searchScope == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          print('Filter changed to: $value');
          onValueChanged(value);
        },
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: Theme.of(context).primaryColor, width: 1)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _loadCurrentUser();
    
    print('HomePage.initState: initialUrl=${widget.initialUrl}, initialTitle=${widget.initialTitle}');
    
    // 如果传入了初始URL，先使用该URL
    if (widget.initialUrl != null) {
      setState(() {
        currentPath = widget.initialUrl!.split('/')
          ..removeWhere((element) => element.isEmpty);
        if (currentPath.isEmpty) {
          currentPath = ['/'];
        } else {
          currentPath.insert(0, '/');
        }
      });
      print('HomePage.initState: 已设置路径 currentPath=${currentPath.join('/')}');
      _getList().then((_) => _animationController.forward());
    } else {
      // 否则加载默认路径
      print('HomePage.initState: 使用默认路径 [/]');
      _getList().then((_) => _animationController.forward());
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    print('HomePage.didUpdateWidget: 旧initialUrl=${oldWidget.initialUrl}, 新initialUrl=${widget.initialUrl}');
    
    // 当widget更新且initialUrl有变化时，重新加载目录
    if (widget.initialUrl != oldWidget.initialUrl && widget.initialUrl != null) {
      setState(() {
        currentPath = widget.initialUrl!.split('/')
          ..removeWhere((element) => element.isEmpty);
        if (currentPath.isEmpty) {
          currentPath = ['/'];
        } else {
          currentPath.insert(0, '/');
        }
      });
      print('HomePage.didUpdateWidget: 路径已更新 currentPath=${currentPath.join('/')}');
      _animationController.reset();
      _getList().then((_) => _animationController.forward());
    }
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUsername = prefs.getString('current_username');
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        title: _isSearchMode
            ? Text(
                '搜索: $_searchKeyword',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              )
            : const Text(
                'Alist Player',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          if (_isSearchMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearchMode = false;
                  _searchKeyword = '';
                });
                _getList();
              },
            )
          else ...[
            // 收藏夹按钮
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.star : Icons.star_border,
                color: _isFavorite ? Colors.amber : null,
              ),
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _showSearchDialog,
            ),
            if (files.isNotEmpty)
              IconButton(
                icon: Icon(_isSelectMode ? Icons.close : Icons.checklist),
                onPressed: () {
                  setState(() {
                    _isSelectMode = !_isSelectMode;
                    _selectedFiles.clear();
                  });
                },
              ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          // 美化后的面包屑导航栏
          _buildBreadcrumb(),
          if (_isSelectMode && _selectedFiles.isNotEmpty)
            _buildBatchOperationBar(),
          const Divider(height: 1.0),
          // 美化后的文件列表
          Expanded(
            child: files.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      // 表头
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: _buildTableHeader(isSmallScreen),
                      ),
                      // 文件列表
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _getList,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                              },
                            ),
                            child: ListView.builder(
                              itemCount: files.length,
                              itemBuilder: (context, index) =>
                                  _buildFileListItem(
                                files[index],
                                isSmallScreen,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // 空状态展示
  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _animationController,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutCubic,
        )),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 80, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                '文件夹为空',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前目录下没有文件',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 表头构建
  Widget _buildTableHeader(bool isSmallScreen) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.1, 0.7, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.1, 0.7),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 8,
              child: InkWell(
                onTap: () {
                  final isAsc = _sortColumnIndex != 0 || !_isAscending;
                  _sort((file) => file.name, 0, isAsc);
                },
                child: Row(
                  children: [
                    Text(
                      '文件名称',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_sortColumnIndex == 0)
                      Icon(
                        _isAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                  ],
                ),
              ),
            ),
            if (!isSmallScreen) ...[
              SizedBox(
                width: 100,
                child: InkWell(
                  onTap: () {
                    final isAsc = _sortColumnIndex != 1 || !_isAscending;
                    _sort((file) => file.size, 1, isAsc);
                  },
                  child: Row(
                    children: [
                      Text(
                        '大小',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_sortColumnIndex == 1)
                        Icon(
                          _isAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: InkWell(
                  onTap: () {
                    final isAsc = _sortColumnIndex != 2 || !_isAscending;
                    _sort((file) => file.modified.millisecondsSinceEpoch, 2,
                        isAsc);
                  },
                  child: Row(
                    children: [
                      Text(
                        '修改时间',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_sortColumnIndex == 2)
                        Icon(
                          _isAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 文件列表项构建
  Widget _buildFileListItem(FileItem file, bool isSmallScreen) {
    final textColor = Colors.grey[800];
    final isLocal = file.type == 2 && _localFiles.contains(file.name);

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.2, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          0.2 + (files.indexOf(file) / files.length) * 0.6,
          1.0,
          curve: Curves.easeOutCubic,
        ),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            0.2 + (files.indexOf(file) / files.length) * 0.6,
            1.0,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _selectedFiles.contains(file)
                ? Colors.blue.withOpacity(0.1)
                : Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey[100]!),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (_isSelectMode) {
                  setState(() {
                    if (_selectedFiles.contains(file)) {
                      _selectedFiles.remove(file);
                    } else {
                      _selectedFiles.add(file);
                    }
                  });
                } else {
                  if (file.type == 1) {
                    setState(() {
                      currentPath.add(file.name);
                    });
                    _animationController.reset();
                    _getList().then((_) => _animationController.forward());
                  } else if (file.type == 2) {
                    _gotoVideo(file);
                  }
                }
              },
              hoverColor: Colors.blue.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  children: [
                    if (_isSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Checkbox(
                          value: _selectedFiles.contains(file),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedFiles.add(file);
                              } else {
                                _selectedFiles.remove(file);
                              }
                            });
                          },
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          // 文件图标
                          SizedBox(
                            width: 24,
                            child: _getIconForFile(file.name),
                          ),
                          const SizedBox(width: 12),
                          
                          // 本地文件标识 (放在文件名前面)
                          if (isLocal)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Tooltip(
                                message: '已下载到本地',
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.download_done,
                                    color: Colors.green,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          
                          // 文件名称和播放进度
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textColor,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // 如果有播放历史记录，显示播放进度
                                if (file.type == 2 && file.historyRecord != null) ...[  
                                  const SizedBox(height: 4),
                                  // 使用RichText来设置不同部分的文本颜色
                                  RichText(
                                    text: TextSpan(
                                      children: _buildWatchProgressText(file.historyRecord!),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isSmallScreen) ...[
                      SizedBox(
                        width: 100,
                        child: Text(
                          _formatSize(file.size),
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          _formatDate(file.modified),
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 日期格式化
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Icon _getIconForFile(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    const double iconSize = 20.0;

    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return const Icon(Icons.image, color: Colors.blue, size: iconSize);
      case 'mp4':
      case 'avi':
      case 'mkv':
        return const Icon(Icons.video_collection,
            color: Colors.blue, size: iconSize);
      case 'mp3':
      case 'wav':
      case 'flac':
        return const Icon(Icons.audiotrack,
            color: Colors.green, size: iconSize);
      case 'pdf':
        return const Icon(Icons.picture_as_pdf,
            color: Colors.orange, size: iconSize);
      case 'doc':
      case 'docx':
      case 'txt':
        return const Icon(Icons.description,
            color: Colors.grey, size: iconSize);
      case '':
        return const Icon(Icons.folder, color: Colors.blue, size: iconSize);
      default:
        return const Icon(Icons.folder, color: Colors.blue, size: iconSize);
    }
  }

  // 面包屑导航动画
  Widget _buildBreadcrumb() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -0.2),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0, 0.6),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // 刷新按钮
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _getList(refresh: true),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 20.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16.0),
              // 面包屑导航
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(
                        currentPath.length,
                        (index) {
                          final isLast = index == currentPath.length - 1;
                          return Row(
                            children: [
                              // 面包屑项
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    currentPath =
                                        currentPath.sublist(0, index + 1);
                                  });
                                  _getList();
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 6.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isLast
                                        ? Theme.of(context)
                                            .primaryColor
                                            .withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currentPath[index] == '/'
                                        ? '主目录'
                                        : currentPath[index],
                                    style: TextStyle(
                                      color: isLast
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey[600],
                                      fontWeight: isLast
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              // 分隔符
                              if (!isLast)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: Colors.grey[400],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void loadUrl(String url, String? title) {
    setState(() {
      currentPath = url.split('/')..removeWhere((element) => element.isEmpty);
      if (currentPath.isEmpty) {
        currentPath = ['/'];
      } else {
        currentPath.insert(0, '/');
      }
    });
    _getList();
  }

  Widget _buildBatchOperationBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('已选择 ${_selectedFiles.length} 项'),
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('批量下载'),
            onPressed: () {
              for (var file in _selectedFiles) {
                if (file.type == 2) {
                  print('${currentPath.join('/').substring(1)}/${file.name}');
                  // 只下载文件，不下载文件夹
                  DownloadManager().addTask(
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
        ],
      ),
    );
  }
}

class FileItem {
  final String name;
  final int size;
  final DateTime modified;
  final int type;
  final String sha1;
  final String parent;
  HistoricalRecord? historyRecord; // 添加历史记录字段

  FileItem({
    required this.name,
    required this.size,
    required this.modified,
    required this.type,
    required this.sha1,
    required this.parent,
    this.historyRecord,
  });
}
