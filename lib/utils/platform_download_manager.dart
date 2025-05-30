import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import '../apis/fs.dart';
import 'logger.dart';

// 下载任务状态枚举
enum DownloadStatus {
  waiting,
  downloading,
  completed,
  paused,
  failed,
  canceled
}

// 统一的下载任务模型
class UnifiedDownloadTask {
  final String id;
  final String path;
  final String url;
  final String fileName;
  final String filePath;
  double progress;
  DownloadStatus status;
  String? error;
  int receivedBytes;
  int? totalBytes;
  double? speed;

  // 平台特定的标识符
  String? flutterDownloaderId; // flutter_downloader 的任务ID
  CancelToken? dioToken; // dio 的取消令牌

  UnifiedDownloadTask({
    required this.id,
    required this.path,
    required this.url,
    required this.fileName,
    required this.filePath,
    this.progress = 0,
    this.status = DownloadStatus.waiting,
    this.error,
    this.receivedBytes = 0,
    this.totalBytes,
    this.speed,
    this.flutterDownloaderId,
    this.dioToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'url': url,
      'fileName': fileName,
      'filePath': filePath,
      'progress': progress,
      'status': status.index,
      'error': error,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'speed': speed,
      'flutterDownloaderId': flutterDownloaderId,
    };
  }

  factory UnifiedDownloadTask.fromMap(Map<String, dynamic> map) {
    return UnifiedDownloadTask(
      id: map['id'],
      path: map['path'],
      url: map['url'],
      fileName: map['fileName'],
      filePath: map['filePath'],
      progress: map['progress']?.toDouble() ?? 0.0,
      status: DownloadStatus.values[map['status'] ?? 0],
      error: map['error'],
      receivedBytes: map['receivedBytes'] ?? 0,
      totalBytes: map['totalBytes'],
      speed: map['speed']?.toDouble(),
      flutterDownloaderId: map['flutterDownloaderId'],
    );
  }
}

class PlatformDownloadManager {
  static final PlatformDownloadManager _instance = PlatformDownloadManager._internal();
  factory PlatformDownloadManager() => _instance;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final Map<String, UnifiedDownloadTask> _tasks = {};
  final ValueNotifier<Map<String, UnifiedDownloadTask>> _taskController =
      ValueNotifier<Map<String, UnifiedDownloadTask>>({});

  // Dio 实例用于桌面平台
  final Dio _dio = Dio();

  // 接收端口用于 flutter_downloader 回调
  ReceivePort? _port;

  bool _isInitialized = false;

  PlatformDownloadManager._internal();

  // 获取任务流
  ValueNotifier<Map<String, UnifiedDownloadTask>> get tasks => _taskController;

  // 初始化下载管理器
  Future<void> initialize() async {
    if (_isInitialized) return;

    await AppLogger().info('DownloadManager', 'Initializing download manager...');
    await AppLogger().info('DownloadManager', 'Platform: ${Platform.operatingSystem}');
    await AppLogger().info('DownloadManager', 'Is mobile platform: ${_isMobilePlatform()}');

    try {
      await _initNotifications();
      await AppLogger().info('DownloadManager', 'Notifications initialized');

      // 根据平台初始化不同的下载器
      if (_isMobilePlatform()) {
        await _initFlutterDownloader();
        await AppLogger().info('DownloadManager', 'Flutter downloader initialized');
      } else {
        await AppLogger().info('DownloadManager', 'Using Dio for desktop platform');
      }

      await _loadTasks();
      await AppLogger().info('DownloadManager', 'Tasks loaded: ${_tasks.length}');

      _isInitialized = true;
      await AppLogger().info('DownloadManager', 'Download manager initialized successfully');
    } catch (e, stackTrace) {
      await AppLogger().error('DownloadManager', 'Failed to initialize download manager', e, stackTrace);
      rethrow;
    }
  }

  // 检查是否为移动平台
  bool _isMobilePlatform() {
    return Platform.isAndroid || Platform.isIOS;
  }

  // 初始化通知
  Future<void> _initNotifications() async {
    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsDarwin = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );
    await _notifications.initialize(initializationSettings);
  }

  // 初始化 flutter_downloader（仅移动端）
  Future<void> _initFlutterDownloader() async {
    if (!_isMobilePlatform()) return;

    await AppLogger().info('FlutterDownloader', 'Starting flutter_downloader initialization');

    try {
      // 请求权限
      await _requestPermissions();

      // 初始化 flutter_downloader
      await AppLogger().info('FlutterDownloader', 'Initializing flutter_downloader...');
      await FlutterDownloader.initialize(debug: kDebugMode);
      await AppLogger().info('FlutterDownloader', 'Flutter_downloader initialized successfully');

      // 注册回调端口
      await AppLogger().info('FlutterDownloader', 'Setting up callback port...');
      _port = ReceivePort();
      IsolateNameServer.registerPortWithName(_port!.sendPort, 'downloader_send_port');
      _port!.listen((dynamic data) {
        _handleDownloadCallback(data);
      });

      // 注册回调
      FlutterDownloader.registerCallback(downloadCallback);
      await AppLogger().info('FlutterDownloader', 'Callback registered successfully');

    } catch (e, stackTrace) {
      await AppLogger().error('FlutterDownloader', 'Failed to initialize flutter_downloader', e, stackTrace);
      rethrow;
    }
  }

  // 请求权限（移动端）
  Future<void> _requestPermissions() async {
    await AppLogger().info('Permissions', 'Requesting permissions...');

    if (Platform.isAndroid) {
      try {
        await AppLogger().info('Permissions', 'Requesting storage permission...');
        final storageStatus = await Permission.storage.request();
        await AppLogger().info('Permissions', 'Storage permission status: $storageStatus');

        await AppLogger().info('Permissions', 'Requesting notification permission...');
        final notificationStatus = await Permission.notification.request();
        await AppLogger().info('Permissions', 'Notification permission status: $notificationStatus');

        // 检查是否需要请求忽略电池优化
        await AppLogger().info('Permissions', 'Checking battery optimization...');
        final batteryOptimizationStatus = await Permission.ignoreBatteryOptimizations.status;
        await AppLogger().info('Permissions', 'Battery optimization status: $batteryOptimizationStatus');

        if (batteryOptimizationStatus != PermissionStatus.granted) {
          await AppLogger().info('Permissions', 'Requesting ignore battery optimizations...');
          final batteryResult = await Permission.ignoreBatteryOptimizations.request();
          await AppLogger().info('Permissions', 'Battery optimization request result: $batteryResult');
        }

      } catch (e, stackTrace) {
        await AppLogger().error('Permissions', 'Failed to request permissions', e, stackTrace);
      }
    } else if (Platform.isIOS) {
      try {
        await AppLogger().info('Permissions', 'Requesting iOS notification permission...');
        final notificationStatus = await Permission.notification.request();
        await AppLogger().info('Permissions', 'iOS notification permission status: $notificationStatus');
      } catch (e, stackTrace) {
        await AppLogger().error('Permissions', 'Failed to request iOS permissions', e, stackTrace);
      }
    }

    await AppLogger().info('Permissions', 'Permission requests completed');
  }

  // flutter_downloader 回调处理
  void _handleDownloadCallback(List<dynamic> data) {
    final String id = data[0];
    final int statusInt = data[1];
    final int progress = data[2];

    final task = _tasks.values.firstWhere(
      (task) => task.flutterDownloaderId == id,
      orElse: () => throw StateError('Task not found'),
    );

    // 更新任务状态
    task.progress = progress / 100.0;

    // 根据状态整数值转换为对应的状态
    switch (statusInt) {
      case 2: // DownloadTaskStatus.running
        task.status = DownloadStatus.downloading;
        break;
      case 3: // DownloadTaskStatus.complete
        task.status = DownloadStatus.completed;
        _showNotification(task.fileName);
        break;
      case 4: // DownloadTaskStatus.paused
        task.status = DownloadStatus.paused;
        break;
      case 5: // DownloadTaskStatus.failed
        task.status = DownloadStatus.failed;
        break;
      case 6: // DownloadTaskStatus.canceled
        task.status = DownloadStatus.canceled;
        break;
      default:
        break;
    }

    _updateTask(task);
  }

  // 静态回调函数（flutter_downloader 要求）
  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  // 加载保存的任务
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getStringList('unified_download_tasks') ?? [];

    for (final taskStr in tasksJson) {
      try {
        final taskMap = json.decode(taskStr);
        final task = UnifiedDownloadTask.fromMap(taskMap);

        // 如果任务未完成，设置为暂停状态
        if (task.status != DownloadStatus.completed) {
          task.status = DownloadStatus.paused;
        }

        _tasks[task.id] = task;
      } catch (e) {
        debugPrint('Error loading task: $e');
      }
    }
    _taskController.value = Map.from(_tasks);
  }

  // 保存任务
  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = _tasks.values.map((task) => json.encode(task.toMap())).toList();
    await prefs.setStringList('unified_download_tasks', tasksJson);
  }

  // 更新任务
  void _updateTask(UnifiedDownloadTask task) {
    _tasks[task.id] = task;
    _taskController.value = Map.from(_tasks);
    _saveTasks();
  }

  // 显示通知
  void _showNotification(String fileName) async {
    const androidDetails = AndroidNotificationDetails(
      'downloads',
      '下载通知',
      channelDescription: '显示下载完成通知',
      importance: Importance.defaultImportance,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '下载完成',
      '$fileName 已下载完成',
      details,
    );
  }

  // 获取下载目录路径
  static Future<String> getDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString('custom_download_path');

    if (customPath != null && await Directory(customPath).exists()) {
      return customPath;
    }

    // 默认路径
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/alist_player/downloads';
  }

  // 添加下载任务
  Future<void> addTask(String path, String fileName) async {
    final taskId = '${path}_$fileName';
    await AppLogger().info('DownloadTask', 'Adding download task: $taskId');

    try {
      if (!_isInitialized) {
        await AppLogger().info('DownloadTask', 'Download manager not initialized, initializing...');
        await initialize();
      }

      // 检查是否已存在相同的任务
      if (_tasks.containsKey(taskId)) {
        await AppLogger().info('DownloadTask', 'Task already exists: $taskId');
        final existingTask = _tasks[taskId]!;
        if (existingTask.status == DownloadStatus.paused) {
          await AppLogger().info('DownloadTask', 'Resuming existing paused task: $taskId');
          await resumeTask(taskId);
        }
        return;
      }

      await AppLogger().info('DownloadTask', 'Getting download URL for: $path/$fileName');

      // 获取真实下载地址
      final response = await FsApi.get(path: '${path.substring(1)}/$fileName');
      if (response.code != 200 || response.data?.rawUrl == null) {
        throw Exception('获取下载地址失败: ${response.message}');
      }

      final downloadUrl = response.data!.rawUrl!;
      await AppLogger().info('DownloadTask', 'Download URL obtained: $downloadUrl');

      // 获取下载路径
      final downloadDir = await getDownloadPath();
      final filePath = '$downloadDir/$fileName';
      await AppLogger().info('DownloadTask', 'Download path: $filePath');

      // 创建下载目录
      await Directory(downloadDir).create(recursive: true);
      await AppLogger().info('DownloadTask', 'Download directory created/verified');

      final task = UnifiedDownloadTask(
        id: taskId,
        path: path,
        url: downloadUrl,
        fileName: fileName,
        filePath: filePath,
      );

      // 检查是否存在未完成的文件
      final file = File(filePath);
      if (await file.exists()) {
        task.receivedBytes = await file.length();
        task.status = DownloadStatus.paused;
        await AppLogger().info('DownloadTask', 'Found existing partial file: ${task.receivedBytes} bytes');
      }

      _tasks[taskId] = task;
      _taskController.value = Map.from(_tasks);
      await AppLogger().info('DownloadTask', 'Task added to queue: $taskId');

      if (task.status != DownloadStatus.paused) {
        await AppLogger().info('DownloadTask', 'Starting download: $taskId');
        await _startDownload(task);
      }
    } catch (e, stackTrace) {
      await AppLogger().error('DownloadTask', 'Failed to add download task: $taskId', e, stackTrace);

      final task = UnifiedDownloadTask(
        id: taskId,
        path: path,
        url: '',
        fileName: fileName,
        filePath: '',
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      _tasks[taskId] = task;
      _taskController.value = Map.from(_tasks);
    }
  }

  // 开始下载
  Future<void> _startDownload(UnifiedDownloadTask task) async {
    task.status = DownloadStatus.downloading;
    _updateTask(task);

    if (_isMobilePlatform()) {
      await _startMobileDownload(task);
    } else {
      await _startDesktopDownload(task);
    }
  }

  // 移动端下载（使用 flutter_downloader）
  Future<void> _startMobileDownload(UnifiedDownloadTask task) async {
    await AppLogger().info('MobileDownload', 'Starting mobile download for: ${task.fileName}');
    await AppLogger().info('MobileDownload', 'URL: ${task.url}');
    await AppLogger().info('MobileDownload', 'Save path: ${task.filePath}');

    try {
      final downloadDir = await getDownloadPath();
      await AppLogger().info('MobileDownload', 'Download directory: $downloadDir');

      final taskId = await FlutterDownloader.enqueue(
        url: task.url,
        savedDir: downloadDir,
        fileName: task.fileName,
        showNotification: true,
        openFileFromNotification: false,
        saveInPublicStorage: false,
      );

      if (taskId != null) {
        task.flutterDownloaderId = taskId;
        await AppLogger().info('MobileDownload', 'Flutter downloader task created: $taskId');
        _updateTask(task);
      } else {
        throw Exception('Flutter downloader returned null task ID');
      }
    } catch (e, stackTrace) {
      await AppLogger().error('MobileDownload', 'Mobile download failed for: ${task.fileName}', e, stackTrace);
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      _updateTask(task);
    }
  }

  // 桌面端下载（使用 dio）
  Future<void> _startDesktopDownload(UnifiedDownloadTask task) async {
    task.dioToken = CancelToken();

    try {
      // 获取已下载的文件大小
      final file = File(task.filePath);
      if (await file.exists()) {
        task.receivedBytes = await file.length();
      }

      final response = await _dio.get(
        task.url,
        cancelToken: task.dioToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (task.receivedBytes > 0) 'Range': 'bytes=${task.receivedBytes}-',
          },
          followRedirects: true,
        ),
      );

      // 获取文件总大小
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        final totalBytes = int.parse(contentLength);
        task.totalBytes = task.receivedBytes + totalBytes;
      }

      // 打开文件进行写入
      final raf = await file.open(mode: FileMode.append);
      final stream = response.data.stream;

      await for (final data in stream) {
        if (task.dioToken?.isCancelled == true) break;

        await raf.writeFrom(data);
        task.receivedBytes += data.length as int;

        if (task.totalBytes != null && task.totalBytes! > 0) {
          task.progress = task.receivedBytes / task.totalBytes!;
        }

        _updateTask(task);
      }

      await raf.close();

      if (task.dioToken?.isCancelled == true) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.completed;
        _showNotification(task.fileName);
      }
      _updateTask(task);
    } catch (e) {
      if (task.dioToken?.isCancelled != true) {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
        _updateTask(task);
      }
    }
  }

  // 暂停任务
  Future<void> pauseTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.downloading) return;

    if (_isMobilePlatform() && task.flutterDownloaderId != null) {
      await FlutterDownloader.pause(taskId: task.flutterDownloaderId!);
    } else if (task.dioToken != null) {
      task.dioToken!.cancel('用户暂停下载');
    }

    task.status = DownloadStatus.paused;
    _updateTask(task);
  }

  // 恢复任务
  Future<void> resumeTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.paused) return;

    if (_isMobilePlatform() && task.flutterDownloaderId != null) {
      final newTaskId = await FlutterDownloader.resume(taskId: task.flutterDownloaderId!);
      if (newTaskId != null) {
        task.flutterDownloaderId = newTaskId;
      }
    } else {
      await _startDesktopDownload(task);
    }
  }

  // 删除任务
  Future<void> removeTask(String taskId, {bool deleteFile = true}) async {
    final task = _tasks[taskId];
    if (task == null) return;

    // 取消下载
    if (task.status == DownloadStatus.downloading) {
      await pauseTask(taskId);
    }

    // 删除 flutter_downloader 任务
    if (_isMobilePlatform() && task.flutterDownloaderId != null) {
      await FlutterDownloader.remove(taskId: task.flutterDownloaderId!, shouldDeleteContent: deleteFile);
    }

    // 删除文件
    if (deleteFile) {
      try {
        final file = File(task.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Error deleting file: $e");
      }
    }

    _tasks.remove(taskId);
    _taskController.value = Map.from(_tasks);
    await _saveTasks();
  }

  // 重新开始任务
  Future<void> restartTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    // 重置任务状态
    task.progress = 0;
    task.receivedBytes = 0;
    task.totalBytes = null;
    task.status = DownloadStatus.waiting;
    task.error = null;
    task.flutterDownloaderId = null;
    task.dioToken = null;
    _updateTask(task);

    // 删除现有文件
    try {
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("Error deleting file: $e");
    }

    // 重新开始下载
    await _startDownload(task);
  }

  // 获取当前使用的下载方法
  String getCurrentDownloadMethod() {
    if (_isMobilePlatform()) {
      return 'Flutter Downloader (支持后台下载)';
    } else {
      return 'Dio HTTP Client (桌面端)';
    }
  }

  // 释放资源
  void dispose() {
    _port?.close();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }
}
