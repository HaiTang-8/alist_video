import 'dart:ui';

import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/views/video_player.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class HomePage extends StatefulWidget {
  final String? initialUrl;
  final String? initialTitle;

  const HomePage({
    Key? key,
    this.initialUrl,
    this.initialTitle,
  }) : super(key: key);

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
                      ))
                  .toList() ??
              [];
        });
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
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => VideoPlayer(
              path: currentPath.join('/'),
              name: file.name,
            )));
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _getList().then((_) => _animationController.forward());
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        loadUrl(widget.initialUrl!, widget.initialTitle);
      });
    }
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
        title: const Text(
          'Alist Player',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: <Widget>[
          // 美化后的面包屑导航栏
          _buildBreadcrumb(),
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
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey[100]!),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (file.type == 1) {
                  setState(() {
                    currentPath.add(file.name);
                  });
                  _animationController.reset();
                  _getList().then((_) => _animationController.forward());
                } else if (file.type == 2) {
                  _gotoVideo(file);
                }
              },
              hoverColor: Colors.blue.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 文件名称列
                    Expanded(
                      flex: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            child: _getIconForFile(file.name),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              file.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 在大屏幕上显示额外信息
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

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
}

class FileItem {
  final String name;
  final int size;
  final DateTime modified;
  final int type;
  final String sha1;

  FileItem(
      {required this.name,
      required this.size,
      required this.modified,
      required this.type,
      required this.sha1});
}
