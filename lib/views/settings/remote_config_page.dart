import 'package:flutter/material.dart';
import 'package:alist_player/utils/config_server.dart';
import 'package:alist_player/utils/network_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class RemoteConfigPage extends StatefulWidget {
  const RemoteConfigPage({Key? key}) : super(key: key);

  @override
  State<RemoteConfigPage> createState() => _RemoteConfigPageState();
}

class _RemoteConfigPageState extends State<RemoteConfigPage> with SingleTickerProviderStateMixin {
  final ConfigServer _configServer = ConfigServer();
  bool _serverRunning = false;
  List<String> _logs = [];
  List<NetworkDevice> _discoveredDevices = [];
  bool _isScanning = false;
  int _scanProgress = 0;
  int _scanMax = 255;
  String? _localIpAddress;
  List<String> _localIpAddresses = [];
  bool _autoStartServer = false;
  List<Map<String, dynamic>> _backups = [];
  bool _isLoadingBackups = false;
  late TabController _tabController;
  int _currentTabIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    _checkServerStatus();
    _getLocalIpAddresses();
    _loadSettings();
    _loadBackups();
    
    // 监听服务器日志
    _configServer.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 100) {
          _logs.removeAt(0); // 限制日志数量
        }
      });
    });
  }
  
  void _handleTabChange() {
    if (_tabController.indexIsChanging || _currentTabIndex != _tabController.index) {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    }
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }
  
  /// 检查服务器状态
  Future<void> _checkServerStatus() async {
    setState(() {
      _serverRunning = _configServer.isRunning;
    });
  }
  
  /// 获取本机IP地址
  Future<void> _getLocalIpAddresses() async {
    final addresses = await _configServer.getLocalIpAddresses();
    setState(() {
      _localIpAddresses = addresses;
      _localIpAddress = addresses.isNotEmpty ? addresses.first : null;
    });
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoStartServer = prefs.getBool('auto_start_config_server') ?? false;
    });
  }
  
  /// 加载备份列表
  Future<void> _loadBackups() async {
    setState(() {
      _isLoadingBackups = true;
    });
    
    try {
      final backups = await _configServer.getConfigBackups();
      setState(() {
        _backups = backups;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载备份列表失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBackups = false;
        });
      }
    }
  }
  
  /// 保存自动启动设置
  Future<void> _saveAutoStartSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_start_config_server', value);
    setState(() {
      _autoStartServer = value;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '已设置应用启动时自动启动服务器' : '已取消应用启动时自动启动服务器'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// 启动或停止服务器
  Future<void> _toggleServer() async {
    if (_serverRunning) {
      await _configServer.stop();
    } else {
      await _configServer.start();
    }
    
    await _checkServerStatus();
  }

  /// 扫描网络设备
  Future<void> _scanDevices() async {
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
        port: 9527, // 扫描配置服务器端口
      );

      setState(() {
        _discoveredDevices = devices;
      });
      
      if (_discoveredDevices.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未发现局域网中运行配置服务器的设备'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描出错: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }
  
  /// 从选定设备同步配置
  Future<void> _syncFromDevice(NetworkDevice device) async {
    // 先获取远程配置信息
    final remoteConfigs = await _configServer.getRemoteConfigs(device.ip);
    if (remoteConfigs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法获取 ${device.ip} 的配置信息'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // 显示确认对话框
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildSyncConfirmDialog(device, remoteConfigs),
    );
    
    if (confirmed != true) return;
    
    // 备份当前配置
    final bool shouldBackup = await showDialog<bool>(
      context: context,
      builder: (context) => _buildBackupConfirmDialog(),
    ) ?? false;
    
    if (shouldBackup) {
      final backupName = '同步前备份 - ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}';
      await _configServer.backupCurrentConfigs(backupName);
    }
    
    // 执行同步
    final bool success = await _configServer.syncFromRemote(device.ip);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功从 ${device.ip} 同步配置'),
          backgroundColor: Colors.green,
        ),
      );
      
      // 刷新备份列表
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('从 ${device.ip} 同步配置失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// 创建配置备份
  Future<void> _createBackup() async {
    final TextEditingController nameController = TextEditingController(
      text: '备份 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
    );
    
    final String? backupName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建配置备份'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '备份名称',
            hintText: '输入备份名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    
    if (backupName == null || backupName.isEmpty) return;
    
    final bool success = await _configServer.backupCurrentConfigs(backupName);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功创建备份: $backupName'),
          backgroundColor: Colors.green,
        ),
      );
      
      // 刷新备份列表
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('创建备份失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// 恢复配置备份
  Future<void> _restoreBackup(int index, String backupName) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复配置'),
        content: Text('确定要恢复备份: $backupName ?\n这将覆盖当前所有配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final bool success = await _configServer.restoreFromBackup(index);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功恢复备份: $backupName'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复备份失败: $backupName'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// 删除配置备份
  Future<void> _deleteBackup(int index, String backupName) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定要删除备份: $backupName ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final bool success = await _configServer.deleteBackup(index);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除备份: $backupName'),
          backgroundColor: Colors.green,
        ),
      );
      
      // 刷新备份列表
      _loadBackups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除备份失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程配置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '设备'),
            Tab(text: '备份'),
            Tab(text: '日志'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _currentTabIndex == 0 ? _scanDevices : null,
            tooltip: '扫描设备',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDevicesTab(),
          _buildBackupsTab(),
          _buildLogsTab(),
        ],
      ),
      floatingActionButton: _currentTabIndex == 1 
          ? FloatingActionButton(
              onPressed: _createBackup,
              tooltip: '创建备份',
              child: const Icon(Icons.save),
            )
          : null,
    );
  }

  /// 构建设备标签页
  Widget _buildDevicesTab() {
    return Column(
      children: [
        _buildServerControl(),
        const Divider(),
        Expanded(
          child: _buildDevicesList(),
        ),
      ],
    );
  }
  
  /// 构建备份标签页
  Widget _buildBackupsTab() {
    if (_isLoadingBackups) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_backups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.save_outlined,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '没有配置备份',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮创建备份',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _backups.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final backup = _backups[index];
        final String name = backup['name'] as String;
        final int timestamp = backup['timestamp'] as int;
        final DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final String formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: const CircleAvatar(
              backgroundColor: Colors.amber,
              child: Icon(
                Icons.restore,
                color: Colors.white,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('创建时间: $formattedDate'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: () => _restoreBackup(index, name),
                  tooltip: '恢复此备份',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteBackup(index, name),
                  tooltip: '删除此备份',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// 构建日志标签页
  Widget _buildLogsTab() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '服务器日志',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 16),
                onPressed: () {
                  setState(() {
                    _logs.clear();
                  });
                },
                tooltip: '清除日志',
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _logs.length,
                    reverse: true,
                    itemBuilder: (context, index) {
                      final log = _logs[_logs.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          log,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建服务器控制面板
  Widget _buildServerControl() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配置服务器状态',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                _serverRunning ? Icons.cloud_done : Icons.cloud_off,
                color: _serverRunning ? Colors.green : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                _serverRunning 
                    ? '服务器正在运行 (端口: ${_configServer.port})'
                    : '服务器未运行',
                style: TextStyle(
                  fontSize: 16,
                  color: _serverRunning ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 添加自动启动设置
          SwitchListTile(
            title: const Text('应用启动时自动启动服务器'),
            subtitle: const Text('每次应用启动都会尝试启动配置服务器'),
            value: _autoStartServer,
            onChanged: _saveAutoStartSetting,
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_localIpAddresses.isNotEmpty) ...[
            const Text(
              '本机地址:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _localIpAddresses
                  .map(
                    (ip) => Chip(
                      label: Text(ip),
                      backgroundColor: Colors.blue.shade100,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _toggleServer,
                icon: Icon(
                  _serverRunning ? Icons.stop : Icons.play_arrow,
                ),
                label: Text(_serverRunning ? '停止服务器' : '启动服务器'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _serverRunning ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _scanDevices,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.search),
                label: _isScanning
                    ? Text('扫描中 $_scanProgress/$_scanMax')
                    : const Text('扫描局域网'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建设备列表
  Widget _buildDevicesList() {
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在扫描设备... $_scanProgress/$_scanMax'),
          ],
        ),
      );
    }

    if (_discoveredDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '未发现设备',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角刷新按钮开始扫描',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _discoveredDevices.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final device = _discoveredDevices[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: device.isLocalDevice 
                  ? Colors.purple.shade200 
                  : Colors.blue.shade200,
              width: device.isLocalDevice ? 2 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            leading: CircleAvatar(
              backgroundColor: device.isLocalDevice 
                  ? Colors.purple.shade100 
                  : Colors.blue.shade100,
              child: Icon(
                device.isLocalDevice
                    ? Icons.computer
                    : Icons.devices_other,
                color: device.isLocalDevice 
                    ? Colors.purple 
                    : Colors.blue,
              ),
            ),
            title: Text(
              device.ip,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (device.deviceName != null)
                  Text(
                    device.deviceName!,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                  ),
                Text(
                  device.isLocalDevice ? '本机' : '远程设备',
                  style: TextStyle(
                    color: device.isLocalDevice 
                        ? Colors.purple 
                        : Colors.blue,
                  ),
                ),
                Text('响应时间: ${device.responseTime.inMilliseconds}ms'),
              ],
            ),
            trailing: device.isLocalDevice
                ? null
                : IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: () => _syncFromDevice(device),
                    tooltip: '从此设备同步配置',
                  ),
          ),
        );
      },
    );
  }
  
  /// 构建同步确认对话框
  Widget _buildSyncConfirmDialog(
    NetworkDevice device,
    List<ConfigCategory> remoteConfigs,
  ) {
    return AlertDialog(
      title: const Text('确认同步配置'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您确定要从 ${device.ip} 同步以下配置吗？'),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: remoteConfigs.length,
                itemBuilder: (context, index) {
                  final category = remoteConfigs[index];
                  return ExpansionTile(
                    title: Text(
                      category.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: category.items.map((item) {
                      return ListTile(
                        dense: true,
                        title: Text(item.name),
                        subtitle: item.type == 'password'
                            ? const Text('******')
                            : Text(item.value),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text('同步'),
        ),
      ],
    );
  }
  
  /// 构建备份确认对话框
  Widget _buildBackupConfirmDialog() {
    return AlertDialog(
      title: const Text('备份当前配置'),
      content: const Text('是否要在同步前备份当前配置？\n这样您可以在同步后恢复原配置。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('不备份'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('备份'),
        ),
      ],
    );
  }
} 