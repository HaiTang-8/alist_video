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
  Map<String, List<HistoricalRecord>> _groupedRecords = {};
  bool _isLoading = true;
  String? _currentUsername;
  bool _isTimelineMode = true;
  String? _selectedDirectory;

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

        final List<HistoricalRecord> historyRecords =
            records.map((r) => HistoricalRecord.fromMap(r)).toList();

        if (_isTimelineMode) {
          _groupByTimeline(historyRecords);
        } else {
          _groupByDirectory(historyRecords);
        }

        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  void _groupByTimeline(List<HistoricalRecord> records) {
    _groupedRecords = {};
    for (var record in records) {
      final localTime = record.changeTime.toLocal();
      final date = DateTime(
        localTime.year,
        localTime.month,
        localTime.day,
      );
      final dateKey = date.toString().substring(0, 10);
      _groupedRecords.putIfAbsent(dateKey, () => []);
      _groupedRecords[dateKey]!.add(record);
    }
  }

  void _groupByDirectory(List<HistoricalRecord> records) {
    _groupedRecords = {};
    for (var record in records) {
      final dirPath = path.dirname(record.videoPath);
      _groupedRecords.putIfAbsent(dirPath, () => []);
      _groupedRecords[dirPath]!.add(record);
    }

    _groupedRecords.forEach((key, list) {
      list.sort((a, b) => b.changeTime.compareTo(a.changeTime));
    });

    final sortedKeys = _groupedRecords.keys.toList()
      ..sort((a, b) {
        final aTime = _groupedRecords[a]!.first.changeTime;
        final bTime = _groupedRecords[b]!.first.changeTime;
        return bTime.compareTo(aTime);
      });

    final sortedMap = Map<String, List<HistoricalRecord>>.fromEntries(
        sortedKeys.map((key) => MapEntry(key, _groupedRecords[key]!)));
    _groupedRecords = sortedMap;
  }

  String _getGroupTitle(String key) {
    if (_isTimelineMode) {
      final now = DateTime.now();
      final date = DateTime.parse(key);
      final localDate = date.toLocal();
      final localNow = now.toLocal();

      final isSameDay = localDate.year == localNow.year &&
          localDate.month == localNow.month &&
          localDate.day == localNow.day;

      final isYesterday = localDate.year == localNow.year &&
          localDate.month == localNow.month &&
          localDate.day == localNow.day - 1;

      if (isSameDay) return '今天';
      if (isYesterday) return '昨天';

      final difference = localNow.difference(localDate).inDays;
      if (difference < 7) return '${difference}天前';
      return key;
    } else {
      return path.basename(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isTimelineMode
            ? '观看历史'
            : (_selectedDirectory != null
                ? path.basename(_selectedDirectory!)
                : '观看历史')),
        leading: !_isTimelineMode && _selectedDirectory != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _selectedDirectory = null);
                },
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(_isTimelineMode ? Icons.folder : Icons.access_time),
            tooltip: _isTimelineMode ? '切换到目录视图' : '切换到时间线视图',
            onPressed: () {
              setState(() {
                _isTimelineMode = !_isTimelineMode;
                _selectedDirectory = null;
                _loadHistory();
              });
            },
          ),
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
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (!_isTimelineMode && _selectedDirectory == null) {
      return _buildDirectoryList();
    } else if (!_isTimelineMode && _selectedDirectory != null) {
      return _buildDirectoryTimeline(_selectedDirectory!);
    } else {
      return _buildTimelineView();
    }
  }

  Widget _buildDirectoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groupedRecords.length,
      itemBuilder: (context, index) {
        final dirPath = _groupedRecords.keys.elementAt(index);
        final records = _groupedRecords[dirPath]!;
        final latestRecord = records.first;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() => _selectedDirectory = dirPath);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          path.basename(dirPath),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${records.length}个视频',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '最近观看：${timeago.format(latestRecord.changeTime, locale: 'zh')}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDirectoryTimeline(String dirPath) {
    final records = _groupedRecords[dirPath]!;
    final timelineRecords = <String, List<HistoricalRecord>>{};

    for (var record in records) {
      final localTime = record.changeTime.toLocal();
      final date = DateTime(
        localTime.year,
        localTime.month,
        localTime.day,
      );
      final dateKey = date.toString().substring(0, 10);
      timelineRecords.putIfAbsent(dateKey, () => []);
      timelineRecords[dateKey]!.add(record);
    }

    return ListView.builder(
      itemCount: timelineRecords.length,
      itemBuilder: (context, index) {
        final dateKey = timelineRecords.keys.elementAt(index);
        final dateRecords = timelineRecords[dateKey]!;
        return _buildDateGroup(dateKey, dateRecords);
      },
    );
  }

  Widget _buildTimelineView() {
    return ListView.builder(
      itemCount: _groupedRecords.length,
      itemBuilder: (context, index) {
        final key = _groupedRecords.keys.elementAt(index);
        final records = _groupedRecords[key]!;
        return _buildDateGroup(key, records);
      },
    );
  }

  Widget _buildDateGroup(String key, List<HistoricalRecord> records) {
    return IntrinsicHeight(
      child: Row(
        children: [
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        _getGroupTitle(key),
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(HistoricalRecord record) async {
    try {
      await DatabaseHelper.instance.deleteHistoricalRecord(record.videoSha1);
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

  Widget _buildHistoryCard(HistoricalRecord record) {
    double progressValue = 0.0;
    String progressText = '0%';

    if (record.totalVideoDuration > 0) {
      progressValue =
          (record.videoSeek / record.totalVideoDuration).clamp(0.0, 1.0);
      progressText = '${(progressValue * 100).toStringAsFixed(1)}%';
    }

    String parentDirName = record.videoPath.substring(1);
    String videoName = path.basename(record.videoName);

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
        margin: const EdgeInsets.only(right: 16, bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey[200]!),
        ),
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayer(
                  path: record.videoPath,
                  name: record.videoName,
                ),
              ),
            );

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
                  parentDirName,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  videoName,
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
