import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:alist_player/utils/download_manager.dart';

class DiskUsagePage extends StatefulWidget {
  const DiskUsagePage({super.key});

  @override
  State<DiskUsagePage> createState() => _DiskUsagePageState();
}

class _DiskUsageItem {
  const _DiskUsageItem({
    required this.label,
    required this.size,
    required this.icon,
    required this.color,
    this.detail,
  });

  final String label;
  final int size;
  final IconData icon;
  final Color color;
  final String? detail;
}

class _DiskUsagePageState extends State<DiskUsagePage> {
  bool _isLoading = false;
  int _totalSize = 0;
  List<_DiskUsageItem> _items = const [];
  String? _error;
  String? _downloadDirectory;

  @override
  void initState() {
    super.initState();
    _loadDiskUsage();
  }

  Future<void> _loadDiskUsage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final appRoot = Directory('${appDocDir.path}/alist_player');

      final downloadPath = await DownloadManager.getDownloadPath();
      final downloadsSize = await _safeDirectorySize(downloadPath);

      final logsDir = Directory('${appRoot.path}/logs');
      final logsSize = await _safeDirectorySize(logsDir.path);

      final tempDir = await getTemporaryDirectory();
      final tempSize = await _safeDirectorySize(tempDir.path);

      final screenshotSize = await _calculateScreenshotSize(appRoot.path);
      final appRootSize = await _safeDirectorySize(appRoot.path);

      final isDownloadInsideApp = _isPathWithin(downloadPath, appRoot.path);
      final otherWithinApp = appRootSize -
          logsSize -
          screenshotSize -
          (isDownloadInsideApp ? downloadsSize : 0);
      final otherSize = otherWithinApp > 0 ? otherWithinApp : 0;

      final items = <_DiskUsageItem>[
        _DiskUsageItem(
          label: '下载内容',
          size: downloadsSize,
          icon: Icons.download_rounded,
          color: const Color(0xFF4C6EF5),
          detail: downloadPath,
        ),
        _DiskUsageItem(
          label: '视频截图',
          size: screenshotSize,
          icon: Icons.image_outlined,
          color: const Color(0xFF845EF7),
          detail: appRoot.path,
        ),
        _DiskUsageItem(
          label: '日志文件',
          size: logsSize,
          icon: Icons.article_outlined,
          color: const Color(0xFFFD7E14),
          detail: logsDir.path,
        ),
        if (tempSize > 0)
          _DiskUsageItem(
            label: '临时缓存',
            size: tempSize,
            icon: Icons.cached_rounded,
            color: const Color(0xFF20C997),
            detail: tempDir.path,
          ),
        if (otherSize > 0)
          _DiskUsageItem(
            label: '其他数据',
            size: otherSize,
            icon: Icons.folder_open_outlined,
            color: const Color(0xFFFF922B),
            detail: appRoot.path,
          ),
      ];

      final total =
          downloadsSize + logsSize + screenshotSize + tempSize + otherSize;
      final visibleItems = items.where((item) => item.size > 0).toList();

      if (!mounted) return;
      setState(() {
        _downloadDirectory = downloadPath;
        _items = visibleItems;
        _totalSize = total;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Failed to load disk usage: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('磁盘使用统计'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadDiskUsage,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDiskUsage,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = _buildContent(context);
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final headlineColor = Colors.white;
    final subtleColor = Colors.white.withOpacity(0.75);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DiskUsageCard(
            isLoading: _isLoading,
            totalUsageLabel: _formatBytes(_totalSize),
            error: _error,
            downloadDirectory: _downloadDirectory,
            items: _items,
            headlineColor: headlineColor,
            subtleColor: subtleColor,
            totalSize: _totalSize,
            onRetry: _loadDiskUsage,
          ),
          const SizedBox(height: 16),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withOpacity(0.4),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用提示',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• 下载目录可以在下载设置中修改\n'
                    '• 日志可在「个人中心 > 清除日志文件」中清理\n'
                    '• 截图在播放过程中自动生成，可在历史记录中查看\n'
                    '• 临时缓存由系统管理，可能随时被回收',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _safeDirectorySize(String path) async {
    if (path.isEmpty) {
      return 0;
    }

    final directory = Directory(path);
    if (!await directory.exists()) {
      return 0;
    }

    try {
      return await compute(_directorySizeWorker, path);
    } catch (e) {
      debugPrint('compute() failed for $path, fallback to async scan: $e');
      int total = 0;
      try {
        await for (final entity
            in directory.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      } catch (err) {
        debugPrint('Failed to enumerate $path: $err');
      }
      return total;
    }
  }

  Future<int> _calculateScreenshotSize(String rootPath) async {
    if (rootPath.isEmpty) {
      return 0;
    }

    final directory = Directory(rootPath);
    if (!await directory.exists()) {
      return 0;
    }

    try {
      return await compute(_screenshotSizeWorker, rootPath);
    } catch (e) {
      debugPrint('compute() failed for screenshots in $rootPath: $e');
      int total = 0;
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (_isScreenshotFileName(name)) {
              total += await entity.length();
            }
          }
        }
      } catch (err) {
        debugPrint('Failed to enumerate screenshots in $rootPath: $err');
      }
      return total;
    }
  }

  bool _isPathWithin(String child, String parent) {
    if (child.isEmpty || parent.isEmpty) {
      return false;
    }
    final normalizedChild = p.normalize(child);
    final normalizedParent = p.normalize(parent);
    return p.equals(normalizedChild, normalizedParent) ||
        p.isWithin(normalizedParent, normalizedChild);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final hasFraction = size < 10 && unitIndex > 0;
    final formatted =
        hasFraction ? size.toStringAsFixed(1) : size.toStringAsFixed(0);
    return '$formatted ${units[unitIndex]}';
  }
}

class _DiskUsageCard extends StatelessWidget {
  const _DiskUsageCard({
    required this.isLoading,
    required this.totalUsageLabel,
    required this.error,
    required this.downloadDirectory,
    required this.items,
    required this.headlineColor,
    required this.subtleColor,
    required this.totalSize,
    required this.onRetry,
  });

  final bool isLoading;
  final String totalUsageLabel;
  final String? error;
  final String? downloadDirectory;
  final List<_DiskUsageItem> items;
  final Color headlineColor;
  final Color subtleColor;
  final int totalSize;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradientColors = [
      theme.colorScheme.primary.withOpacity(0.95),
      theme.colorScheme.primary.withOpacity(0.7),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '磁盘使用概览',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: headlineColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '查看应用占用的磁盘空间',
                      style: TextStyle(
                        fontSize: 12,
                        color: subtleColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            totalUsageLabel,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: headlineColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '总占用空间',
            style: TextStyle(
              fontSize: 13,
              color: subtleColor,
            ),
          ),
          const SizedBox(height: 18),
          if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '统计失败',
                    style: TextStyle(
                      color: headlineColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    style: TextStyle(
                      color: subtleColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('重新统计'),
                  ),
                ],
              ),
            )
          else if (items.isEmpty && !isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '暂无可统计的数据，尝试下载或播放视频后再来查看吧。',
                style: TextStyle(
                  color: subtleColor,
                  fontSize: 13,
                ),
              ),
            )
          else
            Column(
              children: items
                  .map((item) => _DiskUsageRow(
                        item: item,
                        subtleColor: subtleColor,
                        totalSize: totalSize,
                      ))
                  .toList(),
            ),
          if (downloadDirectory != null) ...[
            const SizedBox(height: 18),
            Text(
              '当前下载目录',
              style: TextStyle(
                fontSize: 12,
                color: subtleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              downloadDirectory!,
              style: TextStyle(
                fontSize: 12,
                color: headlineColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _DiskUsageRow extends StatelessWidget {
  const _DiskUsageRow({
    required this.item,
    required this.subtleColor,
    required this.totalSize,
  });

  final _DiskUsageItem item;
  final Color subtleColor;
  final int totalSize;

  @override
  Widget build(BuildContext context) {
    final ratio =
        totalSize <= 0 ? 0.0 : (item.size / totalSize).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.detail!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatBytes(item.size),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                item.color.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final hasFraction = size < 10 && unitIndex > 0;
    final formatted =
        hasFraction ? size.toStringAsFixed(1) : size.toStringAsFixed(0);
    return '$formatted ${units[unitIndex]}';
  }
}

int _directorySizeWorker(String path) {
  try {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return 0;
    }

    int total = 0;
    final stack = <Directory>[directory];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      try {
        for (final entity in current.listSync(followLinks: false)) {
          if (entity is File) {
            total += entity.lengthSync();
          } else if (entity is Directory) {
            stack.add(entity);
          }
        }
      } catch (_) {
        // 忽略无法访问的目录或文件
      }
    }

    return total;
  } catch (_) {
    return 0;
  }
}

int _screenshotSizeWorker(String rootPath) {
  try {
    final directory = Directory(rootPath);
    if (!directory.existsSync()) {
      return 0;
    }

    int total = 0;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (_isScreenshotFileName(name)) {
          total += entity.lengthSync();
        }
      }
    }
    return total;
  } catch (_) {
    return 0;
  }
}

bool _isScreenshotFileName(String name) {
  return name.startsWith('screenshot_') &&
      (name.endsWith('.jpg') || name.endsWith('.png'));
}
