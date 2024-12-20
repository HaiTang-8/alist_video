import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:alist_player/apis/fs.dart';
import 'package:dio/dio.dart';

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
  DownloadManager._internal();

  final Map<String, DownloadTask> _tasks = {};
  final _downloadTaskController = ValueNotifier<Map<String, DownloadTask>>({});
  final _dio = Dio();

  ValueNotifier<Map<String, DownloadTask>> get tasks => _downloadTaskController;

  Future<void> addTask(String path, String fileName) async {
    try {
      // 检查是否已存在相同的任务
      if (_tasks.containsKey(path)) {
        final existingTask = _tasks[path]!;
        if (existingTask.status == '已暂停') {
          resumeTask(path);
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
        path: path,
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

      _tasks[path] = task;
      _downloadTaskController.value = Map.from(_tasks);

      if (task.status != '已暂停') {
        // 开始下载
        _startDownload(task);
      }
    } catch (e) {
      final task = DownloadTask(
        path: path,
        url: path,
        fileName: fileName,
        filePath: '',
      );
      task.status = '错误';
      task.error = e.toString();
      _tasks[path] = task;
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

  Future<void> removeTask(String path) async {
    final task = _tasks[path];
    if (task != null) {
      task.cancelToken?.cancel('用户删除任务');
      _tasks.remove(path);
      _downloadTaskController.value = Map.from(_tasks);

      // 删除文件
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
}
