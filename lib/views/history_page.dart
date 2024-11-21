import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webdav_video/models/historical_record.dart';
import 'package:webdav_video/utils/db.dart';
import 'package:webdav_video/views/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:timeago/timeago.dart' as timeago;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<StatefulWidget> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoricalRecord> _historyRecords = [];
  bool _isLoading = true;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      setState(() => _isLoading = true);

      // 获取当前用户
      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('current_username');

      if (_currentUsername != null) {
        final records =
            await DatabaseHelper.instance.getRecentHistoricalRecords(
          userId: _currentUsername!.hashCode,
          limit: 50, // 限制加载数量
        );

        setState(() {
          _historyRecords =
              records.map((r) => HistoricalRecord.fromMap(r)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  // 构建历史记录卡片
  Widget _buildHistoryCard(HistoricalRecord record) {
    // 安全地计算进度值和百分比
    double progressValue = 0.0;
    String progressText = '0%';

    if (record.totalVideoDuration > 0) {
      progressValue = (record.videoSeek / record.totalVideoDuration)
          .clamp(0.0, 1.0); // 确保值在0到1之间
      progressText = '${(progressValue * 100).toStringAsFixed(1)}%';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayer(
                path: record.videoPath,
                name: record.videoName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图
              FutureBuilder<Uint8List?>(
                future: DatabaseHelper.instance.getHistoricalRecordScreenshot(
                  videoSha1: record.videoSha1,
                  userId: record.userId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print('Error loading screenshot: ${snapshot.error}');
                    return _buildPlaceholder();
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildPlaceholder(showLoading: true);
                  }

                  if (snapshot.hasData && snapshot.data != null) {
                    try {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          snapshot.data!,
                          width: 160,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            print('Error displaying image: $error');
                            return _buildPlaceholder();
                          },
                        ),
                      );
                    } catch (e) {
                      print('Error processing image data: $e');
                      return _buildPlaceholder();
                    }
                  }

                  return _buildPlaceholder();
                },
              ),
              const SizedBox(width: 16),
              // 视频信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      path.basename(record.videoName),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '上次播放: ${timeago.format(record.changeTime, locale: 'zh')}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 使用安全的进度值
                    LinearProgressIndicator(
                      value: progressValue,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
                      minHeight: 4, // 设置进度条高度
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '观看至 $progressText',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder({bool showLoading = false}) {
    return Container(
      width: 160,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: showLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.movie, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyRecords.isEmpty) {
      return const Center(
        child: Text(
          '暂无观看记录',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView.builder(
          itemCount: _historyRecords.length,
          itemBuilder: (context, index) =>
              _buildHistoryCard(_historyRecords[index]),
        ),
      ),
    );
  }
}
