import 'package:flutter/material.dart';
import 'package:alist_player/utils/config_server.dart';
import 'package:alist_player/utils/network_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteConfigPage extends StatefulWidget {
  const RemoteConfigPage({Key? key}) : super(key: key);

  @override
  State<RemoteConfigPage> createState() => _RemoteConfigPageState();
}

class _RemoteConfigPageState extends State<RemoteConfigPage> {
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
  
  @override
  void initState() {
    super.initState();
    _checkServerStatus();
    _getLocalIpAddresses();
    _loadSettings();
    
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
      
      if (_discoveredDevices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未发现局域网中运行配置服务器的设备'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
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
  
  /// 从选定设备同步配置
  Future<void> _syncFromDevice(NetworkDevice device) async {
    final bool success = await _configServer.syncFromRemote(device.ip);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功从 ${device.ip} 同步配置'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('从 ${device.ip} 同步配置失败'),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanDevices,
            tooltip: '扫描设备',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildServerControl(),
          const Divider(),
          Expanded(
            child: _buildDevicesList(),
          ),
          _buildLogSection(),
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

  /// 构建日志部分
  Widget _buildLogSection() {
    return Container(
      height: 150,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
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
                  fontSize: 14,
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
          Expanded(
            child: ListView.builder(
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
} 