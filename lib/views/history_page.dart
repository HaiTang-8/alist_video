import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/views/video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:alist_player/utils/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'home_page.dart';
import 'package:alist_player/utils/download_manager.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:alist_player/services/go_bridge/history_screenshot_service.dart';

// Add this extension to avoid importing additional packages
extension FutureExtensions<T> on Future<T> {
  void unawaited() {}
}

class HistoryEntry {
  final String url;
  final String title;

  HistoryEntry({required this.url, required this.title});
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.refreshSignal});

  /// 当外部 ValueListenable 数值变化时，需重新加载历史记录以保证数据实时
  final ValueListenable<int>? refreshSignal;

  @override
  State<StatefulWidget> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  Map<String, List<HistoricalRecord>> _groupedRecords = {};
  bool _isLoading = true;
  String? _currentUsername;
  bool _isTimelineMode = true;
  bool _isCompactMode = true;
  String? _selectedDirectory;
  bool _isSelectMode = false;
  final Set<String> _selectedItems = <String>{};
  HistoricalRecord? _lastDeletedRecord;
  String? _lastDeletedGroupKey;
  String? _basePath;
  late final AnimationController _controller;
  int? _lastRefreshSignalValue;

  // Cache for screenshot paths to avoid repeated file checks
  final Map<String, String?> _screenshotPathCache = {};

  @override
  bool get wantKeepAlive => true;

  // 瀑布流相关状态
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  List<HistoricalRecord> _allRecords = [];
  int _totalRecords = 0;

  // 搜索相关状态
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<HistoricalRecord> _searchResults = [];
  int _searchTotalRecords = 0;
  Timer? _searchDebounceTimer;

  /// 历史页统一日志输出，方便定位分页/搜索异常
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'HistoryPage',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scrollController.addListener(_onScroll);
    _setupRefreshSignalListener();
    _loadHistory();
    _loadBasePath();

    // Preload screenshots in the background after loading history
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadScreenshots();
    });
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefreshSignal);
    _scrollController.dispose();
    _controller.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_handleExternalRefreshSignal);
      _setupRefreshSignalListener();
    }
  }

  /// 监听由底部导航传入的刷新信号，确保从其他 tab 回来时展示最新历史记录
  void _setupRefreshSignalListener() {
    final signal = widget.refreshSignal;
    if (signal == null) {
      return;
    }
    _lastRefreshSignalValue = signal.value;
    signal.addListener(_handleExternalRefreshSignal);
  }

  /// 每当外部信号值变化（意味着切换自其它页面）时执行自动刷新
  void _handleExternalRefreshSignal() {
    final signal = widget.refreshSignal;
    if (signal == null) {
      return;
    }
    if (_lastRefreshSignalValue == signal.value) {
      return;
    }
    _lastRefreshSignalValue = signal.value;
    _log(
      '收到外部刷新信号，自动重载历史数据',
      level: LogLevel.debug,
    );
    unawaited(_refreshHistoryFromNavigation());
  }

  /// 跨端统一的导航刷新逻辑，进入历史页即清理缓存并重新拉取分页数据
  Future<void> _refreshHistoryFromNavigation() async {
    if (!mounted) {
      return;
    }
    _clearImageCache();
    await _loadHistory();
    if (!mounted) {
      return;
    }
    _controller.forward(from: 0);
  }

  // 滚动监听器
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreData) {
      if (_searchQuery.isNotEmpty) {
        _loadMoreSearchResults();
      } else {
        _loadMoreHistory();
      }
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _hasMoreData = true;
        _allRecords.clear();
      });

      final prefs = await SharedPreferences.getInstance();
      _currentUsername = prefs.getString('current_username');

      // Clear the screenshot cache when refreshing
      _clearImageCache();

      if (_currentUsername != null) {
        // 获取总记录数
        _totalRecords =
            await DatabaseHelper.instance.getUserHistoricalRecordsCount(
          _currentUsername!.hashCode,
        );

        if (_isCompactMode) {
          // 精简模式：按父级路径分组，展示每个目录的最新记录
          final records =
              await DatabaseHelper.instance.getUserHistoricalRecords(
            _currentUsername!.hashCode,
            limit: _totalRecords == 0 ? 1 : _totalRecords,
            offset: 0,
          );

          if (!mounted) return;

          final List<HistoricalRecord> historyRecords =
              records.map((r) => HistoricalRecord.fromMap(r)).toList();

          _allRecords.addAll(historyRecords);
          _hasMoreData = false;
          _groupByCompact(_allRecords);
        } else if (_isTimelineMode) {
          // 时间线模式：使用分页加载
          final records =
              await DatabaseHelper.instance.getRecentHistoricalRecords(
            userId: _currentUsername!.hashCode,
            limit: _pageSize,
            offset: 0,
          );

          if (!mounted) return;

          final List<HistoricalRecord> historyRecords =
              records.map((r) => HistoricalRecord.fromMap(r)).toList();

          _allRecords.addAll(historyRecords);
          _hasMoreData = _allRecords.length < _totalRecords;
          _groupByTimeline(_allRecords);
        } else {
          // 目录模式：加载所有数据以构建完整的目录列表
          final records =
              await DatabaseHelper.instance.getUserHistoricalRecords(
            _currentUsername!.hashCode,
            limit: _totalRecords == 0 ? 1 : _totalRecords, // 加载所有记录
            offset: 0,
          );

          if (!mounted) return;

          final List<HistoricalRecord> historyRecords =
              records.map((r) => HistoricalRecord.fromMap(r)).toList();

          _allRecords.addAll(historyRecords);
          _hasMoreData = false; // 目录模式下不需要瀑布流
          _groupByDirectory(_allRecords);
        }

        setState(() {
          _isLoading = false;
        });
        _controller.forward(from: 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _preloadScreenshots();
          }
        });
      }
    } catch (e, stack) {
      _log(
        '加载历史记录失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreHistory() async {
    // 只在时间线模式下支持瀑布流加载
    if (_isCompactMode ||
        !_isTimelineMode ||
        _isLoadingMore ||
        !_hasMoreData ||
        _currentUsername == null) {
      return;
    }

    try {
      setState(() => _isLoadingMore = true);

      _currentPage++;
      final records = await DatabaseHelper.instance.getRecentHistoricalRecords(
        userId: _currentUsername!.hashCode,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      if (!mounted) return;

      final List<HistoricalRecord> historyRecords =
          records.map((r) => HistoricalRecord.fromMap(r)).toList();

      _allRecords.addAll(historyRecords);
      _hasMoreData = _allRecords.length < _totalRecords;

      _groupByTimeline(_allRecords);

      setState(() => _isLoadingMore = false);
    } catch (e, stack) {
      _log(
        '加载更多历史记录失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // 搜索历史记录
  Future<void> _searchHistory(String query) async {
    if (_currentUsername == null) return;

    try {
      setState(() {
        _isLoading = true;
        _searchQuery = query.trim();
      });

      if (_searchQuery.isEmpty) {
        // 如果搜索为空，恢复正常显示
        await _loadHistory();
        return;
      }

      // 获取搜索结果总数
      _searchTotalRecords =
          await DatabaseHelper.instance.getSearchHistoricalRecordsCount(
        userId: _currentUsername!.hashCode,
        searchQuery: _searchQuery,
      );

      // 获取搜索结果
      final records = await DatabaseHelper.instance.searchHistoricalRecords(
        userId: _currentUsername!.hashCode,
        searchQuery: _searchQuery,
        limit: _pageSize,
        offset: 0,
      );

      if (!mounted) return;

      final List<HistoricalRecord> searchResults =
          records.map((r) => HistoricalRecord.fromMap(r)).toList();

      _searchResults = searchResults;
      _hasMoreData = _searchResults.length < _searchTotalRecords;
      _currentPage = 0;

      // 按时间线分组搜索结果
      _groupByTimeline(_searchResults);

      setState(() {
        _isLoading = false;
      });
      _controller.forward(from: 0);
    } catch (e, stack) {
      _log(
        '搜索历史记录失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // 加载更多搜索结果
  Future<void> _loadMoreSearchResults() async {
    if (_isLoadingMore ||
        !_hasMoreData ||
        _currentUsername == null ||
        _searchQuery.isEmpty) return;

    try {
      setState(() => _isLoadingMore = true);

      _currentPage++;
      final records = await DatabaseHelper.instance.searchHistoricalRecords(
        userId: _currentUsername!.hashCode,
        searchQuery: _searchQuery,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      if (!mounted) return;

      final List<HistoricalRecord> moreResults =
          records.map((r) => HistoricalRecord.fromMap(r)).toList();

      _searchResults.addAll(moreResults);
      _hasMoreData = _searchResults.length < _searchTotalRecords;

      _groupByTimeline(_searchResults);

      setState(() => _isLoadingMore = false);
    } catch (e, stack) {
      _log(
        '加载更多搜索结果失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // 处理搜索输入变化
  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchHistory(value);
    });
  }

  // 切换搜索模式
  void _toggleSearchMode() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _searchController.clear();
        _searchQuery = '';
        _searchResults.clear();
        _searchFocusNode.unfocus();
        // 退出搜索模式时，如果在目录模式下且选择了目录，需要重置
        if (!_isTimelineMode && _selectedDirectory != null) {
          _selectedDirectory = null;
        }
        _loadHistory(); // 恢复正常显示
      } else {
        // 进入搜索模式时聚焦搜索框
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      }
    });
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
        // 使用完整的目录路径作为key，避免同名目录冲突
        // 例如：/movies/action/movie.mp4 -> /movies/action
        final dirPath = pathParts.sublist(0, pathParts.length).join('/');
        _groupedRecords.putIfAbsent(dirPath, () => []);
        _groupedRecords[dirPath]!.add(record);
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

  void _groupByCompact(List<HistoricalRecord> records) {
    final Map<String, List<HistoricalRecord>> grouped = {};

    for (final record in records) {
      final dirPath = path.dirname("${record.videoPath}/${record.videoName}");
      grouped.putIfAbsent(dirPath, () => []);
      grouped[dirPath]!.add(record);
    }

    grouped.forEach((key, list) {
      list.sort((a, b) => b.changeTime.compareTo(a.changeTime));
    });

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aTime = grouped[a]!.first.changeTime;
        final bTime = grouped[b]!.first.changeTime;
        return bTime.compareTo(aTime);
      });

    _groupedRecords = {
      for (final key in sortedKeys) key: grouped[key]!,
    };
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

  String _resolveGroupKey(HistoricalRecord record) {
    if (_isCompactMode) {
      return path.dirname(record.videoPath);
    }

    if (_searchQuery.isNotEmpty || _isTimelineMode) {
      return _buildTimelineGroupKey(record);
    }

    if (_selectedDirectory != null) {
      return _selectedDirectory!;
    }

    return path.dirname(record.videoPath);
  }

  String _buildTimelineGroupKey(HistoricalRecord record) {
    final localTime = record.changeTime.toLocal();
    final date = DateTime(
      localTime.year,
      localTime.month,
      localTime.day,
    );
    return date.toString().substring(0, 10);
  }

  String _formatDirectoryName(String dirPath) {
    final name = path.basename(dirPath);
    if (name.isEmpty || name == '.' || name == '/') {
      return '根目录';
    }
    return name;
  }

  Future<void> _handleRecordTap(HistoricalRecord record) async {
    if (_isSelectMode) {
      _toggleSelect(record.videoSha1);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    final (exists, errorMessage) = await _checkFileExists(record.videoPath);

    if (!mounted) return;

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (!exists) {
      final isFileMovedOrDeleted =
          errorMessage?.contains(AppConstants.fileNotFoundError) ?? false;

      if (isFileMovedOrDeleted) {
        final groupKey = _resolveGroupKey(record);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('该视频文件已不存在或已被移动'),
            action: SnackBarAction(
              label: '删除记录',
              onPressed: () {
                _deleteRecord(record, groupKey);
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('访问文件失败: ${errorMessage ?? "未知错误"}'),
          ),
        );
      }
      return;
    }

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

        if (!_isTimelineMode || _isCompactMode) {
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
    } catch (e, stack) {
      _log(
        '检查远程文件状态失败 path=$path',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return (false, e.toString());
    }
  }

  // Get the screenshot path for a history record
  Future<String?> _getScreenshotPath(HistoricalRecord record) async {
    // Check cache first
    final cacheKey = '${record.videoPath}_${record.videoName}';
    if (_screenshotPathCache.containsKey(cacheKey)) {
      return _screenshotPathCache[cacheKey];
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final screenshotDir = Directory('${directory.path}/alist_player');

      // Sanitize path and name as done in the video player
      final String sanitizedVideoPath =
          record.videoPath.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');
      final String sanitizedVideoName =
          record.videoName.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');

      // 首先尝试新的 JPEG 格式（压缩后的格式）
      final String jpegFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedVideoName.jpg';
      final String jpegFilePath = '${screenshotDir.path}/$jpegFileName';
      final jpegFile = File(jpegFilePath);

      if (await jpegFile.exists()) {
        _screenshotPathCache[cacheKey] = jpegFilePath;
        return jpegFilePath;
      }

      // 如果 JPEG 格式不存在，尝试旧的 PNG 格式（向后兼容）
      final String pngFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedVideoName.png';
      final String pngFilePath = '${screenshotDir.path}/$pngFileName';
      final pngFile = File(pngFilePath);

      if (await pngFile.exists()) {
        _screenshotPathCache[cacheKey] = pngFilePath;
        return pngFilePath;
      }

      // 本地缺图时尝试从 Go 服务拉取远端截图并写入缓存
      final remotePath = await _downloadRemoteScreenshot(
        record: record,
        screenshotDir: screenshotDir,
        sanitizedVideoPath: sanitizedVideoPath,
        sanitizedVideoName: sanitizedVideoName,
      );
      _screenshotPathCache[cacheKey] = remotePath;
      return remotePath;
    } catch (e, stack) {
      _log(
        '获取历史截图路径失败 video=${record.videoName}',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      _screenshotPathCache[cacheKey] = null;
      return null;
    }
  }

  // Get file modification time to use as cache key
  Future<int> _getFileModificationTime(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified.millisecondsSinceEpoch;
      }
      return 0;
    } catch (e, stack) {
      _log(
        '获取截图文件修改时间失败 file=$filePath',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return 0;
    }
  }

  /// 本地无图时访问 Go 服务补拉截图并落盘，确保跨端历史缩略图一致
  Future<String?> _downloadRemoteScreenshot({
    required HistoricalRecord record,
    required Directory screenshotDir,
    required String sanitizedVideoPath,
    required String sanitizedVideoName,
  }) async {
    try {
      final remoteResult = await GoHistoryScreenshotService.downloadScreenshot(
        videoSha1: record.videoSha1,
        userId: record.userId,
      );
      if (remoteResult == null) {
        return null;
      }

      await screenshotDir.create(recursive: true);
      final extension = remoteResult.isJpeg ? 'jpg' : 'png';
      final fileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedVideoName.$extension';
      final filePath = '${screenshotDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(remoteResult.bytes);
      _log(
        '远端截图拉取成功并写入缓存 video=${record.videoName}',
        level: LogLevel.debug,
      );
      return filePath;
    } catch (e, stack) {
      _log(
        '远端截图缓存失败 video=${record.videoName}',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  // Clear image cache to force reload
  void _clearImageCache() {
    // Clear our screenshot path cache
    _screenshotPathCache.clear();

    // Clear Flutter's image cache
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  // Preload screenshots in the background to avoid UI stutters
  Future<void> _preloadScreenshots() async {
    if (_groupedRecords.isEmpty) return;

    // Flatten all records
    final allRecords = <HistoricalRecord>[];
    for (final records in _groupedRecords.values) {
      allRecords.addAll(records);
    }

    // Preload screenshots for visible records first
    for (var i = 0; i < math.min(10, allRecords.length); i++) {
      if (!mounted) return;
      await _getScreenshotPath(allRecords[i]);
    }

    // Then load the rest in the background
    for (var i = 10; i < allRecords.length; i++) {
      if (!mounted) return;
      unawaited(_getScreenshotPath(allRecords[i]));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectMode,
              )
            : _isSearchMode
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _toggleSearchMode,
                  )
                : (!_isTimelineMode &&
                        !_isCompactMode &&
                        _selectedDirectory != null)
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          setState(() => _selectedDirectory = null);
                        },
                      )
                    : null,
        title: _isSearchMode
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: '搜索视频名称或路径...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.black),
              )
            : _isSelectMode
                ? Text('已选择 ${_selectedItems.length} 项')
                : Text(_isCompactMode
                    ? '精简历史'
                    : _isTimelineMode
                        ? (_searchQuery.isNotEmpty ? '搜索结果' : '观看历史')
                        : (_selectedDirectory != null
                            ? _formatDirectoryName(_selectedDirectory!)
                            : '观看历史')),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedItems.isEmpty ? null : _deleteSelected,
            )
          else if (_isSearchMode) ...[
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _searchHistory('');
                },
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _toggleSearchMode,
            ),
            IconButton(
              tooltip: _isCompactMode ? '退出精简模式' : '精简模式',
              icon: Icon(
                _isCompactMode ? Icons.view_agenda : Icons.grid_view_rounded,
              ),
              onPressed: _searchQuery.isNotEmpty
                  ? null
                  : () async {
                      setState(() {
                        _isCompactMode = !_isCompactMode;
                        if (_isCompactMode) {
                          _selectedDirectory = null;
                        }
                      });
                      await _loadHistory();
                    },
            ),
            if (!isMobile) // 桌面端显示所有按钮
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed: _toggleSelectMode,
              ),
            IconButton(
              icon: Icon(_isTimelineMode ? Icons.folder : Icons.access_time),
              onPressed: (_searchQuery.isNotEmpty || _isCompactMode)
                  ? null
                  : () async {
                      setState(() {
                        _isTimelineMode = !_isTimelineMode;
                        _selectedDirectory = null;
                      });
                      await _loadHistory();
                    },
            ),
            // 所有平台都提供显式刷新入口，移动端避免隐藏在二级菜单
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                _clearImageCache();
                if (_searchQuery.isNotEmpty) {
                  await _searchHistory(_searchQuery);
                } else {
                  await _loadHistory();
                }
              },
            ),
            if (!isMobile) // 桌面端显示清空按钮
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
            if (isMobile) // 移动端显示更多菜单
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'select_all':
                      _toggleSelectMode();
                      break;
                    case 'clear_all':
                      if (_groupedRecords.isNotEmpty) {
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
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'select_all',
                    child: Row(
                      children: [
                        Icon(Icons.select_all),
                        SizedBox(width: 8),
                        Text('多选模式'),
                      ],
                    ),
                  ),
                  if (_groupedRecords.isNotEmpty)
                    const PopupMenuItem(
                      value: 'clear_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep, color: Colors.red),
                          SizedBox(width: 8),
                          Text('清空历史', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Clear image cache before refreshing
          _clearImageCache();

          if (_searchQuery.isNotEmpty) {
            await _searchHistory(_searchQuery);
          } else {
            await _loadHistory();
          }
          _controller.forward(from: 0);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _groupedRecords.isEmpty
                  ? Center(
                      child: Text(
                          _searchQuery.isNotEmpty ? '没有找到匹配的视频' : '暂无观看历史'))
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // 在搜索模式下，始终显示时间线视图
    if (_searchQuery.isNotEmpty) {
      return _buildTimelineView();
    }

    if (_isCompactMode) {
      return _buildCompactView();
    }

    if (!_isTimelineMode && _selectedDirectory == null) {
      return _buildDirectoryList();
    } else if (!_isTimelineMode && _selectedDirectory != null) {
      return _buildDirectoryTimeline(_selectedDirectory!);
    } else {
      return _buildTimelineView();
    }
  }

  Widget _buildDirectoryList() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    // 目录模式不需要瀑布流，显示所有目录
    return ListView.builder(
      padding: EdgeInsets.all(isMobile ? 8 : 16),
      itemCount: _groupedRecords.length,
      itemBuilder: (context, index) {
        final dirPath = _groupedRecords.keys.elementAt(index);
        final records = _groupedRecords[dirPath]!;
        final latestRecord = records.first;

        final dirName = _formatDirectoryName(dirPath);

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
              margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                onTap: () {
                  // 在搜索模式下不允许进入目录详情
                  if (_searchQuery.isEmpty) {
                    setState(() => _selectedDirectory = dirPath);
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.folder, size: isMobile ? 18 : 20),
                          SizedBox(width: isMobile ? 6 : 8),
                          Expanded(
                            child: Text(
                              dirName,
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 2 : 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(isMobile ? 8 : 12),
                            ),
                            child: Text(
                              '${records.length}个视频',
                              style: TextStyle(
                                fontSize: isMobile ? 10 : 12,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isMobile ? 4 : 8),
                      Text(
                        '最近观看：${timeago.format(latestRecord.changeTime, locale: 'zh_CN')}',
                        style: TextStyle(
                          fontSize: isMobile ? 11 : 13,
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
    // 检查是否在搜索模式下，如果是则返回到正常模式
    if (_searchQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedDirectory = null;
        });
      });
      return const Center(child: CircularProgressIndicator());
    }

    final records = _groupedRecords[dirPath];
    if (records == null || records.isEmpty) {
      // 如果找不到对应的目录记录，返回到目录列表
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedDirectory = null;
        });
      });
      return const Center(child: Text('目录不存在或已被删除'));
    }

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

    // 目录时间线不需要瀑布流，显示该目录下的所有视频
    return ListView.builder(
      itemCount: timelineRecords.length,
      itemBuilder: (context, index) {
        final dateKey = timelineRecords.keys.elementAt(index);
        final dateRecords = timelineRecords[dateKey]!;
        return _buildDateGroup(dateKey, dateRecords);
      },
    );
  }

  Widget _buildCompactView() {
    final keys = _groupedRecords.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        final horizontalPadding = isMobile ? 8.0 : 16.0;
        final desiredSpacing = isMobile ? 12.0 : 16.0;
        final availableWidth = (constraints.maxWidth - (horizontalPadding * 2))
            .clamp(0.0, double.infinity);
        final spacing = availableWidth > desiredSpacing
            ? desiredSpacing
            : math.max(4.0, availableWidth / 10);
        final totalSpacing = spacing;
        final calculatedWidth = availableWidth > 0
            ? (availableWidth - totalSpacing) / 2
            : constraints.maxWidth / 2;
        final itemWidth = math.max(120.0, calculatedWidth);

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding)
                .copyWith(top: horizontalPadding, bottom: horizontalPadding),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(keys.length, (index) {
                final groupKey = keys[index];
                final records = _groupedRecords[groupKey]!;
                final record = records.first;
                return SizedBox(
                  width: itemWidth,
                  child: _buildCompactCard(record, groupKey),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactCard(
    HistoricalRecord record,
    String groupKey,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final theme = Theme.of(context);
    final isSelected = _selectedItems.contains(record.videoSha1);
    final shadowColor = theme.brightness == Brightness.dark
        ? Colors.black.withOpacity(0.3)
        : Colors.black.withOpacity(0.08);
    final titleFontSize = isMobile ? 13.0 : 15.0;
    final titleLineHeight = 1.25;
    final titleBoxHeight = titleFontSize * titleLineHeight * 2;
    final subtitleFontSize = isMobile ? 11.0 : 12.0;
    final subtitleLineHeight = 1.2;
    final subtitleBoxHeight = subtitleFontSize * subtitleLineHeight;

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, record);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          border: Border.all(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
            onTap: () => _handleRecordTap(record),
            onLongPress: () {
              if (!_isSelectMode) {
                _toggleSelectMode();
              }
              _toggleSelect(record.videoSha1);
            },
            child: LayoutBuilder(
              builder: (context, cardConstraints) {
                final maxTextWidth = cardConstraints.maxWidth -
                    (isMobile ? 20.0 : 28.0); // padding * 2

                return Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(isMobile ? 10 : 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCompactThumbnail(record),
                          SizedBox(height: isMobile ? 8 : 10),
                          SizedBox(
                            height: titleBoxHeight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: maxTextWidth),
                                child: Text(
                                  record.videoName,
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: titleLineHeight,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 3 : 4),
                          SizedBox(
                            height: subtitleBoxHeight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: maxTextWidth),
                                child: Text(
                                  _formatDirectoryName(groupKey),
                                  style: TextStyle(
                                    fontSize: subtitleFontSize,
                                    height: subtitleLineHeight,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 6 : 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: isMobile ? 12 : 13,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  timeago.format(record.changeTime,
                                      locale: 'zh_CN'),
                                  style: TextStyle(
                                    fontSize: isMobile ? 10 : 12,
                                    color: Colors.grey[500],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isMobile ? 6 : 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: record.totalVideoDuration > 0
                                  ? (record.videoSeek /
                                          record.totalVideoDuration)
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                              minHeight: 4,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.primaryColor.withOpacity(0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isSelectMode)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? theme.primaryColor
                                : Colors.grey[300],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactThumbnail(HistoricalRecord record) {
    final borderRadius = BorderRadius.circular(12);

    return ClipRRect(
      borderRadius: borderRadius,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: FutureBuilder<String?>(
          future: _getScreenshotPath(record),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildCompactPlaceholder();
            }

            final screenshotPath = snapshot.data;
            if (screenshotPath == null) {
              return _buildCompactPlaceholder();
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<int>(
                  future: _getFileModificationTime(screenshotPath),
                  builder: (context, timeSnapshot) {
                    final cacheKey = timeSnapshot.hasData
                        ? '${screenshotPath}_${timeSnapshot.data}'
                        : screenshotPath;

                    return Image.file(
                      File(screenshotPath),
                      fit: BoxFit.cover,
                      key: ValueKey(cacheKey),
                      errorBuilder: (context, error, stackTrace) {
                        final recordCacheKey =
                            '${record.videoPath}_${record.videoName}';
                        _screenshotPathCache.remove(recordCacheKey);
                        return _buildCompactPlaceholder();
                      },
                    );
                  },
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECECEC), Color(0xFFDFDFDF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.movie_filter,
          color: Colors.grey,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildTimelineView() {
    final itemCount = _groupedRecords.length + (_hasMoreData ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // 如果是最后一项且还有更多数据，显示加载指示器
        if (index == _groupedRecords.length) {
          return _buildLoadMoreIndicator();
        }

        final key = _groupedRecords.keys.elementAt(index);
        final records = _groupedRecords[key]!;
        return _buildDateGroup(key, records);
      },
    );
  }

  Widget _buildDateGroup(String key, List<HistoricalRecord> records) {
    final isMobile = MediaQuery.of(context).size.width < 600;

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
              // 移动端使用更窄的时间线
              SizedBox(
                width: isMobile ? 40 : 60,
                child: Column(
                  children: [
                    Container(
                      width: 2,
                      height: isMobile ? 16 : 24,
                      color: Colors.grey[300],
                    ),
                    Container(
                      width: isMobile ? 8 : 12,
                      height: isMobile ? 8 : 12,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: isMobile ? 1 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: isMobile ? 2 : 4,
                            offset: Offset(0, isMobile ? 1 : 2),
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
                      padding: EdgeInsets.fromLTRB(0, isMobile ? 8 : 16,
                          isMobile ? 8 : 16, isMobile ? 6 : 12),
                      child: Row(
                        children: [
                          Text(
                            _getGroupTitle(key),
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${records.length})',
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...records.map((record) => _buildHistoryCard(record)),
                    SizedBox(height: isMobile ? 8 : 16),
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
    // 检查是否为移动端
    final isMobile = MediaQuery.of(context).size.width < 600;

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
                final groupKey = _resolveGroupKey(record);
                _deleteRecord(record, groupKey);
              },
              child: Card(
                elevation: 0,
                margin: EdgeInsets.only(
                  right: isMobile ? 8 : 16,
                  bottom: isMobile ? 6 : 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
                  side: BorderSide(
                    color: _selectedItems.contains(record.videoSha1)
                        ? Colors.blue
                        : Colors.grey[200]!,
                  ),
                ),
                child: InkWell(
                  onTap: () => _handleRecordTap(record),
                  onLongPress: () {
                    if (!_isSelectMode) {
                      _toggleSelectMode();
                      _toggleSelect(record.videoSha1);
                    }
                  },
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(isMobile ? 8 : 12),
                        child: isMobile
                            ? _buildMobileCardContent(record)
                            : _buildDesktopCardContent(record),
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

  // 构建移动端卡片内容 - 更紧凑的布局
  Widget _buildMobileCardContent(HistoricalRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 第一行：视频名称和截图
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩小的截图预览
            _buildMobileScreenshotPreview(record),
            const SizedBox(width: 8),
            // 视频信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 视频名称 - 减少行数
                  Text(
                    record.videoName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // 路径信息 - 更小的字体
                  Text(
                    _getDisplayPath(record.videoPath),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 时间信息 - 简化显示
                  Text(
                    timeago.format(record.changeTime, locale: 'zh_CN'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 第二行：进度条和百分比
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: record.totalVideoDuration > 0
                  ? (record.videoSeek / record.totalVideoDuration)
                      .clamp(0.0, 1.0)
                  : 0.0,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
              minHeight: 3,
            ),
            const SizedBox(height: 2),
            Text(
              '观看至 ${((record.videoSeek / record.totalVideoDuration) * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 构建桌面端卡片内容 - 保持原有布局
  Widget _buildDesktopCardContent(HistoricalRecord record) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 显示截图
        _buildScreenshotPreview(record),
        const SizedBox(width: 12),
        // 视频详情
        Expanded(
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
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${timeago.format(record.changeTime, locale: 'zh_CN')} · ${record.changeTime.toLocal().toString().substring(0, 16)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: record.totalVideoDuration > 0
                    ? (record.videoSeek / record.totalVideoDuration)
                        .clamp(0.0, 1.0)
                    : 0.0,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
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
      ],
    );
  }

  // 构建移动端专用的截图预览 - 更小尺寸
  Widget _buildMobileScreenshotPreview(HistoricalRecord record) {
    return FutureBuilder<String?>(
      future: _getScreenshotPath(record),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildMobileScreenshotPlaceholder();
        }

        final screenshotPath = snapshot.data;
        if (screenshotPath == null) {
          return _buildMobileScreenshotPlaceholder();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 80, // 移动端使用更小的宽度
            height: 45, // 移动端使用更小的高度
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<int>(
                  future: _getFileModificationTime(screenshotPath),
                  builder: (context, timeSnapshot) {
                    // 使用文件修改时间作为缓存键，确保图片更新时能重新加载
                    final cacheKey = timeSnapshot.hasData
                        ? '${screenshotPath}_${timeSnapshot.data}'
                        : screenshotPath;

                    return Image.file(
                      File(screenshotPath),
                      fit: BoxFit.cover,
                      key: ValueKey(cacheKey),
                      errorBuilder: (context, error, stackTrace) {
                        // 当图片加载失败时，清除对应的缓存
                        final recordCacheKey =
                            '${record.videoPath}_${record.videoName}';
                        _screenshotPathCache.remove(recordCacheKey);
                        return _buildMobileScreenshotPlaceholder();
                      },
                    );
                  },
                ),
                // 播放图标覆盖层 - 更小的图标
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                // 底部进度指示器
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: record.totalVideoDuration > 0
                        ? (record.videoSeek / record.totalVideoDuration)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: Colors.black45,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    minHeight: 2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 构建移动端截图占位符
  Widget _buildMobileScreenshotPlaceholder() {
    return Container(
      width: 80,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Icon(
          Icons.video_library,
          color: Colors.grey,
          size: 20,
        ),
      ),
    );
  }

  // Build the screenshot preview widget
  Widget _buildScreenshotPreview(HistoricalRecord record) {
    return FutureBuilder<String?>(
      future: _getScreenshotPath(record),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildScreenshotPlaceholder();
        }

        final screenshotPath = snapshot.data;
        if (screenshotPath == null) {
          return _buildScreenshotPlaceholder();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: Container(
            width: 180,
            height: 105,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(1),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<int>(
                  future: _getFileModificationTime(screenshotPath),
                  builder: (context, timeSnapshot) {
                    // 使用文件修改时间作为缓存键，确保图片更新时能重新加载
                    final cacheKey = timeSnapshot.hasData
                        ? '${screenshotPath}_${timeSnapshot.data}'
                        : screenshotPath;

                    return Image.file(
                      File(screenshotPath),
                      fit: BoxFit.cover,
                      key: ValueKey(cacheKey),
                      errorBuilder: (context, error, stackTrace) {
                        _log(
                          '加载截图失败: $error',
                          level: LogLevel.error,
                          error: error,
                          stackTrace: stackTrace,
                        );
                        // 当图片加载失败时，清除对应的缓存
                        final recordCacheKey =
                            '${record.videoPath}_${record.videoName}';
                        _screenshotPathCache.remove(recordCacheKey);
                        return _buildScreenshotPlaceholder();
                      },
                    );
                  },
                ),
                // Add a play icon overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Add video progress indicator at the bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: record.totalVideoDuration > 0
                        ? (record.videoSeek / record.totalVideoDuration)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: Colors.black45,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build a placeholder for when no screenshot is available
  Widget _buildScreenshotPlaceholder() {
    return Container(
      width: 180,
      height: 105,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(1),
      ),
      child: const Center(
        child: Icon(
          Icons.video_library,
          color: Colors.grey,
          size: 40,
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
          child: const Text('下载视频'),
          onTap: () {
            DownloadManager().addTask(record.videoPath, record.videoName);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已添加到下载队列')),
            );
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

  // 构建加载更多指示器（仅在时间线模式下使用）
  Widget _buildLoadMoreIndicator() {
    if (!_isTimelineMode) {
      return const SizedBox.shrink(); // 目录模式下不显示
    }

    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('加载更多...'),
              ],
            )
          : _hasMoreData
              ? const Text(
                  '上拉加载更多',
                  style: TextStyle(color: Colors.grey),
                )
              : const Text(
                  '没有更多数据了',
                  style: TextStyle(color: Colors.grey),
                ),
    );
  }
}
