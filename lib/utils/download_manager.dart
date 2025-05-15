import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:alist_player/apis/fs.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadTask {
  final String path;
  final String url;
  final String fileName;
  final String filePath;
  double progress = 0;
  String status = '等待中'; // 等待中、下载中、已完成、已暂停、错误
  String? error;
  CancelToken? cancelToken;
  num? totalBytes;
  num receivedBytes = 0;
  num? speed;

  DownloadTask({
    required this.path,
    required this.url,
    required this.fileName,
    required this.filePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'url': url,
      'fileName': fileName,
      'filePath': filePath,
      'progress': progress,
      'status': status,
      'error': error,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'speed': speed,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    var task = DownloadTask(
      path: map['path'],
      url: map['url'],
      fileName: map['fileName'],
      filePath: map['filePath'],
    );
    task.progress = map['progress'];
    task.status = map['status'];
    task.error = map['error'];
    task.receivedBytes = map['receivedBytes'] ?? 0;
    task.totalBytes = map['totalBytes'];
    task.speed = map['speed'];
    return task;
  }
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  DownloadManager._internal() {
    _initNotifications();
    _loadTasks();
  }

  Future<void> _initNotifications() async {
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsDarwin = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );
    await _notifications.initialize(initializationSettings);
  }

  final Map<String, DownloadTask> _tasks = {};
  final _downloadTaskController = ValueNotifier<Map<String, DownloadTask>>({});
  final _dio = Dio();

  // 加载保存的任务
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getStringList('download_tasks') ?? [];

    for (final taskStr in tasksJson) {
      try {
        final taskMap = json.decode(taskStr);
        final task = DownloadTask.fromMap(taskMap);
        if (task.status != '已完成') {
          task.status = '已暂停';
        }
        _tasks[task.path] = task;
      } catch (e) {
        print('Error loading task: $e');
      }
    }
    _downloadTaskController.value = Map.from(_tasks);
  }

  // 保存任务到本地
  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson =
        _tasks.values.map((task) => json.encode(task.toMap())).toList();
    await prefs.setStringList('download_tasks', tasksJson);
  }

  ValueNotifier<Map<String, DownloadTask>> get tasks => _downloadTaskController;

  Future<void> addTask(String path, String fileName) async {
    try {
      // 使用 path + fileName 作为唯一标识
      final taskKey = '$path/$fileName';

      // 检查是否已存在相同的任务
      if (_tasks.containsKey(taskKey)) {
        final existingTask = _tasks[taskKey]!;
        if (existingTask.status == '已暂停') {
          resumeTask(taskKey);
        }
        return;
      }

      // 先获取真实下载地址
      final response = await FsApi.get(path: '${path.substring(1)}/$fileName');
      if (response.code != 200 || response.data?.rawUrl == null) {
        throw Exception('获取下载地址失败: ${response.message}');
      }

      final downloadUrl = response.data!.rawUrl!;
      
      // 获取自定义下载路径
      final downloadDir = await getDownloadPath();
      final filePath = '$downloadDir/$fileName';

      // 创建下载目录
      await Directory(downloadDir).create(recursive: true);

      final task = DownloadTask(
        path: taskKey, // 使用新的唯一标识
        url: downloadUrl,
        fileName: fileName,
        filePath: filePath,
      );

      // 检查是否存在未完成的文件
      final file = File(filePath);
      if (await file.exists()) {
        task.receivedBytes = await file.length();
        task.status = '已暂停';
      }

      _tasks[taskKey] = task; // 使用新的唯一标识作为 key
      _downloadTaskController.value = Map.from(_tasks);

      if (task.status != '已暂停') {
        // 开始下载
        _startDownload(task);
      }
    } catch (e) {
      final taskKey = '$path/$fileName';
      final task = DownloadTask(
        path: taskKey,
        url: path,
        fileName: fileName,
        filePath: '',
      );
      task.status = '错误';
      task.error = e.toString();
      _tasks[taskKey] = task;
      _downloadTaskController.value = Map.from(_tasks);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = '下载中';
    task.cancelToken = CancelToken();
    _updateTask(task);

    try {
      // 获取已下载的文件大小
      final file = File(task.filePath);
      if (await file.exists()) {
        task.receivedBytes = await file.length();
      }

      final response = await _dio.get(
        task.url,
        cancelToken: task.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (task.receivedBytes > 0) 'Range': 'bytes=${task.receivedBytes}-',
          },
          followRedirects: true,
        ),
      );

      final total = int.parse(response.headers.value('content-length') ?? '0');
      task.totalBytes = total + task.receivedBytes;

      final raf = await file.open(mode: FileMode.append);
      var received = task.receivedBytes;

      // 计算下载速度
      final stopwatch = Stopwatch()..start();
      var lastReceivedBytes = task.receivedBytes;

      await for (final chunk in response.data.stream) {
        if (task.cancelToken?.isCancelled == true) break;

        await raf.writeFrom(chunk);
        received += chunk.length;
        task.receivedBytes = received;
        task.progress = (received / task.totalBytes!).toDouble();

        // 每秒更新一次速度
        if (stopwatch.elapsedMilliseconds >= 1000) {
          task.speed = (received - lastReceivedBytes) *
              (1000 / stopwatch.elapsedMilliseconds);
          lastReceivedBytes = received;
          stopwatch.reset();
        }

        _updateTask(task);
      }

      await raf.close();

      if (task.cancelToken?.isCancelled == true) {
        task.status = '已暂停';
      } else {
        task.status = '已完成';
        // 发送通知
        _showNotification(task.fileName);
      }
      _updateTask(task);
    } catch (e) {
      if (!task.cancelToken!.isCancelled) {
        print("Download error: $e");
        task.status = '错误';
        task.error = e.toString();
        _updateTask(task);
      }
    }
  }

  void _updateTask(DownloadTask task) {
    _tasks[task.path] = task;
    _downloadTaskController.value = Map.from(_tasks);
    _saveTasks(); // 保存更新
  }

  Future<void> pauseTask(String path) async {
    final task = _tasks[path];
    if (task != null && task.status == '下载中') {
      task.cancelToken?.cancel('用户暂停下载');
      task.status = '已暂停';
      _updateTask(task);
    }
  }

  Future<void> resumeTask(String path) async {
    final task = _tasks[path];
    if (task != null && task.status == '已暂停') {
      _startDownload(task);
    }
  }

  Future<void> removeTask(String path, {bool deleteFile = true}) async {
    final task = _tasks[path];
    if (task != null) {
      task.cancelToken?.cancel('用户删除任务');
      _tasks.remove(path);
      _downloadTaskController.value = Map.from(_tasks);
      await _saveTasks();

      if (deleteFile) {
        try {
          final file = File(task.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print("Error deleting file: $e");
        }
      }
    }
  }

  Future<void> renameTask(String path, String newFileName) async {
    final task = _tasks[path];
    if (task != null) {
      final directory = await getApplicationDocumentsDirectory();
      final newFilePath = '${directory.path}/alist_player/downloads/$newFileName';

      try {
        final file = File(task.filePath);
        if (await file.exists()) {
          await file.rename(newFilePath);
        }

        final newTask = DownloadTask(
          path: task.path,
          url: task.url,
          fileName: newFileName,
          filePath: newFilePath,
        );
        newTask.status = task.status;
        newTask.progress = task.progress;
        newTask.receivedBytes = task.receivedBytes;
        newTask.totalBytes = task.totalBytes;

        _tasks[path] = newTask;
        _downloadTaskController.value = Map.from(_tasks);
        await _saveTasks();
      } catch (e) {
        print("Error renaming file: $e");
      }
    }
  }

  Future<void> restartTask(String path) async {
    final task = _tasks[path];
    if (task != null) {
      task.progress = 0;
      task.receivedBytes = 0;
      task.totalBytes = null;
      task.status = '等待中';
      task.error = null;
      _updateTask(task);

      try {
        final file = File(task.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print("Error deleting file: $e");
      }

      _startDownload(task);
    }
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

  // 获取当前设置的下载路径
  static Future<String> getCustomDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString('custom_download_path');
    
    if (customPath != null) {
      return customPath;
    }
    
    // 返回默认路径
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/alist_player/downloads';
  }
  
  // 设置自定义下载路径
  static Future<bool> setCustomDownloadPath(String path) async {
    try {
      // 确保目录存在
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // 保存设置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_download_path', path);
      return true;
    } catch (e) {
      print("Error setting custom download path: $e");
      return false;
    }
  }

  // 重置为默认下载路径
  static Future<void> resetToDefaultDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_download_path');
  }

  // 打开文件
  Future<void> openFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      // TODO: 实现文件打开功能
    }
  }

  // 打开文件夹
  static Future<void> openFolder(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      print("Error opening folder: $e");
    }
  }

  // 添加通知方法
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
  
  // 扫描下载文件夹，将未记录的视频文件导入到下载记录中
  Future<int> scanDownloadFolder() async {
    int importedCount = 0;
    try {
      final downloadPath = await getDownloadPath();
      print("Scanning download folder: $downloadPath");
      final directory = Directory(downloadPath);
      
      if (!await directory.exists()) {
        print("Download directory does not exist: $downloadPath");
        return 0;
      }
      
      // 获取当前记录的所有下载文件路径
      final recordedFilePaths = _tasks.values
          .map((task) => task.filePath)
          .toSet();
      
      print("Found ${recordedFilePaths.length} existing records");
      
      // 读取目录下的所有文件
      final List<FileSystemEntity> files = [];
      try {
        files.addAll(await directory.list().toList());
        print("Found ${files.length} files/directories in download folder");
      } catch (e) {
        print("Error listing directory contents: $e");
        return 0;
      }
      
      // 创建一个映射，用于存储文件名到可能原始路径的映射
      // 我们将尝试将导入的文件名与已有的文件命名模式进行匹配
      final Map<String, List<String>> existingFilePatterns = {};
      
      // 从已有的下载任务中收集文件命名模式
      for (final task in _tasks.values) {
        final pathParts = task.path.split('/');
        if (pathParts.length >= 2) {
          final fileName = pathParts.last;
          final parentPath = pathParts.take(pathParts.length - 1).join('/');
          
          // 保存文件名到其父路径的映射
          if (!existingFilePatterns.containsKey(fileName)) {
            existingFilePatterns[fileName] = [];
          }
          existingFilePatterns[fileName]!.add(parentPath);
        }
      }
      
      for (var fileEntity in files) {
        try {
          // 跳过隐藏文件
          final fileName = fileEntity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('.')) {
            continue;
          }
          
          if (fileEntity is File) {
            final filePath = fileEntity.path;
            
            // 如果文件已在记录中，跳过
            if (recordedFilePaths.contains(filePath)) {
              continue;
            }
            
            // 检查是否为视频文件
            if (_isVideoFile(filePath)) {
              print("Found video file: $fileName");
              final fileSize = await fileEntity.length();
              
              // 尝试确定文件的原始路径
              String taskPath;
              
              // 1. 尝试根据文件名匹配已有的下载任务路径模式
              if (existingFilePatterns.containsKey(fileName)) {
                // 如果找到了匹配的文件名，使用其第一个父路径
                taskPath = "${existingFilePatterns[fileName]!.first}/$fileName";
                print("Matched existing path pattern: $taskPath");
              } else {
                // 2. 如果没有匹配的模式，使用通用格式
                taskPath = "/imported/$fileName";
                print("Using generic import path: $taskPath");
              }
              
              // 创建一个已完成的下载任务
              final task = DownloadTask(
                path: taskPath, 
                url: '', // 导入的文件没有URL
                fileName: fileName,
                filePath: filePath,
              );
              task.status = '已完成';
              task.progress = 1.0;
              task.totalBytes = fileSize;
              task.receivedBytes = fileSize;
              
              // 添加到任务列表
              _tasks[task.path] = task;
              importedCount++;
              print("Imported video: $fileName (${_formatSize(fileSize)})");
            }
          }
        } catch (e) {
          // 单个文件处理失败不应该影响整个扫描过程
          print("Error processing file ${fileEntity.path}: $e");
          continue;
        }
      }
      
      if (importedCount > 0) {
        // 更新任务列表并保存
        _downloadTaskController.value = Map.from(_tasks);
        await _saveTasks();
        print("Successfully imported $importedCount videos");
      } else {
        print("No new videos found for import");
      }
      
      return importedCount;
    } catch (e) {
      print("Error scanning download folder: $e");
      if (e is Error) {
        print("Stacktrace: ${e.stackTrace}");
      }
      return 0;
    }
  }
  
  // 格式化文件大小显示
  String _formatSize(num bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(1)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  // 检查文件是否为视频文件
  bool _isVideoFile(String filePath) {
    final videoExtensions = [
      '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', 
      '.mpg', '.mpeg', '.3gp', '.ts', '.mts', '.m2ts'
    ];
    
    final lastDotIndex = filePath.toLowerCase().lastIndexOf('.');
    // 如果文件名中没有点号或点号在无效位置，则不是视频文件
    if (lastDotIndex < 0) {
      return false;
    }
    
    final extension = filePath.toLowerCase().substring(lastDotIndex);
    return videoExtensions.contains(extension);
  }

  // 判断任务是否是导入的任务
  bool isImportedTask(String taskPath) {
    return taskPath.startsWith('/imported/');
  }

  // 获取任务列表中具有相同文件名的任务
  DownloadTask? findTaskByFileName(String fileName) {
    for (final task in _tasks.values) {
      if (task.fileName == fileName && task.status == '已完成') {
        return task;
      }
    }
    return null;
  }
  
  // 获取指定目录和文件名的任务
  DownloadTask? findTask(String path, String fileName) {
    final taskKey = '$path/$fileName';
    if (_tasks.containsKey(taskKey)) {
      return _tasks[taskKey];
    }
    
    // 也尝试查找同名导入任务
    for (final entry in _tasks.entries) {
      if (isImportedTask(entry.key) && entry.value.fileName == fileName) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  // 获取特定路径下的视频文件列表
  Future<List<String>> getLocalVideosInPath(String path) async {
    final result = <String>[];
    try {
      for (final task in _tasks.values) {
        if (task.status == '已完成') {
          // 检查任务路径是否匹配
          if (task.path.startsWith('$path/') || isImportedTask(task.path)) {
            // 对于导入的任务，检查文件是否存在
            final file = File(task.filePath);
            if (await file.exists()) {
              result.add(task.fileName);
            }
          }
        }
      }
    } catch (e) {
      print("Error getting local videos: $e");
    }
    return result;
  }
}
