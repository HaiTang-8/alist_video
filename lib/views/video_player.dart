import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/historical_record.dart';
import 'package:alist_player/services/go_bridge/history_screenshot_service.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/download_manager.dart';
import 'package:alist_player/utils/font_helper.dart';
import 'package:alist_player/utils/go_proxy_helper.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:alist_player/utils/user_session.dart';
import 'package:alist_player/widgets/proxy_quality_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Add this for compute
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Add this import for File class and Platform
import 'package:crypto/crypto.dart';
import 'package:image/image.dart'
    as img; // Add this import for image processing
import 'package:path_provider/path_provider.dart'; // Added for path_provider
import 'package:alist_player/widgets/custom_material_video_controls.dart';

class VideoPlayer extends StatefulWidget {
  final String path;
  final String name;
  const VideoPlayer({super.key, required this.path, required this.name});

  @override
  State<VideoPlayer> createState() => VideoPlayerState();
}

// 将 SubtitleInfo 类移到 VideoPlayerState 类外面
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

/// 控制当前视频链接使用模式
enum PlaybackLinkMode {
  sign,
  raw,
}

extension PlaybackLinkModeX on PlaybackLinkMode {
  String get label => this == PlaybackLinkMode.raw ? 'RAW' : 'SIGN';

  String get description =>
      this == PlaybackLinkMode.raw ? 'raw_url' : 'sign 直链';
}

class VideoPlayerState extends State<VideoPlayer> {
  // Player 采用默认配置，先暂时关闭网络激进缓存优化
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
  // _currentLinkMode 表示当前视频实际使用的链接模式（sign/raw_url）。
  // _preferredLinkMode 表示用户最近一次选择的全局偏好，用于新视频的默认模式。
  PlaybackLinkMode _currentLinkMode = PlaybackLinkMode.sign;
  PlaybackLinkMode _preferredLinkMode = PlaybackLinkMode.sign;
  final ValueNotifier<PlaybackLinkMode> _linkModeNotifier =
      ValueNotifier<PlaybackLinkMode>(PlaybackLinkMode.sign);
  bool _isSwitchingLinkMode = false;

  // 添加 ValueNotifier 来管理当前播放索引的状态更新
  final ValueNotifier<int> _currentPlayingIndexNotifier = ValueNotifier<int>(0);

  // 添加 ItemScrollController 用于精确的索引滚动
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  String? _currentUsername;
  int? _currentUserId;
  bool _hasSeekInitialPosition = false;
  bool _isLoading = true;

  // 添加排序相关状态
  bool _isAscending = true;
  bool _isReorderingPlaylist = false; // 避免排序时触发切换逻辑

  // 添加一个状态变量
  bool _isExiting = false;

  // 添加一个变量来跟踪当前播放速度
  double _currentSpeed = AppConstants.defaultPlaybackSpeed;

  // 标记 Player 是否已释放，避免跨端重复触发释放流程导致断言失败
  bool _isPlayerDisposed = false;

  // 添加一个变量来存储长按前的速度
  double _previousSpeed = AppConstants.defaultPlaybackSpeed;

  // 添加变量来存储z/x/c键调速前的速度
  double? _speedBeforeZXCAdjustment;

  late Duration _shortSeekDuration;
  late Duration _longSeekDuration;

  // 添加防抖机制相关变量
  Timer? _saveProgressDebounceTimer;
  bool _isSavingProgress = false;
  bool _isReloadingInterface = false; // 标志是否正在重新加载界面

  /// 播放器流订阅统一收集，便于销毁时立即取消，避免事件晚到触发无效回调。
  final List<StreamSubscription<dynamic>> _streamSubscriptions = [];

  /// 定期输出调试信息的定时器，退出时需取消以防止后台任务泄漏。
  Timer? _debugLogTimer;

  // 将 late 移除，提供默认值
  List<double> _playbackSpeeds = AppConstants.defaultPlaybackSpeeds;

  // 添加字幕相关状态
  SubtitleTrack? _currentSubtitle;

  // 添加音轨相关状态
  AudioTrack? _currentAudio;

  // 添加一个字幕文件列表
  final List<SubtitleInfo> _availableSubtitles = [];

  // 添加搜索控制器
  final TextEditingController _subtitleSearchController =
      TextEditingController();
  // 添加搜索结果状态
  String _subtitleSearchQuery = '';

  // 添加智能匹配字幕相关变量
  SubtitleInfo? _smartMatchedSubtitle;

  // 处理错误管理相关变量
  final Map<String, DateTime> _shownErrors = {};
  static const _errorCooldown = Duration(seconds: 5);
  static const Duration _playlistPolicyRetryDelay =
      Duration(milliseconds: 300);
  static const int _playlistPolicyMaxAttempts = 5;
  String? _playbackErrorMessage;
  int? _lastFailedPlaylistIndex;
  bool _playlistErrorPolicyConfigured = false;
  Timer? _playbackErrorDismissTimer;
  int? _autoAdvanceBlockedIndex;
  bool _isUserInitiatedSwitch = false;

  // 自动重试相关变量
  static const int _maxAutoRetryAttempts = 5; // 最大自动重试次数
  int _currentRetryAttempt = 0; // 当前重试次数
  Timer? _autoRetryTimer; // 自动重试定时器
  bool _isAutoRetrying = false; // 是否正在自动重试

  // 添加自定义播放速度相关变量
  double _customPlaybackSpeed = AppConstants.defaultCustomPlaybackSpeed;
  bool _isCustomSpeedEnabled = false;

  // 添加音轨和字幕记录相关变量
  String? _recordedAudioTrackId;
  String? _recordedSubtitleTrackId;
  String? _recordedSubtitlePath; // 记录外部字幕文件路径

  // 添加倍速提示控制器
  final ValueNotifier<bool> _showSpeedIndicator = ValueNotifier<bool>(false);
  final ValueNotifier<double> _indicatorSpeedValue = ValueNotifier<double>(1.0);
  Timer? _speedIndicatorTimer;

  // 键盘长按状态管理
  static const Duration _keyboardLongPressThreshold =
      Duration(milliseconds: 500);
  Timer? _keyboardLongPressTimer;
  bool _isArrowRightPressed = false;
  bool _isArrowRightLongPressActive = false;

  // 添加Overlay相关变量
  OverlayEntry? _speedIndicatorOverlay;
  OverlayEntry? _videoInfoOverlay;
  OverlayEntry? _playbackErrorOverlayEntry;
  final GlobalKey _videoKey = GlobalKey();

  // 添加无边框模式状态
  bool _isFramelessMode = false;
  // 添加填充模式状态
  bool _isStretchMode = false;

  // Add a map to store local file paths for videos
  final Map<String, String> _localFilePaths = {};

  // Add a set to track which videos have local versions for UI display
  final Set<String> _localVideos = {};

  // 添加初始加载标志
  bool _isInitialLoading = true;

  // 播放器出现错误后标记需要恢复，切换时强制重建流，避免持续缓冲。
  bool _needsPlayerRecovery = false;

  // 添加历史记录映射，用于存储播放列表中每个视频的历史记录
  final Map<String, HistoricalRecord> _videoHistoryRecords = {};
  static const int _screenshotRawLimitBytes = 400 * 1024;

  // 本地优先播放设置
  bool _preferLocalPlayback = AppConstants.defaultPreferLocalPlayback;
  // Go 服务代理配置与缓存的鉴权头，在播放/字幕加载阶段统一复用。
  GoProxyConfig? _goProxyConfig;
  Map<String, String>? _goProxyHeaders;

  /// 视频播放器统一日志封装，方便跨端排查播放/下载/字幕问题
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'VideoPlayer',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // 判断当前是否为移动端平台（排除 Web，避免 Platform 调用异常）
  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载自定义播放速度
    final customSpeed = prefs.getDouble(AppConstants.customPlaybackSpeedKey);
    if (customSpeed != null && mounted) {
      setState(() {
        _customPlaybackSpeed = customSpeed;
      });
    }

    // 加载其他设置
    if (mounted) {
      setState(() {
        _shortSeekDuration = Duration(
          seconds: prefs.getInt(AppConstants.shortSeekKey) ??
              AppConstants.defaultShortSeekDuration.inSeconds,
        );
        _longSeekDuration = Duration(
          seconds: prefs.getInt(AppConstants.longSeekKey) ??
              AppConstants.defaultLongSeekDuration.inSeconds,
        );
        _preferLocalPlayback =
            prefs.getBool(AppConstants.preferLocalPlaybackKey) ??
                AppConstants.defaultPreferLocalPlayback;
      });
    }

    // 加载播放链接模式偏好（sign/raw_url），默认使用 sign 直链
    final linkModeName = prefs.getString(AppConstants.playbackLinkModeKey);
    if (linkModeName != null) {
      _preferredLinkMode = linkModeName == PlaybackLinkMode.raw.name
          ? PlaybackLinkMode.raw
          : PlaybackLinkMode.sign;
      _currentLinkMode = _preferredLinkMode;
      _linkModeNotifier.value = _preferredLinkMode;
      _logDebug('从偏好中恢复播放链接模式: ${_preferredLinkMode.name}');
    }

    final goProxyConfig = await GoProxyHelper.loadConfig();
    if (mounted) {
      setState(() {
        _goProxyConfig = goProxyConfig;
        final headers = goProxyConfig.buildAuthHeaders();
        _goProxyHeaders =
            headers != null ? Map<String, String>.from(headers) : null;
      });
    }

    // 加载当前文件夹的音轨和字幕记录
    await _loadFolderTrackSettings();
  }

  bool get _shouldUseGoProxy => _goProxyConfig?.shouldUseProxy ?? false;

  /// 根据代理配置将原始 URL 包装为 Go 服务可访问的地址，必要时附加 access_token。
  String _wrapGoProxyUrl(String url) {
    final config = _goProxyConfig;
    if (config == null || !config.shouldUseProxy) {
      return url;
    }
    return config.wrapUrl(url);
  }

  /// 构建播放器访问代理流时所需的 HTTP 头，例如 Authorization。
  Map<String, String>? get _currentProxyHeaders =>
      _shouldUseGoProxy ? _goProxyHeaders : null;

  /// 针对移动端高帧率（60FPS）视频出现卡顿问题，通过设置 MPV 属性启用更稳定的渲染与硬解码。
  Future<void> _optimizeMobileMpvPlayback() async {
    if (!_isMobilePlatform) {
      return;
    }

    final dynamic mpvPlayer = player.platform;
    if (mpvPlayer == null) {
      _logDebug('移动端MPV优化跳过：未获取到底层播放器实例');
      return;
    }

    // 参考 mpv 文档（https://mpv.io/manual/master/）中关于 GPU、硬解与插帧的章节进行设定。
    final String hwDecodingBackend =
        Platform.isIOS ? 'videotoolbox' : 'mediacodec';
    final String gpuApi = Platform.isIOS ? 'metal' : 'opengl';

    final properties = <String, String>{
      // 指定 libmpv 视频输出，避免默认值在移动端被包装层覆盖。
      'vo': 'libmpv',
      // 指定平台原生硬解方案，降低 60FPS H.264/HEVC 流的 CPU 压力。
      'hwdec': hwDecodingBackend,
      // 预加载硬解上下文，减少首次切换到高帧率流的卡顿。
      'hwdec-preload': 'yes',
      // MPV GPU 管线强制使用移动端对应后端（iOS Metal、Android GLES）。
      'gpu-api': gpuApi,
      'opengl-es': 'yes',
      // 启用硬解纹理与 GL 共享，防止 YUV->RGB 重复拷贝。
      'opengl-hwdec-interop': 'auto',
      // 启用显示重采样同步，平滑 60FPS 时间戳（mpv 手册 video-sync）。
      'video-sync': 'display-resample',
      // 开启帧插值（mpv 手册 interpolation），配合 tscale 提升动感连续性。
      'interpolation': 'yes',
      'tscale': 'oversample',
      // 避免 GLES 在垂直同步阶段提前 flush，减小掉帧概率。
      'opengl-early-flush': 'no',
    };

    for (final entry in properties.entries) {
      try {
        await mpvPlayer.setProperty(entry.key, entry.value);
        _logDebug('移动端MPV属性 ${entry.key}=${entry.value} 设置成功');
      } catch (e) {
        _logDebug('移动端MPV属性 ${entry.key} 设置失败: $e');
      }
    }
  }

  /// 统一设置 mpv 的 playlist-on-error 行为，避免播放失败时自动跳转下一条
  Future<void> _configurePlaylistErrorPolicy() async {
    if (_playlistErrorPolicyConfigured || kIsWeb) {
      // Web 平台不存在 mpv 属性，直接跳过配置。
      return;
    }

    for (var attempt = 1; attempt <= _playlistPolicyMaxAttempts; attempt++) {
      final dynamic mpvPlayer = player.platform;
      if (mpvPlayer == null) {
        _logDebug(
          '第$attempt次尝试设置 playlist-on-error 失败：mpv 实例尚未就绪',
        );
        await Future.delayed(_playlistPolicyRetryDelay);
        continue;
      }

      try {
        await mpvPlayer.setProperty('playlist-on-error', 'fail');
        _playlistErrorPolicyConfigured = true;
        _logDebug(
          '已设置 playlist-on-error=fail，播放失败将停留在当前条目（尝试$attempt次）',
        );
        return;
      } on NoSuchMethodError {
        _logDebug('当前平台不支持 playlist-on-error 属性，跳过配置');
        return;
      } catch (error, stack) {
        _log(
          '设置 playlist-on-error 失败，第$attempt次重试',
          level: LogLevel.error,
          error: error,
          stackTrace: stack,
        );
        await Future.delayed(_playlistPolicyRetryDelay);
      }
    }

    _logDebug('多次尝试后仍未能设置 playlist-on-error，播放器可能会继续跳播');
  }

  // 加载文件夹的音轨和字幕记录
  Future<void> _loadFolderTrackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final folderKey = 'folder_tracks_${widget.path}';

      final audioTrackId = prefs.getString('${folderKey}_audio');
      final subtitleTrackId = prefs.getString('${folderKey}_subtitle');
      final subtitlePath = prefs.getString('${folderKey}_subtitle_path');

      _recordedAudioTrackId = audioTrackId;
      _recordedSubtitleTrackId = subtitleTrackId;
      _recordedSubtitlePath = subtitlePath;

      _logDebug(
          '加载文件夹音轨字幕记录: 音轨=$audioTrackId, 字幕=$subtitleTrackId, 外部字幕=$subtitlePath');
    } catch (e) {
      _logDebug('加载文件夹音轨字幕记录失败: $e');
    }
  }

  // 保存文件夹的音轨和字幕记录
  Future<void> _saveFolderTrackSettings({
    String? audioTrackId,
    String? subtitleTrackId,
    String? subtitlePath,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final folderKey = 'folder_tracks_${widget.path}';

      if (audioTrackId != null) {
        if (audioTrackId.isEmpty) {
          await prefs.remove('${folderKey}_audio');
        } else {
          await prefs.setString('${folderKey}_audio', audioTrackId);
        }
        _recordedAudioTrackId = audioTrackId.isEmpty ? null : audioTrackId;
      }

      if (subtitleTrackId != null) {
        if (subtitleTrackId.isEmpty) {
          await prefs.remove('${folderKey}_subtitle');
        } else {
          await prefs.setString('${folderKey}_subtitle', subtitleTrackId);
        }
        _recordedSubtitleTrackId =
            subtitleTrackId.isEmpty ? null : subtitleTrackId;
      }

      if (subtitlePath != null) {
        if (subtitlePath.isEmpty) {
          await prefs.remove('${folderKey}_subtitle_path');
        } else {
          await prefs.setString('${folderKey}_subtitle_path', subtitlePath);
        }
        _recordedSubtitlePath = subtitlePath.isEmpty ? null : subtitlePath;
      }

      _logDebug(
          '保存文件夹音轨字幕记录: 音轨=$audioTrackId, 字幕=$subtitleTrackId, 外部字幕=$subtitlePath');
    } catch (e) {
      _logDebug('保存文件夹音轨字幕记录失败: $e');
    }
  }

  // 添加排序相关状态
  void _sortPlaylist() async {
    if (playList.isEmpty) {
      return;
    }

    _isReorderingPlaylist = true;
    try {
      // 记住当前播放的视频名称和位置
      final currentPlayingName =
          playList[currentPlayingIndex].extras!['name'] as String;

      // 创建一个排序后的新列表，但不直接修改原列表
      final sortedList = List<Media>.from(playList);
      sortedList.sort((a, b) {
        final nameA = a.extras!['name'] as String;
        final nameB = b.extras!['name'] as String;
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
      setState(() {
        currentPlayingIndex = playList
            .indexWhere((item) => item.extras!['name'] == currentPlayingName);
        _currentPlayingIndexNotifier.value = currentPlayingIndex;
        _syncLinkModeFromPlaylist(currentPlayingIndex);
      });
    } finally {
      // 等待事件循环的下一帧再取消标记，避免排序触发的回调误判为视频切换
      Future.delayed(Duration.zero, () {
        _isReorderingPlaylist = false;
      });
    }
  }

  // 获取当前登录信息，优先使用真实 userId，兼容历史 hash 行为
  Future<void> _loadCurrentUserIdentity() async {
    final identity = await UserSession.loadIdentity();
    if (mounted) {
      setState(() {
        _currentUsername = identity.username;
        _currentUserId = identity.effectiveUserId;
      });
    }
    if (_currentUserId == null) {
      _log(
        '未获取到当前登录用户 ID，后续操作可能失败',
        level: LogLevel.warning,
      );
    }
  }

  int? _requireUserId(String contextLabel) {
    final resolvedUserId = _currentUserId ?? _currentUsername?.hashCode;
    if (resolvedUserId == null) {
      _log(
        '缺少用户ID，已跳过 $contextLabel',
        level: LogLevel.warning,
      );
    }
    return resolvedUserId;
  }

  // 添加日志方法来统一记录视频播放器相关日志
  void _logDebug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      message,
      level: LogLevel.debug,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // 防抖保存进度方法
  void _debouncedSaveProgress() {
    // 取消之前的定时器
    _saveProgressDebounceTimer?.cancel();

    // 正在退出或播放器释放时只保留同步保存，防止重复截图拖慢返回速度。
    if (_isExiting || _isPlayerDisposed) {
      _logDebug('退出流程中或播放器已释放，跳过防抖保存');
      return;
    }

    // 如果正在保存进度或正在重新加载界面，跳过
    if (_isSavingProgress || _isReloadingInterface) {
      _logDebug(
          '正在保存进度中或重新加载界面中，跳过此次保存请求: isSaving=$_isSavingProgress, isReloading=$_isReloadingInterface');
      return;
    }

    // 设置新的定时器，500ms后执行保存
    _saveProgressDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isSavingProgress && !_isReloadingInterface) {
        _isSavingProgress = true;
        _saveCurrentProgress().then((_) {
          _logDebug('防抖保存进度完成');
          _isSavingProgress = false;
        }).catchError((error) {
          _logDebug('防抖保存进度失败: $error');
          _isSavingProgress = false;
        });
      }
    });
  }

  // 异步处理视频切换时的操作（不包含进度保存），避免阻塞UI
  void _handleVideoSwitchAsyncWithoutProgressSave(int newIndex) {
    _logDebug(
        '_handleVideoSwitchAsyncWithoutProgressSave 被调用: newIndex=$newIndex');
    Future.microtask(() async {
      try {
        // 延迟一段时间后自动应用智能匹配的字幕，确保视频已经开始播放
        if (playList.isNotEmpty && newIndex < playList.length) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              _autoApplySmartMatchedSubtitle();
            }
          });
        }
      } catch (e) {
        _logDebug('视频切换异步处理失败（无进度保存）: $e');
      }
    });
  }

  // Method to take a screenshot
  // Returns 保存结果用于后续上传
  Future<ScreenshotSaveResult?> _takeScreenshot({
    String? specificVideoName,
    String? videoSha1,
    int? userId,
  }) async {
    try {
      _logDebug('开始截图操作...');

      // 获取截图数据（这个操作相对较快）
      final Uint8List? screenshotBytes = await player.screenshot();
      if (screenshotBytes == null) {
        if (mounted && specificVideoName == null) {
          // 只在直接调用时显示错误
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to take screenshot: No data received.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        _logDebug('Screenshot failed: no data received.');
        return null;
      }

      // 获取当前视频名称
      final String videoNameToUse = specificVideoName ??
          (playList.isNotEmpty && currentPlayingIndex < playList.length
              ? playList[currentPlayingIndex].extras!['name'] as String
              : 'video');

      // 使用优化的主线程处理，但通过Future.microtask避免阻塞当前操作
      final result = await _saveScreenshotToFileOptimized(
        screenshotBytes,
        videoNameToUse,
        widget.path,
      );
      if (result != null && videoSha1 != null && userId != null) {
        unawaited(
          _uploadScreenshotToGoService(
            screenshot: result,
            videoSha1: videoSha1,
            userId: userId,
            videoName: videoNameToUse,
          ),
        );
      }
      return result;
    } catch (e) {
      _logDebug('截图操作失败: $e');

      if (mounted && specificVideoName == null) {
        // 只在直接调用时显示错误
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving screenshot: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  // 优化的截图保存方法，在主线程处理但使用异步优化
  Future<ScreenshotSaveResult?> _saveScreenshotToFileOptimized(
      Uint8List screenshotBytes, String videoName, String videoPath) async {
    return await Future.microtask(() async {
      try {
        _logDebug('开始优化截图保存处理...');
        final Directory directory = await getApplicationDocumentsDirectory();
        _logDebug('应用文档目录: ${directory.path}');

        // Sanitize videoName for use in filename, allowing Chinese characters
        final String sanitizedVideoName =
            videoName.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');
        // Sanitize videoPath for use in filename, allowing Chinese characters
        final String sanitizedVideoPath =
            videoPath.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');

        // 确保目录存在
        final screenshotDir = Directory('${directory.path}/alist_player');
        await screenshotDir.create(recursive: true);
        _logDebug('截图目录创建: ${screenshotDir.path}');

        Uint8List processedBytes = screenshotBytes;
        bool isJpeg = true;
        final alreadyCompressed = _hasImageMagicHeader(screenshotBytes);
        if (!alreadyCompressed &&
            screenshotBytes.length > _screenshotRawLimitBytes) {
          final compressionResult =
              await compute(_compressScreenshotInBackground, screenshotBytes);
          processedBytes = compressionResult['bytes'] as Uint8List;
          isJpeg = compressionResult['isJpeg'] as bool;
        } else {
          _log(
            alreadyCompressed
                ? '截图: 直接复用 media_kit 输出 (已是编码图片, size=${screenshotBytes.length} bytes)'
                : '截图: 数据较小，跳过压缩 (size=${screenshotBytes.length} bytes)',
            level: LogLevel.debug,
          );
          isJpeg = _looksLikeJpeg(screenshotBytes);
        }

        // 在主线程处理文件保存
        final String fileExtension = isJpeg ? 'jpg' : 'png';
        final String fileName =
            'screenshot_${sanitizedVideoPath}_$sanitizedVideoName.$fileExtension';
        final String filePath = '${screenshotDir.path}/$fileName';

        final File file = File(filePath);
        await file.writeAsBytes(processedBytes);

        return ScreenshotSaveResult(
          filePath: filePath,
          bytes: processedBytes,
          isJpeg: isJpeg,
        );
      } catch (e) {
        _logDebug('优化截图保存失败: $e');
        return null;
      }
    });
  }

  /// 当底层持久化为 Go 服务时，异步上传截图以便其他端复用
  Future<void> _uploadScreenshotToGoService({
    required ScreenshotSaveResult screenshot,
    required String videoSha1,
    required int userId,
    required String videoName,
  }) async {
    await GoHistoryScreenshotService.uploadScreenshot(
      videoSha1: videoSha1,
      userId: userId,
      videoName: videoName,
      videoPath: widget.path,
      bytes: screenshot.bytes,
      isJpeg: screenshot.isJpeg,
    );
  }

  // Modified playlist change handler to check for local files
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPlaybackSpeeds();

    // 添加定期调试信息
    _debugLogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        if (playList.isNotEmpty && currentPlayingIndex < playList.length) {
          final videoName =
              playList[currentPlayingIndex].extras!['name'] as String;
          final position = player.state.position;
          final duration = player.state.duration;

          _logDebug(
              '当前播放: $videoName, 进度: ${position.inSeconds}/${duration.inSeconds}秒');
        }
      } catch (e) {
        // 忽略任何错误
      }
    });

    player.setPlaylistMode(PlaylistMode.none);

    // 移动端在播放60FPS视频时容易掉帧，提前设置 MPV 属性以启用硬件解码与同步优化
    _optimizeMobileMpvPlayback();
    unawaited(_configurePlaylistErrorPolicy());

    // 注册硬件键盘事件处理，统一管理长按与短按逻辑
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);

    // 监听播放速度变化
    _streamSubscriptions.add(player.stream.rate.listen((rate) {
      _logDebug('播放器速率变更事件: ${rate.toStringAsFixed(2)}x');
      _rateNotifier.value = rate;
      if (!mounted) {
        return;
      }
      setState(() {
        _currentSpeed = rate;
      });
    }));

    _loadCurrentUserIdentity();
    _openAndSeekVideo();

    _streamSubscriptions.add(player.stream.buffer.listen((event) {
      if (event.inSeconds > 0 && mounted && !_hasSeekInitialPosition) {
        _seekToLastPosition(playList[currentPlayingIndex].extras!['name'])
            .then((_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        });
        _hasSeekInitialPosition = true;
      }
    }));

    // 2秒后标记初始加载完成，避免多次检查
    Future.delayed(const Duration(seconds: 2), () {
      _isInitialLoading = false;
      _logDebug('初始加载标记设置为false');
    });

    // 3秒后尝试智能匹配初始视频的字幕
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _autoApplySmartMatchedSubtitle();
      }
    });

    // Modified playlist change handler to check for local files
    _streamSubscriptions.add(player.stream.playlist.listen((event) async {
      if (!mounted) {
        return;
      }

      // 链接模式切换过程中会触发额外的 playlist 事件，这里直接忽略，避免重复处理。
      if (_isSwitchingLinkMode) {
        _logDebug('链接模式切换中，忽略 playlist 事件: 索引=${event.index}');
        return;
      }

      final videoName = playList.isNotEmpty && event.index < playList.length
          ? playList[event.index].extras!['name'] as String
          : "未知";
      _logDebug(
          '播放列表变化: 索引=${event.index}, 视频=$videoName, 初始加载=$_isInitialLoading, userSwitch=$_isUserInitiatedSwitch');

      // 手动切换已经在调用侧处理，这里只负责清理标记，避免与自动跳播逻辑冲突。
      if (_isUserInitiatedSwitch) {
        _logDebug('检测到来源于手动切换的 playlist 事件，跳过自动处理');
        _isUserInitiatedSwitch = false;
        return;
      }

      if (_isReorderingPlaylist) {
        _logDebug('检测到排序导致的播放列表变化，忽略进一步处理');
        return;
      }

      // 如果是初始加载，跳过检查
      if (_isInitialLoading) {
        _logDebug('初始加载中，跳过本地文件检查');
        return;
      }

      if (event.index == currentPlayingIndex) {
        _logDebug('播放列表索引未发生变化，跳过进度保存');
        return;
      }

      // 如果存在未消除的播放错误且当前索引与失败索引不同，阻止 mpv 自动跳到下一条
      if (_autoAdvanceBlockedIndex != null &&
          event.index != _autoAdvanceBlockedIndex) {
        _logDebug(
          '检测到播放错误后的自动跳播: 当前索引=${event.index}, 失败索引=$_autoAdvanceBlockedIndex',
        );
        unawaited(player.pause());
        unawaited(player.stop());
        unawaited(player.jump(_autoAdvanceBlockedIndex!));
        _autoAdvanceBlockedIndex = null;
        return;
      }

      // 优化切换视频逻辑：先保存进度，再更新UI状态，然后异步处理其他操作
      _logDebug('播放列表变化，准备保存当前视频进度');
      await _saveCurrentProgress(updateUIImmediately: true);

      _clearPlaybackErrorMessage(useSetState: false);
      _autoAdvanceBlockedIndex = null;

      setState(() {
        currentPlayingIndex = event.index;
        _currentPlayingIndexNotifier.value = event.index;
        _syncLinkModeFromPlaylist(event.index);
        _isLoading = true;
        _hasSeekInitialPosition = false;
      });

      // 在 setState 完成后再执行滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToCurrentItem();
      });

      // 异步处理本地文件检查等其他操作
      _handleVideoSwitchAsyncWithoutProgressSave(event.index);
    }));

    // 错误监听：过滤非致命错误，仅对真正影响播放的错误进行处理
    _streamSubscriptions.add(player.stream.error.listen((error) {
      if (!mounted) {
        return;
      }
      // 检查是否为非致命警告（只显示提示，不重试不暂停）
      if (_isNonFatalWarning(error)) {
        _logDebug('检测到非致命警告: $error');
        _showWarningMessage(error.toString());
        return;
      }
      unawaited(_handlePlaybackFailure(error));
    }));

    // 监听字幕轨道变化
    _streamSubscriptions.add(player.stream.tracks.listen((tracks) {
      if (!mounted) {
        return;
      }
      setState(() {});

      // 打印当前视频的字幕轨道列表
      _logDebug('当前视频字幕轨道列表: ${tracks.subtitle.length}个轨道');
      // 打印当前视频的音轨列表
      _logDebug('当前视频音轨列表: ${tracks.audio.length}个轨道');
    }));

    // 监听当前选中的字幕和音轨
    _streamSubscriptions.add(player.stream.track.listen((track) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentSubtitle = track.subtitle;
        _currentAudio = track.audio;
      });
    }));

    // Add position monitoring to detect when video ends
    _streamSubscriptions.add(player.stream.position.listen((position) {
      if (player.state.duration.inSeconds > 0 &&
          position.inSeconds >= player.state.duration.inSeconds - 1) {
        // Video reached the end, make sure it's paused
        player.pause();

        // 在视频结束时保存进度
        if (mounted) {
          _saveCurrentProgress().then((_) {
            _logDebug('视频结束，进度已保存');
          });
        }
      }
    }));

    // 添加对播放状态的监听，在暂停时保存进度（使用防抖机制）
    _streamSubscriptions.add(player.stream.playing.listen((isPlaying) {
      if (!isPlaying && mounted) {
        // 使用防抖机制，避免频繁的暂停/播放操作触发多次保存
        _debouncedSaveProgress();
      }
    }));
  }

  // 修改初始化视频加载方法，避免多次检查
  Future<void> _openAndSeekVideo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final basePath = prefs.getString('base_path') ?? '/';
      final baseDownloadUrl =
          prefs.getString(AppConstants.baseDownloadUrlKey) ??
              AppConstants.defaultBaseDownloadUrl;

      _logDebug('开始加载视频: 路径=${widget.path}, 文件=${widget.name}');

      var res = await FsApi.list(
        path: widget.path,
        password: '',
        page: 1,
        perPage: 0,
        refresh: false,
      );

      if (res.code == 200) {
        // 原逻辑通过 /api/fs/get 拉取 raw_url；当前暂时禁用，仅基于 sign 直链
        final videoEntries =
            res.data?.content?.where((data) => data.type == 2).toList() ?? [];

        final List<Media> playMediaList = [];
        for (final entry in videoEntries) {
          // 暂停批量调用 /api/fs/get 以避免首屏频繁请求导致的跨端卡顿
          // final getResp = await FsApi.get(
          //   path: '${widget.path}/${entry.name}',
          //   password: '',
          // );

          String baseUrl = baseDownloadUrl;
          if (basePath != '/') {
            baseUrl = '$baseUrl$basePath';
          }

          final fallbackUrl =
              '$baseUrl${widget.path.substring(1)}/${entry.name}?sign=${entry.sign}';
          // sign 链接用作默认播放地址，待用户手动切换至 raw_url 时再动态请求
          final proxiedUrl = _wrapGoProxyUrl(fallbackUrl);

          playMediaList.add(
            Media(
              proxiedUrl,
              httpHeaders: _currentProxyHeaders,
              extras: {
                'name': entry.name ?? '',
                'size': entry.size ?? 0,
                'modified': entry.modified ?? '',
                // 默认缓存 sign 链接，同时为 raw_url 预留占位
                'signedUrl': fallbackUrl,
                'rawUrl': null,
                // 使用全局偏好作为初始链接模式，后续切换会按需覆盖。
                'linkMode': _preferredLinkMode.name,
              },
            ),
          );
        }

        setState(() {
          playList.clear();
          int index = 0;
          for (final media in playMediaList) {
            if (media.extras?['name'] == widget.name) {
              playIndex = index;
            }
            playList.add(media);
            index++;
          }
          _currentLinkMode = PlaybackLinkMode.sign;
          _linkModeNotifier.value = _currentLinkMode;
        });

        // 如果启用本地优先播放，检查并替换本地文件地址
        if (_preferLocalPlayback) {
          await _replaceWithLocalFiles();
        }

        _logDebug('播放列表加载完成: 总数=${playList.length}, 初始索引=$playIndex');

        // 修改字幕文件收集方式
        final subtitleFiles = res.data?.content
            ?.where((data) =>
                data.name?.toLowerCase().endsWith('.srt') == true ||
                data.name?.toLowerCase().endsWith('.ass') == true ||
                data.name?.toLowerCase().endsWith('.vtt') == true)
            .toList();

        if (subtitleFiles != null && subtitleFiles.isNotEmpty) {
          _availableSubtitles.clear();
          for (var subtitle in subtitleFiles) {
            String baseUrl = baseDownloadUrl;
            if (basePath != '/') {
              baseUrl = '$baseUrl$basePath';
            }
            final subtitleUrl =
                '$baseUrl${widget.path.substring(1)}/${subtitle.name}?sign=${subtitle.sign}';
            _availableSubtitles.add(SubtitleInfo(
              name: subtitle.name ?? '',
              path: '${widget.path.substring(1)}/${subtitle.name}',
              rawUrl: _wrapGoProxyUrl(subtitleUrl),
            ));
          }

          // 打印找到的外部字幕文件
          _logDebug('找到的外部字幕文件: 数量=${_availableSubtitles.length}');
        } else {
          _logDebug('未找到外部字幕文件');
        }

        // 打开视频但不自动播放，等待本地文件检查完成
        _logDebug('准备打开播放列表: 索引=$playIndex');

        // 设置初始加载标志
        _isInitialLoading = true;

        Playable playable = Playlist(
          playList,
          index: playIndex,
        );

        // 初始加载时，手动设置当前播放索引
        currentPlayingIndex = playIndex;
        _currentPlayingIndexNotifier.value = playIndex;
        _syncLinkModeFromPlaylist(playIndex);

        // 监听播放列表索引变化前，防止初始化时触发不必要的检查
        player.stream.playlist.first.then((event) {
          _logDebug('播放列表首次加载完成: 当前索引=${event.index}');
        });

        await player.open(playable, play: true);

        // 如果用户的链接模式偏好为 raw_url，则在首个视频打开后自动切换到 raw_url。
        if (_preferredLinkMode == PlaybackLinkMode.raw &&
            !_isCurrentMediaLocal) {
          _logDebug('根据偏好自动切换到 raw_url 播放模式');
          unawaited(_applyPlaybackLinkMode(PlaybackLinkMode.raw));
        }

        // 避免与播放列表变化监听冲突，手动设置初始值
        if (mounted && !_isInitialLoading) {
          setState(() {
            currentPlayingIndex = playIndex;
            _currentPlayingIndexNotifier.value = playIndex;
            _syncLinkModeFromPlaylist(playIndex);
          });
        }

        // 初始化完成后进行一次排序
        _sortPlaylist();

        // 检查整个播放列表中哪些视频有本地缓存版本
        _checkAllLocalFiles();

        // 加载播放列表中所有视频的历史记录
        _loadPlaylistHistoryRecords();

        // 在所有初始化完成后，执行初始滚动到当前播放项
        _scheduleInitialScroll();
      } else {
        // 处理API错误
        _logDebug('API错误: ${res.message ?? "未知错误"}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('加载失败: ${res.message ?? "未知错误"}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // 处理异常
      _logDebug('异常: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发生错误: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 检查整个播放列表中哪些视频有本地缓存版本
  Future<void> _checkAllLocalFiles() async {
    if (playList.isEmpty) return;

    try {
      final downloadManager = DownloadManager();
      final localVideos =
          await downloadManager.getLocalVideosInPath(widget.path);

      if (mounted) {
        setState(() {
          _localVideos.clear();

          // 遍历播放列表，将本地文件添加到_localVideos集合中
          for (final media in playList) {
            final videoName = media.extras?['name'] as String?;
            if (videoName != null && localVideos.contains(videoName)) {
              _localVideos.add(videoName);

              // 尝试查找任务以获取文件路径
              final task = downloadManager.findTask(widget.path, videoName);
              if (task != null) {
                _localFilePaths["${widget.path}/$videoName"] = task.filePath;
              }
            }
          }
        });
      }

      _log(
        '播放列表中存在 ${_localVideos.length} 个本地缓存文件',
        level: LogLevel.debug,
      );
    } catch (e, stack) {
      _log(
        '扫描播放列表本地缓存失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 替换播放列表中的本地文件地址
  Future<void> _replaceWithLocalFiles() async {
    if (playList.isEmpty) return;

    try {
      final downloadManager = DownloadManager();
      bool hasReplacement = false;

      for (int i = 0; i < playList.length; i++) {
        final videoName = playList[i].extras?['name'] as String?;
        if (videoName != null) {
          final task = downloadManager.findTask(widget.path, videoName);

          if (task != null && task.status == '已完成') {
            // 检查文件是否真实存在
            final file = File(task.filePath);
            if (await file.exists()) {
              // 创建本地文件的Media对象
              final localMedia = Media(
                'file://${task.filePath}',
                extras: playList[i].extras,
              );

              // 替换播放列表中的项目
              playList[i] = localMedia;

              // 缓存本地文件路径
              _localFilePaths["${widget.path}/$videoName"] = task.filePath;

              // 添加到本地视频集合
              _localVideos.add(videoName);

              hasReplacement = true;
              _logDebug('替换为本地文件: $videoName -> ${task.filePath}');
            }
          }
        }
      }

      if (hasReplacement) {
        _logDebug('本地文件替换完成，共替换 ${_localVideos.length} 个文件');
      } else {
        _logDebug('未找到可替换的本地文件');
      }
    } catch (e) {
      _logDebug('替换本地文件时发生错误: $e');
    }
  }

  // 在播放器中切换 sign/raw_url 模式
  Future<void> _togglePlaybackLinkMode() async {
    if (_isSwitchingLinkMode) {
      _logDebug('正在切换链接模式，忽略重复请求');
      return;
    }
    final targetMode = _currentLinkMode == PlaybackLinkMode.sign
        ? PlaybackLinkMode.raw
        : PlaybackLinkMode.sign;
    await _applyPlaybackLinkMode(targetMode);
  }

  Future<void> _applyPlaybackLinkMode(PlaybackLinkMode targetMode) async {
    if (!mounted || playList.isEmpty) {
      await _showLinkModeError('播放列表为空，无法切换播放链接。');
      return;
    }

    if (currentPlayingIndex < 0 ||
        currentPlayingIndex >= playList.length ||
        playList[currentPlayingIndex].extras == null) {
      await _showLinkModeError('当前播放项无效，无法切换播放链接。');
      return;
    }

    if (_isCurrentMediaLocal) {
      await _showLinkModeError('当前视频使用本地文件播放，暂不支持切换。');
      return;
    }

    final previousMedia = playList[currentPlayingIndex];
    final extras = Map<String, dynamic>.from(previousMedia.extras!);
    final videoName = extras['name'] as String? ?? widget.name;
    if (videoName.isEmpty) {
      await _showLinkModeError('无法识别视频文件名，切换已取消。');
      return;
    }

    if (mounted) {
      setState(() {
        _isSwitchingLinkMode = true;
      });
    }

    try {
      String? targetUrl;
      if (targetMode == PlaybackLinkMode.raw) {
        targetUrl = await _ensureRawUrl(extras, videoName);
      } else {
        targetUrl = extras['signedUrl'] as String?;
      }

      if (targetUrl == null || targetUrl.isEmpty) {
        await _showLinkModeError('缺少 ${targetMode.description} 地址。');
        return;
      }

      extras['linkMode'] = targetMode.name;
      final updatedMedia = Media(
        _wrapGoProxyUrl(targetUrl),
        httpHeaders: _currentProxyHeaders,
        extras: extras,
      );

      playList[currentPlayingIndex] = updatedMedia;
      _syncLinkModeFromPlaylist(currentPlayingIndex);

      final wasPlaying = player.state.playing;
      final currentPosition = player.state.position;

      await player.open(
        Playlist(playList, index: currentPlayingIndex),
        play: false,
      );

      if (currentPosition > Duration.zero) {
        await player.seek(currentPosition);
      }

      if (wasPlaying) {
        await player.play();
      }

      _logDebug('已切换播放链接模式: ${targetMode.name}');

      // 将用户选择的播放链接模式持久化，保证下次进入播放器时沿用当前偏好。
      try {
        _preferredLinkMode = targetMode;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppConstants.playbackLinkModeKey,
          targetMode.name,
        );
        _logDebug('已持久化播放链接模式偏好: ${targetMode.name}');
      } catch (persistError, persistStack) {
        _log(
          '持久化播放链接模式失败',
          level: LogLevel.warning,
          error: persistError,
          stackTrace: persistStack,
        );
      }
    } catch (e, stack) {
      playList[currentPlayingIndex] = previousMedia;
      _syncLinkModeFromPlaylist(currentPlayingIndex);
      _logDebug('切换播放链接失败: $e', error: e, stackTrace: stack);
      await _showLinkModeError('切换到 ${targetMode.description} 失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingLinkMode = false;
        });
      }
    }
  }

  Future<String?> _ensureRawUrl(
    Map<String, dynamic> extras,
    String videoName,
  ) async {
    final cached = extras['rawUrl'] as String?;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final resp = await FsApi.get(
      path: '${widget.path}/${videoName}',
      password: '',
    );

    if (resp.code != 200) {
      throw Exception(resp.message ?? 'raw_url 接口返回错误');
    }

    final rawUrl = resp.data?.rawUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      throw Exception('raw_url 缺失');
    }
    extras['rawUrl'] = rawUrl;
    return rawUrl;
  }

  Future<void> _showLinkModeError(String message) async {
    _logDebug('播放链接切换失败: $message');
    await _showSelectableErrorDialog(
      title: '播放链接切换失败',
      message: message,
    );
  }

  Future<void> _showSelectableErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText.rich(
            TextSpan(
              text: message,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  // 切换本地优先播放设置
  Future<void> _toggleLocalPlaybackPreference() async {
    try {
      _logDebug('开始切换本地优先播放设置...');

      // 先保存当前播放进度
      await _saveCurrentPlaybackProgress();

      final prefs = await SharedPreferences.getInstance();
      final newPreference = !_preferLocalPlayback;

      // 保存设置到SharedPreferences
      await prefs.setBool(AppConstants.preferLocalPlaybackKey, newPreference);

      setState(() {
        _preferLocalPlayback = newPreference;
      });

      _logDebug('本地优先播放设置已切换为: ${newPreference ? "启用" : "禁用"}');

      // 显示提示信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newPreference ? '已启用本地优先播放，正在重新加载列表...' : '已禁用本地优先播放，正在重新加载列表...',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: newPreference ? Colors.green : Colors.orange,
          ),
        );
      }

      // 重新加载整个界面
      await _reloadEntireInterface();
    } catch (e) {
      _logDebug('切换本地优先播放设置时发生错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('设置切换失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 保存当前播放进度
  Future<void> _saveCurrentPlaybackProgress() async {
    try {
      if (playList.isEmpty || currentPlayingIndex >= playList.length) {
        _logDebug('没有正在播放的视频，跳过进度保存');
        return;
      }

      final currentVideo = playList[currentPlayingIndex];
      final videoName = currentVideo.extras!['name'] as String;
      final currentPosition = player.state.position;
      final totalDuration = player.state.duration;

      if (currentPosition.inSeconds <= 0 || totalDuration.inSeconds <= 0) {
        _logDebug(
            '播放位置或总时长无效，跳过进度保存: 位置=${currentPosition.inSeconds}秒, 总时长=${totalDuration.inSeconds}秒');
        return;
      }

      // 检查当前是否播放本地文件
      final isPlayingLocalFile = currentVideo.uri.startsWith('file://');
      _logDebug(
          '保存当前播放进度: 视频=$videoName, 位置=${currentPosition.inSeconds}秒, 总时长=${totalDuration.inSeconds}秒, 本地文件=$isPlayingLocalFile');

      // 无论是本地文件还是在线文件，都使用相同的标识符和路径
      // 这样确保本地播放和在线播放的进度记录是同一条
      final videoSha1 = _getVideoSha1(widget.path, videoName);
      final userId = _requireUserId('保存播放进度');
      if (userId == null) {
        return;
      }

      // 使用DatabaseHelper的upsertHistoricalRecord方法保存到数据库
      // 始终使用widget.path作为videoPath，确保本地和在线播放的记录一致
      await DatabaseHelper.instance.upsertHistoricalRecord(
        videoSha1: videoSha1,
        videoPath: widget.path,
        videoSeek: currentPosition.inSeconds,
        userId: userId,
        videoName: videoName,
        totalVideoDuration: totalDuration.inSeconds,
      );

      // 创建历史记录对象用于本地缓存
      final record = HistoricalRecord(
        videoSha1: videoSha1,
        videoPath: widget.path,
        videoName: videoName,
        userId: userId,
        changeTime: DateTime.now(),
        videoSeek: currentPosition.inSeconds,
        totalVideoDuration: totalDuration.inSeconds,
      );

      // 更新本地缓存
      _videoHistoryRecords[videoName] = record;

      _logDebug(
          '播放进度保存成功: $videoName (${isPlayingLocalFile ? "本地文件" : "在线文件"})');
    } catch (e) {
      _logDebug('保存播放进度时发生错误: $e');
    }
  }

  // 重新加载整个界面
  Future<void> _reloadEntireInterface() async {
    try {
      _logDebug('开始重新加载整个界面...');

      // 设置重新加载标志，防止防抖保存覆盖进度
      _isReloadingInterface = true;

      // 暂停播放并关闭播放器
      await player.pause();
      await player.stop();

      _clearPlaybackErrorMessage(useSetState: false);

      // 清空所有状态（保留历史记录缓存）
      setState(() {
        _isLoading = true;
        _localVideos.clear();
        _localFilePaths.clear();
        // 不清空 _videoHistoryRecords，因为这是从数据库加载的历史记录
        _availableSubtitles.clear();
        playList.clear();
        currentPlayingIndex = 0;
        _syncLinkModeFromPlaylist(currentPlayingIndex);
        _currentPlayingIndexNotifier.value = 0;
        playIndex = 0;
        _hasSeekInitialPosition = false;
        _isInitialLoading = true;
      });

      // 重新初始化播放器设置
      player.setPlaylistMode(PlaylistMode.none);

      // 重新加载播放列表
      await _openAndSeekVideo();

      // 重新加载历史记录，确保进度条正确显示
      await _loadPlaylistHistoryRecords();

      setState(() {
        _isLoading = false;
        _isInitialLoading = false;
      });
      _clearPlaybackErrorMessage(useSetState: false);

      // 清除重新加载标志，恢复防抖保存功能
      _isReloadingInterface = false;

      _logDebug('整个界面重新加载完成');
    } catch (e) {
      _logDebug('重新加载整个界面时发生错误: $e');

      // 即使出错也要清除重新加载标志
      _isReloadingInterface = false;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重新加载失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 加载播放列表中所有视频的历史记录
  Future<void> _loadPlaylistHistoryRecords() async {
    if (playList.isEmpty) return;

    final userId = _requireUserId('加载播放列表历史记录');
    if (userId == null) {
      return;
    }

    try {
      // 获取当前目录下所有视频文件的历史记录
      final historyRecords =
          await DatabaseHelper.instance.getHistoricalRecordsByPath(
        path: widget.path,
        userId: userId,
      );

      if (historyRecords.isEmpty) return;

      // 将历史记录关联到对应的视频
      if (mounted) {
        setState(() {
          _videoHistoryRecords.clear();

          for (final record in historyRecords) {
            _videoHistoryRecords[record.videoName] = record;
          }
        });
      }

      _logDebug("Found ${historyRecords.length} history records for playlist");
    } catch (e) {
      _logDebug("Error loading playlist history records: $e");
    }
  }

  // Check if a file with the given path exists in the download tasks
  Future<String?> _checkLocalFile(String path) async {
    // Check if we already know this file is local
    if (_localFilePaths.containsKey(path)) {
      return _localFilePaths[path];
    }

    final downloadManager = DownloadManager();

    // 使用新的findTask方法获取任务
    final fileName = path.split('/').last;
    final directoryPath = path.substring(0, path.lastIndexOf('/'));
    final task = downloadManager.findTask(directoryPath, fileName);

    if (task != null && task.status == '已完成') {
      // Check if the file actually exists on disk
      final file = File(task.filePath);
      if (await file.exists()) {
        // Cache the result
        _localFilePaths[path] = task.filePath;

        // Add to set of local videos for UI
        if (mounted) {
          setState(() {
            _localVideos.add(fileName);
          });
        }

        return task.filePath;
      }
    }

    return null;
  }

  // 立即更新UI中的播放进度，然后异步保存到数据库
  Future<void> _saveCurrentProgress({
    bool updateUIImmediately = false,
    bool waitForCompletion = false, // 新增参数：是否等待完成（用于退出时）
  }) async {
    // 退出阶段只允许 waitForCompletion 的强制保存，避免异步重复执行。
    if (_isExiting && !waitForCompletion) {
      _logDebug('退出流程中收到异步保存请求，直接跳过');
      return;
    }

    // 不需要重置标志，以避免重复调用时重复执行
    if (_isPlayerDisposed) {
      _log(
        '跳过进度保存：播放器已释放',
        level: LogLevel.warning,
      );
      return;
    }

    if (!mounted || playList.isEmpty || _isLoading) {
      _log(
        '跳过进度保存：mounted=$mounted, username=$_currentUsername, isEmpty=${playList.isEmpty}, isLoading=$_isLoading',
        level: LogLevel.debug,
      );
      return;
    }

    final userId = _requireUserId('视频进度保存');
    if (userId == null) {
      return;
    }

    try {
      final currentPosition = player.state.position;
      final duration = player.state.duration; // 获取视频总时长

      // 播放失败或尚未拿到有效时长时不落库，避免 0 进度污染历史记录。
      final isFailedItem = _lastFailedPlaylistIndex == currentPlayingIndex;
      final hasError = _playbackErrorMessage != null || isFailedItem;
      final isInvalidDuration = duration.inSeconds <= 0;
      final isInvalidPosition = currentPosition.inSeconds <= 0;

      if (hasError || isInvalidDuration || isInvalidPosition) {
        _log(
          '跳过进度保存：error=$hasError\n'
          'pos=${currentPosition.inSeconds}, '
          'dur=${duration.inSeconds}, '
          'failIdx=$_lastFailedPlaylistIndex',
          level: LogLevel.debug,
        );
        return;
      }

      // 安全检查：确保当前播放索引有效
      if (currentPlayingIndex < 0 || currentPlayingIndex >= playList.length) {
        _log(
          '跳过进度保存：无效播放索引 $currentPlayingIndex',
          level: LogLevel.warning,
        );
        return;
      }

      final currentVideo = playList[currentPlayingIndex];
      final videoName = currentVideo.extras!['name'] as String;

      _log(
        '正在保存视频进度: $videoName, 位置: ${currentPosition.inSeconds} 秒',
        level: LogLevel.debug,
      );

      final existingRecord =
          await DatabaseHelper.instance.getHistoricalRecordByName(
        name: videoName,
        userId: userId,
      );

      final videoSha1 =
          existingRecord?.videoSha1 ?? _getVideoSha1(widget.path, videoName);

      // 如果需要立即更新UI，先更新本地历史记录映射
      if (updateUIImmediately && mounted) {
        setState(() {
          _videoHistoryRecords[videoName] = HistoricalRecord(
            videoSha1: videoSha1,
            userId: userId,
            videoName: videoName,
            videoPath: widget.path,
            videoSeek: currentPosition.inSeconds,
            totalVideoDuration: duration.inSeconds,
            changeTime: DateTime.now(),
          );
        });
      }

      if (waitForCompletion) {
        // 退出时：同步保存，确保数据完整性
        await _saveProgressToDatabaseSync(
          videoSha1: videoSha1,
          videoName: videoName,
          currentPosition: currentPosition,
          duration: duration,
          updateUIImmediately: updateUIImmediately,
        );
      } else {
        // 正常切换时：异步保存，不阻塞UI
        _saveProgressToDatabase(
          videoSha1: videoSha1,
          videoName: videoName,
          currentPosition: currentPosition,
          duration: duration,
          updateUIImmediately: updateUIImmediately,
        );
      }
    } catch (e, stack) {
      _log(
        '保存进度失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 异步保存进度到数据库的方法
  Future<void> _saveProgressToDatabase({
    required String videoSha1,
    required String videoName,
    required Duration currentPosition,
    required Duration duration,
    required bool updateUIImmediately,
  }) async {
    final userId = _requireUserId('异步保存进度');
    if (userId == null) {
      return;
    }
    try {
      // 先保存到数据库，不等待截图完成
      await DatabaseHelper.instance.upsertHistoricalRecord(
        videoSha1: videoSha1,
        videoPath: widget.path,
        videoSeek: currentPosition.inSeconds,
        userId: userId,
        videoName: videoName,
        totalVideoDuration: duration.inSeconds,
      );

      // 标记进度已保存成功
      _log(
        '播放进度保存成功: $videoName, 位置: ${currentPosition.inSeconds}/${duration.inSeconds} 秒',
        level: LogLevel.debug,
      );

      // 如果之前没有立即更新UI，现在更新
      if (!updateUIImmediately && mounted) {
        setState(() {
          _videoHistoryRecords[videoName] = HistoricalRecord(
            videoSha1: videoSha1,
            userId: userId,
            videoName: videoName,
            videoPath: widget.path,
            videoSeek: currentPosition.inSeconds,
            totalVideoDuration: duration.inSeconds,
            changeTime: DateTime.now(),
          );
        });
      }

      // 异步截图，完全不阻塞主流程
      _takeScreenshotAsync(
        videoName: videoName,
        videoSha1: videoSha1,
        userId: userId,
      );
    } catch (e, stack) {
      _log(
        '数据库保存进度失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 同步保存进度到数据库的方法（用于退出时）
  Future<void> _saveProgressToDatabaseSync({
    required String videoSha1,
    required String videoName,
    required Duration currentPosition,
    required Duration duration,
    required bool updateUIImmediately,
  }) async {
    final userId = _requireUserId('同步保存进度');
    if (userId == null) {
      return;
    }
    try {
      // 先保存到数据库
      await DatabaseHelper.instance.upsertHistoricalRecord(
        videoSha1: videoSha1,
        videoPath: widget.path,
        videoSeek: currentPosition.inSeconds,
        userId: userId,
        videoName: videoName,
        totalVideoDuration: duration.inSeconds,
      );

      // 标记进度已保存成功
      _log(
        '播放进度保存成功: $videoName, 位置: ${currentPosition.inSeconds}/${duration.inSeconds} 秒',
        level: LogLevel.debug,
      );

      // 如果之前没有立即更新UI，现在更新
      if (!updateUIImmediately && mounted) {
        setState(() {
          _videoHistoryRecords[videoName] = HistoricalRecord(
            videoSha1: videoSha1,
            userId: userId,
            videoName: videoName,
            videoPath: widget.path,
            videoSeek: currentPosition.inSeconds,
            totalVideoDuration: duration.inSeconds,
            changeTime: DateTime.now(),
          );
        });
      }

      // 同步截图，等待完成（退出时确保截图也保存）
      try {
        final screenshotResult = await _takeScreenshot(
          specificVideoName: videoName,
          videoSha1: videoSha1,
          userId: userId,
        );
        if (screenshotResult == null) {
          _log(
            '退出时截图保存失败: $videoName',
            level: LogLevel.warning,
          );
        }
      } catch (e, stack) {
        _log(
          '退出时截图过程异常: $videoName',
          level: LogLevel.error,
          error: e,
          stackTrace: stack,
        );
        // 截图失败不影响进度保存
      }
    } catch (e, stack) {
      _log(
        '数据库保存进度失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // 完全异步的截图方法，不阻塞任何操作
  void _takeScreenshotAsync({
    required String videoName,
    required String videoSha1,
    required int userId,
  }) {
    // 使用 Future.microtask 确保在下一个事件循环中执行
    Future.microtask(() async {
      try {
        final screenshotResult = await _takeScreenshot(
          specificVideoName: videoName,
          videoSha1: videoSha1,
          userId: userId,
        );
        if (screenshotResult != null) {
          _log(
            '截图保存成功（异步）：${screenshotResult.filePath}',
            level: LogLevel.debug,
          );
        } else {
          _log(
            '截图保存失败（异步）: $videoName',
            level: LogLevel.warning,
          );
        }
      } catch (e, stack) {
        _log(
          '异步截图异常: $videoName',
          level: LogLevel.error,
          error: e,
          stackTrace: stack,
        );
        // 截图失败不影响任何操作
      }
    });
  }


  // 查询并跳转到上次播放位
  Future<void> _seekToLastPosition(String videoName) async {
    final userId = _requireUserId('恢复播放进度');
    if (userId == null) {
      return;
    }

    try {
      final record = await DatabaseHelper.instance.getHistoricalRecordByName(
        name: videoName,
        userId: userId,
      );

      if (record != null && mounted) {
        player.play();
        player.seek(Duration(seconds: record.videoSeek));
        // await player.seek(Duration(seconds: record.videoSeek));
        _log(
          '恢复播放进度: $videoName -> ${record.videoSeek}s',
          level: LogLevel.debug,
        );
      }
    } catch (e, stack) {
      _log(
        '恢复播放进度失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  void dispose() {
    // Cancel the save progress debounce timer
    _saveProgressDebounceTimer?.cancel();
    // dispose 场景同样视为退出流程，阻止监听器再次调度防抖保存。
    _isExiting = true;

    // 重置进度保存标志，确保可以保存进度

    // 创建一个异步函数来处理清理工作
    Future<void> cleanup() async {
      try {
        _log('视频播放器正在清理资源...', level: LogLevel.debug);

        // 先取消周期任务和流订阅，防止播放器销毁后仍有回调触发。
        _debugLogTimer?.cancel();
        for (final subscription in _streamSubscriptions) {
          await subscription.cancel();
        }
        _streamSubscriptions.clear();

        if (_isPlayerDisposed) {
          _log('播放器已提前释放，跳过重复清理', level: LogLevel.debug);
          return;
        }

        // 先暂停播放器
        await player.pause();

        // 等待进度保存成功
        if (mounted &&
            playList.isNotEmpty &&
            currentPlayingIndex < playList.length) {
          _log('正在保存最终播放进度...', level: LogLevel.debug);
          await _saveCurrentProgress(waitForCompletion: true);
          _log('最终播放进度保存完成', level: LogLevel.debug);
        }

        // 播放器关闭完成
        _log('正在关闭播放器...', level: LogLevel.debug);
        _isPlayerDisposed = true;
        await player.dispose();
        _log('播放器已关闭', level: LogLevel.debug);

        // 其他资源清理
        // ItemScrollController 不需要手动 dispose
        _log('资源清理完成', level: LogLevel.debug);
      } catch (e, stack) {
        _log(
          '清理过程中发生错误',
          level: LogLevel.error,
          error: e,
          stackTrace: stack,
        );
      }
    }

    // 执行清理函数，但不等待它完成
    cleanup();

    _subtitleSearchController.dispose();
    _rateNotifier.dispose();
    _linkModeNotifier.dispose();
    _showSpeedIndicator.dispose();
    _indicatorSpeedValue.dispose();
    _currentPlayingIndexNotifier.dispose();
    _speedIndicatorTimer?.cancel();
    _keyboardLongPressTimer?.cancel();
    _playbackErrorDismissTimer?.cancel();
    _autoRetryTimer?.cancel(); // 取消自动重试定时器
    _hideSpeedIndicatorOverlay();
    _removePlaybackErrorOverlayEntry();

    // 注销键盘事件处理器
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);

    // 最后调用父类的 dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentVideoName =
        playList.isNotEmpty && currentPlayingIndex < playList.length
            ? playList[currentPlayingIndex].extras!['name']
            : '视频播放';

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (_isExiting) return;
            if (_isPlayerDisposed) {
              Navigator.of(context).pop();
              return;
            }

            // 退出时先取消防抖定时器，确保不会再触发额外的进度保存与截图。
            _saveProgressDebounceTimer?.cancel();
            setState(() => _isExiting = true);

            final navigator = Navigator.of(context);
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            try {
              // 暂停视频
              await player.pause();

              // 重置进度保存标志，确保可以保存进度

              // 等待进度保存
              if (playList.isNotEmpty &&
                  currentPlayingIndex < playList.length) {
                await _saveCurrentProgress(waitForCompletion: true);
              }

              // 等播放器关闭
              _isPlayerDisposed = true;
              await player.dispose();

              if (!mounted) return;
              navigator.pop();
            } catch (e) {
              if (scaffoldMessenger.mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('退出时发生错误: $e')),
                );
              }
            } finally {
              if (mounted) {
                setState(() => _isExiting = false);
              }
            }
          },
        ),
        title: Text(
          currentVideoName,
          style: FontHelper.createAppBarTitleStyle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        elevation: 1,
      ),
      body: Stack(
        children: [
          // 原有的布局
          isMobile ? _buildMobileLayout() : _buildDesktopLayout(),

          // 退出时的 loading 遮罩
          if (_isExiting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '正在保存播放进度...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black.withValues(alpha: 0.3),
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 动端布局
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // 视频播放器
        AspectRatio(
          aspectRatio: 16 / 9,
          child: IconButtonTheme(
            // 移动端控件统一缩小点击热区并压缩横向 padding，确保在增大图标尺寸的同时减小按钮间距。
            data: const IconButtonThemeData(
              style: ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 2),
                ),
                minimumSize: WidgetStatePropertyAll(
                  Size(36, 36),
                ),
              ),
            ),
            child: Stack(
              children: [
                MaterialVideoControlsTheme(
                  normal: MaterialVideoControlsThemeData(
                    displaySeekBar: true,
                    seekGesture: true,
                    speedUpOnLongPress: true,
                    volumeGesture: true,
                    brightnessGesture: true,
                    visibleOnMount: false,
                    primaryButtonBar: [],
                    seekBarAlignment: Alignment.topCenter,
                    seekBarMargin:
                        const EdgeInsets.only(bottom: 15, left: 10, right: 10),
                    bottomButtonBarMargin:
                        const EdgeInsets.only(bottom: 0, left: 0, right: 0),
                    // 使用更大的 iconSize 配合上方 IconButtonTheme，改善移动端的操控视觉与间距。
                    bottomButtonBar: [
                      // “上一集/下一集”按钮，确保移动端同样具备完整的集间切换能力。
                      buildSkipPreviousButton(
                        iconSize: 20,
                      ),
                      // 第二行：控制按钮
                      const MaterialPlayOrPauseButton(
                        iconSize: 20,
                      ),
                      buildSkipNextButton(
                        iconSize: 20,
                      ),
                      const MaterialDesktopVolumeButton(
                        iconSize: 20,
                      ),
                      MaterialPositionIndicator(
                        style: TextStyle(
                          height: 1.0,
                          fontSize: 12.0,
                          color: Colors.grey[100],
                        ),
                      ),
                      const Spacer(), // 将全屏按钮推到最右边
                      buildLinkModeButton(),
                      buildSpeedButton(),
                      // buildAudioTrackButton(),
                      // buildSubtitleButton(),
                      // buildScreenshotButton(), // Added screenshot button
                      // 移动端不展示键盘快捷键按钮，避免无物理键盘场景的冗余入口。
                      const MaterialFullscreenButton(
                        iconSize: 24,
                      ),
                    ],
                  ),
                  fullscreen: MaterialVideoControlsThemeData(
                    displaySeekBar: true,
                    seekGesture: true,
                    speedUpOnLongPress: true,
                    volumeGesture: true,
                    brightnessGesture: true,
                    visibleOnMount: false,
                    topButtonBar: [],
                    // 全屏场景的倍速提示由统一覆盖层负责，这里保持空列表避免重复绘制。
                    primaryButtonBar: const [],
                    seekBarAlignment: Alignment.topCenter,
                    seekBarMargin:
                        const EdgeInsets.only(bottom: 15, left: 10, right: 10),
                    bottomButtonBarMargin:
                        const EdgeInsets.only(bottom: 0, left: 0, right: 0),
                    // 全屏下同样提高 iconSize，保持操作一致性。
                    bottomButtonBar: [
                      // 全屏态同样插入上一集按钮，保证横屏时也能一键回退。
                      buildSkipPreviousButton(
                        iconSize: 22,
                      ),
                      // 第二行：控制按钮
                      const MaterialPlayOrPauseButton(
                        iconSize: 22,
                      ),
                      buildSkipNextButton(
                        iconSize: 22,
                      ),
                      const MaterialDesktopVolumeButton(
                        iconSize: 22,
                      ),
                      MaterialPositionIndicator(
                        style: TextStyle(
                          height: 1.0,
                          fontSize: 12.0,
                          color: Colors.grey[100],
                        ),
                      ),
                      const Spacer(), // 将全屏按钮推到最右边
                      buildLinkModeButton(),
                      buildSpeedButton(),
                      buildAudioTrackButton(),
                      buildSubtitleButton(),
                      buildScreenshotButton(), // Added screenshot button
                      // 移动端全屏也不显示键盘快捷键按钮，确保交互元素只与触控相关。
                      const MaterialFullscreenButton(
                        iconSize: 24,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Video(
                        controller: controller,
                        // 当全屏/横竖屏切换触发生命周期暂停时, 自动恢复播放避免误暂停
                        resumeUponEnteringForegroundMode: true,
                        // 使用自定义控件以屏蔽 iOS 全屏长按时的默认遮罩闪现
                        controls: customMaterialVideoControls,
                      ),

                      // 统一倍速提示组件：覆盖全屏与非全屏，确保只渲染一份提示内容。
                      ValueListenableBuilder<bool>(
                        valueListenable: _showSpeedIndicator,
                        builder: (context, isVisible, _) {
                          return _SpeedIndicatorOverlay(
                            isVisible: isVisible,
                            speedValue: _indicatorSpeedValue,
                          );
                        },
                      ),
                      if (_playbackErrorMessage != null &&
                          _shouldUseEmbeddedErrorOverlay())
                        _buildPlaybackErrorOverlay(),
                    ],
                  ),
                ),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        // 播放列表
        Expanded(
          child: _buildPlaylist(),
        ),
      ],
    );
  }

  // 桌面端布局
  Widget _buildDesktopLayout() {
    if (_isFramelessMode) {
      // 无边框模式下只显示视频播放器，占满整个屏幕
      return Material(
        color: Colors.black,
        child: _buildVideoPlayer(isFrameless: true, stretch: _isStretchMode),
      );
    }

    return Row(
      children: [
        // 左侧视频播放器
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: MouseRegion(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildVideoPlayer(isFrameless: false, stretch: false),
              ),
            ),
          ),
        ),
        // 右侧播放列表
        Expanded(
          flex: 1,
          child: _buildPlaylist(),
        ),
      ],
    );
  }

  // 提取视频播放器组件
  Widget _buildVideoPlayer({bool isFrameless = false, bool stretch = false}) {
    // 视频内容包装器
    Widget videoContent = Stack(
      children: [
        GestureDetector(
          key: _videoKey,
          onLongPressStart: (_) {
            _previousSpeed = _currentSpeed;
            _logDebug('非全屏手势长按触发，缓存倍速: $_previousSpeed');
            // 使用当前缓存的倍速，避免播放器状态延迟导致恢复失败
            controller.player.setRate(AppConstants.longPressPlaybackSpeed);

            // 显示全局倍速提示，指定为长按模式
            _showSpeedIndicatorOverlay(AppConstants.longPressPlaybackSpeed,
                isLongPress: true);

            // 取消任何已有定时器，确保长按时指示器不会消失
            _speedIndicatorTimer?.cancel();
            _speedIndicatorTimer = null;
          },
          onLongPressEnd: (_) {
            _logDebug('非全屏手势长按结束，准备恢复至倍速: $_previousSpeed');
            controller.player.setRate(_previousSpeed);
            // 再次校准倍速，避免底层控件异步重置为1.0
            Future.delayed(const Duration(milliseconds: 50), () {
              if (!mounted) return;
              if (player.state.rate != _previousSpeed) {
                _logDebug('检测到长按恢复被覆盖，再次设置倍速为 $_previousSpeed');
                player.setRate(_previousSpeed);
              }
            });

            // 立即更新倍速提示，显示恢复后的倍速值
            _showSpeedIndicatorOverlay(_previousSpeed);

            // 设置定时器，延迟2秒后隐藏提示
            _speedIndicatorTimer?.cancel();
            _speedIndicatorTimer = Timer(
                const Duration(seconds: 2), () => _hideSpeedIndicatorOverlay());

            // 同步内部倍速状态与UI显示，确保后续长按逻辑一致
            setState(() {
              _currentSpeed = _previousSpeed;
            });
            _rateNotifier.value = _previousSpeed;
          },
          child: Video(
            controller: controller,
            // 桌面端也需要在全屏切换时自动恢复播放, 避免误触暂停
            resumeUponEnteringForegroundMode: true,
            controls: MaterialDesktopVideoControls,
          ),
        ),
        if (_playbackErrorMessage != null &&
            _shouldUseEmbeddedErrorOverlay())
          _buildPlaybackErrorOverlay(),
      ],
    );

    // 如果不是拉伸模式且处于无边框模式，则使用Center和AspectRatio包装
    if (!stretch && isFrameless) {
      videoContent = Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: videoContent,
        ),
      );
    }

    return Stack(
      children: [
        // Wrap [Video] widget with [MaterialDesktopVideoControlsTheme].
        MaterialDesktopVideoControlsTheme(
          normal: MaterialDesktopVideoControlsThemeData(
            displaySeekBar: true,
            visibleOnMount: false,
            primaryButtonBar: [],
            seekBarMargin: const EdgeInsets.only(bottom: 10, left: 0, right: 0),
            bottomButtonBarMargin:
                const EdgeInsets.only(bottom: 0, left: 0, right: 0, top: 0),
            bottomButtonBar: [
              buildSkipPreviousButton(iconSize: 24),
              const MaterialPlayOrPauseButton(),
              buildSkipNextButton(iconSize: 24),
              const MaterialDesktopVolumeButton(),
              const MaterialPositionIndicator(),
              const Spacer(), // 将全屏按钮推到最右边
              buildLinkModeButton(),
              buildSpeedButton(),
              buildAudioTrackButton(),
              buildSubtitleButton(),
              buildScreenshotButton(), // Added screenshot button
              buildKeyboardShortcutsButton(),
              buildFramelessButton(), // 始终显示无边框按钮
              // 在无边框模式下显示拉伸切换按钮
              if (isFrameless) buildStretchButton(),
              const MaterialFullscreenButton(
                iconSize: 28,
              ),
            ],
            keyboardShortcuts: _buildDesktopKeyboardShortcuts(), // 添加到normal模式
          ),
          fullscreen: MaterialDesktopVideoControlsThemeData(
              displaySeekBar: true,
              visibleOnMount: false,
              topButtonBar: [],
              primaryButtonBar: [],
              keyboardShortcuts: _buildDesktopKeyboardShortcuts(),
              seekBarMargin:
                  const EdgeInsets.only(bottom: 10, left: 0, right: 0),
              bottomButtonBarMargin:
                  const EdgeInsets.only(bottom: 0, left: 0, right: 0, top: 0),
              bottomButtonBar: [
                buildSkipPreviousButton(iconSize: 28),
                const MaterialPlayOrPauseButton(),
                buildSkipNextButton(iconSize: 28),
                const MaterialDesktopVolumeButton(),
                const MaterialPositionIndicator(),
                const Spacer(), // 将全屏按钮推到最右边
                buildLinkModeButton(),
                buildSpeedButton(),
                buildAudioTrackButton(),
                buildSubtitleButton(),
                buildScreenshotButton(), // Added screenshot button
                buildKeyboardShortcutsButton(),
                buildFramelessButton(), // 始终显示无边框按钮
                // 在无边框模式下显示拉伸切换按钮
                if (isFrameless) buildStretchButton(),
                const MaterialFullscreenButton(
                  iconSize: 28,
                ),
              ]),
          child: videoContent,
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
        // 网络质量徽章：仅在用户开启代理时展示，避免关闭代理后仍发起指标请求。
        if (_shouldUseGoProxy)
          const Positioned(
            top: 12,
            right: 12,
            child: ProxyQualityBadge(),
          ),
      ],
    );
  }

  // 添加无边框播放按钮
  Widget buildFramelessButton() {
    return MaterialCustomButton(
      onPressed: () {
        setState(() {
          // 切换无边框模式状态
          _isFramelessMode = !_isFramelessMode;
          // 进入无边框模式时默认设置为拉伸填充
          if (_isFramelessMode) {
            _isStretchMode = true;
          }
        });
      },
      icon: Tooltip(
        message: _isFramelessMode ? '退出无边框' : '无边框播放',
        child: Icon(
          _isFramelessMode ? Icons.fullscreen_exit : Icons.fit_screen,
          color: Colors.white,
        ),
      ),
    );
  }

  // 添加视频拉伸切换按钮
  Widget buildStretchButton() {
    return MaterialCustomButton(
      onPressed: () {
        setState(() {
          _isStretchMode = !_isStretchMode;
        });
      },
      icon: Tooltip(
        message: _isStretchMode ? '原始比例' : '拉伸填充',
        child: Icon(
          _isStretchMode ? Icons.aspect_ratio : Icons.crop_free,
          color: Colors.white,
        ),
      ),
    );
  }

  // 播放列表组件
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
          _buildPlaylistHeader(), // 使用新的标题组件
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

  /// 生成跨端稳定的唯一标识，避免使用 hashCode 导致不同进程值不一致。
  String _getVideoSha1(String path, String name) {
    final normalized = '$path/$name';
    final digest = sha1.convert(utf8.encode(normalized));
    return digest.toString();
  }

  PlaybackLinkMode _resolveLinkModeForIndex(int index) {
    if (playList.isEmpty || index < 0 || index >= playList.length) {
      return PlaybackLinkMode.sign;
    }
    final extras = playList[index].extras;
    final stored = extras != null ? extras['linkMode'] as String? : null;
    return stored == PlaybackLinkMode.raw.name
        ? PlaybackLinkMode.raw
        : PlaybackLinkMode.sign;
  }

  void _syncLinkModeFromPlaylist(int index) {
    final resolved = _resolveLinkModeForIndex(index);
    _currentLinkMode = resolved;
    _linkModeNotifier.value = resolved;
  }

  bool get _isCurrentMediaLocal {
    if (playList.isEmpty ||
        currentPlayingIndex < 0 ||
        currentPlayingIndex >= playList.length) {
      return false;
    }
    final uri = playList[currentPlayingIndex].uri;
    return uri.startsWith('file://');
  }

  // 智能匹配字幕方法
  SubtitleInfo? _smartMatchSubtitle(String videoName) {
    if (_availableSubtitles.isEmpty) return null;

    _logDebug('开始智能匹配字幕，视频名称: $videoName');

    // 提取视频名称中的SxxxExx模式
    final seasonEpisodePattern =
        RegExp(r'[Ss](\d+)[Ee](\d+)', caseSensitive: false);
    final videoMatch = seasonEpisodePattern.firstMatch(videoName);

    if (videoMatch == null) {
      _logDebug('视频名称中未找到SxxxExx模式，尝试直接名称匹配');
      // 如果没有找到SxxxExx模式，尝试直接匹配文件名（去除扩展名）
      final videoNameWithoutExt = videoName.replaceAll(RegExp(r'\.[^.]+$'), '');

      for (final subtitle in _availableSubtitles) {
        final subtitleNameWithoutExt =
            subtitle.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        if (subtitleNameWithoutExt
                .toLowerCase()
                .contains(videoNameWithoutExt.toLowerCase()) ||
            videoNameWithoutExt
                .toLowerCase()
                .contains(subtitleNameWithoutExt.toLowerCase())) {
          _logDebug('通过名称匹配找到字幕: ${subtitle.name}');
          return subtitle;
        }
      }
      return null;
    }

    final season = videoMatch.group(1)!;
    final episode = videoMatch.group(2)!;
    _logDebug('提取到季集信息: S${season}E${episode}');

    // 创建多种可能的匹配模式
    final patterns = [
      RegExp('S${season}E${episode}', caseSensitive: false),
      RegExp('s${season}e${episode}', caseSensitive: false),
      RegExp('S${season.padLeft(2, '0')}E${episode.padLeft(2, '0')}',
          caseSensitive: false),
      RegExp('s${season.padLeft(2, '0')}e${episode.padLeft(2, '0')}',
          caseSensitive: false),
      RegExp('${season}x${episode.padLeft(2, '0')}', caseSensitive: false),
      RegExp('${season.padLeft(2, '0')}x${episode.padLeft(2, '0')}',
          caseSensitive: false),
    ];

    // 按优先级匹配字幕
    for (final pattern in patterns) {
      for (final subtitle in _availableSubtitles) {
        if (pattern.hasMatch(subtitle.name)) {
          _logDebug('智能匹配成功，找到字幕: ${subtitle.name}');
          return subtitle;
        }
      }
    }

    _logDebug('智能匹配失败，未找到匹配的字幕');
    return null;
  }

  // 自动应用智能匹配的字幕
  Future<void> _autoApplySmartMatchedSubtitle() async {
    if (_availableSubtitles.isEmpty) {
      // 没有外部字幕，尝试应用记录的音轨和字幕
      await _applyRecordedTracks();
      return;
    }

    final currentVideoName =
        playList.isNotEmpty && currentPlayingIndex < playList.length
            ? playList[currentPlayingIndex].extras!['name'] as String
            : '';

    if (currentVideoName.isEmpty) {
      await _applyRecordedTracks();
      return;
    }

    final matchedSubtitle = _smartMatchSubtitle(currentVideoName);
    if (matchedSubtitle != null) {
      _smartMatchedSubtitle = matchedSubtitle;
      _logDebug('自动应用智能匹配的字幕: ${matchedSubtitle.name}');

      try {
        final wasPlaying = player.state.playing;
        await player.pause();

        // 先清除当前字幕
        await player.setSubtitleTrack(SubtitleTrack.no());

        // 加载匹配的外部字幕
        await player.setSubtitleTrack(
          SubtitleTrack.uri(
            matchedSubtitle.rawUrl,
            title: matchedSubtitle.name,
          ),
        );

        setState(() {
          _currentSubtitle = SubtitleTrack.uri(
            matchedSubtitle.rawUrl,
            title: matchedSubtitle.name,
          );
        });

        _logDebug('智能匹配字幕加载成功: ${matchedSubtitle.name}');

        // 在智能匹配成功后，尝试应用记录的音轨
        await _applyRecordedAudioTrack();

        if (wasPlaying) {
          await player.play();
        }

        // 显示提示信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已自动加载匹配字幕: ${matchedSubtitle.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        _logDebug('自动加载智能匹配字幕失败: $e');
        _smartMatchedSubtitle = null;
        // 智能匹配失败，尝试应用记录的音轨和字幕
        await _applyRecordedTracks();
      }
    } else {
      _smartMatchedSubtitle = null;
      _logDebug('未找到匹配的字幕，尝试应用记录的设置');
      // 智能匹配失败，尝试应用记录的音轨和字幕
      await _applyRecordedTracks();
    }
  }

  // 应用记录的音轨和字幕
  Future<void> _applyRecordedTracks() async {
    try {
      // 应用记录的音轨
      await _applyRecordedAudioTrack();

      // 应用记录的字幕
      await _applyRecordedSubtitle();
    } catch (e) {
      _logDebug('应用记录的音轨和字幕失败: $e');
    }
  }

  // 应用记录的音轨
  Future<void> _applyRecordedAudioTrack() async {
    if (_recordedAudioTrackId == null || _recordedAudioTrackId!.isEmpty) {
      return;
    }

    try {
      final tracks = player.state.tracks;
      final audioTrack = tracks.audio.firstWhere(
        (track) => track.id == _recordedAudioTrackId,
        orElse: () => AudioTrack.no(),
      );

      if (audioTrack.id != 'no') {
        await player.setAudioTrack(audioTrack);
        setState(() {
          _currentAudio = audioTrack;
        });
        _logDebug('已应用记录的音轨: ${audioTrack.title ?? audioTrack.id}');
      } else {
        _logDebug('记录的音轨未找到: $_recordedAudioTrackId');
      }
    } catch (e) {
      _logDebug('应用记录的音轨失败: $e');
    }
  }

  // 应用记录的字幕
  Future<void> _applyRecordedSubtitle() async {
    // 如果已经有智能匹配的字幕，不覆盖
    if (_smartMatchedSubtitle != null) {
      return;
    }

    if (_recordedSubtitleTrackId == null && _recordedSubtitlePath == null) {
      return;
    }

    try {
      final wasPlaying = player.state.playing;

      // 如果记录的是外部字幕文件
      if (_recordedSubtitlePath != null && _recordedSubtitlePath!.isNotEmpty) {
        final matchedSubtitle = _availableSubtitles.firstWhere(
          (subtitle) => subtitle.path == _recordedSubtitlePath,
          orElse: () => SubtitleInfo(name: '', path: '', rawUrl: ''),
        );

        if (matchedSubtitle.name.isNotEmpty) {
          await player.pause();
          await player.setSubtitleTrack(SubtitleTrack.no());
          await player.setSubtitleTrack(
            SubtitleTrack.uri(
              matchedSubtitle.rawUrl,
              title: matchedSubtitle.name,
            ),
          );
          setState(() {
            _currentSubtitle = SubtitleTrack.uri(
              matchedSubtitle.rawUrl,
              title: matchedSubtitle.name,
            );
          });
          _logDebug('已应用记录的外部字幕: ${matchedSubtitle.name}');

          if (wasPlaying) {
            await player.play();
          }
          return;
        }
      }

      // 如果记录的是内嵌字幕
      if (_recordedSubtitleTrackId != null &&
          _recordedSubtitleTrackId!.isNotEmpty) {
        final tracks = player.state.tracks;
        final subtitleTrack = tracks.subtitle.firstWhere(
          (track) => track.id == _recordedSubtitleTrackId,
          orElse: () => SubtitleTrack.no(),
        );

        if (subtitleTrack.id != 'no') {
          await player.pause();
          await player.setSubtitleTrack(subtitleTrack);
          setState(() {
            _currentSubtitle = subtitleTrack;
          });
          _logDebug('已应用记录的内嵌字幕: ${subtitleTrack.title ?? subtitleTrack.id}');

          if (wasPlaying) {
            await player.play();
          }
        } else {
          _logDebug('记录的字幕轨未找到: $_recordedSubtitleTrackId');
        }
      }
    } catch (e) {
      _logDebug('应用记录的字幕失败: $e');
    }
  }

  // 获取中文星期几
  String _getChineseWeekday(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
  }

  // 构建带有不同颜色的播放进度文本
  List<TextSpan> _buildWatchProgressText(HistoricalRecord record) {
    // 计算进度百分比
    final progressPercent = (record.progressValue * 100).toStringAsFixed(0);

    // 格式化观看进度时间（分:秒）
    int minutes = 0;
    int seconds = 0;

    // 确保videoSeek有效
    if (record.videoSeek > 0) {
      // videoSeek是总秒数，直接计算分钟和剩余秒数
      minutes = (record.videoSeek / 60).floor();
      seconds = (record.videoSeek % 60).floor();
    }

    final progressTime = "$minutes分$seconds秒";

    // 格式化观看日期时间
    final now = DateTime.now();
    final changeTime = record.changeTime;
    final isSameYear = now.year == changeTime.year;

    // 获取星期几
    final weekday = _getChineseWeekday(changeTime.weekday);

    // 格式化日期，如果是今年则不显示年份
    final dateFormat = isSameYear
        ? DateFormat('MM-dd $weekday HH:mm')
        : DateFormat('yyyy-MM-dd $weekday HH:mm');
    final formattedDate = dateFormat.format(changeTime);

    // 返回带有不同颜色的TextSpan列表
    return [
      const TextSpan(
        text: "观看至",
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue,
          height: 1.2,
        ),
      ),
      TextSpan(
        text: "$progressPercent%（$progressTime）$formattedDate 观看",
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
          height: 1.2,
        ),
      ),
    ];
  }

  // 修改 ListTile 的 onTap 处理
  Widget _buildPlaylistItem(int index, bool isPlaying) {
    final videoName = playList[index].extras!['name'] as String;
    final isLocalVideo = _localVideos.contains(videoName);

    // Get file size and modified time information if available
    final size = playList[index].extras?['size'] as int? ?? 0;
    final modifiedStr = playList[index].extras?['modified'] as String? ?? '';
    final modified =
        modifiedStr.isNotEmpty ? DateTime.tryParse(modifiedStr) : null;

    // 获取该视频的历史记录
    final historyRecord = _videoHistoryRecords[videoName];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isPlaying ? Colors.blue.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: isPlaying
              ? Border.all(color: Colors.blue.withOpacity(0.3), width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: AppConstants.shadowOpacity),
              spreadRadius: AppConstants.defaultSpreadRadius,
              blurRadius: AppConstants.defaultBlurRadius,
            ),
          ],
        ),
        child: InkWell(
          onTap: () async {
            if (!mounted) {
              return;
            }

            // 获取要切换到的视频信息，仅用于日志输出
            final videoName = playList[index].extras!['name'] as String;
            _logDebug('手动点击列表项: 索引=$index, 视频=$videoName');

            await _jumpToIndexFromUser(index);
          },
          hoverColor: Colors.blue.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            child: Row(
              children: [
                // 前导图标，添加序号显示
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: isPlaying
                        ? Border.all(color: Colors.blue, width: 1)
                        : Border.all(
                            color: Colors.grey.withValues(alpha: 0.3),
                            width: 1),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 显示序号 (从1开始)
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isPlaying ? Colors.blue : Colors.grey[700],
                          fontWeight:
                              isPlaying ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                      // 播放中的指示
                      if (isPlaying)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 主要内容区域
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题行
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              videoName,
                              style: TextStyle(
                                fontSize: AppConstants.defaultFontSize,
                                color: isPlaying ? Colors.blue : Colors.black87,
                                fontWeight: isPlaying
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // 副标题
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 4, // horizontal spacing between items
                          runSpacing: 2, // vertical spacing between lines
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Local file indicator
                            if (isLocalVideo)
                              Container(
                                margin: const EdgeInsets.only(right: 2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                      color:
                                          Colors.green.withValues(alpha: 0.5)),
                                ),
                                child: const Text(
                                  '已缓存',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                  ),
                                ),
                              ),

                            // File size
                            if (size > 0)
                              Text(
                                _formatSize(size),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),

                            // Modified date with separator
                            if (modified != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '|',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(modified),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),

                            // 历史记录信息
                            if (historyRecord != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 4),
                                child: RichText(
                                  text: TextSpan(
                                    style: DefaultTextStyle.of(context).style,
                                    children:
                                        _buildWatchProgressText(historyRecord),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 添加格式化日期的方法
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 添加格式化文件大小的方法
  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // 修改播放列表标题部分
  Widget _buildPlaylistHeader() {
    // 计算当前播放索引的文字信息，只保留“正在播放 x/y”提示，去除冗余标题
    String headerText = '暂无播放';
    if (playList.isNotEmpty &&
        currentPlayingIndex >= 0 &&
        currentPlayingIndex < playList.length) {
      // 显示当前播放索引 (索引+1，从1开始计数更符合用户习惯)
      headerText = '正在播放: ${currentPlayingIndex + 1}/${playList.length}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.format_list_bulleted, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headerText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 添加测试滚动按钮
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
            tooltip: _isAscending ? '降序排列' : '升序排',
          ),
          // 添加本地优先播放切换按钮
          IconButton(
            icon: Icon(
              _preferLocalPlayback ? Icons.storage : Icons.cloud,
              size: 20,
              color: _preferLocalPlayback ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              _toggleLocalPlaybackPreference();
            },
            tooltip:
                _preferLocalPlayback ? '本地优先 (点击切换为在线优先)' : '在线优先 (点击切换为本地优先)',
          ),
        ],
      ),
    );
  }

  // 在 VideoPlayerState 类中添加一个方法来构建速度选择对话框
  Widget buildSpeedDialog() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isMobile =
        MediaQuery.of(context).size.width < AppConstants.smallScreenWidth;

    return StatefulBuilder(
      builder: (context, setState) {
        if (isMobile && isLandscape) {
          // 横屏模式：水平排列的现代设计
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 64),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _playbackSpeeds.map((speed) {
                    final isSelected = speed == _currentSpeed;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            await player.setRate(speed);
                            setState(() => _currentSpeed = speed);

                            // 显示倍速提示
                            _showSpeedIndicatorOverlay(speed);

                            if (mounted && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Container(
                            width: AppConstants.speedButtonWidth,
                            height: AppConstants.speedButtonHeight,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                speed == AppConstants.defaultPlaybackSpeed
                                    ? AppConstants.normalSpeedText
                                    : '$speed${AppConstants.speedSuffix}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: AppConstants.speedIndicatorTextSize,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        } else {
          // 竖屏模式和桌面端：统一的现代化对话框
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            child: Container(
              width: AppConstants.speedDialogWidth,
              padding: const EdgeInsets.all(AppConstants.speedDialogPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '播放速度',
                    style: TextStyle(
                      fontSize: AppConstants.speedDialogTitleSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: AppConstants.speedButtonSpacing,
                    runSpacing: AppConstants.speedButtonSpacing,
                    alignment: WrapAlignment.center,
                    children: _playbackSpeeds.map((speed) {
                      final isSelected = speed == _currentSpeed;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            await player.setRate(speed);
                            setState(() => _currentSpeed = speed);

                            // 显示倍速提示
                            _showSpeedIndicatorOverlay(speed);

                            if (mounted && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Container(
                            width: AppConstants.speedButtonWidth,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                speed == AppConstants.defaultPlaybackSpeed
                                    ? AppConstants.normalSpeedText
                                    : '$speed${AppConstants.speedSuffix}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.grey[800],
                                  fontSize: AppConstants.speedButtonTextSize,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // 控制栏 raw/sign 切换按钮，同时展示当前模式与切换状态
  Widget buildLinkModeButton() {
    return MaterialCustomButton(
      onPressed: () {
        if (_isSwitchingLinkMode) {
          return;
        }
        if (_isCurrentMediaLocal) {
          unawaited(_showLinkModeError('当前视频使用本地文件播放，暂不支持切换。'));
          return;
        }
        unawaited(_togglePlaybackLinkMode());
      },
      icon: ValueListenableBuilder<PlaybackLinkMode>(
        valueListenable: _linkModeNotifier,
        builder: (context, mode, _) {
          final nextMode =
              mode == PlaybackLinkMode.sign ? 'raw_url' : 'sign';
          final label = _isCurrentMediaLocal ? 'LOCAL' : mode.label;
          final tooltip = _isCurrentMediaLocal
              ? '正在使用本地缓存，无法切换链接'
              : '切换至 $nextMode';

          if (_isSwitchingLinkMode) {
            return const Tooltip(
              message: '正在切换播放链接',
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            );
          }

          return Tooltip(
            message: tooltip,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  // 修改 buildSpeedButton 中的显示方法
  Widget buildSpeedButton() {
    return MaterialCustomButton(
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
            '${rate}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          );
        },
      ),
    );
  }

  Widget buildSkipPreviousButton({double iconSize = 20}) {
    return MaterialCustomButton(
      onPressed: _goToPreviousVideo,
      icon: Icon(
        Icons.skip_previous,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  Widget buildSkipNextButton({double iconSize = 20}) {
    return MaterialCustomButton(
      onPressed: _goToNextVideo,
      icon: Icon(
        Icons.skip_next,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildDesktopKeyboardShortcuts() {
    return {
      // 添加Tab键快捷键，显示视频流信息
      const SingleActivator(LogicalKeyboardKey.tab): () {
        _toggleVideoInfoOverlay();
      },

      // 添加P键快捷键
      const SingleActivator(LogicalKeyboardKey.keyP): () async {
        if (_isCustomSpeedEnabled) {
          await player.setRate(_previousSpeed);
          _isCustomSpeedEnabled = false;
          setState(() {
            _currentSpeed = _previousSpeed;
          });
          _rateNotifier.value = _previousSpeed;

          // 显示倍速提示
          _showSpeedIndicatorOverlay(_previousSpeed);
        } else {
          _previousSpeed = player.state.rate;
          await player.setRate(_customPlaybackSpeed);
          _isCustomSpeedEnabled = true;
          setState(() {
            _currentSpeed = _customPlaybackSpeed;
          });
          _rateNotifier.value = _customPlaybackSpeed;

          // 显示倍速提示
          _showSpeedIndicatorOverlay(_customPlaybackSpeed);
        }
      },

      // 其他快捷键
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () => player.play(),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
          player.pause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
          player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
          _goToNextVideo(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
          _goToPreviousVideo(),
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
      const SingleActivator(LogicalKeyboardKey.keyF): () =>
          toggleFullscreen(context),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          exitFullscreen(context),

      // 添加z/x/c键快捷键用于播放速度控制
      const SingleActivator(LogicalKeyboardKey.keyZ): () {
        // z键：恢复到调速前的速度
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
      },

      const SingleActivator(LogicalKeyboardKey.keyX): () {
        // x键：减速0.1x
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
      },

      const SingleActivator(LogicalKeyboardKey.keyC): () {
        // c键：加速0.1x
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
      },
    };
  }

  // 添加字幕切换按钮
  Widget buildSubtitleButton() {
    return MaterialCustomButton(
      onPressed: () {
        // 打开对话框时清空搜索
        _subtitleSearchController.clear();
        _subtitleSearchQuery = '';

        showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 400,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.subtitles,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 12),
                              const Text('选择字幕',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _subtitleSearchController,
                            decoration: InputDecoration(
                              hintText: '搜索字幕...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                _subtitleSearchQuery = value.toLowerCase();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          // 添加智能匹配按钮
                          if (_availableSubtitles.isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final currentVideoName = playList
                                              .isNotEmpty &&
                                          currentPlayingIndex < playList.length
                                      ? playList[currentPlayingIndex]
                                          .extras!['name'] as String
                                      : '';

                                  if (currentVideoName.isNotEmpty) {
                                    final matchedSubtitle =
                                        _smartMatchSubtitle(currentVideoName);
                                    if (matchedSubtitle != null) {
                                      // 自动加载匹配的字幕
                                      final wasPlaying = player.state.playing;
                                      await player.pause();

                                      try {
                                        await player.setSubtitleTrack(
                                            SubtitleTrack.no());
                                        await player.setSubtitleTrack(
                                          SubtitleTrack.uri(
                                            matchedSubtitle.rawUrl,
                                            title: matchedSubtitle.name,
                                          ),
                                        );

                                        setDialogState(() {
                                          _smartMatchedSubtitle =
                                              matchedSubtitle;
                                          _currentSubtitle = SubtitleTrack.uri(
                                            matchedSubtitle.rawUrl,
                                            title: matchedSubtitle.name,
                                          );
                                        });

                                        // 保存智能匹配的字幕记录
                                        await _saveFolderTrackSettings(
                                          subtitleTrackId: '',
                                          subtitlePath: matchedSubtitle.path,
                                        );

                                        if (wasPlaying) {
                                          await player.play();
                                        }

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '智能匹配成功: ${matchedSubtitle.name}'),
                                            backgroundColor: Colors.green,
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      } catch (e) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '加载字幕失败: ${matchedSubtitle.name}'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('未找到匹配的字幕'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.auto_fix_high, size: 18),
                                label: const Text('智能匹配字幕'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[50],
                                  foregroundColor: Colors.blue[700],
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_subtitleSearchQuery.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 8,
                                ),
                                child: _buildSubtitleOption(
                                  context,
                                  SubtitleTrack.no(),
                                  '关闭字幕',
                                  setDialogState,
                                ),
                              ),

                            // 添加内嵌字幕选项
                            if (player.state.tracks.subtitle.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 16, bottom: 8),
                                child: Text(
                                  '内嵌字幕',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),

                            ...player.state.tracks.subtitle.where((track) {
                              final title = track.title?.toLowerCase() ?? '';
                              final language =
                                  track.language?.toLowerCase() ?? '';
                              return _subtitleSearchQuery.isEmpty ||
                                  title.contains(_subtitleSearchQuery) ||
                                  language.contains(_subtitleSearchQuery);
                            }).map((track) {
                              final displayName =
                                  track.title?.isNotEmpty == true
                                      ? track.title!
                                      : track.language?.isNotEmpty == true
                                          ? track.language!
                                          : '字幕 ${track.id}';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _buildSubtitleOption(
                                  context,
                                  track,
                                  displayName,
                                  setDialogState,
                                ),
                              );
                            }),

                            // 添加外部字幕选项标题
                            if (_availableSubtitles.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 16, bottom: 8),
                                child: Row(
                                  children: [
                                    Text(
                                      '外部字幕文件',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    if (_smartMatchedSubtitle != null)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color:
                                                Colors.green.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          '已智能匹配',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            ..._availableSubtitles
                                .where((subtitle) => subtitle.name
                                    .toLowerCase()
                                    .contains(_subtitleSearchQuery))
                                .map((subtitle) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: _buildExternalSubtitleOption(
                                        context,
                                        subtitle,
                                        setDialogState,
                                      ),
                                    ))
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      icon: Icon(
        _currentSubtitle?.id == 'no' ? Icons.subtitles_off : Icons.subtitles,
        color: Colors.white,
      ),
    );
  }

  // 添加外部字幕处理方法
  Widget _buildExternalSubtitleOption(
      BuildContext context, SubtitleInfo subtitle, StateSetter setDialogState) {
    final isSelected = _currentSubtitle?.title == subtitle.name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final wasPlaying = player.state.playing;
          await player.pause();

          try {
            _log(
              '正在加载外部字幕: ${subtitle.name} (${subtitle.rawUrl})',
              level: LogLevel.debug,
            );

            // 直接使用预先生成的 URL
            await player.setSubtitleTrack(SubtitleTrack.no());
            await player.setSubtitleTrack(
              SubtitleTrack.uri(
                subtitle.rawUrl,
                title: subtitle.name,
              ),
            );
            setDialogState(() {
              _currentSubtitle = SubtitleTrack.uri(
                subtitle.rawUrl,
                title: subtitle.name,
              );
            });
            _log('外部字幕加载成功: ${subtitle.name}', level: LogLevel.debug);

            // 保存字幕记录（外部字幕）
            await _saveFolderTrackSettings(
              subtitleTrackId: '',
              subtitlePath: subtitle.path,
            );

            if (wasPlaying) {
              await player.play();
            }
          } catch (e, stack) {
            _log(
              '加载外部字幕失败: ${subtitle.name}',
              level: LogLevel.error,
              error: e,
              stackTrace: stack,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('加载字幕失败: ${subtitle.name}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          if (mounted) {
            Navigator.pop(context);
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  subtitle.name,
                  style: TextStyle(
                    color: isSelected ? Colors.blue : Colors.grey[800],
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (_smartMatchedSubtitle?.name == subtitle.name)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '智能匹配',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleOption(BuildContext context, SubtitleTrack track,
      String label, StateSetter setDialogState) {
    final isSelected = track.id == 'no'
        ? _currentSubtitle?.id == 'no'
        : _currentSubtitle?.id == track.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final wasPlaying = player.state.playing;
          await player.pause();

          try {
            if (track.id == 'no') {
              await player.setSubtitleTrack(track);
              setDialogState(() {
                _currentSubtitle = track;
              });
              _log('已关闭字幕', level: LogLevel.debug);

              // 保存字幕记录（关闭字幕）
              await _saveFolderTrackSettings(
                subtitleTrackId: '',
                subtitlePath: '',
              );
            } else {
              // 内嵌字幕直接设置
              _log(
                '正在加载内嵌字幕: $label (ID: ${track.id})',
                level: LogLevel.debug,
              );
              await player.setSubtitleTrack(track);
              setDialogState(() {
                _currentSubtitle = track;
              });
              _log(
                '内嵌字幕加载成功: $label (ID: ${track.id})',
                level: LogLevel.debug,
              );

              // 保存字幕记录（内嵌字幕）
              await _saveFolderTrackSettings(
                subtitleTrackId: track.id,
                subtitlePath: '',
              );
            }

            if (wasPlaying) {
              await player.play();
            }
          } catch (e, stack) {
            _log(
              '加载内嵌字幕失败: $label',
              level: LogLevel.error,
              error: e,
              stackTrace: stack,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('加载字幕失败: ${label}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          if (mounted) {
            Navigator.pop(context);
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey[800],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // 添加音轨选择按钮
  Widget buildAudioTrackButton() {
    return MaterialCustomButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 400,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Icon(Icons.audiotrack,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 12),
                          const Text('选择音轨',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              )),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 自动选择选项
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildAudioTrackOption(
                                context,
                                AudioTrack.auto(),
                                '自动选择',
                                setDialogState,
                              ),
                            ),

                            // 禁用音轨选项
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildAudioTrackOption(
                                context,
                                AudioTrack.no(),
                                '禁用音轨',
                                setDialogState,
                              ),
                            ),

                            // 可用音轨列表
                            if (player.state.tracks.audio.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 8),
                                child: Text(
                                  '可用音轨',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),

                            ...player.state.tracks.audio.map((track) {
                              final displayName =
                                  _getAudioTrackDisplayName(track);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _buildAudioTrackOption(
                                  context,
                                  track,
                                  displayName,
                                  setDialogState,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      icon: Icon(
        _currentAudio?.id == 'no' ? Icons.volume_off : Icons.audiotrack,
        color: Colors.white,
      ),
    );
  }

  // 获取音轨显示名称
  String _getAudioTrackDisplayName(AudioTrack track) {
    if (track.title?.isNotEmpty == true) {
      return track.title!;
    }
    if (track.language?.isNotEmpty == true) {
      return track.language!;
    }
    return '音轨 ${track.id}';
  }

  // 构建音轨选项
  Widget _buildAudioTrackOption(BuildContext context, AudioTrack track,
      String label, StateSetter setDialogState) {
    final isSelected = _isAudioTrackSelected(track);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final wasPlaying = player.state.playing;
          await player.pause();

          try {
            await player.setAudioTrack(track);
            setDialogState(() {
              _currentAudio = track;
            });
            _logDebug('音轨切换成功: $label (ID: ${track.id})');

            // 保存音轨记录
            await _saveFolderTrackSettings(audioTrackId: track.id);

            if (wasPlaying) {
              await player.play();
            }
          } catch (e) {
            _logDebug('音轨切换失败: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('切换音轨失败: $label'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          if (mounted) {
            Navigator.pop(context);
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey[800],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // 判断音轨是否被选中
  bool _isAudioTrackSelected(AudioTrack track) {
    if (track.id == 'auto') {
      return _currentAudio?.id == 'auto';
    }
    if (track.id == 'no') {
      return _currentAudio?.id == 'no';
    }
    return _currentAudio?.id == track.id;
  }

  /// 判断是否为非致命警告（只需显示提示，不需要重试和暂停播放）
  /// 这些错误通常是警告性质，不会真正影响视频播放
  bool _isNonFatalWarning(Object error) {
    final message = error.toString().toLowerCase();

    // 可忽略的错误关键词列表
    const ignorablePatterns = [
      // 字幕相关的非致命错误
      'subtitle',
      'sub',
      'ass',
      'srt',
      // 元数据/标签相关
      'metadata',
      'tag',
      'cover',
      'album',
      'artist',
      'title tag',
      // 编解码器警告（非致命）
      'aviavi',
      'avi header',
      'discarding',
      'discarded',
      'deprecated',
      // 缓冲相关的临时警告
      'buffer underflow',
      'underrun',
      // 音频相关的轻微问题
      'audio sync',
      'audio discontinuity',
      'pts discontinuity',
      'av_interleaved',
      'audio device', // 音频设备初始化失败，视频仍可播放
      'no sound', // 无声音警告，不影响视频播放
      // 网络相关的临时问题（通常会自动恢复）
      'timed out', // 注意：严重超时应该让它重试
      'temporarily',
      // 格式检测相关
      'probing',
      'probe',
      'detection',
      // 流信息更新
      'stream info',
      'track info',
      // HDR/色彩空间相关（不影响播放）
      'hdr',
      'color space',
      'color primaries',
      'transfer characteristics',
      // 章节/导航相关
      'chapter',
      'navigation',
      // 外部滤镜相关
      'filter',
      'vf ',
      'af ',
      // 播放器内部信息性消息
      'info:',
      'warning:',
    ];

    // 特殊情况：音频设备问题虽然包含 "could not open" 但不影响视频播放
    // 需要优先检查这些特殊模式
    const audioDevicePatterns = [
      'audio device',
      'no sound',
      'initialize audio',
    ];
    for (final pattern in audioDevicePatterns) {
      if (message.contains(pattern)) {
        return true; // 音频设备问题，视频仍可播放
      }
    }

    // 致命错误关键词 - 这些错误即使包含上述关键词也不能忽略
    const fatalPatterns = [
      'failed to open',
      'could not open',
      'no such file',
      'file not found',
      'access denied',
      'permission denied',
      'connection refused',
      'connection reset',
      'network unreachable',
      'host not found',
      'dns',
      '404',
      '403',
      '401',
      '500',
      '502',
      '503',
      'codec not found',
      'unsupported codec',
      'no video',
      'no audio',
      'demuxer',
      'corrupted',
      'invalid data',
      'end of file',
      'eof',
    ];

    // 先检查是否包含致命错误关键词
    for (final pattern in fatalPatterns) {
      if (message.contains(pattern)) {
        return false; // 致命错误，不可忽略
      }
    }

    // 再检查是否包含可忽略的关键词
    for (final pattern in ignorablePatterns) {
      if (message.contains(pattern)) {
        return true; // 非致命错误，可忽略
      }
    }

    // 检查播放器是否仍在正常播放（如果正在播放，说明错误不影响播放）
    if (player.state.playing && player.state.position.inSeconds > 0) {
      _logDebug('播放器仍在播放中，错误可能不影响播放: $message');
      return true;
    }

    return false; // 默认不忽略，保守处理
  }

  /// 显示非致命警告信息（不触发重试，不暂停播放）
  void _showWarningMessage(String warning) {
    // 检查是否是重复警告且在冷却时间内
    final now = DateTime.now();
    final lastShown = _shownErrors[warning];
    if (lastShown != null && now.difference(lastShown) < _errorCooldown) {
      return;
    }
    _shownErrors[warning] = now;

    // 使用 SnackBar 显示简短警告，不干扰播放
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          warning,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange.shade700,
        margin: const EdgeInsets.only(
          bottom: 16,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  /// 处理播放失败：停止自动跳播并标记错误信息，同时触发自动重试
  Future<void> _handlePlaybackFailure(Object error) async {
    final message = error.toString();
    _log(
      '播放失败，停止在当前条目: $message',
      level: LogLevel.error,
      error: error,
    );
    _lastFailedPlaylistIndex = currentPlayingIndex;
    _autoAdvanceBlockedIndex = currentPlayingIndex;
    _isUserInitiatedSwitch = false;
    _needsPlayerRecovery = true;

    try {
      await player.pause();
    } catch (pauseError, stackTrace) {
      _log(
        '播放失败后暂停播放器异常',
        level: LogLevel.warning,
        error: pauseError,
        stackTrace: stackTrace,
      );
    }

    try {
      await player.stop();
    } catch (stopError, stackTrace) {
      _log(
        '播放失败后停止播放器异常',
        level: LogLevel.warning,
        error: stopError,
        stackTrace: stackTrace,
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // 显示错误信息并触发自动重试
    _showErrorMessageWithRetry(message);
  }

  /// 显示错误信息并启动自动重试机制
  void _showErrorMessageWithRetry(String error) {
    // 检查是否是重复错误且在冷却时间内
    final now = DateTime.now();
    final lastShown = _shownErrors[error];
    if (lastShown != null && now.difference(lastShown) < _errorCooldown) {
      return;
    }

    // 更新错误显示时间
    _shownErrors[error] = now;

    // 如果当前未在自动重试中，重置重试计数
    if (!_isAutoRetrying) {
      _currentRetryAttempt = 0;
    }

    // 更新错误提示内容
    if (!mounted) {
      _playbackErrorMessage = error;
      _startAutoRetry();
      return;
    }
    setState(() {
      _playbackErrorMessage = error;
    });
    _updatePlaybackErrorOverlay();

    // 启动自动重试
    _startAutoRetry();
  }

  /// 启动自动重试机制
  void _startAutoRetry() {
    // 如果已达到最大重试次数，停止重试
    if (_currentRetryAttempt >= _maxAutoRetryAttempts) {
      _log(
        '已达到最大自动重试次数 ($_maxAutoRetryAttempts)，停止重试',
        level: LogLevel.warning,
      );
      _isAutoRetrying = false;
      return;
    }

    _isAutoRetrying = true;
    _currentRetryAttempt++;

    _log(
      '准备第 $_currentRetryAttempt/$_maxAutoRetryAttempts 次自动重试',
      level: LogLevel.info,
    );

    // 取消之前的重试定时器
    _autoRetryTimer?.cancel();

    // 根据重试次数增加延迟时间（指数退避）
    final delaySeconds = _currentRetryAttempt * 2;
    _autoRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _playbackErrorMessage != null) {
        _performAutoRetry();
      }
    });

    // 更新 UI 显示重试状态
    if (mounted) {
      setState(() {});
    }
  }

  /// 执行自动重试
  Future<void> _performAutoRetry() async {
    if (!mounted || _isExiting || _isPlayerDisposed) {
      _isAutoRetrying = false;
      return;
    }

    _log(
      '执行第 $_currentRetryAttempt/$_maxAutoRetryAttempts 次自动重试',
      level: LogLevel.info,
    );

    // 清除错误状态但保留重试计数
    final retryAttempt = _currentRetryAttempt;
    _clearPlaybackErrorMessage(useSetState: false);

    // 恢复重试计数
    _currentRetryAttempt = retryAttempt;

    // 执行重试
    await _retryCurrentVideo();
  }

  /// 重置自动重试状态（用于用户手动操作时）
  void _resetAutoRetryState() {
    _autoRetryTimer?.cancel();
    _currentRetryAttempt = 0;
    _isAutoRetrying = false;
  }

  /// 清除错误提示并允许后续重新尝试
  void _clearPlaybackErrorMessage({bool useSetState = true}) {
    if (_playbackErrorMessage == null && _lastFailedPlaylistIndex == null) {
      _removePlaybackErrorOverlayEntry();
      _playbackErrorDismissTimer?.cancel();
      return;
    }

    void clearFields() {
      _playbackErrorMessage = null;
      _lastFailedPlaylistIndex = null;
      _autoAdvanceBlockedIndex = null;
    }

    _playbackErrorDismissTimer?.cancel();

    if (!mounted) {
      clearFields();
      _removePlaybackErrorOverlayEntry();
      return;
    }

    if (useSetState) {
      setState(clearFields);
    } else {
      clearFields();
    }

    _updatePlaybackErrorOverlay();
  }

  /// 从用户交互发起的 index 跳转，统一处理进度保存、状态更新与异步逻辑。
  Future<void> _jumpToIndexFromUser(int index) async {
    if (playList.isEmpty) {
      _logDebug('跳转失败: 播放列表为空');
      return;
    }
    if (index < 0 || index >= playList.length) {
      _logDebug('跳转失败: 无效索引 $index, 播放列表长度: ${playList.length}');
      return;
    }

    _logDebug('用户请求跳转到索引: $index');

    // 用户手动操作时重置自动重试状态
    _resetAutoRetryState();

    // 先保存当前视频进度
    await _saveCurrentProgress(updateUIImmediately: true);
    if (!mounted) {
      return;
    }

    _clearPlaybackErrorMessage();
    _disableAutoAdvanceGuard();

    setState(() {
      currentPlayingIndex = index;
      _currentPlayingIndexNotifier.value = index;
      _syncLinkModeFromPlaylist(index);
      _isLoading = true;
      _hasSeekInitialPosition = false;
    });

    // 标记为手动切换，防止 playlist 监听再次介入导致错误回滚。
    _isUserInitiatedSwitch = true;

    // 发生过播放错误后强制重新 open，避免 mpv 停止状态导致后续视频卡缓冲。
    final shouldForceReopen = _needsPlayerRecovery ||
        _playbackErrorMessage != null ||
        _lastFailedPlaylistIndex != null;

    if (shouldForceReopen) {
      _logDebug('检测到错误后手动切换，强制重新打开播放列表: index=$index');
      await player.stop();
      await player.open(Playlist(playList, index: index), play: true);
      // 恢复完成后清除错误标记，避免后续切换再次强制重建。
      _needsPlayerRecovery = false;
    } else {
      player.jump(index);
      if (!player.state.playing) {
        // 确保切换后立即拉流，避免停留在暂停状态造成假缓冲。
        unawaited(player.play());
      }
    }

    // 如果当前全局偏好为 raw_url，则为新视频自动应用 raw_url 链接。
    if (_preferredLinkMode == PlaybackLinkMode.raw && !_isCurrentMediaLocal) {
      _logDebug('根据当前偏好为索引 $index 应用 raw_url 链接');
      unawaited(_applyPlaybackLinkMode(PlaybackLinkMode.raw));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToCurrentItem();
    });

    // 异步处理字幕等后续工作
    _handleVideoSwitchAsyncWithoutProgressSave(index);
  }

  /// 手动交互前关闭自动跳播拦截，允许用户自由切换集数。
  void _disableAutoAdvanceGuard() {
    _autoAdvanceBlockedIndex = null;
    _lastFailedPlaylistIndex = null;
  }

  /// 处理上一集操作，确保不会触发自动跳播拦截。
  void _goToPreviousVideo() {
    final targetIndex = currentPlayingIndex - 1;
    if (targetIndex < 0) {
      _logDebug('上一集跳转被忽略: 已经是第一集');
      return;
    }
    unawaited(_jumpToIndexFromUser(targetIndex));
  }

  /// 处理下一集操作，确保不会触发自动跳播拦截。
  void _goToNextVideo() {
    final targetIndex = currentPlayingIndex + 1;
    if (targetIndex >= playList.length) {
      _logDebug('下一集跳转被忽略: 已经是最后一集');
      return;
    }
    unawaited(_jumpToIndexFromUser(targetIndex));
  }

  /// 允许用户主动重新尝试当前视频的播放
  Future<void> _retryCurrentVideo() async {
    if (playList.isEmpty ||
        currentPlayingIndex < 0 ||
        currentPlayingIndex >= playList.length) {
      return;
    }

    final targetIndex = currentPlayingIndex;
    _logDebug('用户触发重试: 索引=$targetIndex');

    _hasSeekInitialPosition = false;
    await _jumpToIndexFromUser(targetIndex);
  }

  /// 将当前错误内容复制到剪贴板，便于反馈
  Future<void> _copyPlaybackError() async {
    final message = _playbackErrorMessage;
    if (message == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: message));
    _logDebug('播放错误信息已复制到剪贴板');
  }

  /// 构建统一的错误浮层，移动端采用更紧凑的布局，桌面端保持原有样式
  Widget _buildPlaybackErrorOverlay({BuildContext? overlayContext}) {
    final message = _playbackErrorMessage ?? '';
    final BuildContext hostContext = overlayContext ?? context;
    MediaQueryData? mediaQuery = MediaQuery.maybeOf(hostContext);
    mediaQuery ??= MediaQuery.maybeOf(context);

    // 判断是否为移动端布局（屏幕宽度小于 600dp）
    final screenWidth = mediaQuery?.size.width ?? 600;
    final isMobileLayout = screenWidth < 600;

    // 截断错误信息，移动端最多显示 80 个字符，桌面端不限制
    final displayMessage = isMobileLayout && message.length > 80
        ? '${message.substring(0, 80)}...'
        : message;

    // 构建重试状态文本
    String retryStatusText = '';
    if (_isAutoRetrying && _currentRetryAttempt > 0) {
      if (_currentRetryAttempt < _maxAutoRetryAttempts) {
        retryStatusText = '正在自动重试 ($_currentRetryAttempt/$_maxAutoRetryAttempts)...';
      } else {
        retryStatusText = '已达最大重试次数 ($_maxAutoRetryAttempts)';
      }
    }

    Widget content;

    if (isMobileLayout) {
      // 移动端紧凑布局
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题行：图标 + 标题 + 关闭按钮
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '播放失败',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                // 自动重试状态
                if (retryStatusText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAutoRetrying &&
                            _currentRetryAttempt < _maxAutoRetryAttempts)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.orange,
                              ),
                            ),
                          ),
                        if (_isAutoRetrying &&
                            _currentRetryAttempt < _maxAutoRetryAttempts)
                          const SizedBox(width: 4),
                        Text(
                          retryStatusText,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    _resetAutoRetryState();
                    _clearPlaybackErrorMessage();
                  },
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 错误信息（可点击展开/复制）
            GestureDetector(
              onTap: _copyPlaybackError,
              onLongPress: () {
                // 长按显示完整错误信息的对话框
                _showFullErrorDialog(message);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayMessage,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 操作按钮行
            Row(
              children: [
                Expanded(
                  child: _buildCompactButton(
                    icon: Icons.refresh,
                    label: '重试',
                    onTap: () {
                      _resetAutoRetryState();
                      _retryCurrentVideo();
                    },
                    isPrimary: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactButton(
                    icon: Icons.copy,
                    label: '复制',
                    onTap: _copyPlaybackError,
                    isPrimary: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactButton(
                    icon: Icons.info_outline,
                    label: '详情',
                    onTap: () => _showFullErrorDialog(message),
                    isPrimary: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // 桌面端原有布局
      content = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.8),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '播放失败：',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: message,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 显示自动重试状态
                      if (retryStatusText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              if (_isAutoRetrying &&
                                  _currentRetryAttempt < _maxAutoRetryAttempts)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.orange,
                                    ),
                                  ),
                                ),
                              if (_isAutoRetrying &&
                                  _currentRetryAttempt < _maxAutoRetryAttempts)
                                const SizedBox(width: 6),
                              Text(
                                retryStatusText,
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭错误提示',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _resetAutoRetryState();
                    _clearPlaybackErrorMessage();
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () {
                    _resetAutoRetryState();
                    _retryCurrentVideo();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.redAccent.withOpacity(0.25),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                  ),
                  child: const Text('重试播放'),
                ),
                TextButton(
                  onPressed: _copyPlaybackError,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blueGrey.withOpacity(0.25),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                  ),
                  child: const Text('复制错误信息'),
                ),
                // 停止自动重试按钮
                if (_isAutoRetrying &&
                    _currentRetryAttempt < _maxAutoRetryAttempts)
                  TextButton(
                    onPressed: _resetAutoRetryState,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.orange.withOpacity(0.25),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                    ),
                    child: const Text('停止重试'),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    content = Material(
      color: Colors.transparent,
      child: content,
    );

    Widget overlayChild = SafeArea(child: content);
    if (mediaQuery != null) {
      overlayChild = MediaQuery(data: mediaQuery, child: overlayChild);
    }

    // 移动端定位更靠近顶部，桌面端保持原位置
    return Positioned(
      top: isMobileLayout ? 8 : 16,
      left: isMobileLayout ? 8 : 16,
      right: isMobileLayout ? 8 : 16,
      child: overlayChild,
    );
  }

  /// 构建移动端紧凑按钮
  Widget _buildCompactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary
              ? Colors.redAccent.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isPrimary
                ? Colors.redAccent.withOpacity(0.5)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : Colors.white70,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示完整错误信息的对话框
  void _showFullErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 8),
            const Text(
              '错误详情',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isAutoRetrying)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在自动重试 ($_currentRetryAttempt/$_maxAutoRetryAttempts)',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              SelectableText(
                message,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              Navigator.of(dialogContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('错误信息已复制'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 添加快捷键说明按钮
  Widget buildKeyboardShortcutsButton() {
    return MaterialCustomButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => _buildKeyboardShortcutsDialog(),
        );
      },
      icon: const Icon(
        Icons.keyboard,
        color: Colors.white,
      ),
    );
  }

  // 构建快捷键说明对话框
  Widget _buildKeyboardShortcutsDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Icon(Icons.keyboard, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 12),
                  const Text('快捷键说明',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      )),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShortcutCategory('播放控制'),
                    _buildShortcutItem('空格', '播放/暂停'),
                    _buildShortcutItem(
                        'P', '切换自定义播放速度(${_customPlaybackSpeed}x)'),
                    _buildShortcutItem(
                        '→', '短跳进 (${_shortSeekDuration.inSeconds}秒)'),
                    _buildShortcutItem(
                        '←', '短跳回 (${_shortSeekDuration.inSeconds}秒)'),
                    _buildShortcutItem(
                        'I', '长跳进 (${_longSeekDuration.inSeconds}秒)'),
                    _buildShortcutItem(
                        'J', '长跳回 (${_longSeekDuration.inSeconds}秒)'),
                    _buildShortcutCategory('播放速度控制'),
                    _buildShortcutItem('Z', '恢复调速前的速度'),
                    _buildShortcutItem('X', '减速 0.1x'),
                    _buildShortcutItem('C', '加速 0.1x'),
                    _buildShortcutCategory('音量控制'),
                    _buildShortcutItem('↑', '增加音量'),
                    _buildShortcutItem('↓', '降低音量'),
                    _buildShortcutCategory('视频控制'),
                    _buildShortcutItem('F', '切换全屏'),
                    _buildShortcutItem('ESC', '退出全屏'),
                    _buildShortcutCategory('其他功能'),
                    _buildShortcutItem('长按→', '临时加速播放'),
                    _buildShortcutItem('Tab', '显示/隐藏视频流信息'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建快捷键分类标题
  Widget _buildShortcutCategory(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  // 构建快捷键条目
  Widget _buildShortcutItem(String key, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Text(
              key,
              // 使用等宽字体展示快捷键，确保在 Windows 下字符对齐，
              // 避免默认西文字体导致中英文混排不一致。
              style: FontHelper.createMonospaceTextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                description,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 显示全局倍速提示
  void _showSpeedIndicatorOverlay(double speed, {bool isLongPress = false}) {
    // 先移除已有的提示
    _hideSpeedIndicatorOverlay();

    // 更新显示值
    _logDebug('显示倍速提示: ${speed.toStringAsFixed(2)}x, 长按模式: $isLongPress');
    _showSpeedIndicator.value = true;
    _indicatorSpeedValue.value = speed;

    // 只有在非长按模式下才设置自动隐藏定时器
    if (!isLongPress) {
      _speedIndicatorTimer?.cancel();
      _speedIndicatorTimer = Timer(const Duration(seconds: 2), () {
        _hideSpeedIndicatorOverlay();
      });
    }

    final bool useEmbeddedIndicator = _shouldUseEmbeddedSpeedIndicator();
    if (useEmbeddedIndicator) {
      // 移动端非全屏场景已经通过 Stack 中的 _SpeedIndicatorOverlay 展示提示，这里无需重复插入 OverlayEntry。
      return;
    }

    // 创建新overlay
    _speedIndicatorOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        width: MediaQuery.of(context).size.width,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(179), // 0.7 * 255 = 178.5 ≈ 179
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(102), // 0.4 * 255 = 102
                      blurRadius: 15,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 根据长按状态显示不同的图标
                    isLongPress
                        ? const Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.white,
                            size: 28,
                          )
                        : const Icon(
                            Icons.speed,
                            color: Colors.white,
                            size: 28,
                          ),
                    const SizedBox(width: 12),
                    Text(
                      '${speed}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 添加到overlay
    if (mounted) {
      Overlay.of(context).insert(_speedIndicatorOverlay!);
    }
  }

  bool _shouldUseEmbeddedSpeedIndicator() {
    if (!mounted) {
      return false;
    }
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return false;
    }
    final bool isMobileLayout = mediaQuery.size.width < 600;
    final bool isFullscreenContext =
        FullscreenInheritedWidget.maybeOf(context) != null;
    // 仅在移动端非全屏时需要使用内嵌的倍速提示，其余场景依旧通过 OverlayEntry 覆盖整个播放器。
    return isMobileLayout && !isFullscreenContext;
  }

  // 隐藏全局倍速提示
  void _hideSpeedIndicatorOverlay() {
    if (_speedIndicatorOverlay != null) {
      _logDebug('隐藏倍速提示');
    }
    _speedIndicatorOverlay?.remove();
    _speedIndicatorOverlay = null;
    _showSpeedIndicator.value = false;
  }

  /// 判断是否需要将播放错误提示嵌入当前 Stack，而不是通过全局 OverlayEntry。
  bool _shouldUseEmbeddedErrorOverlay() {
    if (!mounted) {
      return true;
    }
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return true;
    }
    final bool isMobileLayout = mediaQuery.size.width < 600;
    final bool isFullscreenContext =
        FullscreenInheritedWidget.maybeOf(context) != null;
    return isMobileLayout && !isFullscreenContext;
  }

  /// 根据当前布局动态更新播放错误浮层的呈现方式（嵌入或全局 Overlay）。
  void _updatePlaybackErrorOverlay() {
    final shouldShowError = _playbackErrorMessage?.isNotEmpty == true;
    if (!mounted || !shouldShowError) {
      _removePlaybackErrorOverlayEntry();
      return;
    }

    if (_shouldUseEmbeddedErrorOverlay()) {
      // 在需要嵌入式的场景下，直接移除 OverlayEntry，剩余渲染交给 Stack。
      _removePlaybackErrorOverlayEntry();
      return;
    }

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) {
      _log(
        'Overlay 不可用，播放失败浮层无法展示',
        level: LogLevel.warning,
      );
      return;
    }

    if (_playbackErrorOverlayEntry == null) {
      _playbackErrorOverlayEntry = OverlayEntry(
        builder: (overlayContext) => InheritedTheme.captureAll(
          context,
          _buildPlaybackErrorOverlay(
            overlayContext: overlayContext,
          ),
        ),
      );
      overlayState.insert(_playbackErrorOverlayEntry!);
    } else {
      _playbackErrorOverlayEntry!.markNeedsBuild();
    }
  }

  /// 移除全局播放错误浮层，适配切换视频或恢复成功等场景。
  void _removePlaybackErrorOverlayEntry() {
    _playbackErrorOverlayEntry?.remove();
    _playbackErrorOverlayEntry = null;
  }

  /// 构建链接模式切换按钮

  // 统一处理键盘右箭头的长按与短按逻辑
  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!mounted || event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }

    if (event is KeyDownEvent) {
      if (_isArrowRightPressed) {
        // 重复的 KeyDown 也需消费，否则 Flutter 会认为我们未处理，进一步冒泡
        return true;
      }

      _isArrowRightPressed = true;
      _keyboardLongPressTimer?.cancel();
      _keyboardLongPressTimer = Timer(_keyboardLongPressThreshold, () {
        if (!_isArrowRightPressed || !mounted) {
          return;
        }
        _isArrowRightLongPressActive = true;
        _previousSpeed = _currentSpeed;
        _logDebug('键盘长按触发，缓存倍速: $_previousSpeed');
        player.setRate(AppConstants.longPressPlaybackSpeed);
        _showSpeedIndicatorOverlay(
          AppConstants.longPressPlaybackSpeed,
          isLongPress: true,
        );
        _speedIndicatorTimer?.cancel();
        _speedIndicatorTimer = null;
      });
      return true;
    }

    if (event is KeyRepeatEvent) {
      // 长按会持续触发 KeyRepeat，需要继续消费，避免误触发短按逻辑
      return true;
    }

    if (event is KeyUpEvent) {
      _keyboardLongPressTimer?.cancel();
      _keyboardLongPressTimer = null;

      final bool wasLongPress = _isArrowRightLongPressActive;
      _isArrowRightPressed = false;
      _isArrowRightLongPressActive = false;

      if (wasLongPress) {
        _logDebug('键盘长按松开，恢复倍速: $_previousSpeed');
        player.setRate(_previousSpeed);
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) return;
          if (player.state.rate != _previousSpeed) {
            _logDebug('检测到键盘长按恢复被覆盖，再次设置倍速为 $_previousSpeed');
            player.setRate(_previousSpeed);
          }
        });

        _showSpeedIndicatorOverlay(_previousSpeed);
        _speedIndicatorTimer?.cancel();
        _speedIndicatorTimer = Timer(
          const Duration(seconds: 2),
          () => _hideSpeedIndicatorOverlay(),
        );

        setState(() {
          _currentSpeed = _previousSpeed;
        });
        _rateNotifier.value = _previousSpeed;
      } else {
        final target = player.state.position + _shortSeekDuration;
        _logDebug('键盘短按松开，快进至: ${target.inMilliseconds}ms');
        player.seek(target);
      }

      return true;
    }

    return false;
  }

  // 切换视频信息显示
  void _toggleVideoInfoOverlay() {
    if (_videoInfoOverlay != null) {
      _hideVideoInfoOverlay();
    } else {
      _showVideoInfoOverlay();
    }
  }

  // 显示视频信息
  void _showVideoInfoOverlay() {
    // 先移除已有的提示
    _hideVideoInfoOverlay();

    // 创建新overlay
    _videoInfoOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 20,
        left: 20,
        child: Material(
          color: Colors.transparent,
          child: StreamBuilder<void>(
            // 使用一个定时器来定期刷新视频信息
            stream: Stream.periodic(const Duration(milliseconds: 500)),
            builder: (context, _) {
              // 获取视频信息
              final videoParams = player.state.videoParams;

              // 基础信息（不依赖于MPV属性的Future）
              final position = player.state.position;
              final duration = player.state.duration;
              final rate = player.state.rate;
              final volume = player.state.volume;
              final width = videoParams.w ?? 0;
              final height = videoParams.h ?? 0;
              final pixelFormat = videoParams.pixelformat ?? 'unknown';
              final double aspect = videoParams.aspect ?? 0.0;
              final colorMatrix = videoParams.colormatrix ?? 'unknown';
              final primaries = videoParams.primaries ?? 'unknown';
              final currentMedia = player.state.playlist.medias.isNotEmpty &&
                      player.state.playlist.index >= 0
                  ? player.state.playlist.medias[player.state.playlist.index]
                  : null;
              final currentUrl = currentMedia?.uri ?? 'unknown';

              // 获取当前视频名称
              String videoName = '视频播放';
              if (playList.isNotEmpty &&
                  currentPlayingIndex >= 0 &&
                  currentPlayingIndex < playList.length) {
                videoName =
                    playList[currentPlayingIndex].extras!['name'] as String;
              }

              // 使用FutureBuilder获取更多视频信息
              return FutureBuilder<Map<String, String>>(
                  future: _getExtendedVideoInfo(),
                  builder: (context, snapshot) {
                    // 获取扩展视频信息
                    final extInfo = snapshot.data ?? {};
                    final videoBitrateStr = extInfo['videoBitrate'] ?? 'N/A';
                    final codecInfo = extInfo['videoCodec'] ?? 'N/A';
                    final videoFps = extInfo['videoFps'] ?? 'N/A';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '视频流信息',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '视频名称: ${_truncateString(videoName, 35)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '分辨率: ${width}x$height',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '帧率: $videoFps',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '编码: $codecInfo',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '像素格式: $pixelFormat',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '宽高比: ${aspect.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '视频码率: $videoBitrateStr',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '色彩矩阵: $colorMatrix',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '色彩原色: $primaries',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '播放速度: ${rate}x',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '音量: ${volume.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            '进度: ${_formatDuration(position)}/${_formatDuration(duration)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          // 当前URL（可点击复制）
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: currentUrl));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已复制URL到剪切板'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: 300, // 添加固定宽度
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize:
                                    MainAxisSize.min, // 改为MainAxisSize.min
                                children: [
                                  const Icon(
                                    Icons.link,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    // 改为Flexible
                                    child: Text(
                                      '当前URL: ${_truncateString(currentUrl, 50)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Colors.white,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.copy,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  });
            },
          ),
        ),
      ),
    );

    // 添加到overlay
    if (mounted) {
      Overlay.of(context).insert(_videoInfoOverlay!);
    }
  }

  // 隐藏视频信息
  void _hideVideoInfoOverlay() {
    _videoInfoOverlay?.remove();
    _videoInfoOverlay = null;
  }

  // 格式化时间
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // 截断字符串
  String _truncateString(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }

  // 安全获取播放器属性
  Future<dynamic> _getPlayerProperty(String property,
      [dynamic defaultValue]) async {
    try {
      final value = await (player.platform as dynamic).getProperty(property);
      return value;
    } catch (e) {
      return defaultValue;
    }
  }

  // 获取扩展的视频信息
  Future<Map<String, String>> _getExtendedVideoInfo() async {
    final result = <String, String>{};

    try {
      // 检查是否有下面这些属性
      final mpvProperties = [
        // 视频码率相关
        'video-bitrate', 'video-params/bitrate', 'stats/video/bitrate',
        'packet-video-bitrate', 'estimated-vf-fps', 'container-fps',
        // 视频编码相关
        'video-codec', 'video-format', 'video-codec-name',
        'current-tracks/video/codec', 'current-tracks/video/demux-fps'
      ];

      // 收集所有可用的MPV属性
      final debugValues = <String, dynamic>{};
      for (final prop in mpvProperties) {
        try {
          final value = await _getPlayerProperty(prop, null);
          if (value != null) {
            debugValues[prop] = value;
          }
        } catch (e) {
          // 忽略单个属性的错误
        }
      }

      // 尝试获取视频帧率
      String fps = 'N/A';
      for (final prop in [
        'container-fps',
        'estimated-vf-fps',
        'current-tracks/video/demux-fps'
      ]) {
        final value = debugValues[prop];
        if (value != null) {
          if (value is num) {
            fps = value.toStringAsFixed(2);
            break;
          } else if (value is String && double.tryParse(value) != null) {
            fps = double.parse(value).toStringAsFixed(2);
            break;
          }
        }
      }
      result['videoFps'] = '$fps fps';

      // 尝试获取视频编码
      String codec = 'N/A';
      for (final prop in [
        'video-codec',
        'video-format',
        'video-codec-name',
        'current-tracks/video/codec'
      ]) {
        final value = debugValues[prop];
        if (value != null && value is String && value.isNotEmpty) {
          codec = value;
          break;
        }
      }
      result['videoCodec'] = codec;

      // 尝试从已知属性获取视频码率
      for (final prop in [
        'video-bitrate',
        'video-params/bitrate',
        'stats/video/bitrate',
        'packet-video-bitrate'
      ]) {
        final value = debugValues[prop];
        if (value != null) {
          double? bitrate;
          if (value is num) {
            bitrate = value.toDouble();
          } else if (value is String) {
            bitrate = double.tryParse(value);
          }

          if (bitrate != null && bitrate > 0) {
            final mbps = bitrate / 1000000;
            result['videoBitrate'] = '${mbps.toStringAsFixed(2)} Mbps';
            return result;
          }
        }
      }

      // 如果找不到直接的码率值，尝试计算
      final fileSize = await _getPlayerProperty('file-size', null);
      final duration = player.state.duration.inSeconds;

      if (fileSize != null && duration > 0) {
        double? fileSizeBytes;

        if (fileSize is num) {
          fileSizeBytes = fileSize.toDouble();
        } else if (fileSize is String) {
          fileSizeBytes = double.tryParse(fileSize);
        }

        if (fileSizeBytes != null && fileSizeBytes > 0) {
          // 计算总码率
          final totalBitrate = (fileSizeBytes * 8) / duration;
          // 减去音频码率（如果有）
          final audioBitrateValue = player.state.audioBitrate ?? 0;
          // 估算视频码率
          final estimatedVideoBitrate =
              (totalBitrate - audioBitrateValue * 1000) / 1000000;
          if (estimatedVideoBitrate > 0) {
            result['videoBitrate'] =
                '约 ${estimatedVideoBitrate.toStringAsFixed(2)} Mbps (估算)';
            return result;
          }
        }
      }

      // 打印调试信息
      _log(
        'MPV视频属性: $debugValues',
        level: LogLevel.debug,
      );
      result['videoBitrate'] = 'N/A (无法读取)';
    } catch (e, stack) {
      _log(
        '获取扩展视频信息错误',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      result['videoBitrate'] = 'N/A (错误)';
    }

    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePlaybackErrorOverlay();

    // Refresh which videos are available locally when dependencies change
    // This ensures the UI gets updated when new downloads complete
    _refreshLocalVideosList();
  }

  // Refresh the list of locally available videos
  Future<void> _refreshLocalVideosList() async {
    // Check all videos in the playlist
    for (int i = 0; i < playList.length; i++) {
      final videoName = playList[i].extras?['name'] as String?;
      if (videoName != null) {
        final videoKey = "${widget.path}/$videoName";
        final localPath = await _checkLocalFile(videoKey);

        if (localPath != null) {
          if (!mounted) {
            return;
          }
          setState(() {
            _localVideos.add(videoName);
          });
        }
      }
    }
  }

  Future<void> _loadPlaybackSpeeds() async {
    final prefs = await SharedPreferences.getInstance();
    final speedsString = prefs.getStringList(AppConstants.playbackSpeedsKey);
    if (speedsString != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playbackSpeeds = speedsString.map((s) => double.parse(s)).toList()
          ..sort();
      });
    }
  }

  // 安排初始滚动，确保在列表构建完成后执行
  void _scheduleInitialScroll() {
    _logDebug('安排初始滚动到索引: $currentPlayingIndex');

    // 使用多层延迟确保列表完全构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 第一层：等待当前帧完成
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // 第二层：再等待一小段时间确保 ScrollablePositionedList 完全初始化
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              _logDebug('执行初始滚动到索引: $currentPlayingIndex');
              scrollToCurrentItem();
            }
          });
        }
      });
    });
  }

  // 使用 ScrollablePositionedList 的精确索引滚动
  void scrollToCurrentItem() {
    // 确保索引有效
    if (currentPlayingIndex < 0 || currentPlayingIndex >= playList.length) {
      _logDebug('滚动失败: 无效索引 $currentPlayingIndex, 播放列表长度: ${playList.length}');
      return;
    }

    // 确保组件已挂载
    if (!mounted) {
      _logDebug('滚动失败: 组件未挂载');
      return;
    }

    _logDebug('准备滚动到索引: $currentPlayingIndex');

    // 使用 ItemScrollController 精确滚动到指定索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _logDebug('滚动失败: 回调时组件未挂载');
        return;
      }

      try {
        // 检查控制器是否已附加
        if (!_itemScrollController.isAttached) {
          _logDebug('滚动失败: ItemScrollController 未附加到列表');
          return;
        }

        // 获取屏幕宽度判断是否为移动端
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;

        _logDebug(
            '开始滚动到索引 $currentPlayingIndex, 设备类型: ${isMobile ? "移动端" : "桌面端"}');

        // 根据设备类型选择不同的对齐方式
        // 移动端：将项目滚动到顶部
        // 桌面端：将项目滚动到中间位置以获得更好的可见性
        _itemScrollController.scrollTo(
          index: currentPlayingIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: isMobile ? 0.0 : 0.3, // 0.0 = 顶部, 0.5 = 中间, 1.0 = 底部
        );

        _logDebug('滚动命令已发送到索引: $currentPlayingIndex');
      } catch (e) {
        // 如果滚动失败，记录错误但不影响其他功能
        _logDebug('滚动到当前项目失败: $e');
      }
    });
  }

  // Build screenshot button
  Widget buildScreenshotButton() {
    return MaterialCustomButton(
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

        final currentVideoName =
            playList.isNotEmpty && currentPlayingIndex < playList.length
                ? playList[currentPlayingIndex].extras!['name'] as String
                : null;
        final userId = _requireUserId('手动截图');
        if (userId == null) {
          return;
        }
        final String? videoSha1 = currentVideoName != null
            ? _getVideoSha1(widget.path, currentVideoName)
            : null;

        final result = await _takeScreenshot(
          videoSha1: videoSha1,
          userId: userId,
        );
        _logDebug('截图结果: ${result?.filePath}');

        if (result != null && mounted) {
          // 获取文件大小信息
          try {
            final file = File(result.filePath);
            final fileSize = await file.length();
            final fileSizeKB = (fileSize / 1024).toStringAsFixed(1);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('截图已保存 (${fileSizeKB}KB)\n路径: ${result.filePath}'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                  action: SnackBarAction(
                    label: '打开文件夹',
                    onPressed: () {
                      // 在macOS上打开文件夹
                      Process.run('open', [file.parent.path]);
                    },
                  ),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('截图已保存: $result'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('截图保存失败，请检查权限或存储空间'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
      icon: const Tooltip(
        message: 'Take Screenshot',
        child: Icon(
          Icons.camera_alt,
          color: Colors.white,
        ),
      ),
    );
  }
}

// 添加倍速提示组件
class _SpeedIndicatorOverlay extends StatefulWidget {
  final bool isVisible;
  final ValueNotifier<double> speedValue;

  const _SpeedIndicatorOverlay({
    required this.isVisible,
    required this.speedValue,
  });

  @override
  State<_SpeedIndicatorOverlay> createState() => _SpeedIndicatorOverlayState();
}

class _SpeedIndicatorOverlayState extends State<_SpeedIndicatorOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
  }

  @override
  void didUpdateWidget(_SpeedIndicatorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _animationController.forward(from: 0.0);
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible && _animationController.isDismissed) {
      return const SizedBox.shrink();
    }

    // 获取安全区域顶部间距，确保不被刘海/状态栏遮挡
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned.fill(
      child: Stack(
        children: [
          // 倍速提示 - 位置靠上，样式紧凑，减少对画面遮挡
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              // 移动端全屏时位置更靠上，仅留出安全区域 + 少量间距
              padding: EdgeInsets.only(top: topPadding + 12),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _opacityAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.speedValue,
                  builder: (context, speed, _) {
                    return Container(
                      // 紧凑的内边距
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        // 半透明背景，减少视觉干扰
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${speed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 截图保存结果，统一携带路径与压缩后的二进制，便于上传/缓存
class ScreenshotSaveResult {
  final String filePath;
  final Uint8List bytes;
  final bool isJpeg;

  const ScreenshotSaveResult({
    required this.filePath,
    required this.bytes,
    required this.isJpeg,
  });
}

bool _hasImageMagicHeader(Uint8List bytes) {
  if (bytes.length < 8) return false;
  return _looksLikeJpeg(bytes) || _looksLikePng(bytes);
}

bool _looksLikeJpeg(Uint8List bytes) {
  return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
}

bool _looksLikePng(Uint8List bytes) {
  if (bytes.length < 8) return false;
  return bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
}

// 后台线程压缩截图的函数
Future<Map<String, dynamic>> _compressScreenshotInBackground(
    Uint8List originalBytes) async {
  try {
    // 解码原始图片
    final img.Image? originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      return {
        'bytes': originalBytes,
        'isJpeg': false,
      };
    }

    // 获取原始尺寸
    final originalWidth = originalImage.width;
    final originalHeight = originalImage.height;

    // 计算压缩后的尺寸（保持宽高比，最大宽度1280像素）
    const int maxWidth = 1280;
    int newWidth = originalWidth;
    int newHeight = originalHeight;
    bool needsResize = false;

    if (originalWidth > maxWidth) {
      newWidth = maxWidth;
      newHeight = (originalHeight * maxWidth / originalWidth).round();
      needsResize = true;
    }

    // 调整图片尺寸（如果需要）。
    img.Image resizedImage = originalImage;
    if (needsResize) {
      resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    }

    // 编码为 JPEG 格式，质量设置为 85（平衡质量和文件大小）
    const int quality = 85;
    final jpegBytes = img.encodeJpg(resizedImage, quality: quality);
    final compressedBytes = Uint8List.fromList(jpegBytes);

    // 如果压缩后的文件反而更大，或者原始文件很小（小于100KB），则保持原格式
    const int minSizeForCompression = 100 * 1024; // 100KB
    if (originalBytes.length < minSizeForCompression ||
        compressedBytes.length >= originalBytes.length) {
      // 如果需要调整尺寸但不需要压缩，使用PNG格式保存调整后的图片
      if (needsResize) {
        final resizedPngBytes = img.encodePng(resizedImage);
        return {
          'bytes': Uint8List.fromList(resizedPngBytes),
          'isJpeg': false,
        };
      }
      return {
        'bytes': originalBytes,
        'isJpeg': false,
      };
    }

    return {
      'bytes': compressedBytes,
      'isJpeg': true,
    };
  } catch (e) {
    return {
      'bytes': originalBytes,
      'isJpeg': false,
    };
  }
}
