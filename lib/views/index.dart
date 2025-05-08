import 'package:alist_player/views/favorites_page.dart';
import 'package:alist_player/views/history_page.dart';
import 'package:alist_player/views/home_page.dart';
import 'package:alist_player/views/person_page.dart';
import 'package:alist_player/views/downloads_page.dart';
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';

class IndexPage extends StatefulWidget {
  // 静态实例用于访问当前激活的IndexPage状态
  static _IndexState? currentState;
  
  const IndexPage({super.key});
  
  // 静态方法用于页面间导航
  static void navigateToHome(BuildContext context, String path, String? title) {
    print('IndexPage.navigateToHome 被调用: path=$path, title=$title');
    if (currentState != null) {
      print('找到当前IndexPage状态，执行导航');
      currentState!.navigateToHomeWithPath(path, title);
    } else {
      print('未找到当前IndexPage状态，导航失败');
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
  String? _pendingPath;
  String? _pendingTitle;
  
  @override
  void initState() {
    super.initState();
    // 注册为当前活动实例
    IndexPage.currentState = this;
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
    print('_IndexState.navigateToHomeWithPath 被调用: path=$path, title=$title, 当前索引=$_selectedIndex');
    setState(() {
      _pendingPath = path;
      _pendingTitle = title;
      _selectedIndex = 0; // 切换到首页
    });
    print('导航状态已更新: _pendingPath=$_pendingPath, _pendingTitle=$_pendingTitle, _selectedIndex=$_selectedIndex');
  }

  @override
  Widget build(BuildContext context) {
    // 构建主页面时考虑是否有待处理的路径
    print('IndexPage.build: _pendingPath=$_pendingPath, _pendingTitle=$_pendingTitle, _selectedIndex=$_selectedIndex');
    
    // 根据选中的索引确定当前应该显示的页面
    Widget currentPage;
    switch (_selectedIndex) {
      case 0:
        currentPage = HomePage(
          key: ValueKey('home-${_pendingPath ?? "root"}'),
          initialUrl: _pendingPath,
          initialTitle: _pendingTitle,
        );
        break;
      case 1:
        currentPage = const FavoritesPage();
        break;
      case 2:
        currentPage = const HistoryPage();
        break;
      case 3:
        currentPage = const DownloadsPage();
        break;
      case 4:
        currentPage = const PersonPage();
        break;
      default:
        currentPage = const HomePage();
    }
    
    return Scaffold(
      body: currentPage,
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
                // 如果切换到其他页面，清除待处理的路径
                if (index != 0) {
                  _pendingPath = null;
                  _pendingTitle = null;
                }
                _selectedIndex = index;
              });
            },
          );
        },
      ),
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
