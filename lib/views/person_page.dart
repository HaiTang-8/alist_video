import 'package:alist_player/main.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/settings/playback_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/views/storage_page.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('current_username') ?? '';
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
                                    child: const Text(
                                      '普通用户',
                                      style: TextStyle(
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
                  onTap: () => _showDatabaseSettings(),
                ),
                _buildMenuItem(
                  icon: Icons.api_rounded,
                  title: 'API 设置',
                  onTap: () => _showApiSettings(),
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

  Future<void> _showDatabaseSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final currentHost =
        prefs.getString(AppConstants.dbHostKey) ?? AppConstants.defaultDbHost;
    final currentName =
        prefs.getString(AppConstants.dbNameKey) ?? AppConstants.defaultDbName;
    final currentUser =
        prefs.getString(AppConstants.dbUserKey) ?? AppConstants.defaultDbUser;
    final currentPassword = prefs.getString(AppConstants.dbPasswordKey) ??
        AppConstants.defaultDbPassword;
    final currentPort =
        prefs.getInt(AppConstants.dbPortKey) ?? AppConstants.defaultDbPort;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => DatabaseSettingsDialog(
        host: currentHost,
        name: currentName,
        user: currentUser,
        password: currentPassword,
        port: currentPort,
      ),
    );
  }

  Future<void> _showApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBaseUrl =
        prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;
    final currentBaseDownloadUrl =
        prefs.getString(AppConstants.baseDownloadUrlKey) ??
            AppConstants.defaultBaseDownloadUrl;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => ApiSettingsDialog(
        baseUrl: currentBaseUrl,
        baseDownloadUrl: currentBaseDownloadUrl,
      ),
    );
  }
}

class DatabaseSettingsDialog extends StatefulWidget {
  final String host;
  final String name;
  final String user;
  final String password;
  final int port;

  const DatabaseSettingsDialog({
    super.key,
    required this.host,
    required this.name,
    required this.user,
    required this.password,
    required this.port,
  });

  @override
  State<DatabaseSettingsDialog> createState() => _DatabaseSettingsDialogState();
}

class _DatabaseSettingsDialogState extends State<DatabaseSettingsDialog> {
  late TextEditingController _hostController;
  late TextEditingController _nameController;
  late TextEditingController _userController;
  late TextEditingController _passwordController;
  late TextEditingController _portController;
  bool _isTesting = false;
  final _baseUrlController = TextEditingController();
  final _baseDownloadUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.host);
    _nameController = TextEditingController(text: widget.name);
    _userController = TextEditingController(text: widget.user);
    _passwordController = TextEditingController(text: widget.password);
    _portController = TextEditingController(text: widget.port.toString());
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text =
          prefs.getString(AppConstants.dbHostKey) ?? AppConstants.defaultDbHost;
      _nameController.text =
          prefs.getString(AppConstants.dbNameKey) ?? AppConstants.defaultDbName;
      _userController.text =
          prefs.getString(AppConstants.dbUserKey) ?? AppConstants.defaultDbUser;
      _passwordController.text = prefs.getString(AppConstants.dbPasswordKey) ??
          AppConstants.defaultDbPassword;
      _portController.text = prefs.getInt(AppConstants.dbPortKey)?.toString() ??
          AppConstants.defaultDbPort.toString();
      _baseUrlController.text = prefs.getString(AppConstants.baseUrlKey) ??
          AppConstants.defaultBaseUrl;
      _baseDownloadUrlController.text =
          prefs.getString(AppConstants.baseDownloadUrlKey) ??
              AppConstants.defaultBaseDownloadUrl;
    });
  }

  Future<void> _saveSettings(BuildContext context) async {
    setState(() {
      _isTesting = true;
    });

    try {
      // 创建一个临时的数据库连接进行测试
      final db = DatabaseHelper.instance;
      await db.init(
        host: _hostController.text,
        port: int.parse(_portController.text),
        database: _nameController.text,
        username: _userController.text,
        password: _passwordController.text,
      );

      // 测试连接
      await db.query('SELECT 1');

      // 连接成功，保存设置
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(AppConstants.dbHostKey, _hostController.text),
        prefs.setString(AppConstants.dbNameKey, _nameController.text),
        prefs.setString(AppConstants.dbUserKey, _userController.text),
        prefs.setString(AppConstants.dbPasswordKey, _passwordController.text),
        prefs.setInt(AppConstants.dbPortKey, int.parse(_portController.text)),
        prefs.setString(AppConstants.baseUrlKey, _baseUrlController.text),
        prefs.setString(
            AppConstants.baseDownloadUrlKey, _baseDownloadUrlController.text),
      ]);

      // 使用新的配置重新初始化数据库连接
      await DatabaseHelper.instance.close(); // 先关闭现有连��
      await DatabaseHelper.instance.init(
        host: _hostController.text,
        port: int.parse(_portController.text),
        database: _nameController.text,
        username: _userController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      // 显示成功息并关闭对话框
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('数据库设置已保存并重新连接'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // 显示错误消息
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[700]),
              const SizedBox(width: 8),
              const Text('连接失败'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('无法连接到数据库，请检查以下内容：'),
              const SizedBox(height: 8),
              Text('• 主机地址和端口是否正确', style: TextStyle(color: Colors.grey[600])),
              Text('• 数据库名称是否存在', style: TextStyle(color: Colors.grey[600])),
              Text('• 用户名和密码是否正确', style: TextStyle(color: Colors.grey[600])),
              Text('• 数据库服务是否正常运行', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              Text(
                '错误详情：${e.toString()}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  '数据库设置',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '配置数据库连接信息',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _hostController,
              label: '主机地址',
              icon: Icons.dns_rounded,
              hint: '例如: localhost 或 192.168.1.100',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTextField(
                    controller: _nameController,
                    label: '数据库名',
                    icon: Icons.storage_rounded,
                    hint: '数据库名称',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _portController,
                    label: '端口',
                    icon: Icons.numbers_rounded,
                    hint: '3306',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _userController,
              label: '用户名',
              icon: Icons.person_outline_rounded,
              hint: '据库用户名',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: '密码',
              icon: Icons.lock_outline_rounded,
              hint: '数据库密码',
              obscureText: true,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isTesting ? null : () => _saveSettings(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isTesting)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.save_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _isTesting ? '测试连接中...' : '保存设置',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Text('API 设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: '基础 URL',
                hintText: '例如: https://alist.tt1.top',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseDownloadUrlController,
              decoration: const InputDecoration(
                labelText: '下载 URL',
                hintText: '例如: https://alist.tt1.top/d',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _nameController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _baseUrlController.dispose();
    _baseDownloadUrlController.dispose();
    super.dispose();
  }
}

class ApiSettingsDialog extends StatefulWidget {
  final String baseUrl;
  final String baseDownloadUrl;

  const ApiSettingsDialog({
    super.key,
    required this.baseUrl,
    required this.baseDownloadUrl,
  });

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  late TextEditingController _baseUrlController;
  late TextEditingController _baseDownloadUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.baseUrl);
    _baseDownloadUrlController =
        TextEditingController(text: widget.baseDownloadUrl);
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(AppConstants.baseUrlKey, _baseUrlController.text),
        prefs.setString(
            AppConstants.baseDownloadUrlKey, _baseDownloadUrlController.text),
      ]);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API 设置已保存'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.api_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'API 设置',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '配置 AList API 地址',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _baseUrlController,
              label: '基础 URL',
              icon: Icons.link_rounded,
              hint: '例如: https://alist.example.com',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _baseDownloadUrlController,
              label: '播放 URL',
              icon: Icons.download_rounded,
              hint: '例如: https://alist.example.com/d',
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.save_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _isSaving ? '保存中...' : '保存设置',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _baseDownloadUrlController.dispose();
    super.dispose();
  }
}
