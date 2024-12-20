import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/views/video_player.dart';
import 'package:flutter/material.dart';
import 'package:alist_player/utils/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'home_page.dart';

class HistoryEntry {
  final String url;
  final String title;

  HistoryEntry({required this.url, required this.title});
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<StatefulWidget> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  Map<String, List<HistoricalRecord>> _groupedRecords = {};
  bool _isLoading = true;
  String? _currentUsername;
  bool _isTimelineMode = true;
  String? _selectedDirectory;
  bool _isSelectMode = false;
  final Set<String> _selectedItems = <String>{};
  HistoricalRecord? _lastDeletedRecord;
  String? _lastDeletedGroupKey;
  String? _basePath;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _loadHistory();
    _loadBasePath();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;

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

        if (!mounted) return;

        final List<HistoricalRecord> historyRecords =
            records.map((r) => HistoricalRecord.fromMap(r)).toList();

        if (_isTimelineMode) {
          _groupByTimeline(historyRecords);
        } else {
          _groupByDirectory(historyRecords);
        }

        setState(() {
          _isLoading = false;
        });
        _controller.forward(from: 0);
      }
    } catch (e) {
      print('Error loading history: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBasePath() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _basePath = prefs.getString('base_path') ?? '/';
    });
  }

  String _getDisplayPath(String videoPath) {
    if (_basePath == null || _basePath == '/') {
      return videoPath.substring(1);
    }
    return '$_basePath${videoPath.substring(1)}';
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
      final pathParts = record.videoPath.split('/');
      if (pathParts.length >= 2) {
        final lastDirName = pathParts[pathParts.length - 2];
        _groupedRecords.putIfAbsent(lastDirName, () => []);
        _groupedRecords[lastDirName]!.add(record);
      }
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
      if (difference < 7) return '$difference天前';
      return key;
    } else {
      return path.basename(key);
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedItems.clear();
      }
    });
  }

  void _toggleSelect(String videoSha1) {
    setState(() {
      if (_selectedItems.contains(videoSha1)) {
        _selectedItems.remove(videoSha1);
      } else {
        _selectedItems.add(videoSha1);
      }

      if (_selectedItems.isEmpty) {
        _isSelectMode = false;
      }
    });
  }

  Future<void> _deleteRecord(HistoricalRecord record, String groupKey) async {
    try {
      final deletedRecord = record;
      final deletedGroupKey = groupKey;
      final deletedIndex = _groupedRecords[groupKey]?.indexOf(record) ?? 0;

      await _controller.reverse();

      setState(() {
        _groupedRecords[groupKey]?.remove(record);
        if (_groupedRecords[groupKey]?.isEmpty ?? false) {
          _groupedRecords.remove(groupKey);
        }
        _lastDeletedRecord = deletedRecord;
        _lastDeletedGroupKey = deletedGroupKey;
      });

      await _controller.forward();

      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();

      final remainingSeconds = ValueNotifier<int>(3);
      Timer? countdownTimer;

      final snackBar = SnackBar(
        content: Row(
          children: [
            const Text('已删除该记录（'),
            ValueListenableBuilder<int>(
              valueListenable: remainingSeconds,
              builder: (context, seconds, _) => Text(
                '$seconds秒',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Text('内可撤销）'),
          ],
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            countdownTimer?.cancel();
            _undoDelete(deletedIndex);
          },
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      );

      countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (remainingSeconds.value > 0) {
          remainingSeconds.value--;
        } else {
          timer.cancel();
        }
      });

      final result =
          await ScaffoldMessenger.of(context).showSnackBar(snackBar).closed;

      countdownTimer.cancel();
      remainingSeconds.dispose();

      if (result == SnackBarClosedReason.timeout &&
          _lastDeletedRecord == deletedRecord) {
        await DatabaseHelper.instance.deleteHistoricalRecord(record.videoSha1);
        _lastDeletedRecord = null;
        _lastDeletedGroupKey = null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _undoDelete([int? index]) async {
    if (_lastDeletedRecord != null && _lastDeletedGroupKey != null) {
      setState(() {
        _groupedRecords.putIfAbsent(_lastDeletedGroupKey!, () => []);

        if (index != null &&
            index < _groupedRecords[_lastDeletedGroupKey]!.length) {
          _groupedRecords[_lastDeletedGroupKey]!
              .insert(index, _lastDeletedRecord!);
        } else {
          _groupedRecords[_lastDeletedGroupKey]!.add(_lastDeletedRecord!);
        }

        if (!_isTimelineMode) {
          _groupedRecords[_lastDeletedGroupKey]!
              .sort((a, b) => b.changeTime.compareTo(a.changeTime));
        }
      });
      _lastDeletedRecord = null;
      _lastDeletedGroupKey = null;
    }
  }

  Future<void> _deleteSelected() async {
    try {
      if (_selectedItems.isEmpty) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除${_selectedItems.length}条记录'),
          content: const Text('确定要删除选中的记录吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '删除',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        for (var sha1 in _selectedItems) {
          await DatabaseHelper.instance.deleteHistoricalRecord(sha1);
        }

        setState(() {
          _isSelectMode = false;
          _selectedItems.clear();
        });

        await _loadHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除选中的记录')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<(bool, String?)> _checkFileExists(String path) async {
    try {
      final response = await FsApi.get(path: path);
      return (response.code == 200, response.message);
    } catch (e) {
      print('Error checking file: $e');
      return (false, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectMode,
              )
            : (!_isTimelineMode && _selectedDirectory != null)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() => _selectedDirectory = null);
                    },
                  )
                : null,
        title: _isSelectMode
            ? Text('已选择 ${_selectedItems.length} 项')
            : Text(_isTimelineMode
                ? '观看历史'
                : (_selectedDirectory != null
                    ? path.basename(_selectedDirectory!)
                    : '观看历史')),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedItems.isEmpty ? null : _deleteSelected,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _toggleSelectMode,
            ),
            IconButton(
              icon: Icon(_isTimelineMode ? Icons.folder : Icons.access_time),
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadHistory();
          _controller.forward(from: 0);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _groupedRecords.isEmpty
                  ? const Center(child: Text('暂无观看历史'))
                  : _buildContent(),
        ),
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

        final pathParts = latestRecord.videoPath.split('/');
        final lastDirName = pathParts[pathParts.length - 1];

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Interval(
              index * 0.05,
              0.8,
              curve: Curves.easeOutCubic,
            ),
          )),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Interval(
                index * 0.05,
                0.8,
                curve: Curves.easeOut,
              ),
            ),
            child: Card(
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
                              lastDirName,
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
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.2),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: _controller,
        child: IntrinsicHeight(
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
        ),
      ),
    );
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
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, record);
      },
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.3, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        )),
        child: FadeTransition(
          opacity: _controller,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()
              ..scale(_selectedItems.contains(record.videoSha1) ? 0.98 : 1.0),
            child: Dismissible(
              key: Key(record.videoSha1),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              direction: DismissDirection.endToStart,
              confirmDismiss: (direction) async {
                if (_isSelectMode) {
                  _toggleSelect(record.videoSha1);
                  return false;
                }
                return true;
              },
              onDismissed: (direction) {
                final groupKey = _selectedDirectory ??
                    (_isTimelineMode
                        ? record.changeTime
                            .toLocal()
                            .toString()
                            .substring(0, 10)
                        : path.dirname(record.videoPath));
                _deleteRecord(record, groupKey);
              },
              child: Card(
                elevation: 0,
                margin: const EdgeInsets.only(right: 16, bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _selectedItems.contains(record.videoSha1)
                        ? Colors.blue
                        : Colors.grey[200]!,
                  ),
                ),
                child: InkWell(
                  onTap: _isSelectMode
                      ? () => _toggleSelect(record.videoSha1)
                      : () async {
                          // 显示加载指示器
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext context) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                          );

                          // 检查文件是否存在
                          final (exists, errorMessage) =
                              await _checkFileExists(record.videoPath);

                          // 关闭加载指示器
                          if (mounted) {
                            Navigator.pop(context);
                          }

                          if (!mounted) return;

                          if (exists) {
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
                          } else {
                            // 检查是否是文件被移动或删除的错误
                            final isFileMovedOrDeleted = errorMessage?.contains(
                                    AppConstants.fileNotFoundError) ??
                                false;

                            if (isFileMovedOrDeleted) {
                              // 显示删除记录选项
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('该视频文件已不存在或已被移动'),
                                  action: SnackBarAction(
                                    label: '删除记录',
                                    onPressed: () {
                                      final groupKey = _selectedDirectory ??
                                          (_isTimelineMode
                                              ? record.changeTime
                                                  .toLocal()
                                                  .toString()
                                                  .substring(0, 10)
                                              : path.dirname(record.videoPath));
                                      _deleteRecord(record, groupKey);
                                    },
                                  ),
                                ),
                              );
                            } else {
                              // 显示一般错误消息
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('访问文件失败: ${errorMessage ?? "未知错误"}'),
                                ),
                              );
                            }
                          }
                        },
                  onLongPress: () {
                    if (!_isSelectMode) {
                      _toggleSelectMode();
                      _toggleSelect(record.videoSha1);
                    }
                  },
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getDisplayPath(record.videoPath),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              record.videoName,
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
                                Icon(Icons.access_time,
                                    size: 14, color: Colors.grey[600]),
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
                              value: record.totalVideoDuration > 0
                                  ? (record.videoSeek /
                                          record.totalVideoDuration)
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue[400]!),
                              minHeight: 4,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '观看至 ${((record.videoSeek / record.totalVideoDuration) * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isSelectMode)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _selectedItems.contains(record.videoSha1)
                                  ? Colors.blue
                                  : Colors.grey[300],
                            ),
                            child: _selectedItems.contains(record.videoSha1)
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, HistoricalRecord record) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Text('跳转至文件列表'),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    initialUrl: record.videoPath,
                    initialTitle: record.videoName,
                  ),
                ),
              );
            });
          },
        ),
        PopupMenuItem(
          child: const Text('复制链接'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: record.videoPath));
          },
        ),
      ],
    );
  }
}
