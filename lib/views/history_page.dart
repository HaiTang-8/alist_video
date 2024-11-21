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
    double progressValue = 0.0;
    String progressText = '0%';

    if (record.totalVideoDuration > 0) {
      progressValue =
          (record.videoSeek / record.totalVideoDuration).clamp(0.0, 1.0);
      progressText = '${(progressValue * 100).toStringAsFixed(1)}%';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () async {
          // 等待视频播放页面返回
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayer(
                path: record.videoPath,
                name: record.videoName,
              ),
            ),
          );

          // 视频播放页面返回后刷新历史记录
          if (mounted) {
            _loadHistory();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
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
              LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
                minHeight: 4,
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
