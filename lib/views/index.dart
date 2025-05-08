import 'package:alist_player/views/favorites_page.dart';
import 'package:alist_player/views/history_page.dart';
import 'package:alist_player/views/home_page.dart';
import 'package:alist_player/views/person_page.dart';
import 'package:alist_player/views/downloads_page.dart';
import 'package:flutter/material.dart';
import '../utils/download_manager.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});
  @override
  State<IndexPage> createState() => _IndexState();
}

class _IndexState extends State<IndexPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          HomePage(),
          FavoritesPage(),
          HistoryPage(),
          DownloadsPage(),
          PersonPage(),
        ],
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
