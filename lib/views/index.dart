import 'package:alist_player/views/favorites_page.dart';
import 'package:alist_player/views/history_page.dart';
import 'package:alist_player/views/home_page.dart';
import 'package:alist_player/views/person_page.dart';
import 'package:alist_player/views/downloads_page.dart';
import 'package:flutter/material.dart';
import 'package:alist_player/utils/logger.dart';
import '../utils/download_manager.dart';

/// Index 页统一日志方法，方便定位多 Tab 导航问题
void _logIndex(
  String message, {
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger().captureConsoleOutput(
    'IndexPage',
    message,
    level: level,
    error: error,
    stackTrace: stackTrace,
  );
}

class IndexPage extends StatefulWidget {
  // 静态实例用于访问当前激活的IndexPage状态
  static _IndexState? currentState;

  const IndexPage({super.key});

  // 静态方法用于页面间导航
  static void navigateToHome(BuildContext context, String path, String? title) {
    _logIndex('navigateToHome 被调用 path=$path, title=$title',
        level: LogLevel.debug);
    if (currentState != null) {
      _logIndex('找到当前 IndexPage 状态，执行导航', level: LogLevel.debug);
      currentState!.navigateToHomeWithPath(path, title);
    } else {
      _logIndex('未找到当前 IndexPage 状态，导航失败', level: LogLevel.warning);
      // 降级处理，直接导航到新页面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => HomePage(
            initialUrl: path,
            initialTitle: title,
          ),
        ),
      );
    }
  }

  @override
  State<IndexPage> createState() => _IndexState();
}

class _IndexState extends State<IndexPage> {
  int _selectedIndex = 0;

  // 保存页面实例，避免重复创建
  late final List<Widget> _pages;
  late final GlobalKey<_HomePageWrapperState> _homePageKey;

  @override
  void initState() {
    super.initState();
    // 注册为当前活动实例
    IndexPage.currentState = this;

    // 初始化页面key
    _homePageKey = GlobalKey<_HomePageWrapperState>();

    // 初始化页面列表
    _pages = [
      _HomePageWrapper(key: _homePageKey),
      const FavoritesPage(),
      const HistoryPage(),
      const DownloadsPage(),
      const PersonPage(),
    ];
  }

  @override
  void dispose() {
    // 移除引用，避免内存泄漏
    if (IndexPage.currentState == this) {
      IndexPage.currentState = null;
    }
    super.dispose();
  }

  // 添加方法，允许其他页面直接切换到主页并加载指定路径
  void navigateToHomeWithPath(String path, String? title) {
    _logIndex(
      '_IndexState.navigateToHomeWithPath path=$path, title=$title, 当前索引=$_selectedIndex',
      level: LogLevel.debug,
    );

    // 通知HomePage更新路径
    _homePageKey.currentState?.updatePath(path, title);

    setState(() {
      _selectedIndex = 0; // 切换到首页
    });
    _logIndex(
      '导航状态已更新 path=$path, title=$title, _selectedIndex=$_selectedIndex',
      level: LogLevel.debug,
    );
  }

  @override
  Widget build(BuildContext context) {
    _logIndex('build: _selectedIndex=$_selectedIndex', level: LogLevel.debug);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: ValueListenableBuilder<Map<String, DownloadTask>>(
        valueListenable: DownloadManager().tasks,
        builder: (context, tasks, child) {
          final downloadingCount =
              tasks.values.where((task) => task.status == '下载中').length;
          final completedCount =
              tasks.values.where((task) => task.status == '已完成').length;

          return BottomNavigationBar(
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: '首页',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.star),
                label: '收藏',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: '历史',
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: downloadingCount > 0 || completedCount > 0,
                  label: Text(
                    downloadingCount > 0
                        ? '$downloadingCount'
                        : '$completedCount',
                  ),
                  backgroundColor:
                      downloadingCount > 0 ? Colors.blue : Colors.green,
                  child: const Icon(Icons.download),
                ),
                label: '下载',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: '我的',
              ),
            ],
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          );
        },
      ),
    );
  }
}

// HomePage包装器，用于保持状态并支持动态路径更新
class _HomePageWrapper extends StatefulWidget {
  const _HomePageWrapper({super.key});

  @override
  State<_HomePageWrapper> createState() => _HomePageWrapperState();
}

class _HomePageWrapperState extends State<_HomePageWrapper> {
  String? _currentPath;
  String? _currentTitle;

  void updatePath(String? path, String? title) {
    if (mounted) {
      setState(() {
        _currentPath = path;
        _currentTitle = title;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomePage(
      key: ValueKey('home-${_currentPath ?? "root"}'),
      initialUrl: _currentPath,
      initialTitle: _currentTitle,
    );
  }
}

class Index extends StatelessWidget {
  const Index({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter入门示例程序',
      theme: ThemeData(
        primaryColor: Colors.blue,
      ),
      home: const IndexPage(),
    );
  }
}
