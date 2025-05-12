import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

enum DeviceStatus {
  unknown,
  online,
  offline,
}

class NetworkDevice {
  final String ip;
  final Duration responseTime;
  bool isSelected;
  DeviceStatus status;
  bool isLocalDevice; // 标识是否为本机设备
  String? deviceName; // 设备名称

  NetworkDevice({
    required this.ip,
    required this.responseTime,
    this.isSelected = false,
    this.status = DeviceStatus.unknown,
    this.isLocalDevice = false,
    this.deviceName,
  });

  /// 检测设备是否在线
  Future<DeviceStatus> checkStatus({
    int port = 5244,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      status = DeviceStatus.online;
      return DeviceStatus.online;
    } catch (e) {
      status = DeviceStatus.offline;
      return DeviceStatus.offline;
    }
  }
}

class NetworkScanner {
  static final NetworkScanner _instance = NetworkScanner._internal();
  final NetworkInfo _networkInfo = NetworkInfo();

  factory NetworkScanner() {
    return _instance;
  }

  NetworkScanner._internal();

  /// 获取本机IP地址
  Future<String?> getLocalIpAddress() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      return null;
    }
  }

  /// 获取本机IP地址的子网掩码前缀部分（如：192.168.1）
  Future<String?> getSubnetPrefix() async {
    final ip = await getLocalIpAddress();
    if (ip == null) return null;
    
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }
  
  /// 尝试解析设备主机名
  Future<String?> resolveDeviceName(String ip) async {
    try {
      // 尝试使用DNS反向解析获取主机名
      final result = await InternetAddress(ip).reverse();
      if (result.host != ip && result.host.isNotEmpty) {
        return result.host;
      }
    } catch (e) {
      // 忽略解析错误
    }
    
    // 返回一些常见IP的名称
    if (ip.endsWith('.1') || ip.endsWith('.254')) {
      return '可能是路由器';
    }
    
    // 无法解析，返回null
    return null;
  }
  
  /// 扫描局域网设备
  /// [onProgress] 扫描进度回调 (当前进度, 最大进度)
  /// [port] 要扫描的端口，默认为5244，这是AList常用端口
  Future<List<NetworkDevice>> scanDevices({
    required void Function(int current, int max) onProgress,
    int port = 5244,
    Duration timeout = const Duration(milliseconds: 200),
  }) async {
    final subnetPrefix = await getSubnetPrefix();
    if (subnetPrefix == null) return [];
    
    final List<NetworkDevice> devices = [];
    final int maxHosts = 255; // 最大主机数
    int count = 0;
    
    // 先获取本机IP地址，用于标识本机设备
    final localIp = await getLocalIpAddress();
    
    // 创建多个并发连接测试
    final List<Future<NetworkDevice?>> futures = [];
    
    for (int i = 1; i <= 255; i++) {
      final String ip = '$subnetPrefix.$i';
      futures.add(_pingHost(ip, port, timeout, localIp).then((device) {
        count++;
        onProgress(count, maxHosts);
        return device;
      }));
    }
    
    // 使用Future.wait等待所有ping完成，限制并发数量为20
    final int batchSize = 20;
    for (int i = 0; i < futures.length; i += batchSize) {
      final int end = (i + batchSize < futures.length) ? i + batchSize : futures.length;
      final batch = futures.sublist(i, end);
      
      final results = await Future.wait(batch);
      for (final device in results) {
        if (device != null) {
          devices.add(device);
        }
      }
    }
    
    // 异步解析设备名称
    await _resolveDeviceNames(devices);
    
    // 按响应时间排序
    devices.sort((a, b) => a.responseTime.compareTo(b.responseTime));
    return devices;
  }
  
  /// 解析所有设备的主机名
  Future<void> _resolveDeviceNames(List<NetworkDevice> devices) async {
    final List<Future<void>> nameFutures = [];
    
    for (final device in devices) {
      nameFutures.add(() async {
        device.deviceName = await resolveDeviceName(device.ip);
      }());
    }
    
    await Future.wait(nameFutures);
  }
  
  /// 测试单个主机是否在线
  Future<NetworkDevice?> _pingHost(
    String ip, 
    int port, 
    Duration timeout, 
    String? localIp
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      stopwatch.stop();
      
      final isLocalDevice = ip == localIp;
      
      return NetworkDevice(
        ip: ip,
        responseTime: stopwatch.elapsed,
        status: DeviceStatus.online,
        isLocalDevice: isLocalDevice,
        deviceName: isLocalDevice ? '本机' : null,
      );
    } catch (e) {
      return null; // 连接失败，该设备不可用
    }
  }
  
  /// 检查特定IP和端口是否可连接
  Future<bool> checkConnection(String ip, int port,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }
} 