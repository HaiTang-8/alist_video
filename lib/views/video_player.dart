import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/utils/db.dart';
import 'package:flutter/material.dart';
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

  // 排序方法
  void _sortPlaylist() async {
    setState(() {
      playList.sort((a, b) {
        String nameA = a.extras!['name'] as String;
        String nameB = b.extras!['name'] as String;
        int comparison =
            _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
        return comparison;
      });
      // 更新当前播放索引
      for (int i = 0; i < playList.length; i++) {
        if (playList[i].extras!['name'] == widget.name) {
          currentPlayingIndex = i;
          break;
        }
      }
    });

    // 更新播放器的播放列表
    await player.open(
      Playlist(playList, index: currentPlayingIndex),
      play: player.state.playing, // 保持当前播放状态
    );
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
      var res = await FsApi.list(
          path: widget.path, password: '', page: 1, perPage: 0, refresh: false);
      if (res.code == 200) {
        setState(() {
          List<Media> playMediaList = res.data?.content!
                  .where((data) => data.type == 2)
                  .map((data) => Media(
                      'https://alist.tt1.top/d${widget.path.substring(1)}/${data.name}?sign=${data.sign}',
                      extras: {'name': data.name ?? ''}))
                  .toList() ??
              [];
          playList.clear();
          for (var i = 0; i < playMediaList.length; i++) {}

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
            _scrollToCurrentItem();
            _isLoading = true;
            _hasSeekInitialPosition = false;
          });
        }
      }
    });

    // player.stream.position.listen((Duration position) {
    //   if (position.inSeconds > 0 && mounted && !_hasSeekInitialPosition) {
    //     _seekToLastPosition(playList[currentPlayingIndex].extras!['name'])
    //         .then((_) {
    //       if (mounted) {
    //         setState(() => _isLoading = false);
    //       }
    //     });
    //     _hasSeekInitialPosition = true;
    //   }
    // });

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

  // 添加滚动到当前项的方法
  void _scrollToCurrentItem() {
    // 确保构建完成后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        const itemHeight = 72.0; // ListTile的预估高度（包含margin）
        final screenHeight = MediaQuery.of(context).size.height;
        final scrollOffset =
            (currentPlayingIndex * itemHeight) - (screenHeight / 3);

        _scrollController.animateTo(
          scrollOffset.clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // 查询并跳转到上次播放位置
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
        // 等待进度保存完成
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

            try {
              // 暂停视频
              await player.pause();
              // 等待进度保存
              await _saveCurrentProgress();
              // 等待播放器关闭
              await player.dispose();

              if (!mounted) return;
              Navigator.of(context).pop();
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
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

  // 移动端布局
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
                      MaterialCustomButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('播放速度'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [0.5, 1.0, 1.5, 2.0]
                                    .map((speed) => ListTile(
                                          dense: true,
                                          title: Text('${speed}x'),
                                          onTap: () {
                                            player.setRate(speed);
                                            Navigator.pop(context);
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.speed,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const MaterialFullscreenButton(
                        iconSize: 20,
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
                      MaterialCustomButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('播放速度'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [0.5, 1.0, 1.5, 2.0]
                                    .map((speed) => ListTile(
                                          dense: true,
                                          title: Text('${speed}x'),
                                          onTap: () {
                                            player.setRate(speed);
                                            Navigator.pop(context);
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.speed,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
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
                            MaterialCustomButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('播放速度'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [0.5, 1.0, 1.5, 2.0]
                                          .map((speed) => ListTile(
                                                dense: true,
                                                title: Text('${speed}x'),
                                                onTap: () {
                                                  player.setRate(speed);
                                                  Navigator.pop(context);
                                                },
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.speed,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const MaterialFullscreenButton(
                              iconSize: 28,
                            ),
                          ]),
                      fullscreen: MaterialDesktopVideoControlsThemeData(
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
                            MaterialCustomButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('播放速度'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [0.5, 1.0, 1.5, 2.0]
                                          .map((speed) => ListTile(
                                                dense: true,
                                                title: Text('${speed}x'),
                                                onTap: () {
                                                  player.setRate(speed);
                                                  Navigator.pop(context);
                                                },
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.speed,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const MaterialFullscreenButton(
                              iconSize: 28,
                            ),
                          ]),
                      child: GestureDetector(
                        onLongPressStart: (_) {
                          controller.player.setRate(2.0);
                        },
                        onLongPressEnd: (_) {
                          controller.player.setRate(1.0);
                        },
                        child: Video(
                          controller: controller,
                          controls: MaterialDesktopVideoControls,
                          // controls: (state) {
                          //   return Stack(
                          //     children: [
                          //       GestureDetector(
                          //         onTap: () {
                          //           setState(() {
                          //             _showControls = !_showControls;
                          //           });
                          //         },
                          //         onDoubleTap: () {
                          //           if (player.state.playing) {
                          //             player.pause();
                          //           } else {
                          //             player.play();
                          //           }
                          //         },
                          //         child: Container(color: Colors.transparent),
                          //       ),
                          //       if (_showControls)
                          //         Positioned(
                          //           left: 0,
                          //           right: 0,
                          //           bottom: 0,
                          //           child: Container(
                          //             padding: const EdgeInsets.symmetric(
                          //                 horizontal: 16, vertical: 8),
                          //             decoration: BoxDecoration(
                          //               gradient: LinearGradient(
                          //                 begin: Alignment.topCenter,
                          //                 end: Alignment.bottomCenter,
                          //                 colors: [
                          //                   Colors.transparent,
                          //                   Colors.black.withOpacity(0.7),
                          //                 ],
                          //               ),
                          //             ),
                          //             child: Column(
                          //               mainAxisSize: MainAxisSize.min,
                          //               children: [
                          //                 // 添加进度条
                          //                 const MaterialSeekBar(),
                          //                 const SizedBox(height: 2),
                          //                 // 控制按钮行
                          //                 Row(
                          //                   children: [
                          //                     const MaterialSkipPreviousButton(),
                          //                     const MaterialPlayOrPauseButton(),
                          //                     const MaterialSkipNextButton(),
                          //                     const MaterialDesktopVolumeButton(),
                          //                     const MaterialPositionIndicator(),
                          //                     const Spacer(),
                          //                     // 速率控制按钮
                          //                     MaterialCustomButton(
                          //                       onPressed: () {
                          //                         showDialog(
                          //                           context: context,
                          //                           builder: (context) =>
                          //                               AlertDialog(
                          //                             title: const Text('播放速度'),
                          //                             content: Column(
                          //                               mainAxisSize:
                          //                                   MainAxisSize.min,
                          //                               children:
                          //                                   [0.5, 1.0, 1.5, 2.0]
                          //                                       .map(
                          //                                         (speed) =>
                          //                                             ListTile(
                          //                                           title: Text(
                          //                                               '${speed}x'),
                          //                                           onTap: () {
                          //                                             state
                          //                                                 .widget
                          //                                                 .controller
                          //                                                 .player
                          //                                                 .setRate(
                          //                                                     speed);
                          //                                             Navigator.pop(
                          //                                                 context);
                          //                                           },
                          //                                         ),
                          //                                       )
                          //                                       .toList(),
                          //                             ),
                          //                           ),
                          //                         );
                          //                       },
                          //                       icon: const Icon(
                          //                         Icons.speed,
                          //                         color: Colors.white,
                          //                       ),
                          //                     ),
                          //                     const MaterialFullscreenButton(),
                          //                   ],
                          //                 ),
                          //               ],
                          //             ),
                          //           ),
                          //         ),
                          //     ],
                          //   );
                          // },
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
                    color:
                        isPlaying ? Colors.blue.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 2,
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
          fontSize: 14,
          color: isPlaying ? Colors.blue : Colors.black87,
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        // 先保存当前视频进度，再切换视频
        await _saveCurrentProgress();
        if (mounted) {
          player.jump(index);
          _scrollToCurrentItem();
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
          const Icon(Icons.playlist_play, color: Colors.blue),
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
            tooltip: _isAscending ? '降序排列' : '升序排列',
          ),
        ],
      ),
    );
  }
}
