import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/woo_http.dart';
import 'package:alist_player/utils/logger.dart';

class ConfigItem {
  final String key;
  final String name;
  final String value;
  final String type;
  final String? description;

  ConfigItem({
    required this.key,
    required this.name,
    required this.value,
    required this.type,
    this.description,
  });

  factory ConfigItem.fromJson(Map<String, dynamic> json) {
    return ConfigItem(
      key: json['key'] as String,
      name: json['name'] as String,
      value: json['value'] as String,
      type: json['type'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'value': value,
      'type': type,
      if (description != null) 'description': description,
    };
  }
}

class ConfigCategory {
  final String id;
  final String name;
  final List<ConfigItem> items;

  ConfigCategory({
    required this.id,
    required this.name,
    required this.items,
  });

  factory ConfigCategory.fromJson(Map<String, dynamic> json) {
    return ConfigCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      items: (json['items'] as List)
          .map((item) => ConfigItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class ServerInfo {
  final String appName;
  final String version;
  final String deviceName;
  final String osInfo;
  final String ipAddress;
  final int serverPort;

  ServerInfo({
    required this.appName,
    required this.version,
    required this.deviceName,
    required this.osInfo,
    required this.ipAddress,
    required this.serverPort,
  });

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'version': version,
      'deviceName': deviceName,
      'osInfo': osInfo,
      'ipAddress': ipAddress,
      'serverPort': serverPort,
    };
  }
}

class ConfigServer {
  static final ConfigServer _instance = ConfigServer._internal();

  HttpServer? _server;
  bool _isRunning = false;
  final int _defaultPort = 9527; // 默认端口
  final List<ConfigCategory> _configCategories = [];
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  // 用于公开日志流
  Stream<String> get logStream => _logController.stream;

  factory ConfigServer() {
    return _instance;
  }

  ConfigServer._internal();

  bool get isRunning => _isRunning;
  int get port => _server?.port ?? _defaultPort;

  /// 启动配置服务器
  Future<bool> start() async {
    if (_isRunning) {
      _log('配置服务器已在运行中');
      return true;
    }

    try {
      // 尝试绑定到指定端口
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _defaultPort);
      _log('配置服务器启动成功，监听端口: ${_server!.port}');
      _isRunning = true;

      // 加载配置数据
      await _loadConfigurations();

      // 处理请求
      _server!.listen((request) async {
        try {
          await _handleRequest(request);
        } catch (e) {
          _log('处理请求时出错: $e');
          try {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write(jsonEncode({'error': e.toString()}))
              ..close();
          } catch (_) {
            // 忽略关闭响应时的错误
          }
        }
      });

      return true;
    } catch (e) {
      _log('启动配置服务器失败: $e');
      return false;
    }
  }

  /// 停止配置服务器
  Future<void> stop() async {
    if (!_isRunning || _server == null) {
      _log('配置服务器未在运行');
      return;
    }

    try {
      await _server!.close();
      _server = null;
      _isRunning = false;
      _log('配置服务器已停止');
    } catch (e) {
      _log('停止配置服务器时出错: $e');
    }
  }

  /// 加载应用的配置
  Future<void> _loadConfigurations() async {
    _configCategories.clear();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载API配置
      final apiConfigs = [
        ConfigItem(
          key: AppConstants.baseUrlKey,
          name: 'AList 基础 URL',
          value: prefs.getString(AppConstants.baseUrlKey) ??
              AppConstants.defaultBaseUrl,
          type: 'url',
          description: 'AList 服务器的基础 URL',
        ),
        ConfigItem(
          key: AppConstants.baseDownloadUrlKey,
          name: 'AList 下载 URL',
          value: prefs.getString(AppConstants.baseDownloadUrlKey) ??
              AppConstants.defaultBaseDownloadUrl,
          type: 'url',
          description: 'AList 服务器的文件下载 URL',
        ),
      ];

      // 加载数据库配置
      final dbConfigs = [
        ConfigItem(
          key: AppConstants.dbHostKey,
          name: '数据库主机',
          value: prefs.getString(AppConstants.dbHostKey) ??
              AppConstants.defaultDbHost,
          type: 'text',
          description: '数据库服务器地址',
        ),
        ConfigItem(
          key: AppConstants.dbPortKey,
          name: '数据库端口',
          value: (prefs.getInt(AppConstants.dbPortKey) ??
                  AppConstants.defaultDbPort)
              .toString(),
          type: 'number',
          description: '数据库服务器端口',
        ),
        ConfigItem(
          key: AppConstants.dbNameKey,
          name: '数据库名称',
          value: prefs.getString(AppConstants.dbNameKey) ??
              AppConstants.defaultDbName,
          type: 'text',
          description: '数据库名称',
        ),
        ConfigItem(
          key: AppConstants.dbUserKey,
          name: '数据库用户',
          value: prefs.getString(AppConstants.dbUserKey) ??
              AppConstants.defaultDbUser,
          type: 'text',
          description: '数据库用户名',
        ),
        ConfigItem(
          key: AppConstants.dbPasswordKey,
          name: '数据库密码',
          value: prefs.getString(AppConstants.dbPasswordKey) ??
              AppConstants.defaultDbPassword,
          type: 'password',
          description: '数据库密码',
        ),
      ];

      _configCategories.addAll([
        ConfigCategory(
          id: 'api',
          name: 'API 设置',
          items: apiConfigs,
        ),
        ConfigCategory(
          id: 'database',
          name: '数据库设置',
          items: dbConfigs,
        ),
      ]);

      _log('已加载${_configCategories.length}个配置分类');
    } catch (e) {
      _log('加载配置时出错: $e');
    }
  }

  /// 处理HTTP请求
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    _log('收到请求: $method $path');

    // 设置CORS头
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers
        .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type');

    if (method == 'OPTIONS') {
      // 处理预检请求
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }

    // 设置内容类型
    request.response.headers.contentType = ContentType.json;

    switch (path) {
      case '/':
      case '/info':
        // 返回服务器信息
        await _handleInfoRequest(request);
        break;
      case '/configs':
        if (method == 'GET') {
          // 获取所有配置
          await _handleGetConfigsRequest(request);
        } else {
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..write(jsonEncode({'error': 'Method not allowed'}))
            ..close();
        }
        break;
      case '/apply':
        if (method == 'POST') {
          // 应用配置
          await _handleApplyConfigRequest(request);
        } else {
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..write(jsonEncode({'error': 'Method not allowed'}))
            ..close();
        }
        break;
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write(jsonEncode({'error': 'Not found'}))
          ..close();
    }
  }

  /// 处理获取服务器信息的请求
  Future<void> _handleInfoRequest(HttpRequest request) async {
    try {
      final info = ServerInfo(
        appName: 'AlistPlayer',
        version: '1.0.0',
        deviceName: Platform.localHostname,
        osInfo:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ipAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        serverPort: port,
      );

      request.response
        ..write(jsonEncode(info.toJson()))
        ..close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  /// 处理获取配置的请求
  Future<void> _handleGetConfigsRequest(HttpRequest request) async {
    try {
      // 重新加载最新配置
      await _loadConfigurations();

      final configsJson =
          _configCategories.map((category) => category.toJson()).toList();

      request.response
        ..write(jsonEncode(configsJson))
        ..close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  /// 处理应用配置的请求
  Future<void> _handleApplyConfigRequest(HttpRequest request) async {
    try {
      // 读取请求体
      final requestBody = await utf8.decoder.bind(request).join();
      final Map<String, dynamic> data = jsonDecode(requestBody);

      // 验证数据格式
      if (!data.containsKey('configs') || !(data['configs'] is List)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'Invalid request format'}))
          ..close();
        return;
      }

      // 应用配置
      final List<dynamic> configs = data['configs'];
      final prefs = await SharedPreferences.getInstance();
      int appliedCount = 0;
      bool hasApiConfigChanged = false;

      for (var config in configs) {
        if (config is Map<String, dynamic> &&
            config.containsKey('key') &&
            config.containsKey('value') &&
            config.containsKey('type')) {
          final key = config['key'] as String;
          final value = config['value'] as String;
          final type = config['type'] as String;

          // 检查是否是API相关配置
          if (key == AppConstants.baseUrlKey ||
              key == AppConstants.baseDownloadUrlKey) {
            hasApiConfigChanged = true;
          }

          // 根据类型保存值
          switch (type) {
            case 'number':
              final numValue = int.tryParse(value);
              if (numValue != null) {
                await prefs.setInt(key, numValue);
                appliedCount++;
              }
              break;
            case 'boolean':
              final boolValue = value.toLowerCase() == 'true';
              await prefs.setBool(key, boolValue);
              appliedCount++;
              break;
            case 'text':
            case 'password':
            case 'url':
            default:
              await prefs.setString(key, value);
              appliedCount++;
              break;
          }
        }
      }

      // 如果API配置有变化，立即更新HTTP客户端
      if (hasApiConfigChanged) {
        try {
          await WooHttpUtil().updateBaseUrl();
          _log('已更新HTTP客户端配置');
        } catch (e) {
          _log('更新HTTP客户端配置失败: $e');
        }
      }

      _log('已应用$appliedCount项配置');

      request.response
        ..write(jsonEncode({
          'success': true,
          'message': '已成功应用$appliedCount项配置',
        }))
        ..close();
    } catch (e) {
      _log('应用配置时出错: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  /// 获取本机IP地址列表
  Future<List<String>> getLocalIpAddresses() async {
    final List<String> addresses = [];

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            addresses.add(addr.address);
          }
        }
      }
    } catch (e) {
      _log('获取本地IP地址出错: $e');
    }

    return addresses;
  }

  /// 记录日志
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'ConfigServer',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
    _logController.add(message);
  }

  /// 从远程服务器同步配置
  Future<bool> syncFromRemote(String ipAddress, {int port = 9527}) async {
    try {
      _log('开始从 $ipAddress:$port 同步配置');

      // 创建HTTP客户端
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      // 获取配置
      final request =
          await client.getUrl(Uri.parse('http://$ipAddress:$port/configs'));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        _log('同步配置失败: HTTP ${response.statusCode}');
        return false;
      }

      // 读取响应
      final responseBody = await utf8.decoder.bind(response).join();
      final List<dynamic> configsJson = jsonDecode(responseBody);

      // 转换为配置类别
      final List<ConfigCategory> remoteCategories = configsJson
          .map((json) => ConfigCategory.fromJson(json as Map<String, dynamic>))
          .toList();

      // 准备要应用的配置项
      final List<Map<String, dynamic>> configsToApply = [];

      for (var category in remoteCategories) {
        for (var item in category.items) {
          String value = item.value;

          // 检查是否需要替换本地地址
          bool shouldReplace = false;

          // 需要替换的情况:
          // 1. URL类型 且 包含本地地址
          // 2. 数据库主机配置项 且 包含本地地址
          if (value.contains('127.0.0.1') || value.contains('localhost')) {
            if (item.type == 'url' || item.key == AppConstants.dbHostKey) {
              shouldReplace = true;
            }
          }

          if (shouldReplace) {
            // 对于数据库主机，直接替换为远程IP
            if (item.key == AppConstants.dbHostKey) {
              value = ipAddress;
              _log('将数据库主机从 ${item.value} 替换为 $value');
            } else {
              // 对于URL，替换主机部分
              value = _replaceLocalhost(value, ipAddress);
              _log('将${item.name}从 ${item.value} 替换为 $value');
            }
          }

          configsToApply.add({
            'key': item.key,
            'value': value,
            'type': item.type,
          });
        }
      }

      // 应用配置
      final prefs = await SharedPreferences.getInstance();
      int appliedCount = 0;
      bool hasApiConfigChanged = false;

      for (var config in configsToApply) {
        final key = config['key'] as String;
        final value = config['value'] as String;
        final type = config['type'] as String;

        // 检查是否是API相关配置
        if (key == AppConstants.baseUrlKey ||
            key == AppConstants.baseDownloadUrlKey) {
          hasApiConfigChanged = true;
        }

        switch (type) {
          case 'number':
            final numValue = int.tryParse(value);
            if (numValue != null) {
              await prefs.setInt(key, numValue);
              appliedCount++;
            }
            break;
          case 'boolean':
            final boolValue = value.toLowerCase() == 'true';
            await prefs.setBool(key, boolValue);
            appliedCount++;
            break;
          case 'text':
          case 'password':
          case 'url':
          default:
            await prefs.setString(key, value);
            appliedCount++;
            break;
        }
      }

      // 如果API配置有变化，立即更新HTTP客户端
      if (hasApiConfigChanged) {
        try {
          await WooHttpUtil().updateBaseUrl();
          _log('已更新HTTP客户端配置');
        } catch (e) {
          _log('更新HTTP客户端配置失败: $e');
        }
      }

      _log('成功从远程同步$appliedCount项配置');
      return true;
    } catch (e) {
      _log('从远程同步配置时出错: $e');
      return false;
    }
  }

  /// 获取当前所有配置
  Future<List<ConfigCategory>> getCurrentConfigs() async {
    await _loadConfigurations();
    return List<ConfigCategory>.from(_configCategories);
  }

  /// 创建当前配置的备份
  Future<bool> backupCurrentConfigs(String backupName) async {
    try {
      // 加载最新配置
      await _loadConfigurations();

      // 准备备份数据
      final Map<String, dynamic> backupData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'name': backupName,
        'configs':
            _configCategories.map((category) => category.toJson()).toList(),
      };

      // 获取已有备份
      final prefs = await SharedPreferences.getInstance();
      final String backupsJson = prefs.getString('config_backups') ?? '[]';
      final List<dynamic> backups = jsonDecode(backupsJson);

      // 添加新备份
      backups.add(backupData);

      // 保存备份列表
      await prefs.setString('config_backups', jsonEncode(backups));

      _log('创建配置备份: $backupName');
      return true;
    } catch (e) {
      _log('创建配置备份失败: $e');
      return false;
    }
  }

  /// 获取所有备份
  Future<List<Map<String, dynamic>>> getConfigBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String backupsJson = prefs.getString('config_backups') ?? '[]';
      final List<dynamic> backups = jsonDecode(backupsJson);

      // 转换为所需格式
      return backups.map((backup) => backup as Map<String, dynamic>).toList();
    } catch (e) {
      _log('获取配置备份失败: $e');
      return [];
    }
  }

  /// 从备份恢复配置
  Future<bool> restoreFromBackup(int backupIndex) async {
    try {
      // 获取所有备份
      final backups = await getConfigBackups();
      if (backupIndex < 0 || backupIndex >= backups.length) {
        _log('无效的备份索引');
        return false;
      }

      final backup = backups[backupIndex];
      final List<dynamic> configsJson = backup['configs'];

      // 转换为配置类别
      final List<ConfigCategory> categories = configsJson
          .map((json) => ConfigCategory.fromJson(json as Map<String, dynamic>))
          .toList();

      // 准备要应用的配置项
      final List<Map<String, dynamic>> configsToApply = [];

      for (var category in categories) {
        for (var item in category.items) {
          configsToApply.add({
            'key': item.key,
            'value': item.value,
            'type': item.type,
          });
        }
      }

      // 应用配置
      final prefs = await SharedPreferences.getInstance();
      int appliedCount = 0;
      bool hasApiConfigChanged = false;

      for (var config in configsToApply) {
        final key = config['key'] as String;
        final value = config['value'] as String;
        final type = config['type'] as String;

        // 检查是否是API相关配置
        if (key == AppConstants.baseUrlKey ||
            key == AppConstants.baseDownloadUrlKey) {
          hasApiConfigChanged = true;
        }

        switch (type) {
          case 'number':
            final numValue = int.tryParse(value);
            if (numValue != null) {
              await prefs.setInt(key, numValue);
              appliedCount++;
            }
            break;
          case 'boolean':
            final boolValue = value.toLowerCase() == 'true';
            await prefs.setBool(key, boolValue);
            appliedCount++;
            break;
          case 'text':
          case 'password':
          case 'url':
          default:
            await prefs.setString(key, value);
            appliedCount++;
            break;
        }
      }

      // 如果API配置有变化，立即更新HTTP客户端
      if (hasApiConfigChanged) {
        try {
          await WooHttpUtil().updateBaseUrl();
          _log('已更新HTTP客户端配置');
        } catch (e) {
          _log('更新HTTP客户端配置失败: $e');
        }
      }

      _log('已从备份恢复$appliedCount项配置');
      return true;
    } catch (e) {
      _log('从备份恢复配置失败: $e');
      return false;
    }
  }

  /// 删除备份
  Future<bool> deleteBackup(int backupIndex) async {
    try {
      // 获取所有备份
      final prefs = await SharedPreferences.getInstance();
      final String backupsJson = prefs.getString('config_backups') ?? '[]';
      final List<dynamic> backups = jsonDecode(backupsJson);

      if (backupIndex < 0 || backupIndex >= backups.length) {
        _log('无效的备份索引');
        return false;
      }

      // 删除指定备份
      backups.removeAt(backupIndex);

      // 保存备份列表
      await prefs.setString('config_backups', jsonEncode(backups));

      _log('删除备份成功');
      return true;
    } catch (e) {
      _log('删除备份失败: $e');
      return false;
    }
  }

  /// 从远程服务器获取配置（不立即应用）
  Future<List<ConfigCategory>?> getRemoteConfigs(String ipAddress,
      {int port = 9527}) async {
    try {
      _log('获取 $ipAddress:$port 的配置');

      // 创建HTTP客户端
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      // 获取配置
      final request =
          await client.getUrl(Uri.parse('http://$ipAddress:$port/configs'));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        _log('获取配置失败: HTTP ${response.statusCode}');
        return null;
      }

      // 读取响应
      final responseBody = await utf8.decoder.bind(response).join();
      final List<dynamic> configsJson = jsonDecode(responseBody);

      // 转换为配置类别
      final List<ConfigCategory> remoteCategories = [];

      for (var categoryJson in configsJson) {
        final category =
            ConfigCategory.fromJson(categoryJson as Map<String, dynamic>);

        // 替换URL和数据库主机中的localhost或127.0.0.1为远程设备IP
        final updatedItems = category.items.map((item) {
          String value = item.value;
          bool shouldReplace = false;

          // 需要替换的情况:
          // 1. URL类型 且 包含本地地址
          // 2. 数据库主机配置项 且 包含本地地址
          if (value.contains('127.0.0.1') || value.contains('localhost')) {
            if (item.type == 'url' || item.key == AppConstants.dbHostKey) {
              shouldReplace = true;
            }
          }

          if (shouldReplace) {
            // 对于数据库主机，直接替换为远程IP
            if (item.key == AppConstants.dbHostKey) {
              value = ipAddress;
            } else {
              // 对于URL，替换主机部分
              value = _replaceLocalhost(value, ipAddress);
            }

            return ConfigItem(
              key: item.key,
              name: item.name,
              value: value,
              type: item.type,
              description: item.description,
            );
          }
          return item;
        }).toList();

        remoteCategories.add(ConfigCategory(
          id: category.id,
          name: category.name,
          items: updatedItems,
        ));
      }

      return remoteCategories;
    } catch (e) {
      _log('获取远程配置时出错: $e');
      return null;
    }
  }

  /// 替换URL中的localhost或127.0.0.1为指定IP
  String _replaceLocalhost(String url, String newIp) {
    if (url.isEmpty || newIp.isEmpty) return url;

    try {
      final uri = Uri.parse(url);
      if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
        final newUri = uri.replace(host: newIp);
        return newUri.toString();
      }
    } catch (e) {
      _log('替换URL中的localhost失败: $e');
    }

    return url;
  }

  /// 应用指定的配置列表
  Future<int> applyConfigs(List<ConfigItem> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int appliedCount = 0;
      bool hasApiConfigChanged = false;

      for (var config in configs) {
        final key = config.key;
        final value = config.value;
        final type = config.type;

        // 检查是否是API相关配置
        if (key == AppConstants.baseUrlKey ||
            key == AppConstants.baseDownloadUrlKey) {
          hasApiConfigChanged = true;
        }

        switch (type) {
          case 'number':
            final numValue = int.tryParse(value);
            if (numValue != null) {
              await prefs.setInt(key, numValue);
              appliedCount++;
            }
            break;
          case 'boolean':
            final boolValue = value.toLowerCase() == 'true';
            await prefs.setBool(key, boolValue);
            appliedCount++;
            break;
          case 'text':
          case 'password':
          case 'url':
          default:
            await prefs.setString(key, value);
            appliedCount++;
            break;
        }
      }

      // 如果API配置有变化，立即更新HTTP客户端
      if (hasApiConfigChanged) {
        try {
          await WooHttpUtil().updateBaseUrl();
          _log('已更新HTTP客户端配置');
        } catch (e) {
          _log('更新HTTP客户端配置失败: $e');
        }
      }

      _log('已应用$appliedCount项配置');
      return appliedCount;
    } catch (e) {
      _log('应用配置时出错: $e');
      return 0;
    }
  }
}
