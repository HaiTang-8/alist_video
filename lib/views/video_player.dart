import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class VideoPlayer extends StatefulWidget {
  final String path;
  final String name;
  const VideoPlayer({super.key, required this.path, required this.name});

  @override
  State<VideoPlayer> createState() => VideoPlayerState();
}

class VideoPlayerState extends State<VideoPlayer> {
  // Create a [Player] to control playback.
  late final player = Player();
  late bool initover = false;
  // Create a [VideoController] to handle video output from [Player].
  late final controller = VideoController(player);

  List<Media> playList = [];
  int playIndex = 0;
  late int currentPlayingIndex = 0;

  // 添加 ScrollController
  final ScrollController _scrollController = ScrollController();

  String? _currentUsername;
  bool _hasSeekInitialPosition = false;
  bool _isLoading = true;

  // 添加排序相关状态
  bool _isAscending = true;

  // 添加一个状态变量
  bool _isExiting = false;

  // 添加一个变量来跟踪当前播放速度
  double _currentSpeed = AppConstants.defaultPlaybackSpeed;

  // 添加一个变量来存储长按前的速度
  double _previousSpeed = AppConstants.defaultPlaybackSpeed;

  late Duration _shortSeekDuration;
  late Duration _longSeekDuration;

  // 将 late 移除，提供默认值
  List<double> _playbackSpeeds = AppConstants.defaultPlaybackSpeeds;

  Future<void> _loadSeekSettings() async {
    final prefs = await SharedPreferences.getInstance();
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

  // 添加排序相关状态
  void _sortPlaylist() async {
    // 记住当前播放的视频名称和位置
    final currentPlayingName =
        playList[currentPlayingIndex].extras!['name'] as String;

    // 创建一个排序后的新列表，但不直接修改原列表
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
    setState(() {
      currentPlayingIndex = playList
          .indexWhere((item) => item.extras!['name'] == currentPlayingName);
    });
  }

  // 获取当前登录用户名
  Future<void> _getCurrentUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUsername = prefs.getString('current_username');
    });
    if (_currentUsername == null) {
      print('Warning: No logged in user found!');
    }
  }

  Future<void> _openAndSeekVideo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final basePath = prefs.getString('base_path') ?? '/';

      var res = await FsApi.list(
          path: widget.path, password: '', page: 1, perPage: 0, refresh: false);

      if (res.code == 200) {
        setState(() {
          List<Media> playMediaList =
              res.data?.content!.where((data) => data.type == 2).map((data) {
                    String baseUrl = AppConstants.baseDownloadUrl;
                    if (basePath != '/') {
                      baseUrl = '$baseUrl$basePath';
                    }
                    return Media(
                        '$baseUrl${widget.path.substring(1)}/${data.name}?sign=${data.sign}',
                        extras: {'name': data.name ?? ''});
                  }).toList() ??
                  [];

          playList.clear();
          int index = 0;
          for (var element in playMediaList) {
            if (element.extras!['name'] == widget.name) {
              playIndex = index;
            }
            playList.add(element);
            index++;
          }
        });

        Playable playable = Playlist(
          playList,
          index: playIndex,
        );
        await player.open(playable, play: false);

        // 初始化完成后进行一次排序
        _sortPlaylist();
      } else {
        // 处理API错误
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

  // 存当前播放进度
  Future<void> _saveCurrentProgress() async {
    if (!mounted ||
        _currentUsername == null ||
        playList.isEmpty ||
        _isLoading) {
      return;
    }

    try {
      final currentPosition = player.state.position;
      final duration = player.state.duration; // 获取视频总时长
      final currentVideo = playList[currentPlayingIndex];
      final videoName = currentVideo.extras!['name'] as String;

      final existingRecord =
          await DatabaseHelper.instance.getHistoricalRecordByName(
        name: videoName,
        userId: _currentUsername!.hashCode,
      );

      final videoSha1 =
          existingRecord?.videoSha1 ?? _getVideoSha1(widget.path, videoName);

      await DatabaseHelper.instance.upsertHistoricalRecord(
        videoSha1: videoSha1,
        videoPath: widget.path,
        videoSeek: currentPosition.inSeconds,
        userId: _currentUsername!.hashCode,
        videoName: videoName,
        totalVideoDuration: duration.inSeconds, // 保存视频总时长
      );
    } catch (e) {
      print('Failed to save progress: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSeekSettings();
    _loadPlaybackSpeeds();

    (player.platform as dynamic).setProperty('cache', 'no');
    (player.platform as dynamic).setProperty('cache-secs', '0');
    (player.platform as dynamic).setProperty('demuxer-seekable-cache', 'no');
    (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '0');
    (player.platform as dynamic).setProperty('demuxer-donate-buffer', 'no');

    _getCurrentUsername();
    _openAndSeekVideo();

    player.stream.buffer.listen((event) {
      if (event.inSeconds > 0 && mounted && !_hasSeekInitialPosition) {
        _seekToLastPosition(playList[currentPlayingIndex].extras!['name'])
            .then((_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        });
        _hasSeekInitialPosition = true;
      }
    });

    player.stream.playlist.listen((event) async {
      if (mounted) {
        // 先保存当前视频进度，再更新状态
        await _saveCurrentProgress(); // 切换视频时保存进度
        if (mounted) {
          setState(() {
            currentPlayingIndex = event.index;
            scrollToCurrentItem();
            _isLoading = true;
            _hasSeekInitialPosition = false;
          });
        }
      }
    });

    player.stream.error.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放错误: ${error.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Future<void> _loadPlaybackSpeeds() async {
    final prefs = await SharedPreferences.getInstance();
    final speedsString = prefs.getStringList(AppConstants.playbackSpeedsKey);
    if (speedsString != null) {
      setState(() {
        _playbackSpeeds = speedsString.map((s) => double.parse(s)).toList()
          ..sort();
      });
    }
  }

  // Move the method outside of initState and rename it
  void scrollToCurrentItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      // 获取屏幕宽度判断是否为移动端
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;

      const itemHeight = AppConstants.defaultItemHeight; // ListTile的预估高度
      final screenHeight = MediaQuery.of(context).size.height;

      // 移动端和桌面端使用不同的滚动位置计算
      final scrollOffset = isMobile
          ? (currentPlayingIndex * itemHeight)
          : (currentPlayingIndex * itemHeight) - (screenHeight / 3);

      _scrollController.animateTo(
        scrollOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  // 查询并跳转到上次播放位
  Future<void> _seekToLastPosition(String videoName) async {
    if (_currentUsername == null) return;

    try {
      final record = await DatabaseHelper.instance.getHistoricalRecordByName(
        name: videoName,
        userId: _currentUsername!.hashCode, // 使用用户名的希值作为userId
      );

      if (record != null && mounted) {
        player.play();
        player.seek(Duration(seconds: record.videoSeek));
        // await player.seek(Duration(seconds: record.videoSeek));
        print('Seeked to position: ${record.videoSeek}s for video: $videoName');
      }
    } catch (e) {
      print('Failed to seek to last position: $e');
    }
  }

  @override
  void dispose() {
    // 先调用父类的 dispose
    super.dispose();

    // 创建一个异步函数来处理清理工作
    Future<void> cleanup() async {
      try {
        // 等待进度保存成
        await _saveCurrentProgress();

        // 放器关闭完成
        await player.dispose();

        // 其他资源清理
        _scrollController.dispose();
      } catch (e) {
        print('Error during cleanup: $e');
      }
    }

    // 执行清理
    cleanup();
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (_isExiting) return;

            setState(() => _isExiting = true);

            final navigator = Navigator.of(context);
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            try {
              // 暂停视频
              await player.pause();
              // 等待进度保存
              await _saveCurrentProgress();
              // 等播放器关闭
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
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
                            color: Colors.black.withOpacity(0.3),
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
                    bottomButtonBar: [
                      // 第二行：控制按钮
                      const MaterialPlayOrPauseButton(
                        iconSize: 16,
                      ),
                      const MaterialSkipNextButton(
                        iconSize: 16,
                      ),
                      const MaterialDesktopVolumeButton(
                        iconSize: 16,
                      ),
                      MaterialPositionIndicator(
                        style: TextStyle(
                          height: 1.0,
                          fontSize: 12.0,
                          color: Colors.grey[100],
                        ),
                      ),
                      const Spacer(), // 将全屏按钮推到最右边
                      buildSpeedButton(),
                      const MaterialFullscreenButton(
                        iconSize: 22,
                      ),
                    ]),
                fullscreen: MaterialVideoControlsThemeData(
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
                    bottomButtonBar: [
                      // 第二行：控制按钮
                      const MaterialPlayOrPauseButton(
                        iconSize: 18,
                      ),
                      const MaterialSkipNextButton(
                        iconSize: 18,
                      ),
                      const MaterialDesktopVolumeButton(
                        iconSize: 18,
                      ),
                      MaterialPositionIndicator(
                        style: TextStyle(
                          height: 1.0,
                          fontSize: 12.0,
                          color: Colors.grey[100],
                        ),
                      ),
                      const Spacer(), // 将全屏按钮推到最右边
                      buildSpeedButton(),
                      const MaterialFullscreenButton(
                        iconSize: 22,
                      ),
                    ]),
                child: Video(
                  controller: controller,
                  controls: MaterialVideoControls,
                ),
              ),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
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
                child: Stack(
                  children: [
                    // Wrap [Video] widget with [MaterialDesktopVideoControlsTheme].
                    MaterialDesktopVideoControlsTheme(
                      normal: MaterialDesktopVideoControlsThemeData(
                          displaySeekBar: true,
                          visibleOnMount: false,
                          primaryButtonBar: [],
                          seekBarMargin: const EdgeInsets.only(
                              bottom: 10, left: 0, right: 0),
                          bottomButtonBarMargin: const EdgeInsets.only(
                              bottom: 0, left: 0, right: 0, top: 0),
                          bottomButtonBar: [
                            const MaterialDesktopSkipPreviousButton(),
                            const MaterialPlayOrPauseButton(),
                            const MaterialSkipNextButton(),
                            const MaterialDesktopVolumeButton(),
                            const MaterialPositionIndicator(),
                            const Spacer(), // 将全屏按钮推到最右边
                            buildSpeedButton(),
                            const MaterialFullscreenButton(
                              iconSize: 28,
                            ),
                          ]),
                      fullscreen: MaterialDesktopVideoControlsThemeData(
                          displaySeekBar: true,
                          visibleOnMount: false,
                          primaryButtonBar: [],
                          keyboardShortcuts: _buildDesktopKeyboardShortcuts(),
                          seekBarMargin: const EdgeInsets.only(
                              bottom: 10, left: 0, right: 0),
                          bottomButtonBarMargin: const EdgeInsets.only(
                              bottom: 0, left: 0, right: 0, top: 0),
                          bottomButtonBar: [
                            const MaterialDesktopSkipPreviousButton(),
                            const MaterialPlayOrPauseButton(),
                            const MaterialSkipNextButton(),
                            const MaterialDesktopVolumeButton(),
                            const MaterialPositionIndicator(),
                            const Spacer(), // 将全屏按钮推到最右边
                            buildSpeedButton(),
                            const MaterialFullscreenButton(
                              iconSize: 28,
                            ),
                          ]),
                      child: GestureDetector(
                        onLongPressStart: (_) {
                          _previousSpeed = controller.player.state.rate;
                          controller.player
                              .setRate(AppConstants.longPressPlaybackSpeed);
                        },
                        onLongPressEnd: (_) {
                          controller.player.setRate(_previousSpeed);
                        },
                        child: Video(
                          controller: controller,
                          controls: MaterialDesktopVideoControls,
                        ),
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
            child: ListView.builder(
              controller: _scrollController,
              itemCount: playList.length,
              itemBuilder: (context, index) {
                final isPlaying = index == currentPlayingIndex;
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? Colors.blue.withOpacity(AppConstants.hoverOpacity)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.grey.withOpacity(AppConstants.shadowOpacity),
                        spreadRadius: AppConstants.defaultSpreadRadius,
                        blurRadius: AppConstants.defaultBlurRadius,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: _buildPlaylistItem(index, isPlaying),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getVideoSha1(String path, String name) {
    return '${path}_$name'.hashCode.toString();
  }

  // 修改 ListTile 的 onTap 处理
  Widget _buildPlaylistItem(int index, bool isPlaying) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      leading: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 24,
            color: isPlaying ? Colors.blue : Colors.grey[600],
          ),
          if (isPlaying)
            const Icon(
              Icons.play_circle_fill,
              size: 24,
              color: Colors.blue,
            ),
        ],
      ),
      title: Text(
        playList[index].extras!['name'],
        style: TextStyle(
          fontSize: AppConstants.defaultFontSize,
          color: isPlaying ? Colors.blue : Colors.black87,
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        // 先保当前视频进，再切换视频
        await _saveCurrentProgress();
        if (mounted) {
          player.jump(index);
          scrollToCurrentItem();
        }
      },
      hoverColor: Colors.blue.withOpacity(0.05),
    );
  }

  // 修改播放列表标题部分
  Widget _buildPlaylistHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.format_list_bulleted, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '播放列表 (${playList.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
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

  // 修改 buildSpeedButton 中的显示方法
  Widget buildSpeedButton() {
    return StatefulBuilder(
      builder: (context, setState) => MaterialCustomButton(
        onPressed: () {
          showDialog(
            context: context,
            barrierColor: Colors.black54,
            builder: (context) => buildSpeedDialog(),
          );
        },
        icon: Text(
          '${_currentSpeed}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildDesktopKeyboardShortcuts() {
    return {
      VideoShortcutActivator(
        key: LogicalKeyboardKey.arrowRight,
        onPress: () {
          print("_shortSeekDuration, $_shortSeekDuration");
          final rate = player.state.position + _shortSeekDuration;
          player.seek(rate);
        },
        onLongPress: () {
          _previousSpeed = controller.player.state.rate;
          player.setRate(AppConstants.longPressPlaybackSpeed);
        },
        onRelease: () {
          player.setRate(_previousSpeed);
        },
      ): () {},

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
      const SingleActivator(LogicalKeyboardKey.keyF): () =>
          toggleFullscreen(context),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          exitFullscreen(context),
    };
  }
}

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

  static DateTime? _pressStartTime;
  static bool _isLongPress = false;
  static Timer? _pressTimer;
  static const _longPressThreshold = Duration(milliseconds: 500);

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is KeyDownEvent && event.logicalKey == key) {
      _pressStartTime = DateTime.now();
      _isLongPress = false;

      // 使用Timer延迟判断是否为短按
      _pressTimer?.cancel();
      _pressTimer = Timer(_longPressThreshold, () {
        if (_pressStartTime != null) {
          _isLongPress = true;
          onLongPress?.call();
        }
      });
    } else if (event is KeyUpEvent && event.logicalKey == key) {
      _pressTimer?.cancel();

      if (_isLongPress) {
        onRelease?.call();
      } else if (_pressStartTime != null &&
          DateTime.now().difference(_pressStartTime!) < _longPressThreshold) {
        onPress?.call();
      }

      _pressStartTime = null;
      _isLongPress = false;
    }
    return false;
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
