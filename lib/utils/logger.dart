import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 日志级别
enum LogLevel { debug, info, warning, error, fatal }

/// 应用日志管理器
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  AppLogger._internal();

  /// 控制台降级输出，避免在重定向 print 时递归
  void _consoleFallback(String message) {
    try {
      stdout.writeln('[Logger] $message');
    } catch (_) {
      // 忽略控制台输出失败，防止影响业务流程
    }
  }

  static const String _logDirName = 'alist_player/logs';
  static const int _maxLogFiles = 10; // 最多保留10个日志文件
  static const int _maxLogFileSize = 5 * 1024 * 1024; // 5MB

  Directory? _logDirectory;
  File? _currentLogFile;
  bool _isInitialized = false;

  /// 初始化日志系统
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 获取应用文档目录
      final appDocDir = await getApplicationDocumentsDirectory();
      _logDirectory = Directory('${appDocDir.path}/$_logDirName');

      // 创建日志目录
      if (!await _logDirectory!.exists()) {
        await _logDirectory!.create(recursive: true);
      }

      // 创建当前日志文件
      await _createNewLogFile();

      // 清理旧日志文件
      await _cleanupOldLogs();

      _isInitialized = true;

      // 记录初始化成功
      await info('Logger', 'Logger initialized successfully');
      await info('Logger', 'Log directory: ${_logDirectory!.path}');
    } catch (e) {
      _consoleFallback('Failed to initialize logger: $e');
    }
  }

  /// 创建新的日志文件
  Future<void> _createNewLogFile() async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final fileName = 'app_log_$timestamp.log';
    _currentLogFile = File('${_logDirectory!.path}/$fileName');

    // 写入日志文件头部信息
    final header = '''
=== AList Player Log File ===
Created: ${DateTime.now().toIso8601String()}
Platform: ${Platform.operatingSystem}
Version: ${Platform.operatingSystemVersion}
================================

''';
    await _currentLogFile!.writeAsString(header);
  }

  /// 清理旧日志文件
  Future<void> _cleanupOldLogs() async {
    try {
      final logFiles = await _logDirectory!
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // 按修改时间排序
      logFiles
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // 删除超出数量限制的文件
      if (logFiles.length > _maxLogFiles) {
        for (int i = _maxLogFiles; i < logFiles.length; i++) {
          await logFiles[i].delete();
        }
      }
    } catch (e) {
      _consoleFallback('Failed to cleanup old logs: $e');
    }
  }

  /// 检查并轮转日志文件
  Future<void> _checkLogRotation() async {
    if (_currentLogFile == null) return;

    try {
      final fileSize = await _currentLogFile!.length();
      if (fileSize > _maxLogFileSize) {
        await _createNewLogFile();
        await _cleanupOldLogs();
      }
    } catch (e) {
      _consoleFallback('Failed to check log rotation: $e');
    }
  }

  /// 写入日志
  Future<void> _writeLog(LogLevel level, String tag, String message,
      [Object? error, StackTrace? stackTrace]) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      await _checkLogRotation();

      final timestamp = DateTime.now().toIso8601String();
      final levelStr = level.name.toUpperCase().padRight(7);
      final tagStr = tag.padRight(15);

      final logEntry = StringBuffer();
      logEntry.writeln('[$timestamp] $levelStr [$tagStr] $message');

      if (error != null) {
        logEntry.writeln('Error: $error');
      }

      if (stackTrace != null) {
        logEntry.writeln('StackTrace:');
        logEntry.writeln(stackTrace.toString());
      }

      logEntry.writeln('---');

      // 写入文件
      await _currentLogFile?.writeAsString(logEntry.toString(),
          mode: FileMode.append);

      // 在调试模式下也输出到控制台
      if (kDebugMode) {
        _consoleFallback('[$levelStr] [$tagStr] $message');
        if (error != null) {
          _consoleFallback('Error: $error');
        }
      }
    } catch (e) {
      _consoleFallback('Failed to write log: $e');
    }
  }

  /// 捕获由 print / debugPrint 等入口产生的日志
  void captureConsoleOutput(
    String tag,
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (message.isEmpty) return;
    unawaited(
      _writeLog(level, tag, message, error, stackTrace).catchError(
        (Object err, StackTrace stack) {
          _consoleFallback(
            'Failed to capture console output: $err\n$stack',
          );
        },
      ),
    );
  }

  /// Debug 级别日志
  Future<void> debug(String tag, String message) async {
    await _writeLog(LogLevel.debug, tag, message);
  }

  /// Info 级别日志
  Future<void> info(String tag, String message) async {
    await _writeLog(LogLevel.info, tag, message);
  }

  /// Warning 级别日志
  Future<void> warning(String tag, String message, [Object? error]) async {
    await _writeLog(LogLevel.warning, tag, message, error);
  }

  /// Error 级别日志
  Future<void> error(String tag, String message,
      [Object? error, StackTrace? stackTrace]) async {
    await _writeLog(LogLevel.error, tag, message, error, stackTrace);
  }

  /// Fatal 级别日志
  Future<void> fatal(String tag, String message,
      [Object? error, StackTrace? stackTrace]) async {
    await _writeLog(LogLevel.fatal, tag, message, error, stackTrace);
  }

  /// 获取日志目录路径
  String? get logDirectoryPath => _logDirectory?.path;

  /// 获取所有日志文件
  Future<List<File>> getLogFiles() async {
    if (_logDirectory == null) return [];

    try {
      final logFiles = await _logDirectory!
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // 按修改时间排序（最新的在前）
      logFiles
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      return logFiles;
    } catch (e) {
      _consoleFallback('Failed to get log files: $e');
      return [];
    }
  }

  /// 读取指定日志文件内容
  Future<String> readLogFile(File logFile) async {
    try {
      return await logFile.readAsString();
    } catch (e) {
      return 'Failed to read log file: $e';
    }
  }

  /// 导出所有日志到单个文件
  Future<File?> exportAllLogs() async {
    try {
      final logFiles = await getLogFiles();
      if (logFiles.isEmpty) return null;

      final timestamp =
          DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final exportFile =
          File('${_logDirectory!.path}/exported_logs_$timestamp.txt');

      final buffer = StringBuffer();
      buffer.writeln('=== AList Player - Exported Logs ===');
      buffer.writeln('Export Time: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Total Files: ${logFiles.length}');
      buffer.writeln('=====================================\n');

      for (final logFile in logFiles) {
        buffer.writeln('\n=== ${logFile.path.split('/').last} ===');
        final content = await readLogFile(logFile);
        buffer.writeln(content);
        buffer.writeln('\n=== End of ${logFile.path.split('/').last} ===\n');
      }

      await exportFile.writeAsString(buffer.toString());
      return exportFile;
    } catch (e) {
      await error('Logger', 'Failed to export logs', e);
      return null;
    }
  }

  /// 清空所有日志
  Future<void> clearAllLogs() async {
    try {
      final logFiles = await getLogFiles();
      for (final file in logFiles) {
        await file.delete();
      }

      // 重新创建当前日志文件
      await _createNewLogFile();
      await info('Logger', 'All logs cleared');
    } catch (e) {
      _consoleFallback('Failed to clear logs: $e');
    }
  }
}
