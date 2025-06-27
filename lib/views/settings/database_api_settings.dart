import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';
import 'package:alist_player/views/settings/database_preset_settings_dialog.dart';

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

  static Future<void> show(BuildContext context) async {
    // 使用新的数据库预设设置对话框
    await DatabasePresetSettingsDialog.show(context);
  }

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
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.host);
    _nameController = TextEditingController(text: widget.name);
    _userController = TextEditingController(text: widget.user);
    _passwordController = TextEditingController(text: widget.password);
    _portController = TextEditingController(text: widget.port.toString());
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
      ]);

      // 使用新的配置重新初始化数据库连接
      await DatabaseHelper.instance.close(); // 先关闭现有连接
      await DatabaseHelper.instance.init(
        host: _hostController.text,
        port: int.parse(_portController.text),
        database: _nameController.text,
        username: _userController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      // 显示成功消息并关闭对话框
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
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return _buildMobileLayout(context);
    } else {
      return _buildDesktopLayout(context);
    }
  }

  /// 构建移动端布局
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库设置'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _isTesting ? null : () => _saveSettings(context),
            icon: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: _isTesting ? '测试连接中...' : '保存设置',
          ),
        ],
      ),
      body: _buildFormContent(context, true),
    );
  }

  /// 构建桌面端布局
  Widget _buildDesktopLayout(BuildContext context) {
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
            _buildFormContent(context, false),
            const SizedBox(height: 32),
            _buildDesktopButtons(context),
          ],
        ),
      ),
    );
  }

  /// 构建表单内容
  Widget _buildFormContent(BuildContext context, bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 0.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              const SizedBox(height: 8),
              Text(
                '配置数据库连接信息',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
            ],
            _buildTextField(
              controller: _hostController,
              label: '主机地址',
              icon: Icons.dns_rounded,
              hint: '例如: localhost 或 192.168.1.100',
              isMobile: isMobile,
            ),
            SizedBox(height: isMobile ? 20 : 16),
            if (isMobile) ...[
              // 移动端垂直布局
              _buildTextField(
                controller: _nameController,
                label: '数据库名',
                icon: Icons.storage_rounded,
                hint: '数据库名称',
                isMobile: isMobile,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _portController,
                label: '端口',
                icon: Icons.numbers_rounded,
                hint: '3306',
                keyboardType: TextInputType.number,
                isMobile: isMobile,
              ),
            ] else ...[
              // 桌面端水平布局
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _nameController,
                      label: '数据库名',
                      icon: Icons.storage_rounded,
                      hint: '数据库名称',
                      isMobile: isMobile,
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
                      isMobile: isMobile,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: isMobile ? 20 : 16),
            _buildTextField(
              controller: _userController,
              label: '用户名',
              icon: Icons.person_outline_rounded,
              hint: '数据库用户名',
              isMobile: isMobile,
            ),
            SizedBox(height: isMobile ? 20 : 16),
            _buildTextField(
              controller: _passwordController,
              label: '密码',
              icon: Icons.lock_outline_rounded,
              hint: '数据库密码',
              obscureText: !_showPassword,
              isMobile: isMobile,
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[400],
                  size: isMobile ? 24 : 20,
                ),
                onPressed: () {
                  setState(() {
                    _showPassword = !_showPassword;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建桌面端按钮
  Widget _buildDesktopButtons(BuildContext context) {
    return Row(
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
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    bool isMobile = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 16 : 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: isMobile ? 12 : 8),
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
              prefixIcon: Icon(
                icon,
                color: Colors.grey[400],
                size: isMobile ? 24 : 20,
              ),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isMobile ? 16 : 12,
              ),
            ),
            style: TextStyle(fontSize: isMobile ? 16 : 15),
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
    super.dispose();
  }
}

class ApiSettingsDialog {
  static Future<void> show(BuildContext context) async {
    // 使用新的API预设设置对话框
    await ApiPresetSettingsDialog.show(context);
  }
}








