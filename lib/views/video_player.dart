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

  // 保存当前播放进度
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
        userId: _currentUsername!.hashCode, // 使用用户名的哈希值作为userId
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

        // 等待播放器关闭完成
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
    // 获取当前播放视频名称
    String currentVideoName =
        playList.isNotEmpty && currentPlayingIndex < playList.length
            ? playList[currentPlayingIndex].extras!['name']
            : '视频播放';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 创建异步函数来处理返回前的操作
            Future<void> handleBack() async {
              try {
                await _saveCurrentProgress();
                if (!mounted) return;
                Navigator.of(context).pop();
              } catch (e) {
                print('Error saving progress before navigation: $e');
              }
            }

            // 执行返回处理
            handleBack();
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
      body: Row(
        children: [
          // Left side video player
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(controller: controller),
                  ),
                  if (_isLoading)
                    const AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Right side playlist
          Expanded(
            flex: 1,
            child: Container(
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
                  // Playlist header
                  Container(
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
                      ],
                    ),
                  ),
                  // Playlist items with ScrollController
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController, // 添加 ScrollController
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
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.white,
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
}
