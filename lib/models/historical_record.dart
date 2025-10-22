import 'dart:typed_data';

class HistoricalRecord {
  final String videoSha1;
  // videoPath是记录到父级 不携带本身的videoName, 如果要获取全路径必须要拼接videoName
  final String videoPath;
  final int videoSeek;
  final int userId;
  final DateTime changeTime;
  final String videoName;
  final int totalVideoDuration;
  final Uint8List? screenshot;

  HistoricalRecord({
    required this.videoSha1,
    // videoPath是记录到父级 不携带本身的videoName, 如果要获取全路径必须要拼接videoName
    required this.videoPath,
    required this.videoSeek,
    required this.userId,
    required this.changeTime,
    required this.videoName,
    required this.totalVideoDuration,
    this.screenshot,
  });

  factory HistoricalRecord.fromMap(Map<String, dynamic> map) {
    return HistoricalRecord(
      videoSha1: map['video_sha1'] as String,
      videoPath: map['video_path'] as String,
      videoSeek: map['video_seek'] as int,
      userId: map['user_id'] as int,
      changeTime: map['change_time'] as DateTime,
      videoName: map['video_name'] as String,
      totalVideoDuration: map['total_video_duration'] as int,
      screenshot: map['screenshot'] as Uint8List?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'video_sha1': videoSha1,
      'video_path': videoPath,
      'video_seek': videoSeek,
      'user_id': userId,
      'video_name': videoName,
      'total_video_duration': totalVideoDuration,
      'screenshot': screenshot,
    };
  }

  double get progressValue {
    if (totalVideoDuration <= 0) return 0.0;
    return (videoSeek / totalVideoDuration).clamp(0.0, 1.0);
  }

  String get progressText {
    if (totalVideoDuration <= 0) return '0%';
    return '${(progressValue * 100).toStringAsFixed(1)}%';
  }
}
