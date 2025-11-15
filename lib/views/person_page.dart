import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/main.dart';
import 'package:alist_player/utils/woo_http.dart';
import 'package:alist_player/views/disk_usage_page.dart';
import 'package:alist_player/views/admin/admin_dashboard_page.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';
import 'package:alist_player/views/settings/database_api_settings.dart';
import 'package:alist_player/views/settings/playback_settings_page.dart';
import 'package:alist_player/views/settings/shared_preferences_viewer.dart';
import 'package:alist_player/views/settings/remote_config_page.dart';
import 'package:alist_player/views/storage_page.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage>
    with AutomaticKeepAliveClientMixin {
  String _username = '';
  bool _isAdmin = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('current_username') ?? '';
      final role = prefs.getInt(AppConstants.userRoleKey) ?? 0;
      _isAdmin = role == AppConstants.adminRoleValue;
    });
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove('current_username'),
        prefs.remove('remember_me'),
        prefs.remove('token'),
        prefs.remove('base_path'),
        prefs.remove(AppConstants.userRoleKey),
        prefs.remove(AppConstants.userPermissionKey),
      ]);
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景渐变
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.8),
                          Theme.of(context).primaryColor.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  // 装饰图案
                  Positioned(
                    right: -50,
                    top: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ),
                  // 用户信息
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 40,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _username.isNotEmpty
                                      ? _username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _username,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          offset: Offset(0, 2),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _isAdmin ? '管理员' : '普通用户',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildSectionTitle('设置'),
                if (_isAdmin)
                  _buildMenuItem(
                    icon: Icons.dashboard_customize,
                    title: '全局运营面板',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminDashboardPage(),
                        ),
                      );
                    },
                  ),
                _buildMenuItem(
                  icon: Icons.pie_chart_outline,
                  title: '磁盘使用统计',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DiskUsagePage(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.video_settings,
                  title: '播放设置',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PlaybackSettingsPage(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.storage,
                  title: '数据库设置',
                  onTap: () => DatabaseSettingsDialog.show(context),
                ),
                _buildMenuItem(
                  icon: Icons.api_rounded,
                  title: 'API 设置',
                  onTap: () => ApiPresetSettingsDialog.show(context),
                ),
                _buildMenuItem(
                  icon: Icons.sync_alt_rounded,
                  title: '远程配置',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RemoteConfigPage(),
                    ),
                  ),
                ),
                _buildMenuItem(
                  icon: Icons.data_usage,
                  title: '共享首选项查看器',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SharedPreferencesViewer(),
                    ),
                  ),
                ),
                _buildMenuItem(
                  icon: Icons.cloud_queue_rounded,
                  title: '存储管理',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StoragePage(),
                    ),
                  ),
                ),
                const Divider(),
                _buildSectionTitle('其他'),
                _buildMenuItem(
                  icon: Icons.info_outline,
                  title: '关于',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AboutDialog(
                        applicationName: 'AList Player',
                        applicationVersion: 'v1.0.0',
                        applicationIcon: const Icon(
                          Icons.play_circle_outline,
                          size: 48,
                          color: Colors.blue,
                        ),
                        children: [
                          const SizedBox(height: 16),
                          const Text(
                              'AList Player 是一个基于 AList 的在线视频播放器，支持在线播放和视频进度记录等功能。'),
                          const SizedBox(height: 8),
                          const Text('© 2024 AList Player'),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('项目地址'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.exit_to_app,
                  title: '退出登录',
                  textColor: Colors.red,
                  onTap: () => _logout(context),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('打开日志文件夹'),
                  onTap: WooHttpUtil.openLogDirectory,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('清除日志文件'),
                  onTap: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认'),
                        content: const Text('确定要清除所有日志文件吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    );
                    if (result == true) {
                      await WooHttpUtil.clearLogs();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Colors.grey[800],
          fontSize: 16,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey[400],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[800],
        ),
      ),
    );
  }
}
