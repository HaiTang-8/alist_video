import 'package:flutter/material.dart';
import 'package:alist_player/utils/config_server.dart';
import 'package:alist_player/utils/network_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class RemoteConfigPage extends StatefulWidget {
  const RemoteConfigPage({super.key});

  @override
  State<RemoteConfigPage> createState() => _RemoteConfigPageState();
}

class _RemoteConfigPageState extends State<RemoteConfigPage> with SingleTickerProviderStateMixin {
  final ConfigServer _configServer = ConfigServer();
  bool _serverRunning = false;
  final List<String> _logs = [];
  List<NetworkDevice> _discoveredDevices = [];
  bool _isScanning = false;
  int _scanProgress = 0;
  int _scanMax = 255;
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
    
    // 延迟执行，确保页面已完全加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 如果服务器已经在运行，则自动扫描一次设备
      if (_serverRunning) {
        _scanDevices();
      }
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
  
  /// 获取本机IP地址(用于识别本地设备)
  Future<void> _getLocalIpAddresses() async {
    final addresses = await _configServer.getLocalIpAddresses();
    setState(() {
      _localIpAddresses = addresses;
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
        const SnackBar(
          content: Text('删除备份失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程配置'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.devices),
                  text: '设备',
                ),
                Tab(
                  icon: Icon(Icons.backup),
                  text: '备份',
                ),
                Tab(
                  icon: Icon(Icons.list_alt),
                  text: '日志',
                ),
              ],
              labelStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: theme.textTheme.titleSmall,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.0),
                    theme.colorScheme.primary.withOpacity(0.05),
                  ],
                ),
              ),
              indicatorWeight: 0,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        actions: [
          if (_currentTabIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _scanDevices,
              tooltip: '扫描设备',
            ),
        ],
      ),
      body: Container(
        color: theme.colorScheme.surface,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildDevicesTab(),
            _buildBackupsTab(),
            _buildLogsTab(),
          ],
        ),
      ),
      floatingActionButton: _currentTabIndex == 1 
          ? FloatingActionButton.extended(
              onPressed: _createBackup,
              icon: const Icon(Icons.save),
              label: const Text('创建备份'),
              tooltip: '创建备份',
            )
          : null,
    );
  }

  /// 构建设备标签页
  Widget _buildDevicesTab() {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildServerControl(),
          Divider(color: theme.dividerColor.withOpacity(0.1), thickness: 1),
          Expanded(
            child: _buildDevicesList(),
          ),
        ],
      ),
    );
  }
  
  /// 构建备份标签页
  Widget _buildBackupsTab() {
    final theme = Theme.of(context);
    
    if (_isLoadingBackups) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '加载备份列表...',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    
    if (_backups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.save_outlined,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              '没有配置备份',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮创建备份',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createBackup,
              icon: const Icon(Icons.save),
              label: const Text('创建备份'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.secondary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.restore,
                          color: theme.colorScheme.secondary,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formattedDate,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _restoreBackup(index, name),
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: theme.colorScheme.secondary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _deleteBackup(index, name),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
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
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '服务器日志',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: theme.colorScheme.error),
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.onInverseSurface.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无日志',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '服务器活动日志将在此显示',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      reverse: true,
                      itemBuilder: (context, index) {
                        final log = _logs[_logs.length - 1 - index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                          child: Text(
                            log,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: log.contains('错误') || log.contains('失败')
                                  ? theme.colorScheme.error
                                  : log.contains('成功')
                                      ? Colors.green
                                      : theme.colorScheme.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建服务器控制面板
  Widget _buildServerControl() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings_remote,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '配置服务器',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _serverRunning 
                  ? Colors.green.withOpacity(0.1) 
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _serverRunning 
                    ? Colors.green.withOpacity(0.3) 
                    : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _serverRunning ? Icons.cloud_done : Icons.cloud_off,
                  color: _serverRunning ? Colors.green : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _serverRunning ? '服务器在线' : '服务器离线',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _serverRunning ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (_serverRunning)
                        Text(
                          '端口: ${_configServer.port}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleServer,
                  icon: Icon(
                    _serverRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(_serverRunning ? '停止' : '启动'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _serverRunning ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 添加自动启动设置
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: SwitchListTile(
              title: const Text('应用启动时自动启动服务器'),
              subtitle: const Text('每次应用启动都会尝试启动配置服务器'),
              value: _autoStartServer,
              onChanged: _saveAutoStartSetting,
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              secondary: Icon(
                Icons.auto_mode,
                color: _autoStartServer 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _scanDevices,
            icon: _isScanning
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.search),
            label: _isScanning
                ? Text('扫描中 $_scanProgress/$_scanMax')
                : const Text('扫描局域网设备'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建设备列表
  Widget _buildDevicesList() {
    final theme = Theme.of(context);
    
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              '正在扫描设备...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '进度: $_scanProgress/$_scanMax',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
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
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              '未发现设备',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请确保设备已开启配置服务器',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('开始扫描'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
        final bool isLocalDevice = device.isLocalDevice;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: isLocalDevice 
                  ? theme.colorScheme.tertiary.withOpacity(0.3) 
                  : theme.colorScheme.primary.withOpacity(0.3),
              width: isLocalDevice ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isLocalDevice 
                    ? null 
                    : () => _syncFromDevice(device),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isLocalDevice 
                                  ? theme.colorScheme.tertiary.withOpacity(0.1) 
                                  : theme.colorScheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                isLocalDevice ? Icons.computer : Icons.devices_other,
                                color: isLocalDevice 
                                    ? theme.colorScheme.tertiary 
                                    : theme.colorScheme.primary,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.ip,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (device.deviceName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    device.deviceName!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!isLocalDevice)
                            IconButton(
                              icon: const Icon(Icons.sync),
                              onPressed: () => _syncFromDevice(device),
                              tooltip: '从此设备同步配置',
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isLocalDevice 
                              ? theme.colorScheme.tertiary.withOpacity(0.1) 
                              : theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLocalDevice ? Icons.home : Icons.public,
                              size: 16,
                              color: isLocalDevice 
                                  ? theme.colorScheme.tertiary 
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isLocalDevice ? '本机' : '远程设备',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: isLocalDevice 
                                    ? theme.colorScheme.tertiary 
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '响应时间: ${device.responseTime.inMilliseconds}ms',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      if (!isLocalDevice) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _syncFromDevice(device),
                            icon: const Icon(Icons.sync),
                            label: const Text('同步配置'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: theme.colorScheme.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
        );
      },
    );
  }
  
  /// 构建同步确认对话框
  Widget _buildSyncConfirmDialog(
    NetworkDevice device,
    List<ConfigCategory> remoteConfigs,
  ) {
    final theme = Theme.of(context);
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对话框头部
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sync,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '确认同步配置',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '从 ${device.ip} 同步以下配置',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 对话框内容
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '配置详情',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...remoteConfigs.map((category) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outline.withOpacity(0.2),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              title: Row(
                                children: [
                                  Icon(
                                    category.id == 'api' 
                                        ? Icons.api 
                                        : category.id == 'database' 
                                            ? Icons.storage 
                                            : Icons.settings,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    category.name,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              collapsedBackgroundColor: theme.colorScheme.surface,
                              backgroundColor: theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              children: category.items.map((item) {
                                IconData iconData;
                                switch (item.type) {
                                  case 'url':
                                    iconData = Icons.link;
                                    break;
                                  case 'password':
                                    iconData = Icons.password;
                                    break;
                                  case 'number':
                                    iconData = Icons.pin;
                                    break;
                                  case 'boolean':
                                    iconData = Icons.toggle_on;
                                    break;
                                  default:
                                    iconData = Icons.text_fields;
                                }
                                
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: theme.colorScheme.outline.withOpacity(0.1),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        iconData,
                                        size: 18,
                                        color: theme.colorScheme.primary.withOpacity(0.7),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (item.description != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.description!,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary.withOpacity(0.05),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Text(
                                                item.type == 'password' ? '••••••••' : item.value,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontFamily: 'monospace',
                                                  color: theme.colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 16),
                      Text(
                        '注意: 同步将覆盖当前配置，请确保已备份重要数据。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 对话框底部按钮
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.sync),
                    label: const Text('同步'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建备份确认对话框
  Widget _buildBackupConfirmDialog() {
    final theme = Theme.of(context);
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对话框头部
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.save,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '备份当前配置',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '在同步前保存您的配置',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 对话框内容
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '备份可以帮助您在需要时恢复配置',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '如果同步的配置有问题，您可以随时恢复到之前的状态。',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 对话框底部按钮
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '跳过备份',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.save),
                    label: const Text('创建备份'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 