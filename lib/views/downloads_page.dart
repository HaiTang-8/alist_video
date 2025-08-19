import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/download_manager.dart';
import '../utils/download_adapter.dart';
import 'log_viewer_page.dart';
import 'local_video_player.dart';
import 'dart:io';
import 'settings/download_settings_page.dart';

// 下载任务筛选状态枚举
enum DownloadFilter {
  all,        // 全部
  downloading, // 下载中
  completed,   // 已完成
  failed,      // 失败
  paused,      // 已暂停
  waiting,     // 等待中
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> with AutomaticKeepAliveClientMixin {
  bool _isSelectMode = false;
  final Set<String> _selectedTasks = {};
  DownloadFilter _currentFilter = DownloadFilter.all;

  @override
  bool get wantKeepAlive => true;

  /// 根据筛选条件过滤任务列表
  List<DownloadTask> _filterTasks(Map<String, DownloadTask> tasks) {
    final taskList = tasks.values.toList();

    switch (_currentFilter) {
      case DownloadFilter.all:
        return taskList;
      case DownloadFilter.downloading:
        return taskList.where((task) {
          final status = task.status;
          return status == '下载中' || status == 'downloading';
        }).toList();
      case DownloadFilter.completed:
        return taskList.where((task) {
          final status = task.status;
          return status == '已完成' || status == 'completed';
        }).toList();
      case DownloadFilter.failed:
        return taskList.where((task) {
          final status = task.status;
          return status == '错误' || status == 'failed' || status == '失败';
        }).toList();
      case DownloadFilter.paused:
        return taskList.where((task) {
          final status = task.status;
          return status == '已暂停' || status == 'paused';
        }).toList();
      case DownloadFilter.waiting:
        return taskList.where((task) {
          final status = task.status;
          return status == '等待中' || status == 'waiting';
        }).toList();
    }
  }



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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloadSettingsPage()),
              );
            },
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
              // 根据模式显示统计信息或批量操作
              _isSelectMode
                ? _buildBatchOperationBar(tasks)
                : _buildStatisticsBar(tasks),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final filteredTasks = _filterTasks(tasks);

                    if (filteredTasks.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.builder(
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
                        return _buildTaskItem(task);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatisticsBar(Map<String, DownloadTask> tasks) {
    // 计算各种状态的任务数量
    int totalTasks = tasks.length;
    int downloadingTasks = tasks.values.where((task) => task.status == '下载中').length;
    int completedTasks = tasks.values.where((task) => task.status == '已完成').length;
    int failedTasks = tasks.values.where((task) => task.status == '错误').length;
    int pausedTasks = tasks.values.where((task) => task.status == '已暂停').length;
    int waitingTasks = tasks.values.where((task) => task.status == '等待中').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 如果屏幕宽度足够（每个项目至少60px），使用平均分布
          // 否则使用滚动布局
          const double minItemWidth = 60.0;
          const int itemCount = 6;
          final bool useExpandedLayout = constraints.maxWidth >= (minItemWidth * itemCount);

          if (useExpandedLayout) {
            return Row(
              children: [
                Expanded(
                  child: _buildStatItem('总计', totalTasks, Theme.of(context).colorScheme.primary, DownloadFilter.all),
                ),
                Expanded(
                  child: _buildStatItem('下载中', downloadingTasks, Colors.blue, DownloadFilter.downloading),
                ),
                Expanded(
                  child: _buildStatItem('等待中', waitingTasks, Colors.amber, DownloadFilter.waiting),
                ),
                Expanded(
                  child: _buildStatItem('已暂停', pausedTasks, Colors.orange, DownloadFilter.paused),
                ),
                Expanded(
                  child: _buildStatItem('已完成', completedTasks, Colors.green, DownloadFilter.completed),
                ),
                Expanded(
                  child: _buildStatItem('失败', failedTasks, Colors.red, DownloadFilter.failed),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _buildStatItem('总计', totalTasks, Theme.of(context).colorScheme.primary, DownloadFilter.all),
                  _buildStatItem('下载中', downloadingTasks, Colors.blue, DownloadFilter.downloading),
                  _buildStatItem('等待中', waitingTasks, Colors.amber, DownloadFilter.waiting),
                  _buildStatItem('已暂停', pausedTasks, Colors.orange, DownloadFilter.paused),
                  _buildStatItem('已完成', completedTasks, Colors.green, DownloadFilter.completed),
                  _buildStatItem('失败', failedTasks, Colors.red, DownloadFilter.failed),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color, DownloadFilter filter) {
    final isSelected = _currentFilter == filter;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _currentFilter = filter;
            // 退出多选模式
            _isSelectMode = false;
            _selectedTasks.clear();
          });
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 60),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: color.withValues(alpha: 0.3), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : color,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? color
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchOperationBar(Map<String, DownloadTask> tasks) {
    final filteredTasks = _filterTasks(tasks);
    final selectedTasks = filteredTasks
        .where((task) => _selectedTasks.contains(task.path))
        .toList();

    final hasDownloading = selectedTasks.any((task) => task.status == '下载中');
    final hasPaused = selectedTasks.any((task) => task.status == '已暂停');
    final allSelected = _selectedTasks.length == filteredTasks.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 选择状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_selectedTasks.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已选择 ${_selectedTasks.length} 个项目',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // 全选/取消全选按钮
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _toggleSelectAll(tasks),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      allSelected ? '取消全选' : '全选',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 操作按钮 - 紧凑布局
          if (selectedTasks.isNotEmpty) ...[
            const SizedBox(width: 8),
            if (hasDownloading)
              _buildCompactActionButton(
                icon: Icons.pause,
                color: Colors.orange,
                onPressed: () {
                  for (var task in selectedTasks) {
                    if (task.status == '下载中') {
                      DownloadManager().pauseTask(task.path);
                    }
                  }
                },
              ),
            if (hasPaused) ...[
              if (hasDownloading) const SizedBox(width: 6),
              _buildCompactActionButton(
                icon: Icons.play_arrow,
                color: Colors.green,
                onPressed: () {
                  for (var task in selectedTasks) {
                    if (task.status == '已暂停') {
                      DownloadManager().resumeTask(task.path);
                    }
                  }
                },
              ),
            ],
            const SizedBox(width: 6),
            _buildCompactActionButton(
              icon: Icons.delete_outline,
              color: Colors.red,
              onPressed: () => _showBatchDeleteDialog(selectedTasks),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }

  void _toggleSelectAll(Map<String, DownloadTask> tasks) {
    final filteredTasks = _filterTasks(tasks);
    setState(() {
      if (_selectedTasks.length == filteredTasks.length) {
        // 如果已全选，则取消全选
        _selectedTasks.clear();
      } else {
        // 否则全选
        _selectedTasks.clear();
        _selectedTasks.addAll(filteredTasks.map((task) => task.path));
      }
    });
  }

  Widget _buildEmptyState() {
    String message;
    String subtitle;
    IconData icon;
    Color iconColor;

    switch (_currentFilter) {
      case DownloadFilter.all:
        message = '暂无下载任务';
        subtitle = '开始下载文件，它们会出现在这里';
        icon = Icons.download_outlined;
        iconColor = Theme.of(context).colorScheme.primary;
        break;
      case DownloadFilter.downloading:
        message = '暂无正在下载的任务';
        subtitle = '当前没有正在进行的下载任务';
        icon = Icons.downloading_outlined;
        iconColor = Colors.blue;
        break;
      case DownloadFilter.completed:
        message = '暂无已完成的任务';
        subtitle = '完成的下载任务会显示在这里';
        icon = Icons.download_done_outlined;
        iconColor = Colors.green;
        break;
      case DownloadFilter.failed:
        message = '暂无失败的任务';
        subtitle = '下载失败的任务会显示在这里';
        icon = Icons.error_outline;
        iconColor = Colors.red;
        break;
      case DownloadFilter.paused:
        message = '暂无已暂停的任务';
        subtitle = '暂停的下载任务会显示在这里';
        icon = Icons.pause_circle_outline;
        iconColor = Colors.orange;
        break;
      case DownloadFilter.waiting:
        message = '暂无等待中的任务';
        subtitle = '等待下载的任务会显示在这里';
        icon = Icons.schedule_outlined;
        iconColor = Colors.amber;
        break;
    }

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
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(60),
              ),
              child: Icon(
                icon,
                size: 60,
                color: iconColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (_currentFilter != DownloadFilter.all) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _currentFilter = DownloadFilter.all;
                  });
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('查看全部任务'),
                style: TextButton.styleFrom(
                  foregroundColor: iconColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DownloadSettingsPage()),
                    );
                  },
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _isSelectMode && isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
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
          borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 文件图标或复选框
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  child: _isSelectMode
                      ? Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
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
                            borderRadius: BorderRadius.circular(10),
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
                      // 文件名
                      Text(
                        task.fileName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // 进度条
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getStatusColor(task.status),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      // 文件大小信息 - 单独一行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatSize(task.receivedBytes)} / ${_formatSize(task.totalBytes ?? 0)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            '${(task.progress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      // 下载速度和剩余时间信息 - 单独一行
                      if (task.status == '下载中' && task.speed != null && task.speed! > 0) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.download,
                                  size: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${_formatSpeed(task.speed!)}/s',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 11,
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
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ],
                      // 错误信息
                      if (task.error != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  task.error!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 11,
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
                // 操作按钮列 - 垂直居中在最右侧
                if (!_isSelectMode) ...[
                  const SizedBox(width: 12),
                  _buildActionIcon(task),
                ],
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => DownloadManager().pauseTask(task.path),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.pause,
                  size: 24,
                  color: Colors.orange,
                ),
              ),
            ),
          ),
        );
      case '已暂停':
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => DownloadManager().resumeTask(task.path),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow,
                  size: 24,
                  color: Colors.green,
                ),
              ),
            ),
          ),
        );
      case '错误':
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => DownloadManager().restartTask(task.path),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.refresh,
                  size: 24,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        );
      case '已完成':
        // 如果是视频文件，显示播放按钮；否则显示完成图标
        if (_isVideoFile(task.fileName)) {
          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final file = File(task.filePath);
                  if (await file.exists()) {
                    if (mounted) {
                      LocalVideoPlayer.playLocalVideo(context, task.filePath, task.fileName);
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('视频文件不存在')),
                      );
                    }
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow,
                    size: 24,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          );
        } else {
          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_circle,
                size: 24,
                color: Colors.green,
              ),
            ),
          );
        }
      default:
        return const SizedBox(width: 32, height: 32);
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
        if (task.status == '已完成' && _isVideoFile(task.fileName))
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.play_arrow, size: 18),
                SizedBox(width: 8),
                Text('播放视频'),
              ],
            ),
            onTap: () async {
              Future.delayed(const Duration(milliseconds: 10), () async {
                final file = File(task.filePath);
                if (await file.exists() && mounted) {
                  LocalVideoPlayer.playLocalVideo(context, task.filePath, task.fileName);
                }
              });
            },
          ),
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





  // 检查是否为视频文件
  bool _isVideoFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
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
}
