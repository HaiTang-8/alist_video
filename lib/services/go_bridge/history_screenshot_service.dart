import 'dart:convert';
import 'dart:typed_data';

import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:dio/dio.dart';

/// Go 本地服务截图相关的 HTTP 封装，统一负责上传与下载逻辑
class GoHistoryScreenshotService {
  GoHistoryScreenshotService._();

  static Dio? _client;
  static String? _cachedBaseUrl;
  static String? _cachedToken;

  static bool get _isGoBridgeEnabled =>
      DatabaseHelper.instance.currentDriverType ==
      DatabasePersistenceType.localGoBridge;

  static DatabaseConnectionConfig? get _currentConfig =>
      DatabaseHelper.instance.currentConfig;

  static Dio? _ensureClient() {
    if (!_isGoBridgeEnabled) {
      return null;
    }

    final config = _currentConfig;
    if (config == null) {
      return null;
    }

    final baseUrl =
        (config.goBridgeEndpoint ?? AppConstants.defaultGoBridgeEndpoint)
            .trim();
    final token = (config.goBridgeAuthToken ?? '').trim();

    final shouldRebuild =
        _client == null || _cachedBaseUrl != baseUrl || _cachedToken != token;

    if (shouldRebuild) {
      _client = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: AppConstants.apiConnectTimeout,
          receiveTimeout: AppConstants.apiReceiveTimeout,
          headers: {
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );
      _cachedBaseUrl = baseUrl;
      _cachedToken = token;
    }

    return _client;
  }

  /// 上传截图到 Go 服务侧进行集中管理，确保多端能共享历史缩略图
  static Future<void> uploadScreenshot({
    required String videoSha1,
    required int userId,
    required String videoName,
    required String videoPath,
    required Uint8List bytes,
    required bool isJpeg,
  }) async {
    final client = _ensureClient();
    if (client == null) {
      return;
    }

    try {
      final payload = {
        'videoSha1': videoSha1,
        'userId': userId,
        'videoName': videoName,
        'videoPath': videoPath,
        'isJpeg': isJpeg,
        'imageBase64': base64Encode(bytes),
      };

      await client.post('/history/screenshot', data: payload);
    } on DioException catch (e) {
      AppLogger().captureConsoleOutput(
        'GoHistoryScreenshotService',
        '截图上传失败 videoSha1=$videoSha1 userId=$userId',
        level: LogLevel.warning,
        error: e,
        stackTrace: e.stackTrace,
      );
    }
  }

  /// 拉取远端截图并返回原始二进制，用于历史列表兜底显示
  static Future<RemoteScreenshotResult?> downloadScreenshot({
    required String videoSha1,
    required int userId,
  }) async {
    final client = _ensureClient();
    if (client == null) {
      return null;
    }

    try {
      final response = await client.get<List<int>>(
        '/history/screenshot',
        queryParameters: {
          'videoSha1': videoSha1,
          'userId': userId.toString(),
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        return null;
      }

      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? 'image/jpeg';
      final isJpeg = contentType.toLowerCase().contains('jpeg') ||
          contentType.toLowerCase().contains('jpg');

      return RemoteScreenshotResult(
        bytes: Uint8List.fromList(data),
        isJpeg: isJpeg,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }

      AppLogger().captureConsoleOutput(
        'GoHistoryScreenshotService',
        '截图下载失败 videoSha1=$videoSha1 userId=$userId',
        level: LogLevel.warning,
        error: e,
        stackTrace: e.stackTrace,
      );
      return null;
    }
  }

  /// 触发 Go 服务执行截图目录同步，可选择 dryRun 以获取删除预览结果。
  static Future<GoScreenshotSyncStats?> syncScreenshots({
    bool dryRun = true,
    int previewLimit = 200,
  }) async {
    final client = _ensureClient();
    if (client == null) {
      return null;
    }

    try {
      final response = await client.post<Map<String, dynamic>>(
        '/history/screenshot/sync',
        data: {
          'dryRun': dryRun,
          'previewLimit': previewLimit,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Go 服务未返回同步结果');
      }
      return GoScreenshotSyncStats.fromJson(data);
    } on DioException catch (e) {
      AppLogger().captureConsoleOutput(
        'GoHistoryScreenshotService',
        '截图目录同步失败，dryRun=$dryRun',
        level: LogLevel.error,
        error: e,
        stackTrace: e.stackTrace,
      );
      rethrow;
    }
  }
}

/// 远端截图下载结果，携带图片格式方便选择本地缓存扩展名
class RemoteScreenshotResult {
  final Uint8List bytes;
  final bool isJpeg;

  const RemoteScreenshotResult({
    required this.bytes,
    required this.isJpeg,
  });
}

/// 对齐截图目录后的统计数据，供前端展示执行细节。
class GoScreenshotSyncStats {
  final bool dryRun;
  final int totalCandidates;
  final int orphanCandidates;
  final int deletedFiles;
  final int skippedEntries;
  final int durationMillis;
  final List<String> orphanFiles;
  final List<GoScreenshotOrphanDetail> orphanDetails;
  final int orphanPreviewLimit;
  final int orphanOverflow;
  final List<String> errors;

  const GoScreenshotSyncStats({
    required this.dryRun,
    required this.totalCandidates,
    required this.orphanCandidates,
    required this.deletedFiles,
    required this.skippedEntries,
    required this.durationMillis,
    required this.orphanFiles,
    required this.orphanDetails,
    required this.orphanPreviewLimit,
    required this.orphanOverflow,
    required this.errors,
  });

  factory GoScreenshotSyncStats.fromJson(Map<String, dynamic> json) {
    List<String> coerceList(dynamic value) {
      if (value == null) return const [];
      if (value is List) {
        return value.map((e) => e.toString()).toList(growable: false);
      }
      return [value.toString()];
    }

    Map<String, dynamic> coerceMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
      return const {};
    }

    final details = <GoScreenshotOrphanDetail>[];
    final detailList = json['orphanDetails'];
    if (detailList is List) {
      for (final item in detailList) {
        details.add(GoScreenshotOrphanDetail.fromJson(coerceMap(item)));
      }
    }

    return GoScreenshotSyncStats(
      dryRun: json['dryRun'] as bool? ?? true,
      totalCandidates: json['totalCandidates'] as int? ?? 0,
      orphanCandidates: json['orphanCandidates'] as int? ?? 0,
      deletedFiles: json['deletedFiles'] as int? ?? 0,
      skippedEntries: json['skippedEntries'] as int? ?? 0,
      durationMillis: json['durationMillis'] as int? ?? 0,
      orphanFiles: coerceList(json['orphanFiles']),
      orphanDetails: details,
      orphanPreviewLimit: json['orphanPreviewLimit'] as int? ?? 0,
      orphanOverflow: json['orphanOverflow'] as int? ?? 0,
      errors: coerceList(json['errors']),
    );
  }
}

class GoScreenshotOrphanDetail {
  final int userId;
  final String videoSha1;
  final String relativePath;
  final int sizeBytes;
  final DateTime? modTime;

  const GoScreenshotOrphanDetail({
    required this.userId,
    required this.videoSha1,
    required this.relativePath,
    required this.sizeBytes,
    required this.modTime,
  });

  factory GoScreenshotOrphanDetail.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toLocal();
      }
      return null;
    }

    return GoScreenshotOrphanDetail(
      userId: json['userId'] is int
          ? json['userId'] as int
          : int.tryParse(json['userId']?.toString() ?? '') ?? 0,
      videoSha1: json['videoSha1']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '',
      sizeBytes: json['sizeBytes'] is int
          ? json['sizeBytes'] as int
          : int.tryParse(json['sizeBytes']?.toString() ?? '') ?? 0,
      modTime: parseTime(json['modTime']),
    );
  }
}
