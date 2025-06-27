import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/download_manager.dart';
import '../utils/download_adapter.dart';
import 'log_viewer_page.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> with AutomaticKeepAliveClientMixin {
  bool _isSelectMode = false;
  final Set<String> _selectedTasks = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '下载管理',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新任务状态',
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            onPressed: () async {
              await DownloadAdapter().refreshTasks();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('任务状态已刷新'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '打开下载文件夹',
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            onPressed: () async {
              final directory = await DownloadManager.getDownloadPath();
              await DownloadManager.openFolder(directory);
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '查看日志',
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogViewerPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '下载设置',
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            onPressed: () => _showSettingsDialog(context),
          ),
          ValueListenableBuilder<Map<String, DownloadTask>>(
            valueListenable: DownloadManager().tasks,
            builder: (context, tasks, child) {
              if (tasks.isEmpty) return const SizedBox(width: 8);
              return IconButton(
                icon: Icon(_isSelectMode ? Icons.close : Icons.checklist_rtl),
                tooltip: _isSelectMode ? '退出多选' : '多选模式',
                color: _isSelectMode
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                onPressed: () {
                  setState(() {
                    _isSelectMode = !_isSelectMode;
                    _selectedTasks.clear();
                  });
                },
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<Map<String, DownloadTask>>(
        valueListenable: DownloadManager().tasks,
        builder: (context, tasks, child) {
          if (tasks.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              if (_isSelectMode && _selectedTasks.isNotEmpty)
                _buildBatchOperationBar(tasks),
              Expanded(
                child: ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks.values.elementAt(index);
                    return _buildTaskItem(task);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBatchOperationBar(Map<String, DownloadTask> tasks) {
    final selectedTasks = tasks.entries
        .where((entry) => _selectedTasks.contains(entry.key))
        .map((e) => e.value)
        .toList();

    final hasDownloading = selectedTasks.any((task) => task.status == '下载中');
    final hasPaused = selectedTasks.any((task) => task.status == '已暂停');
    final allSelected = _selectedTasks.length == tasks.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // 顶部选择状态栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedTasks.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '已选择 ${_selectedTasks.length} 个项目',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _toggleSelectAll(tasks),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            allSelected ? Icons.deselect : Icons.select_all,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            allSelected ? '取消全选' : '全选',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 操作按钮区域
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (hasDownloading)
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.pause_circle_outline,
                      label: '暂停全部',
                      color: Colors.orange,
                      onPressed: () {
                        for (var task in selectedTasks) {
                          if (task.status == '下载中') {
                            DownloadManager().pauseTask(task.path);
                          }
                        }
                      },
                    ),
                  ),
                if (hasDownloading && hasPaused) const SizedBox(width: 12),
                if (hasPaused)
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.play_circle_outline,
                      label: '开始全部',
                      color: Colors.green,
                      onPressed: () {
                        for (var task in selectedTasks) {
                          if (task.status == '已暂停') {
                            DownloadManager().resumeTask(task.path);
                          }
                        }
                      },
                    ),
                  ),
                if ((hasDownloading || hasPaused)) const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.delete_outline,
                    label: '删除',
                    color: Colors.red,
                    onPressed: () => _showBatchDeleteDialog(selectedTasks),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSelectAll(Map<String, DownloadTask> tasks) {
    setState(() {
      if (_selectedTasks.length == tasks.length) {
        // 如果已全选，则取消全选
        _selectedTasks.clear();
      } else {
        // 否则全选
        _selectedTasks.clear();
        _selectedTasks.addAll(tasks.keys);
      }
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(60),
              ),
              child: Icon(
                Icons.download_outlined,
                size: 60,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无下载任务',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '开始下载文件，它们会出现在这里',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showSettingsDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '下载设置',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(DownloadTask task) {
    final isSelected = _selectedTasks.contains(task.path);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _isSelectMode && isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: _isSelectMode && isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: _isSelectMode && isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: () {
            // 长按启用多选模式
            HapticFeedback.mediumImpact();
            setState(() {
              _isSelectMode = true;
              _selectedTasks.add(task.path);
            });
          },
          onTap: _isSelectMode
              ? () {
                  // 在多选模式下，点击切换选择状态
                  setState(() {
                    if (_selectedTasks.contains(task.path)) {
                      _selectedTasks.remove(task.path);
                    } else {
                      _selectedTasks.add(task.path);
                    }
                  });
                }
              : null,
          onSecondaryTapDown: _isSelectMode
              ? null
              : (details) {
                  _showContextMenu(context, details.globalPosition, task);
                },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 文件图标或复选框
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 16),
                  child: _isSelectMode
                      ? Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  size: 24,
                                )
                              : null,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: _getFileTypeColor(task.fileName).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getFileTypeIcon(task.fileName),
                            color: _getFileTypeColor(task.fileName),
                            size: 28,
                          ),
                        ),
                ),
                // 主要内容区域
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 文件名和操作按钮
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.fileName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(task.status).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        task.status,
                                        style: TextStyle(
                                          color: _getStatusColor(task.status),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!_isSelectMode) ...[
                            const SizedBox(width: 8),
                            _buildActionIcon(task),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 进度条
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getStatusColor(task.status),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 文件大小信息 - 单独一行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatSize(task.receivedBytes)} / ${_formatSize(task.totalBytes ?? 0)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            '${(task.progress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      // 下载速度和剩余时间信息 - 单独一行
                      if (task.status == '下载中' && task.speed != null && task.speed! > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.download,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_formatSpeed(task.speed!)}/s',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (_calculateRemainingTime(task).isNotEmpty)
                              Text(
                                '剩余 ${_calculateRemainingTime(task)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                      // 错误信息
                      if (task.error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task.error!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  String _formatSize(num bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(1)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatSpeed(num bytesPerSecond) {
    return _formatSize(bytesPerSecond);
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return '';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours小时$minutes分';
    } else if (minutes > 0) {
      return '$minutes分$secs秒';
    } else {
      return '$secs秒';
    }
  }

  String _calculateRemainingTime(DownloadTask task) {
    if (task.status != '下载中' ||
        task.speed == null ||
        task.speed! <= 0 ||
        task.totalBytes == null) {
      return '';
    }

    final remainingBytes = task.totalBytes! - task.receivedBytes;
    if (remainingBytes <= 0) return '';

    final remainingSeconds = (remainingBytes / task.speed!).round();
    return _formatTime(remainingSeconds);
  }

  void _showBatchDeleteDialog(List<DownloadTask> tasks) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除下载任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除选中的 ${tasks.length} 个任务吗？'),
            const SizedBox(height: 16),
            const Text('请选择删除方式：'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              for (var task in tasks) {
                DownloadManager().removeTask(task.path, deleteFile: false);
              }
              Navigator.pop(context);
              setState(() {
                _isSelectMode = false;
                _selectedTasks.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除下载记录')),
              );
            },
            child: const Text('仅删除记录'),
          ),
          TextButton(
            onPressed: () {
              for (var task in tasks) {
                DownloadManager().removeTask(task.path, deleteFile: true);
              }
              Navigator.pop(context);
              setState(() {
                _isSelectMode = false;
                _selectedTasks.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除记录和文件')),
              );
            },
            child: const Text(
              '删除记录和文件',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case '下载中':
        return Colors.blue;
      case '已完成':
        return Colors.green;
      case '已暂停':
        return Colors.orange;
      case '错误':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileTypeIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
      case 'm4v':
      case 'mpg':
      case 'mpeg':
      case '3gp':
      case 'ts':
      case 'mts':
      case 'm2ts':
        return Icons.play_circle_outline;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'm4a':
        return Icons.music_note;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileTypeColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
      case 'm4v':
      case 'mpg':
      case 'mpeg':
      case '3gp':
      case 'ts':
      case 'mts':
      case 'm2ts':
        return Colors.red;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'm4a':
        return Colors.purple;
      case 'pdf':
        return Colors.red.shade700;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.orange;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionIcon(DownloadTask task) {
    switch (task.status) {
      case '下载中':
        return Container(
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: const Icon(Icons.pause, size: 20),
            color: Colors.orange,
            tooltip: '暂停',
            onPressed: () => DownloadManager().pauseTask(task.path),
          ),
        );
      case '已暂停':
        return Container(
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: const Icon(Icons.play_arrow, size: 20),
            color: Colors.green,
            tooltip: '继续',
            onPressed: () => DownloadManager().resumeTask(task.path),
          ),
        );
      case '错误':
        return Container(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: Colors.red,
            tooltip: '重试',
            onPressed: () => DownloadManager().restartTask(task.path),
          ),
        );
      case '已完成':
        return Container(
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: const Icon(Icons.check_circle, size: 20),
            color: Colors.green,
            tooltip: '已完成',
            onPressed: null,
          ),
        );
      default:
        return const SizedBox();
    }
  }

  void _showContextMenu(
      BuildContext context, Offset position, DownloadTask task) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (task.status == '已完成')
          PopupMenuItem(
            child: const Text('打开文件'),
            onTap: () async {
              Future.delayed(const Duration(milliseconds: 10), () async {
                final file = File(task.filePath);
                if (await file.exists()) {
                  DownloadManager().openFile(task.filePath);
                }
              });
            },
          ),
        PopupMenuItem(
          child: const Text('打开所在文件夹'),
          onTap: () async {
            Future.delayed(const Duration(milliseconds: 10), () async {
              final directory = await DownloadManager.getDownloadPath();
              await DownloadManager.openFolder(directory);
            });
          },
        ),
        PopupMenuItem(
          child: const Text('复制文件名'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: task.fileName));
            Future.delayed(const Duration(milliseconds: 10), () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制文件名到剪贴板')),
              );
            });
          },
        ),
        PopupMenuItem(
          child: const Text('重命名'),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              _showRenameDialog(context, task);
            });
          },
        ),
        if (task.status != '下载中')
          PopupMenuItem(
            child: const Text('重新下载'),
            onTap: () {
              DownloadManager().restartTask(task.path);
            },
          ),
        PopupMenuItem(
          child: const Text('删除'),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 10), () {
              _showDeleteDialog(context, task);
            });
          },
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, DownloadTask task) {
    final controller = TextEditingController(text: task.fileName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名文件'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '文件名',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                DownloadManager().renameTask(task.path, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除下载任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除 ${task.fileName} 吗？'),
            const SizedBox(height: 16),
            const Text('请选择删除方式：'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              DownloadManager().removeTask(task.path, deleteFile: false);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除下载记录')),
              );
            },
            child: const Text('仅删除记录'),
          ),
          TextButton(
            onPressed: () {
              DownloadManager().removeTask(task.path, deleteFile: true);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除记录和文件')),
              );
            },
            child: const Text(
              '删除记录和文件',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    final currentPath = await DownloadManager.getCustomDownloadPath();
    final downloadMethod = DownloadAdapter().getCurrentDownloadMethod();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 显示当前下载方法
            const Text('当前下载方法：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    DownloadAdapter().isMobilePlatform
                        ? Icons.smartphone
                        : Icons.computer,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      downloadMethod,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('当前下载位置：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      currentPath,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: currentPath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制路径到剪贴板')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('扫描文件夹并导入视频'),
              onPressed: () async {
                Navigator.pop(context);
                await _scanAndImportVideos(context);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () async {
              await DownloadManager.resetToDefaultDownloadPath();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已重置为默认下载位置')),
              );
            },
            child: const Text('重置为默认'),
          ),
          TextButton(
            onPressed: () async {
              String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
              if (selectedDirectory != null) {
                final success = await DownloadManager.setCustomDownloadPath(selectedDirectory);
                Navigator.pop(context);

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('下载位置已更新')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('设置下载位置失败')),
                  );
                }
              }
            },
            child: const Text('选择文件夹'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndImportVideos(BuildContext context) async {
    // 显示加载提示
    const loadingDialog = AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('正在扫描文件夹...'),
        ],
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => loadingDialog,
    );

    try {
      // 执行扫描
      final importedCount = await DownloadManager().scanDownloadFolder();

      // 关闭加载对话框
      Navigator.pop(context);

      // 显示结果
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('扫描完成'),
          content: Text(
            importedCount > 0
                ? '已导入 $importedCount 个视频文件到下载记录'
                : '没有找到新的视频文件',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      // 出错时关闭加载对话框
      Navigator.pop(context);

      // 显示错误
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: ${e.toString()}')),
      );
    }
  }
}
