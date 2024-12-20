import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:alist_player/apis/fs.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

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
    return task;
  }
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  final Map<String, DownloadTask> _tasks = {};
  final _downloadTaskController = ValueNotifier<Map<String, DownloadTask>>({});
  final _dio = Dio();

  DownloadManager._internal() {
    // 初始化时加载保存的任务
    _loadTasks();
  }

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
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/downloads/$fileName';

      // 创建下载目录
      await Directory('${directory.path}/downloads').create(recursive: true);

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

      await for (final chunk in response.data.stream) {
        if (task.cancelToken?.isCancelled == true) break;

        await raf.writeFrom(chunk);
        received += chunk.length.toInt();
        task.receivedBytes = received;
        task.progress = (received / task.totalBytes!).toDouble();
        _updateTask(task);
      }

      await raf.close();

      if (task.cancelToken?.isCancelled == true) {
        task.status = '已暂停';
      } else {
        task.status = '已完成';
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
      final newFilePath = '${directory.path}/downloads/$newFileName';

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
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/downloads';
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
}
