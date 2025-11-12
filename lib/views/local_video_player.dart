import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/download_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:async';
import 'dart:io';
import 'package:alist_player/utils/logger.dart';

class LocalVideoPlayer extends StatefulWidget {
  final String filePath;
  final String fileName;
  final List<String>? playlistPaths; // 可选的播放列表

  const LocalVideoPlayer({
    super.key,
    required this.filePath,
    required this.fileName,
    this.playlistPaths,
  });

  @override
  State<LocalVideoPlayer> createState() => LocalVideoPlayerState();

  // 静态方法：播放单个本地视频文件
  static void playLocalVideo(
      BuildContext context, String filePath, String fileName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocalVideoPlayer(
          filePath: filePath,
          fileName: fileName,
        ),
      ),
    );
  }

  // 静态方法：播放本地视频播放列表
  static void playLocalPlaylist(
      BuildContext context,
      List<String> playlistPaths,
      String currentFilePath,
      String currentFileName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocalVideoPlayer(
          filePath: currentFilePath,
          fileName: currentFileName,
          playlistPaths: playlistPaths,
        ),
      ),
    );
  }

  // 静态方法：播放下载目录中的所有视频
  static void playDownloadedVideos(BuildContext context,
      {String? startWithFile}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocalVideoPlayer(
          filePath: startWithFile ?? '',
          fileName: startWithFile?.split('/').last ?? '本地视频',
        ),
      ),
    );
  }
}

class LocalVideoPlayerState extends State<LocalVideoPlayer> {
  // Create a [Player] to control playback.
  late final player = Player();
  late bool initover = false;
  // Create a [VideoController] to handle video output from [Player].
  late final controller = VideoController(player);

  // 添加播放速度的ValueNotifier
  late final ValueNotifier<double> _rateNotifier =
      ValueNotifier<double>(AppConstants.defaultPlaybackSpeed);

  List<Media> playList = [];
  int playIndex = 0;
  late int currentPlayingIndex = 0;

  // 添加 ItemScrollController 用于精确的索引滚动
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  String? _currentUsername;
  bool _hasSeekInitialPosition = false;

  // 添加排序相关状态
  bool _isAscending = true;

  // 添加一个状态变量
  bool _isExiting = false;

  // 添加一个变量来跟踪当前播放速度
  double _currentSpeed = AppConstants.defaultPlaybackSpeed;

  // 添加一个变量来存储长按前的速度
  double _previousSpeed = AppConstants.defaultPlaybackSpeed;

  // 添加变量来存储z/x/c键调速前的速度
  double? _speedBeforeZXCAdjustment;

  late Duration _shortSeekDuration;
  late Duration _longSeekDuration;

  // 添加防抖机制相关变量
  Timer? _saveProgressDebounceTimer;
  bool _isSavingProgress = false;

  // 将 late 移除，提供默认值
  final List<double> _playbackSpeeds = AppConstants.defaultPlaybackSpeeds;

  // 添加搜索控制器
  final TextEditingController _subtitleSearchController =
      TextEditingController();

  // 添加自定义播放速度相关变量
  double _customPlaybackSpeed = AppConstants.defaultCustomPlaybackSpeed;
  bool _isCustomSpeedEnabled = false;

  // 添加倍速指示器相关变量
  OverlayEntry? _speedIndicatorOverlay;
  final ValueNotifier<bool> _showSpeedIndicator = ValueNotifier<bool>(false);
  final ValueNotifier<double> _indicatorSpeedValue = ValueNotifier<double>(1.0);
  Timer? _speedIndicatorTimer;

  // 添加视频信息覆盖层相关变量
  OverlayEntry? _videoInfoOverlay;
  bool _isVideoInfoVisible = false;

  // 添加全屏相关变量
  final bool _isFramelessMode = false;
  final GlobalKey _videoKey = GlobalKey();

  // 添加历史记录相关变量
  final Map<String, HistoricalRecord> _playlistHistoryRecords = {};

  // 添加初始加载标志
  bool _isInitialLoading = true;

  // 添加调试日志方法
  void _logDebug(
    String message, {
    LogLevel level = LogLevel.debug,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 统一将播放器日志写入 AppLogger，便于跨端排查问题
    AppLogger().captureConsoleOutput(
      'LocalVideoPlayer',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    unawaited(_configurePlaylistErrorPolicy());
    _getCurrentUsername();
    _initializeLocalPlaylist();
  }

  // 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载自定义播放速度
    final customSpeed = prefs.getDouble(AppConstants.customPlaybackSpeedKey);
    if (customSpeed != null) {
      setState(() {
        _customPlaybackSpeed = customSpeed;
      });
    }

    // 加载其他设置
    setState(() {
      _shortSeekDuration = Duration(
        seconds: prefs.getInt(AppConstants.shortSeekKey) ??
            AppConstants.defaultShortSeekDuration.inSeconds,
      );
      _longSeekDuration = Duration(
        seconds: prefs.getInt(AppConstants.longSeekKey) ??
            AppConstants.defaultLongSeekDuration.inSeconds,
      );
    });
  }

  /// 设置 mpv playlist-on-error 行为，避免播放失败时跳到下一条本地视频
  Future<void> _configurePlaylistErrorPolicy() async {
    final dynamic mpvPlayer = player.platform;
    if (mpvPlayer == null) {
      _logDebug('未获取到 mpv 实例，无法配置 playlist-on-error');
      return;
    }

    try {
      await mpvPlayer.setProperty('playlist-on-error', 'fail');
      _logDebug('本地播放已设置 playlist-on-error=fail');
    } catch (e, stack) {
      _logDebug('配置 playlist-on-error 失败: $e');
      AppLogger().captureConsoleOutput(
        'LocalVideoPlayer',
        '配置 playlist-on-error 失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 获取当前用户名
  Future<void> _getCurrentUsername() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUsername = prefs.getString('username');
  }

  // 初始化本地播放列表
  Future<void> _initializeLocalPlaylist() async {
    try {
      _logDebug('开始初始化本地播放列表: 文件=${widget.fileName}');

      List<String> filePaths;

      // 如果提供了播放列表，使用播放列表；否则扫描下载目录
      if (widget.playlistPaths != null && widget.playlistPaths!.isNotEmpty) {
        filePaths = widget.playlistPaths!;
      } else {
        // 扫描下载目录中的所有视频文件
        filePaths = await _scanDownloadDirectory();
      }

      // 过滤出存在的视频文件
      List<String> validPaths = [];
      for (String path in filePaths) {
        final file = File(path);
        if (await file.exists() && _isVideoFile(path)) {
          validPaths.add(path);
        }
      }

      if (validPaths.isEmpty) {
        _logDebug('没有找到有效的视频文件');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('没有找到有效的视频文件'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 构建播放列表
      setState(() {
        playList.clear();
        int index = 0;
        for (String path in validPaths) {
          final file = File(path);
          final fileName = file.path.split('/').last;

          if (path == widget.filePath) {
            playIndex = index;
          }

          playList.add(Media(
            'file://$path',
            extras: {
              'name': fileName,
              'path': path,
              'size': 0, // 本地文件暂时不获取大小
              'modified': '',
            },
          ));
          index++;
        }

        _logDebug('本地播放列表构建完成: 总数=${playList.length}, 初始索引=$playIndex');
      });

      // 初始化播放器
      await _initializePlayer();
    } catch (e) {
      _logDebug('初始化本地播放列表失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('初始化播放列表失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 扫描下载目录中的视频文件
  Future<List<String>> _scanDownloadDirectory() async {
    List<String> videoPaths = [];

    try {
      final downloadPath = await DownloadManager.getDownloadPath();
      final directory = Directory(downloadPath);

      if (!await directory.exists()) {
        _logDebug('下载目录不存在: $downloadPath');
        return videoPaths;
      }

      _logDebug('扫描下载目录: $downloadPath');

      // 递归扫描目录中的所有文件
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final filePath = entity.path;
          if (_isVideoFile(filePath)) {
            videoPaths.add(filePath);
            _logDebug('找到视频文件: ${filePath.split('/').last}');
          }
        }
      }

      // 按文件名排序
      videoPaths.sort((a, b) {
        final nameA = a.split('/').last.toLowerCase();
        final nameB = b.split('/').last.toLowerCase();
        return nameA.compareTo(nameB);
      });

      _logDebug('扫描完成，找到${videoPaths.length}个视频文件');
    } catch (e) {
      _logDebug('扫描下载目录失败: $e');
    }

    return videoPaths;
  }

  // 检查是否为视频文件
  bool _isVideoFile(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    const videoExtensions = [
      // 常见视频格式
      'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', 'm4v',
      '3gp', 'mpg', 'mpeg', 'ts', 'mts', 'm2ts', 'vob', 'asf',
      'rm', 'rmvb', 'divx', 'xvid', 'f4v', 'ogv',
      // 高清视频格式
      'mp2', 'mpe', 'mpv', 'm1v', 'm2v', 'mp2v', 'mpg2', 'mpeg2',
      // 其他格式
      'dat', 'bin', 'ifo', 'img', 'iso', 'nrg', 'gho', 'fla',
      // 流媒体格式
      'm3u8', 'hls', 'dash', 'mpd',
      // 音视频容器格式
      'mxf', 'gxf', 'r3d', 'braw', 'ari', 'arw',
    ];
    return videoExtensions.contains(extension);
  }

  // 初始化播放器
  Future<void> _initializePlayer() async {
    try {
      if (playList.isEmpty) {
        _logDebug('播放列表为空，无法初始化播放器');
        return;
      }

      _logDebug('准备打开播放列表: 索引=$playIndex');

      // 设置初始加载标志
      _isInitialLoading = true;

      Playable playable = Playlist(
        playList,
        index: playIndex,
      );

      // 初始加载时，手动设置当前播放索引
      currentPlayingIndex = playIndex;

      await player.open(playable, play: true);

      // 设置播放器监听
      _setupPlayerListeners();

      // 初始化完成后进行一次排序
      _sortPlaylist();

      // 加载播放列表中所有视频的历史记录
      _loadPlaylistHistoryRecords();

      // 在所有初始化完成后，执行初始滚动到当前播放项
      _scheduleInitialScroll();

      // 2秒后标记初始加载完成
      Future.delayed(const Duration(seconds: 2), () {
        _isInitialLoading = false;
        _logDebug('初始加载标记设置为false');
      });
    } catch (e) {
      _logDebug('初始化播放器失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('初始化播放器失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 设置播放器监听
  void _setupPlayerListeners() {
    // 监听播放列表变化
    player.stream.playlist.listen((event) async {
      if (mounted) {
        final videoName = playList.isNotEmpty && event.index < playList.length
            ? playList[event.index].extras!['name'] as String
            : "未知";
        _logDebug(
            '播放列表变化: 索引=${event.index}, 视频=$videoName, 初始加载=$_isInitialLoading');

        // 如果是初始加载，跳过检查
        if (_isInitialLoading) {
          _logDebug('初始加载中，跳过处理');
          return;
        }

        // 优化切换视频逻辑：先更新UI状态
        if (mounted) {
          setState(() {
            currentPlayingIndex = event.index;
            _hasSeekInitialPosition = false;
          });

          // 在 setState 完成后再执行滚动
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scrollToCurrentItem();
          });

          // 异步处理保存进度
          _handleVideoSwitchAsync(event.index);
        }
      }
    });

    // 监听播放状态
    player.stream.playing.listen((isPlaying) {
      if (!isPlaying && mounted) {
        // 使用防抖机制，避免频繁的暂停/播放操作触发多次保存
        _debouncedSaveProgress();
      }
    });

    // 监听缓冲状态
    player.stream.buffer.listen((event) {
      if (event.inSeconds > 0 && mounted && !_hasSeekInitialPosition) {
        _seekToLastPosition(playList[currentPlayingIndex].extras!['name'])
            .then((_) {
          if (mounted) {}
        });
        _hasSeekInitialPosition = true;
      }
    });

    // 监听错误，提示用户，playlist-on-error=fail 已阻止自动跳播
    player.stream.error.listen((error) {
      _logDebug('本地播放器错误: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放出错: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  // 处理视频切换的异步操作
  Future<void> _handleVideoSwitchAsync(int index) async {
    // 保存当前视频进度
    await _saveCurrentProgress();

    // 加载新视频的历史记录
    if (playList.isNotEmpty && index < playList.length) {
      final videoName = playList[index].extras!['name'] as String;
      await _seekToLastPosition(videoName);
    }
  }

  // 防抖保存进度
  void _debouncedSaveProgress() {
    _saveProgressDebounceTimer?.cancel();
    _saveProgressDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveCurrentProgress();
    });
  }

  // 保存当前播放进度
  Future<void> _saveCurrentProgress({bool updateUIImmediately = false}) async {
    if (_isSavingProgress ||
        playList.isEmpty ||
        currentPlayingIndex >= playList.length) {
      return;
    }

    _isSavingProgress = true;

    try {
      final videoName = playList[currentPlayingIndex].extras!['name'] as String;
      final position = player.state.position;
      final duration = player.state.duration;

      if (duration.inSeconds > 0 && position.inSeconds > 0) {
        // 使用DatabaseHelper的upsertHistoricalRecord方法
        await DatabaseHelper.instance.upsertHistoricalRecord(
          videoSha1: _getVideoSha1('local', videoName),
          videoPath: 'local',
          videoSeek: position.inSeconds,
          userId: (_currentUsername ?? 'unknown').hashCode,
          videoName: videoName,
          totalVideoDuration: duration.inSeconds,
        );

        // 创建历史记录对象用于本地缓存
        final record = HistoricalRecord(
          videoSha1: _getVideoSha1('local', videoName),
          videoPath: 'local',
          videoName: videoName,
          userId: (_currentUsername ?? 'unknown').hashCode,
          changeTime: DateTime.now(),
          videoSeek: position.inSeconds,
          totalVideoDuration: duration.inSeconds,
        );

        // 更新本地缓存
        _playlistHistoryRecords[videoName] = record;

        _logDebug(
            '保存播放进度: 视频=$videoName, 位置=${position.inSeconds}s, 进度=${(position.inSeconds / duration.inSeconds * 100).toStringAsFixed(1)}%');

        if (updateUIImmediately && mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      _logDebug('保存播放进度失败: $e');
    } finally {
      _isSavingProgress = false;
    }
  }

  // 跳转到上次播放位置
  Future<void> _seekToLastPosition(String videoName) async {
    try {
      final record = await DatabaseHelper.instance.getHistoricalRecordByName(
        name: videoName,
        userId: (_currentUsername ?? 'unknown').hashCode,
      );

      if (record != null && record.videoSeek > 0) {
        final seekPosition = Duration(seconds: record.videoSeek);
        await player.seek(seekPosition);
        _logDebug('跳转到上次播放位置: 视频=$videoName, 位置=${record.videoSeek}s');
      }
    } catch (e) {
      _logDebug('跳转到上次播放位置失败: $e');
    }
  }

  // 生成视频SHA1标识
  String _getVideoSha1(String path, String name) {
    return '${path}_$name'.hashCode.toString();
  }

  // 排序播放列表
  void _sortPlaylist() async {
    if (playList.isEmpty) return;

    // 记住当前播放的视频名称
    final currentPlayingName =
        playList[currentPlayingIndex].extras!['name'] as String;

    // 创建一个排序后的新列表
    final sortedList = List<Media>.from(playList);
    sortedList.sort((a, b) {
      String nameA = a.extras!['name'] as String;
      String nameB = b.extras!['name'] as String;
      return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
    });

    // 使用 move API 重新排列播放列表
    for (int i = 0; i < sortedList.length; i++) {
      final currentIndex = playList.indexWhere(
          (item) => item.extras!['name'] == sortedList[i].extras!['name']);
      if (currentIndex != i) {
        await player.move(currentIndex, i);
        // 同步更新本地列表
        final item = playList.removeAt(currentIndex);
        playList.insert(i, item);
      }
    }

    // 更新当前播放索引
    final newIndex = playList
        .indexWhere((item) => item.extras!['name'] == currentPlayingName);
    if (newIndex != -1) {
      setState(() {
        currentPlayingIndex = newIndex;
      });
    }

    _logDebug('播放列表排序完成: ${_isAscending ? "升序" : "降序"}');
  }

  // 加载播放列表历史记录
  Future<void> _loadPlaylistHistoryRecords() async {
    try {
      for (final media in playList) {
        final videoName = media.extras!['name'] as String;
        final record = await DatabaseHelper.instance.getHistoricalRecordByName(
          name: videoName,
          userId: (_currentUsername ?? 'unknown').hashCode,
        );
        if (record != null) {
          _playlistHistoryRecords[videoName] = record;
        }
      }
      _logDebug('加载播放列表历史记录完成: ${_playlistHistoryRecords.length}条记录');
    } catch (e) {
      _logDebug('加载播放列表历史记录失败: $e');
    }
  }

  // 安排初始滚动
  void _scheduleInitialScroll() {
    // 使用多层延迟确保列表完全构建后再滚动
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                scrollToCurrentItem();
              }
            });
          }
        });
      }
    });
  }

  // 滚动到当前播放项
  void scrollToCurrentItem() {
    if (playList.isNotEmpty &&
        currentPlayingIndex >= 0 &&
        currentPlayingIndex < playList.length &&
        _itemScrollController.isAttached) {
      try {
        _itemScrollController.scrollTo(
          index: currentPlayingIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _logDebug('滚动到当前播放项: 索引=$currentPlayingIndex');
      } catch (e) {
        _logDebug('滚动失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentVideoName =
        playList.isNotEmpty && currentPlayingIndex < playList.length
            ? playList[currentPlayingIndex].extras!['name']
            : '本地视频播放';

    // 获取屏幕宽度
    final screenWidth = MediaQuery.of(context).size.width;
    // 判断是否是移动端布局（小于 600dp 使用移动端布局）
    final isMobile = screenWidth < 600;

    // 在无边框模式下，直接返回桌面端布局
    if (_isFramelessMode) {
      return _buildDesktopLayout();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentVideoName,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  // 构建桌面端布局
  Widget _buildDesktopLayout() {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event);
      },
      child: Row(
        children: [
          // 左侧视频播放器
          Expanded(
            flex: 3,
            child: _buildVideoPlayer(),
          ),
          // 右侧播放列表
          SizedBox(
            width: 350,
            child: _buildPlaylist(),
          ),
        ],
      ),
    );
  }

  // 处理键盘事件
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          player.playOrPause();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          final rate = player.state.position + _shortSeekDuration;
          player.seek(rate);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          final rate = player.state.position - _shortSeekDuration;
          player.seek(rate);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          final volume = player.state.volume + 5.0;
          player.setVolume(volume.clamp(0.0, 100.0));
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          final volume = player.state.volume - 5.0;
          player.setVolume(volume.clamp(0.0, 100.0));
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyJ:
          final rate = player.state.position - _longSeekDuration;
          player.seek(rate);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyI:
          final rate = player.state.position + _longSeekDuration;
          player.seek(rate);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyF:
          _toggleFullscreen();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _exitFullscreen();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.tab:
          _toggleVideoInfoOverlay();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyP:
          _toggleCustomSpeed();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyZ:
          _restoreSpeed();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
          _decreaseSpeed();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyC:
          _increaseSpeed();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // 构建移动端布局
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // 视频播放器
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoPlayer(),
        ),
        // 播放列表
        Expanded(
          child: _buildPlaylist(),
        ),
      ],
    );
  }

  // 构建视频播放器
  Widget _buildVideoPlayer() {
    // 视频内容包装器
    Widget videoContent = Stack(
      children: [
        GestureDetector(
          key: _videoKey,
          onLongPressStart: (_) {
            _previousSpeed = controller.player.state.rate;
            controller.player.setRate(AppConstants.longPressPlaybackSpeed);

            // 显示全局倍速提示，指定为长按模式
            _showSpeedIndicatorOverlay(AppConstants.longPressPlaybackSpeed,
                isLongPress: true);

            // 取消任何已有定时器，确保长按时指示器不会消失
            _speedIndicatorTimer?.cancel();
            _speedIndicatorTimer = null;
          },
          onLongPressEnd: (_) {
            controller.player.setRate(_previousSpeed);

            // 立即更新倍速提示，显示恢复后的倍速值
            _showSpeedIndicatorOverlay(_previousSpeed);

            // 设置定时器，延迟2秒后隐藏提示
            _speedIndicatorTimer?.cancel();
            _speedIndicatorTimer = Timer(
                const Duration(seconds: 2), () => _hideSpeedIndicatorOverlay());
          },
          child: MaterialDesktopVideoControlsTheme(
            normal: MaterialDesktopVideoControlsThemeData(
              displaySeekBar: true,
              visibleOnMount: false,
              primaryButtonBar: [],
              seekBarMargin:
                  const EdgeInsets.only(bottom: 10, left: 0, right: 0),
              bottomButtonBarMargin:
                  const EdgeInsets.only(bottom: 0, left: 0, right: 0, top: 0),
              bottomButtonBar: [
                const MaterialDesktopSkipPreviousButton(),
                const MaterialPlayOrPauseButton(),
                const MaterialSkipNextButton(),
                const MaterialDesktopVolumeButton(),
                const MaterialPositionIndicator(),
                const Spacer(),
                buildSpeedButton(),
                buildScreenshotButton(),
                const MaterialFullscreenButton(iconSize: 28),
              ],
              keyboardShortcuts: _buildDesktopKeyboardShortcuts(),
            ),
            fullscreen: MaterialDesktopVideoControlsThemeData(
              displaySeekBar: true,
              visibleOnMount: false,
              primaryButtonBar: [],
              seekBarMargin:
                  const EdgeInsets.only(bottom: 10, left: 0, right: 0),
              bottomButtonBarMargin:
                  const EdgeInsets.only(bottom: 0, left: 0, right: 0, top: 0),
              bottomButtonBar: [
                const MaterialDesktopSkipPreviousButton(),
                const MaterialPlayOrPauseButton(),
                const MaterialSkipNextButton(),
                const MaterialDesktopVolumeButton(),
                const MaterialPositionIndicator(),
                const Spacer(),
                buildSpeedButton(),
                buildScreenshotButton(),
                const MaterialFullscreenButton(iconSize: 28),
              ],
              keyboardShortcuts: _buildDesktopKeyboardShortcuts(),
            ),
            child: Video(
              controller: controller,
              controls: MaterialDesktopVideoControls,
            ),
          ),
        ),
      ],
    );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: videoContent,
    );
  }

  // 构建播放列表
  Widget _buildPlaylist() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          left: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildPlaylistHeader(),
          Expanded(
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              itemCount: playList.length,
              itemBuilder: (context, index) {
                final isPlaying = index == currentPlayingIndex;
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: _buildPlaylistItem(index, isPlaying),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 构建播放列表头部
  Widget _buildPlaylistHeader() {
    final playingIndexInfo = playList.isNotEmpty
        ? ' (${currentPlayingIndex + 1}/${playList.length})'
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_list_bulleted, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本地播放列表 (${playList.length})$playingIndexInfo',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 添加滚动到当前项按钮
          IconButton(
            icon: const Icon(
              Icons.center_focus_strong,
              size: 20,
            ),
            onPressed: () {
              _logDebug('手动测试滚动功能');
              scrollToCurrentItem();
            },
            tooltip: '滚动到当前项',
          ),
          // 添加排序按钮
          IconButton(
            icon: Icon(
              _isAscending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isAscending = !_isAscending;
                _sortPlaylist();
              });
            },
            tooltip: _isAscending ? '降序排列' : '升序排列',
          ),
        ],
      ),
    );
  }

  // 构建播放列表项
  Widget _buildPlaylistItem(int index, bool isPlaying) {
    final media = playList[index];
    final videoName = media.extras!['name'] as String;
    final videoPath = media.extras!['path'] as String;

    // 获取历史记录
    final historyRecord = _playlistHistoryRecords[videoName];

    return Card(
      elevation: isPlaying ? 4 : 1,
      color: isPlaying ? Colors.blue[50] : Colors.white,
      child: InkWell(
        onTap: () async {
          // 先保存当前视频进度，再切换视频
          await _saveCurrentProgress(updateUIImmediately: true);
          if (mounted) {
            // 如果在初始加载中，只执行视频切换
            if (_isInitialLoading) {
              _logDebug('初始加载中，跳过手动点击的处理');
              player.jump(index);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                scrollToCurrentItem();
              });
              return;
            }

            _logDebug('手动点击列表项: 索引=$index, 视频=$videoName');
            player.jump(index);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              scrollToCurrentItem();
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 视频名称
              Text(
                videoName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  color: isPlaying ? Colors.blue[700] : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // 文件路径
              Text(
                videoPath,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // 历史记录进度条
              if (historyRecord != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: historyRecord.progressValue,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isPlaying ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      historyRecord.progressText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 切换自定义播放速度
  void _toggleCustomSpeed() {
    if (_isCustomSpeedEnabled) {
      player.setRate(_previousSpeed);
      _isCustomSpeedEnabled = false;
      setState(() {
        _currentSpeed = _previousSpeed;
      });
      _rateNotifier.value = _previousSpeed;

      // 显示倍速提示
      _showSpeedIndicatorOverlay(_previousSpeed);
    } else {
      _previousSpeed = player.state.rate;
      player.setRate(_customPlaybackSpeed);
      _isCustomSpeedEnabled = true;
      setState(() {
        _currentSpeed = _customPlaybackSpeed;
      });
      _rateNotifier.value = _customPlaybackSpeed;

      // 显示倍速提示
      _showSpeedIndicatorOverlay(_customPlaybackSpeed);
    }
  }

  // 恢复到调速前的速度
  void _restoreSpeed() {
    if (_speedBeforeZXCAdjustment != null) {
      final targetSpeed = _speedBeforeZXCAdjustment!;
      player.setRate(targetSpeed);
      setState(() {
        _currentSpeed = targetSpeed;
      });
      _rateNotifier.value = targetSpeed;
      _showSpeedIndicatorOverlay(targetSpeed);
      // 恢复后清除缓存，下次x/c会重新缓存当前速度
      _speedBeforeZXCAdjustment = null;
    }
  }

  // 减速0.1x
  void _decreaseSpeed() {
    // 如果是第一次使用x/c键，保存当前速度
    _speedBeforeZXCAdjustment ??= _currentSpeed;

    // 使用四舍五入避免浮点数精度问题
    final newSpeed = ((_currentSpeed - 0.1) * 10).round() / 10.0;
    final clampedSpeed = newSpeed.clamp(0.1, 5.0);

    player.setRate(clampedSpeed);
    setState(() {
      _currentSpeed = clampedSpeed;
    });
    _rateNotifier.value = clampedSpeed;
    _showSpeedIndicatorOverlay(clampedSpeed);
  }

  // 加速0.1x
  void _increaseSpeed() {
    // 如果是第一次使用x/c键，保存当前速度
    _speedBeforeZXCAdjustment ??= _currentSpeed;

    // 使用四舍五入避免浮点数精度问题
    final newSpeed = ((_currentSpeed + 0.1) * 10).round() / 10.0;
    final clampedSpeed = newSpeed.clamp(0.1, 5.0);

    player.setRate(clampedSpeed);
    setState(() {
      _currentSpeed = clampedSpeed;
    });
    _rateNotifier.value = clampedSpeed;
    _showSpeedIndicatorOverlay(clampedSpeed);
  }

  // 显示倍速指示器覆盖层
  void _showSpeedIndicatorOverlay(double speed, {bool isLongPress = false}) {
    _hideSpeedIndicatorOverlay();

    _indicatorSpeedValue.value = speed;
    _showSpeedIndicator.value = true;

    _speedIndicatorOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.3,
        left: MediaQuery.of(context).size.width * 0.5 - 50,
        child: ValueListenableBuilder<bool>(
          valueListenable: _showSpeedIndicator,
          builder: (context, show, child) {
            if (!show) return const SizedBox.shrink();
            return ValueListenableBuilder<double>(
              valueListenable: _indicatorSpeedValue,
              builder: (context, speedValue, child) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isLongPress
                        ? Colors.orange.withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${speedValue.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    Overlay.of(context).insert(_speedIndicatorOverlay!);

    if (!isLongPress) {
      _speedIndicatorTimer?.cancel();
      _speedIndicatorTimer = Timer(const Duration(seconds: 2), () {
        _hideSpeedIndicatorOverlay();
      });
    }
  }

  // 隐藏倍速指示器覆盖层
  void _hideSpeedIndicatorOverlay() {
    _speedIndicatorOverlay?.remove();
    _speedIndicatorOverlay = null;
    _showSpeedIndicator.value = false;
  }

  // 切换视频信息覆盖层
  void _toggleVideoInfoOverlay() {
    if (_isVideoInfoVisible) {
      _hideVideoInfoOverlay();
    } else {
      _showVideoInfoOverlay();
    }
  }

  // 显示视频信息覆盖层
  void _showVideoInfoOverlay() {
    _hideVideoInfoOverlay();

    _videoInfoOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 20,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '视频信息',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (playList.isNotEmpty &&
                  currentPlayingIndex < playList.length) ...[
                Text(
                  '文件名: ${playList[currentPlayingIndex].extras!['name']}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  '路径: ${playList[currentPlayingIndex].extras!['path']}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
              Text(
                '播放速度: ${player.state.rate.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                '音量: ${player.state.volume.toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_videoInfoOverlay!);
    _isVideoInfoVisible = true;

    // 5秒后自动隐藏
    Timer(const Duration(seconds: 5), () {
      _hideVideoInfoOverlay();
    });
  }

  // 隐藏视频信息覆盖层
  void _hideVideoInfoOverlay() {
    _videoInfoOverlay?.remove();
    _videoInfoOverlay = null;
    _isVideoInfoVisible = false;
  }

  // 切换全屏
  void _toggleFullscreen() {
    // 本地播放器的全屏功能可以根据需要实现
    _logDebug('切换全屏模式');
  }

  // 退出全屏
  void _exitFullscreen() {
    // 本地播放器的退出全屏功能可以根据需要实现
    _logDebug('退出全屏模式');
  }

  // 截图功能
  Future<String?> _takeScreenshot({String? specificVideoName}) async {
    try {
      _logDebug('开始截图操作...');

      // 获取截图数据
      final screenshotBytes = await player.screenshot();
      if (screenshotBytes == null) {
        if (mounted && specificVideoName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('截图失败：无法获取截图数据'),
              backgroundColor: Colors.red,
            ),
          );
        }
        _logDebug('截图失败：无法获取截图数据');
        return null;
      }

      // 获取当前视频名称
      final videoName = specificVideoName ??
          (playList.isNotEmpty && currentPlayingIndex < playList.length
              ? playList[currentPlayingIndex].extras!['name'] as String
              : 'local_video');

      // 生成截图文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final screenshotFileName = '${videoName}_$timestamp.png';

      // 获取下载目录
      final downloadPath = await DownloadManager.getDownloadPath();
      final screenshotsDir = Directory('$downloadPath/screenshots');

      // 确保截图目录存在
      if (!await screenshotsDir.exists()) {
        await screenshotsDir.create(recursive: true);
      }

      // 保存截图文件
      final screenshotFile = File('${screenshotsDir.path}/$screenshotFileName');
      await screenshotFile.writeAsBytes(screenshotBytes);

      _logDebug('截图保存成功: ${screenshotFile.path}');

      if (mounted && specificVideoName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('截图已保存: $screenshotFileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return screenshotFile.path;
    } catch (e) {
      _logDebug('截图失败: $e');
      if (mounted && specificVideoName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('截图失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  // 构建截图按钮
  Widget buildScreenshotButton() {
    return MaterialDesktopCustomButton(
      onPressed: () async {
        _logDebug('截图按钮被点击');

        // 显示开始截图的提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('正在截图...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 1),
            ),
          );
        }

        await _takeScreenshot();
      },
      icon: const Tooltip(
        message: '截图',
        child: Icon(
          Icons.camera_alt,
          color: Colors.white,
        ),
      ),
    );
  }

  // 构建速度按钮
  Widget buildSpeedButton() {
    return MaterialDesktopCustomButton(
      onPressed: () {
        showDialog(
          context: context,
          barrierColor: Colors.black54,
          builder: (context) => buildSpeedDialog(),
        );
      },
      icon: ValueListenableBuilder<double>(
        valueListenable: _rateNotifier,
        builder: (context, rate, _) {
          return Text(
            '${rate.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          );
        },
      ),
    );
  }

  // 构建速度对话框
  Widget buildSpeedDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 300,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '播放速度',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // 速度选项
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _playbackSpeeds.map((speed) {
                    final isSelected = (speed - _currentSpeed).abs() < 0.01;
                    return SizedBox(
                      width: 80,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          player.setRate(speed);
                          setState(() {
                            _currentSpeed = speed;
                          });
                          _rateNotifier.value = speed;
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isSelected ? Colors.blue : Colors.grey[200],
                          foregroundColor:
                              isSelected ? Colors.white : Colors.black87,
                          elevation: isSelected ? 2 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          speed == 1.0 ? '正常' : '${speed}x',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建桌面端快捷键
  Map<ShortcutActivator, VoidCallback> _buildDesktopKeyboardShortcuts() {
    return {
      VideoShortcutActivator(
        key: LogicalKeyboardKey.arrowRight,
        onPress: () {
          final rate = player.state.position + _shortSeekDuration;
          player.seek(rate);
        },
        onLongPress: () {
          _previousSpeed = controller.player.state.rate;
          player.setRate(AppConstants.longPressPlaybackSpeed);

          // 显示倍速提示，并取消任何已有定时器
          _showSpeedIndicatorOverlay(AppConstants.longPressPlaybackSpeed,
              isLongPress: true);
          _speedIndicatorTimer?.cancel();
          _speedIndicatorTimer = null;
        },
        onRelease: () {
          player.setRate(_previousSpeed);

          // 立即更新倍速提示，显示恢复后的倍速值
          _showSpeedIndicatorOverlay(_previousSpeed);

          // 设置定时器，延迟2秒后隐藏提示
          _speedIndicatorTimer?.cancel();
          _speedIndicatorTimer = Timer(
              const Duration(seconds: 2), () => _hideSpeedIndicatorOverlay());
        },
      ): () {},

      // 添加Tab键快捷键，显示视频流信息
      const SingleActivator(LogicalKeyboardKey.tab): () {
        _toggleVideoInfoOverlay();
      },

      // 添加P键快捷键
      const SingleActivator(LogicalKeyboardKey.keyP): () {
        _toggleCustomSpeed();
      },

      // 其他快捷键
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () => player.play(),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
          player.pause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
          player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
          player.next(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
          player.previous(),
      const SingleActivator(LogicalKeyboardKey.space): () =>
          player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.keyJ): () {
        final rate = player.state.position - _longSeekDuration;
        player.seek(rate);
      },
      const SingleActivator(LogicalKeyboardKey.keyI): () {
        final rate = player.state.position + _longSeekDuration;
        player.seek(rate);
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        final rate = player.state.position - _shortSeekDuration;
        player.seek(rate);
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        final volume = player.state.volume + 5.0;
        player.setVolume(volume.clamp(0.0, 100.0));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        final volume = player.state.volume - 5.0;
        player.setVolume(volume.clamp(0.0, 100.0));
      },
      const SingleActivator(LogicalKeyboardKey.keyF): () => _toggleFullscreen(),
      const SingleActivator(LogicalKeyboardKey.escape): () => _exitFullscreen(),

      // 添加z/x/c键快捷键用于播放速度控制
      const SingleActivator(LogicalKeyboardKey.keyZ): () {
        _restoreSpeed();
      },

      const SingleActivator(LogicalKeyboardKey.keyX): () {
        _decreaseSpeed();
      },

      const SingleActivator(LogicalKeyboardKey.keyC): () {
        _increaseSpeed();
      },
    };
  }

  @override
  void dispose() {
    // 保存当前播放进度
    if (!_isExiting) {
      _isExiting = true;
      _saveCurrentProgress();
    }

    // 清理定时器
    _saveProgressDebounceTimer?.cancel();
    _speedIndicatorTimer?.cancel();

    // 清理覆盖层
    _hideSpeedIndicatorOverlay();
    _hideVideoInfoOverlay();

    // 清理控制器
    _subtitleSearchController.dispose();
    _rateNotifier.dispose();
    _showSpeedIndicator.dispose();
    _indicatorSpeedValue.dispose();

    // 清理键盘事件处理器
    VideoShortcutActivator.dispose();

    // 清理播放器
    player.dispose();

    super.dispose();
  }
}

// VideoShortcutActivator类定义（复用自video_player.dart）
class VideoShortcutActivator extends ShortcutActivator {
  final LogicalKeyboardKey key;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final VoidCallback? onRelease;

  VideoShortcutActivator({
    required this.key,
    this.onPress,
    this.onLongPress,
    this.onRelease,
  });

  static final Map<LogicalKeyboardKey, DateTime> _pressStartTimes = {};
  static final Map<LogicalKeyboardKey, bool> _isLongPressMap = {};
  static final Map<LogicalKeyboardKey, Timer> _pressTimers = {};
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  static void dispose() {
    for (var timer in _pressTimers.values) {
      timer.cancel();
    }
    _pressTimers.clear();
    _pressStartTimes.clear();
    _isLongPressMap.clear();
  }

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is KeyDownEvent && event.logicalKey == key) {
      // Check if key is already pressed to avoid duplicate KeyDownEvents
      if (_pressStartTimes.containsKey(key)) {
        return false; // Skip duplicate key down events
      }

      _pressStartTimes[key] = DateTime.now();
      _isLongPressMap[key] = false;

      // 使用Timer延迟判断是否为短按
      _pressTimers[key]?.cancel();
      _pressTimers[key] = Timer(_longPressThreshold, () {
        if (_pressStartTimes[key] != null) {
          _isLongPressMap[key] = true;
          onLongPress?.call();
        }
      });
      return true; // 返回true表示已处理此事件
    } else if (event is KeyUpEvent && event.logicalKey == key) {
      _pressTimers[key]?.cancel();

      if (_isLongPressMap[key] == true) {
        onRelease?.call();
      } else if (_pressStartTimes[key] != null &&
          DateTime.now().difference(_pressStartTimes[key]!) <
              _longPressThreshold) {
        onPress?.call();
      }

      // Clear key state on key up
      _pressStartTimes.remove(key);
      _isLongPressMap.remove(key);
      _pressTimers.remove(key);
      return true; // 返回true表示已处理此事件
    }
    return false; // 不是我们关心的事件
  }

  @override
  bool operator ==(Object other) {
    return other is VideoShortcutActivator && other.key == key;
  }

  @override
  int get hashCode => key.hashCode;

  @override
  String debugDescribeKeys() {
    return key.debugName ?? 'unknown';
  }
}

// SubtitleInfo类定义（如果需要的话）
class SubtitleInfo {
  final String name;
  final String path;
  final String rawUrl;

  SubtitleInfo({
    required this.name,
    required this.path,
    required this.rawUrl,
  });
}
