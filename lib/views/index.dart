import 'package:flutter/material.dart';
import 'package:webdav_video/views/history_page.dart';
import 'package:webdav_video/views/home_page.dart';
import 'package:webdav_video/views/person_page.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});
  @override
  State<IndexPage> createState() => _IndexState();
}

class _IndexState extends State<IndexPage> {
  final List<BottomNavigationBarItem> bottomNavItems = [
    const BottomNavigationBarItem(
      backgroundColor: Colors.blue,
      icon: Icon(Icons.home),
      label: "首页",
    ),
    const BottomNavigationBarItem(
      backgroundColor: Colors.green,
      icon: Icon(Icons.history),
      label: "历史记录",
    ),
    const BottomNavigationBarItem(
      backgroundColor: Colors.red,
      icon: Icon(Icons.person),
      label: "个人中心",
    ),
  ];

  late int currentIndex;

  final pages = [const HomePage(), const HistoryPage(), const PersonPage()];

  @override
  void initState() {
    super.initState();
    currentIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        items: bottomNavItems,
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          _changePage(index);
        },
      ),
      body: pages[currentIndex],
    );
  }

  /*切换页面*/
  void _changePage(int index) {
    /*如果点击的导航项不是当前项  切换 */
    if (index != currentIndex) {
      setState(() {
        currentIndex = index;
      });
    }
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
