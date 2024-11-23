import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/views/video_player.dart';
import 'package:flutter/material.dart';
import 'package:alist_player/utils/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:timeago/timeago.dart' as timeago;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<StatefulWidget> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // 添加分组数据结构
  Map<String, List<HistoricalRecord>> _groupedRecords = {};
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
      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('current_username');

      if (_currentUsername != null) {
        final records =
            await DatabaseHelper.instance.getRecentHistoricalRecords(
          userId: _currentUsername!.hashCode,
          limit: 50,
        );

        // 按日期分组
        _groupedRecords = {};
        for (var record in records.map((r) => HistoricalRecord.fromMap(r))) {
          final date = DateTime(
            record.changeTime.year,
            record.changeTime.month,
            record.changeTime.day,
          );
          final dateKey = date.toString().substring(0, 10);
          _groupedRecords.putIfAbsent(dateKey, () => []);
          _groupedRecords[dateKey]!.add(record);
        }

        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  // 删除单个历史记录
  Future<void> _deleteRecord(HistoricalRecord record) async {
    try {
      await DatabaseHelper.instance.deleteHistoricalRecord(record.videoSha1);
      // 刷新列表
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除该记录')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  // 清空所有历史记录
  Future<void> _clearAllHistory() async {
    try {
      if (_currentUsername != null) {
        await DatabaseHelper.instance.clearUserHistoricalRecords(
          _currentUsername!.hashCode,
        );
        await _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清空所有记录')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e')),
        );
      }
    }
  }

  // 修改日期组标题样式
  Widget _buildDateGroup(String dateKey, List<HistoricalRecord> records) {
    return IntrinsicHeight(
      child: Row(
        children: [
          // 时间轴
          SizedBox(
            width: 60,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 24,
                  color: Colors.grey[300],
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        _getDateTitle(dateKey),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${records.length})',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                ...records.map((record) => _buildHistoryCard(record)),
                const SizedBox(height: 16), // 底部间距
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 获取日期标题
  String _getDateTitle(String dateKey) {
    final now = DateTime.now();
    final date = DateTime.parse(dateKey);
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return '今天';
    } else if (difference == 1) {
      return '昨天';
    } else if (difference < 7) {
      return '${difference}天前';
    } else {
      return dateKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          // 添加清空按钮
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _groupedRecords.isEmpty
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清空历史记录'),
                        content: const Text('确定要清空所有历史记录吗？此操作不可恢复。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _clearAllHistory();
                            },
                            child: const Text(
                              '确定',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: _groupedRecords.isEmpty
            ? const Center(child: Text('暂无观看历史'))
            : ListView.builder(
                itemCount: _groupedRecords.length,
                itemBuilder: (context, index) {
                  final dateKey = _groupedRecords.keys.elementAt(index);
                  final records = _groupedRecords[dateKey]!;
                  return _buildDateGroup(dateKey, records);
                },
              ),
      ),
    );
  }

  // 调整卡片样式
  Widget _buildHistoryCard(HistoricalRecord record) {
    double progressValue = 0.0;
    String progressText = '0%';

    if (record.totalVideoDuration > 0) {
      progressValue =
          (record.videoSeek / record.totalVideoDuration).clamp(0.0, 1.0);
      progressText = '${(progressValue * 100).toStringAsFixed(1)}%';
    }

    return Dismissible(
      key: Key(record.videoSha1),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _deleteRecord(record),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(right: 16, bottom: 8), // 调整边距以适应时间轴
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey[200]!),
        ),
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
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${timeago.format(record.changeTime, locale: 'zh')} · ${record.changeTime.toLocal().toString().substring(0, 16)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
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
      ),
    );
  }
}
