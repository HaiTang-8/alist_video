import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/download_manager.dart';
import 'dart:io';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
      ),
      body: ValueListenableBuilder<Map<String, DownloadTask>>(
        valueListenable: DownloadManager().tasks,
        builder: (context, tasks, child) {
          if (tasks.isEmpty) {
            return const Center(
              child: Text('暂无下载任务'),
            );
          }

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks.values.elementAt(index);
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: InkWell(
                  onSecondaryTapDown: (details) {
                    _showContextMenu(context, details.globalPosition, task);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                task.fileName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (task.status == '下载中')
                              IconButton(
                                icon: const Icon(Icons.pause),
                                onPressed: () =>
                                    DownloadManager().pauseTask(task.path),
                              )
                            else if (task.status == '已暂停')
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () =>
                                    DownloadManager().resumeTask(task.path),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: task.progress,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${(task.progress * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              task.status,
                              style: TextStyle(
                                color: _getStatusColor(task.status),
                              ),
                            ),
                          ],
                        ),
                        if (task.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              task.error!,
                              style: const TextStyle(
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
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
            const Text('请选择删除方式���'),
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
}
