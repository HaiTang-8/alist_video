import 'package:flutter/material.dart';
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
                  onTap: () async {
                    if (task.status == '已完成') {
                      final file = File(task.filePath);
                      if (await file.exists()) {
                        // 打开文件
                        DownloadManager().openFile(task.filePath);
                      }
                    }
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
}
