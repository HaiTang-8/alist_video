import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/network_scanner.dart';
import 'package:alist_player/utils/woo_http.dart';

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

    if (!context.mounted) return;

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
              hint: '数据库用户名',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: '密码',
              icon: Icons.lock_outline_rounded,
              hint: '数据库密码',
              obscureText: !_showPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[400],
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _showPassword = !_showPassword;
                  });
                },
              ),
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
    Widget? suffixIcon,
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
              suffixIcon: suffixIcon,
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

  static Future<void> show(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentBaseUrl =
        prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;
    final currentBaseDownloadUrl =
        prefs.getString(AppConstants.baseDownloadUrlKey) ??
            AppConstants.defaultBaseDownloadUrl;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => ApiSettingsDialog(
        baseUrl: currentBaseUrl,
        baseDownloadUrl: currentBaseDownloadUrl,
      ),
    );
  }

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  late TextEditingController _baseUrlController;
  late TextEditingController _baseDownloadUrlController;
  bool _isSaving = false;
  bool _isScanning = false;
  int _scanProgress = 0;
  int _scanMax = 100;
  List<NetworkDevice> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.baseUrl);
    _baseDownloadUrlController =
        TextEditingController(text: widget.baseDownloadUrl);
  }

  // 扫描局域网设备
  Future<void> _scanLocalDevices() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _scanMax = 255;
      _discoveredDevices = [];
    });

    try {
      final scanner = NetworkScanner();
      final devices = await scanner.scanDevices(
        onProgress: (current, max) {
          setState(() {
            _scanProgress = current;
            _scanMax = max;
          });
        },
        // AList默认端口是5244
        port: 5244,
        timeout: const Duration(milliseconds: 100),
      );

      setState(() {
        _discoveredDevices = devices;
      });
      
      if (_discoveredDevices.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未发现局域网设备'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        // 显示设备选择对话框
        if (!mounted) return;
        _showDeviceSelectionDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('扫描出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  // 显示设备选择对话框
  void _showDeviceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.devices_rounded,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              const Text('选择局域网设备'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _discoveredDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '未发现设备',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = _discoveredDevices[index];
                      
                      // 检测设备状态
                      _checkDeviceStatus(device, setState);
                      
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: device.isLocalDevice
                                ? Colors.purple.shade200
                                : device.status == DeviceStatus.online
                                    ? Colors.green.shade200
                                    : device.status == DeviceStatus.offline
                                        ? Colors.red.shade200
                                        : Colors.grey.shade200,
                            width: device.isLocalDevice ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Icon(
                            device.isLocalDevice
                                ? Icons.computer_outlined
                                : Icons.devices_other_rounded,
                            color: device.isLocalDevice
                                ? Colors.purple
                                : device.status == DeviceStatus.online
                                    ? Colors.green
                                    : device.status == DeviceStatus.offline
                                        ? Colors.red
                                        : Colors.grey,
                            size: 36,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  device.ip,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: device.isLocalDevice ? Colors.purple : null,
                                  ),
                                ),
                              ),
                              if (device.isLocalDevice)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '本机',
                                    style: TextStyle(
                                      color: Colors.purple.shade700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (device.deviceName != null && !device.isLocalDevice)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    device.deviceName!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text('响应时间: ${device.responseTime.inMilliseconds}ms'),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: device.isLocalDevice
                                          ? Colors.purple
                                          : device.status == DeviceStatus.online
                                              ? Colors.green
                                              : device.status == DeviceStatus.offline
                                                  ? Colors.red
                                                  : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    device.isLocalDevice
                                        ? '本机'
                                        : device.status == DeviceStatus.online
                                            ? '在线'
                                            : device.status == DeviceStatus.offline
                                                ? '离线'
                                                : '未知',
                                    style: TextStyle(
                                      color: device.isLocalDevice
                                          ? Colors.purple
                                          : device.status == DeviceStatus.online
                                              ? Colors.green
                                              : device.status == DeviceStatus.offline
                                                  ? Colors.red
                                                  : Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: device.status == DeviceStatus.online
                              ? () {
                                  _selectDevice(device);
                                  Navigator.pop(context);
                                }
                              : null,
                          enabled: device.status == DeviceStatus.online,
                          trailing: device.status == DeviceStatus.online
                              ? const Icon(Icons.arrow_forward_ios, size: 16)
                              : device.status == DeviceStatus.unknown
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                // 重新扫描
                Navigator.pop(context);
                _scanLocalDevices();
              },
              child: const Text('重新扫描'),
            ),
          ],
        ),
      ),
    );
  }

  // 检查设备状态
  Future<void> _checkDeviceStatus(NetworkDevice device, StateSetter setState) async {
    if (device.status == DeviceStatus.unknown) {
      // 异步检查设备状态
      Future.microtask(() async {
        await device.checkStatus();
        setState(() {});
      });
    }
  }

  // 选择设备
  void _selectDevice(NetworkDevice device) {
    setState(() {
      // 更新URL，使用选中的IP地址
      final String baseUrl = 'http://${device.ip}:5244';
      final String baseDownloadUrl = 'http://${device.ip}:5244/d';
      
      _baseUrlController.text = baseUrl;
      _baseDownloadUrlController.text = baseDownloadUrl;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已选择设备: ${device.ip}'),
        backgroundColor: Colors.green,
      ),
    );
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

      // 立即更新HTTP客户端的baseUrl，使设置立即生效
      await WooHttpUtil().updateBaseUrl();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API 设置已保存并立即生效'),
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
            // 添加扫描按钮
            OutlinedButton.icon(
              onPressed: _isScanning ? null : _scanLocalDevices,
              icon: _isScanning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor),
                      ),
                    )
                  : const Icon(Icons.wifi_find),
              label: _isScanning
                  ? Text('扫描中 $_scanProgress/$_scanMax')
                  : const Text('扫描局域网设备'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).primaryColor),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
