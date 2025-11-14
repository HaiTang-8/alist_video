import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 提供 mpv 播放器的激进缓存策略配置，帮助网络源尽量占满带宽。
class AggressiveCacheService {
  /// 统一放大的解复用缓存尺寸，保障移动端与桌面端都尽可能多拉取片段。
  static const int defaultBufferBytes = 256 * 1024 * 1024;

  /// 默认想要提前填充的秒数窗口。
  static const Duration defaultCacheWindow = Duration(seconds: 60);

  /// 根据业务需求生成 PlayerConfiguration，传入 ready 回调用于下发命令。
  static PlayerConfiguration configuration({void Function()? onReady}) {
    return PlayerConfiguration(
      bufferSize: defaultBufferBytes,
      ready: onReady,
      // 允许常见流媒体协议，避免远端源因为协议白名单受限。
      protocolWhitelist: const [
        'udp',
        'rtp',
        'tcp',
        'tls',
        'data',
        'file',
        'http',
        'https',
        'crypto',
        'rtmp',
        'rtsp',
      ],
    );
  }

  /// 将激进的缓存与连接复用命令写入 mpv，需在 ready 回调后执行。
  static Future<void> apply(Player player, {
    Duration cacheWindow = defaultCacheWindow,
    Duration readaheadWindow = defaultCacheWindow,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final commands = <List<String>>[
      // 提高 cache-secs 以保持更长的缓冲窗口。
      ['set', 'cache-secs', '${cacheWindow.inSeconds}'],
      // 设置 demuxer 预读时长，让 libmpv 持续读取后续片段。
      ['set', 'demuxer-readahead-secs', '${readaheadWindow.inSeconds}'],
      // 禁用 cache-pause，避免 mpv 在缓冲阶段停下下载。
      ['set', 'cache-pause', 'no'],
      // 缩短 cache 恢复等待时间，立刻触发新一轮拉流。
      ['set', 'cache-pause-wait', '0'],
      // 多请求 + 复用连接以榨干 HTTP 容量。
      ['set', 'stream-lavf-o', 'multiple_requests=1'],
      // 强制 HTTP 持久化并开启断线重连，保持吞吐连续性。
      [
        'set',
        'demuxer-lavf-o',
        'http_persistent=1,reconnect_streamed=1,reconnect_delay_max=3'
      ],
    ];

    for (final command in commands) {
      try {
        await _dispatchCommand(player, command);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
        break;
      }
    }
  }

  /// 通过动态方式调用底层 platform 的 command 能力，避免直接依赖 src API。
  static Future<void> _dispatchCommand(
    Player player,
    List<String> command,
  ) async {
    final platform = player.platform;
    if (platform == null) {
      return;
    }
    // NativePlayer 暴露 command(List<String>)，但接口未在 Player 上公开。
    // 这里通过 dynamic 调用，并捕获 NoSuchMethodError 以兼容不支持的平台（如 Web）。
    try {
      await (platform as dynamic).command(command);
    } on NoSuchMethodError {
      // Web 端使用 WebPlayer，不具备 command 接口，直接忽略即可。
    }
  }
}
