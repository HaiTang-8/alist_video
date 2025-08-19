import 'package:shared_preferences/shared_preferences.dart';

/// 下载设置管理器
/// 管理下载相关的配置参数，如并发下载数量、下载速度限制等
class DownloadSettingsManager {
  static final DownloadSettingsManager _instance = DownloadSettingsManager._internal();
  factory DownloadSettingsManager() => _instance;
  DownloadSettingsManager._internal();

  // 设置键名
  static const String _maxConcurrentDownloadsKey = 'max_concurrent_downloads';
  static const String _downloadSpeedLimitKey = 'download_speed_limit';
  static const String _autoRetryCountKey = 'auto_retry_count';
  static const String _retryDelayKey = 'retry_delay';
  static const String _enableNotificationsKey = 'enable_notifications';
  static const String _autoStartDownloadKey = 'auto_start_download';

  // 默认值
  static const int defaultMaxConcurrentDownloads = 3;
  static const int defaultDownloadSpeedLimit = 0; // 0表示无限制，单位KB/s
  static const int defaultAutoRetryCount = 3;
  static const int defaultRetryDelay = 5; // 秒
  static const bool defaultEnableNotifications = true;
  static const bool defaultAutoStartDownload = true;

  // 缓存的设置值
  int? _maxConcurrentDownloads;
  int? _downloadSpeedLimit;
  int? _autoRetryCount;
  int? _retryDelay;
  bool? _enableNotifications;
  bool? _autoStartDownload;

  /// 获取最大并发下载数量
  Future<int> getMaxConcurrentDownloads() async {
    if (_maxConcurrentDownloads != null) {
      return _maxConcurrentDownloads!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _maxConcurrentDownloads = prefs.getInt(_maxConcurrentDownloadsKey) ?? defaultMaxConcurrentDownloads;
    return _maxConcurrentDownloads!;
  }

  /// 设置最大并发下载数量
  Future<void> setMaxConcurrentDownloads(int count) async {
    if (count < 1 || count > 10) {
      throw ArgumentError('并发下载数量必须在1-10之间');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxConcurrentDownloadsKey, count);
    _maxConcurrentDownloads = count;
  }

  /// 获取下载速度限制 (KB/s)
  Future<int> getDownloadSpeedLimit() async {
    if (_downloadSpeedLimit != null) {
      return _downloadSpeedLimit!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _downloadSpeedLimit = prefs.getInt(_downloadSpeedLimitKey) ?? defaultDownloadSpeedLimit;
    return _downloadSpeedLimit!;
  }

  /// 设置下载速度限制 (KB/s, 0表示无限制)
  Future<void> setDownloadSpeedLimit(int speedKBps) async {
    if (speedKBps < 0) {
      throw ArgumentError('下载速度限制不能为负数');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_downloadSpeedLimitKey, speedKBps);
    _downloadSpeedLimit = speedKBps;
  }

  /// 获取自动重试次数
  Future<int> getAutoRetryCount() async {
    if (_autoRetryCount != null) {
      return _autoRetryCount!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _autoRetryCount = prefs.getInt(_autoRetryCountKey) ?? defaultAutoRetryCount;
    return _autoRetryCount!;
  }

  /// 设置自动重试次数
  Future<void> setAutoRetryCount(int count) async {
    if (count < 0 || count > 10) {
      throw ArgumentError('自动重试次数必须在0-10之间');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoRetryCountKey, count);
    _autoRetryCount = count;
  }

  /// 获取重试延迟时间 (秒)
  Future<int> getRetryDelay() async {
    if (_retryDelay != null) {
      return _retryDelay!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _retryDelay = prefs.getInt(_retryDelayKey) ?? defaultRetryDelay;
    return _retryDelay!;
  }

  /// 设置重试延迟时间 (秒)
  Future<void> setRetryDelay(int delaySeconds) async {
    if (delaySeconds < 1 || delaySeconds > 300) {
      throw ArgumentError('重试延迟时间必须在1-300秒之间');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retryDelayKey, delaySeconds);
    _retryDelay = delaySeconds;
  }

  /// 获取是否启用通知
  Future<bool> getEnableNotifications() async {
    if (_enableNotifications != null) {
      return _enableNotifications!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _enableNotifications = prefs.getBool(_enableNotificationsKey) ?? defaultEnableNotifications;
    return _enableNotifications!;
  }

  /// 设置是否启用通知
  Future<void> setEnableNotifications(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableNotificationsKey, enable);
    _enableNotifications = enable;
  }

  /// 获取是否自动开始下载
  Future<bool> getAutoStartDownload() async {
    if (_autoStartDownload != null) {
      return _autoStartDownload!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    _autoStartDownload = prefs.getBool(_autoStartDownloadKey) ?? defaultAutoStartDownload;
    return _autoStartDownload!;
  }

  /// 设置是否自动开始下载
  Future<void> setAutoStartDownload(bool autoStart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartDownloadKey, autoStart);
    _autoStartDownload = autoStart;
  }

  /// 重置所有设置为默认值
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    
    await Future.wait([
      prefs.remove(_maxConcurrentDownloadsKey),
      prefs.remove(_downloadSpeedLimitKey),
      prefs.remove(_autoRetryCountKey),
      prefs.remove(_retryDelayKey),
      prefs.remove(_enableNotificationsKey),
      prefs.remove(_autoStartDownloadKey),
    ]);
    
    // 清除缓存
    _maxConcurrentDownloads = null;
    _downloadSpeedLimit = null;
    _autoRetryCount = null;
    _retryDelay = null;
    _enableNotifications = null;
    _autoStartDownload = null;
  }

  /// 获取所有设置的摘要
  Future<Map<String, dynamic>> getSettingsSummary() async {
    return {
      'maxConcurrentDownloads': await getMaxConcurrentDownloads(),
      'downloadSpeedLimit': await getDownloadSpeedLimit(),
      'autoRetryCount': await getAutoRetryCount(),
      'retryDelay': await getRetryDelay(),
      'enableNotifications': await getEnableNotifications(),
      'autoStartDownload': await getAutoStartDownload(),
    };
  }
}
