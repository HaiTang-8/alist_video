import 'package:flutter/material.dart';
import 'package:alist_player/models/file_item.dart';
import 'package:alist_player/apis/fs.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/utils/user_session.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class RenamePreview {
  final String originalName;
  final String newName;
  final bool hasChanged;

  RenamePreview({
    required this.originalName,
    required this.newName,
    required this.hasChanged,
  });
}

class QuickRegexRenameDialog extends StatefulWidget {
  final List<FileItem> files;
  final String currentPath;
  final VoidCallback onRenameComplete;

  const QuickRegexRenameDialog({
    super.key,
    required this.files,
    required this.currentPath,
    required this.onRenameComplete,
  });

  @override
  State<QuickRegexRenameDialog> createState() => _QuickRegexRenameDialogState();
}

class _QuickRegexRenameDialogState extends State<QuickRegexRenameDialog> {
  // 正则表达式输入控制器
  final TextEditingController _regexController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  // 选项
  bool _matchCase = false;
  bool _onlyFirstMatch = false;

  // 内置正则模式
  int _builtInRegexPattern = 0; // 默认选择删除[]内容

  // 预览选项
  bool _showOnlyChanged = false; // 是否只显示有修改的项

  // 预览结果
  List<RenamePreview> _previewList = [];

  @override
  void initState() {
    super.initState();
    // 默认使用内置模式
    _updatePreview();
  }

  @override
  void dispose() {
    _regexController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      _previewList = widget.files.map((file) {
        String newName = _applyRegexRule(file.name);
        return RenamePreview(
          originalName: file.name,
          newName: newName,
          hasChanged: newName != file.name,
        );
      }).toList();
    });
  }

  String _applyRegexRule(String originalName) {
    String findText = _regexController.text;
    String replaceText = _replaceController.text;

    // 如果选择了内置正则模式
    if (_builtInRegexPattern >= 0) {
      findText = _getBuiltInRegexPattern(_builtInRegexPattern);
      replaceText = ''; // 内置模式通常是删除内容
    }

    if (findText.isEmpty) return originalName;

    try {
      RegExp regex = RegExp(findText, caseSensitive: _matchCase);
      String result = originalName;
      if (_onlyFirstMatch) {
        result = result.replaceFirst(regex, replaceText);
      } else {
        result = result.replaceAll(regex, replaceText);
      }
      return result;
    } catch (e) {
      // 正则表达式错误，返回原名称
      debugPrint('正则表达式错误: $e');
      return originalName;
    }
  }

  String _getBuiltInRegexPattern(int patternIndex) {
    switch (patternIndex) {
      case 0:
        return r'\[.*?\]'; // 删除[]内容
      case 1:
        return r'\(.*?\)'; // 删除()内容
      case 2:
        return r'【.*?】'; // 删除【】内容
      case 3:
        return r'[\[\(【].*?[\]\)】]'; // 删除所有括号内容
      case 4:
        return r'\s+'; // 删除多余空格
      case 5:
        return r'[._-]+'; // 删除连续的点、下划线、横线
      default:
        return '';
    }
  }

  String _getBuiltInPatternDescription(int patternIndex) {
    switch (patternIndex) {
      case 0:
        return '删除 [方括号] 内容';
      case 1:
        return '删除 (圆括号) 内容';
      case 2:
        return '删除 【中文括号】 内容';
      case 3:
        return '删除所有括号内容';
      case 4:
        return '合并多余空格';
      case 5:
        return '合并连续符号 (._-)';
      default:
        return '';
    }
  }

  // 重命名截图文件的方法
  Future<void> _renameScreenshotFiles({
    required String oldName,
    required String newName,
    required String basePath,
    required int fileType, // 1=文件夹, 2=文件
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final screenshotDir = Directory('${directory.path}/alist_player');

      if (!await screenshotDir.exists()) {
        return; // 截图目录不存在，无需处理
      }

      if (fileType == 1) {
        // 文件夹重命名：需要重命名所有包含该文件夹路径的截图文件
        await _renameFolderScreenshots(
          screenshotDir: screenshotDir,
          oldFolderName: oldName,
          newFolderName: newName,
          basePath: basePath,
        );
      } else if (fileType == 2) {
        // 视频文件重命名：重命名对应的截图文件
        await _renameVideoScreenshots(
          screenshotDir: screenshotDir,
          oldVideoName: oldName,
          newVideoName: newName,
          videoPath: basePath,
        );
      }
    } catch (e) {
      debugPrint('重命名截图文件失败: $oldName -> $newName, 错误: $e');
      // 截图文件重命名失败不影响主要的重命名流程
    }
  }

  // 重命名文件夹相关的截图文件
  Future<void> _renameFolderScreenshots({
    required Directory screenshotDir,
    required String oldFolderName,
    required String newFolderName,
    required String basePath,
  }) async {
    try {
      // 构建旧的和新的文件夹路径
      final String oldFolderPath = '$basePath/$oldFolderName';
      final String newFolderPath = '$basePath/$newFolderName';

      // 清理路径中的非法字符
      final String sanitizedOldFolderPath =
          oldFolderPath.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');
      final String sanitizedNewFolderPath =
          newFolderPath.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');

      // 遍历截图目录中的所有文件
      final List<FileSystemEntity> files = screenshotDir.listSync();

      for (final file in files) {
        if (file is File) {
          final String fileName = file.path.split('/').last;

          // 检查文件名是否包含旧的文件夹路径
          if (fileName.startsWith('screenshot_$sanitizedOldFolderPath')) {
            // 构建新的文件名
            final String newFileName = fileName.replaceFirst(
              'screenshot_$sanitizedOldFolderPath',
              'screenshot_$sanitizedNewFolderPath',
            );

            final String newFilePath = '${screenshotDir.path}/$newFileName';

            // 重命名文件
            await file.rename(newFilePath);
            debugPrint('文件夹截图重命名成功: $fileName -> $newFileName');
          }
        }
      }
    } catch (e) {
      debugPrint('重命名文件夹截图失败: $oldFolderName -> $newFolderName, 错误: $e');
    }
  }

  // 重命名视频文件的截图文件
  Future<void> _renameVideoScreenshots({
    required Directory screenshotDir,
    required String oldVideoName,
    required String newVideoName,
    required String videoPath,
  }) async {
    try {
      // 清理文件名中的非法字符，与视频播放器中的逻辑保持一致
      final String sanitizedVideoPath =
          videoPath.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');
      final String sanitizedOldVideoName =
          oldVideoName.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');
      final String sanitizedNewVideoName =
          newVideoName.replaceAll(RegExp(r'[\/\\:*?"<>|\x00-\x1F]'), '_');

      // 尝试重命名 JPEG 格式的截图文件
      final String oldJpegFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedOldVideoName.jpg';
      final String newJpegFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedNewVideoName.jpg';
      final File oldJpegFile = File('${screenshotDir.path}/$oldJpegFileName');
      final File newJpegFile = File('${screenshotDir.path}/$newJpegFileName');

      if (await oldJpegFile.exists()) {
        await oldJpegFile.rename(newJpegFile.path);
        debugPrint('视频截图重命名成功: $oldJpegFileName -> $newJpegFileName');
      }

      // 尝试重命名 PNG 格式的截图文件（向后兼容）
      final String oldPngFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedOldVideoName.png';
      final String newPngFileName =
          'screenshot_${sanitizedVideoPath}_$sanitizedNewVideoName.png';
      final File oldPngFile = File('${screenshotDir.path}/$oldPngFileName');
      final File newPngFile = File('${screenshotDir.path}/$newPngFileName');

      if (await oldPngFile.exists()) {
        await oldPngFile.rename(newPngFile.path);
        debugPrint('视频截图重命名成功: $oldPngFileName -> $newPngFileName');
      }
    } catch (e) {
      debugPrint('重命名视频截图失败: $oldVideoName -> $newVideoName, 错误: $e');
    }
  }

  Future<void> _performQuickRename() async {
    try {
      // 显示进度对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在重命名文件...'),
            ],
          ),
        ),
      );

      int successCount = 0;
      int failCount = 0;
      List<Map<String, dynamic>> successfulRenames = [];

      // 逐个重命名文件
      for (int i = 0; i < _previewList.length; i++) {
        final preview = _previewList[i];
        if (preview.hasChanged) {
          try {
            final response = await FsApi.rename(
              path: '${widget.currentPath}/${preview.originalName}',
              name: preview.newName,
            );

            if (response.code == 200) {
              successCount++;
              // 记录成功的重命名操作，用于后续更新数据库
              successfulRenames.add({
                'oldName': preview.originalName,
                'newName': preview.newName,
                'type': widget.files[i].type, // 1=文件夹, 2=文件
              });

              // 重命名对应的截图文件（无论是文件还是文件夹）
              await _renameScreenshotFiles(
                oldName: preview.originalName,
                newName: preview.newName,
                basePath: widget.currentPath,
                fileType: widget.files[i].type,
              );
            } else {
              failCount++;
              debugPrint(
                  '重命名失败: ${preview.originalName} -> ${preview.newName}, 错误: ${response.message}');
            }
          } catch (e) {
            failCount++;
            debugPrint(
                '重命名异常: ${preview.originalName} -> ${preview.newName}, 错误: $e');
          }
        }
      }

      // 如果有成功的重命名操作，更新数据库中的历史记录
      if (successfulRenames.isNotEmpty) {
        try {
          // 获取当前用户名
          final identity = await UserSession.loadIdentity();
          final userId = identity.effectiveUserId;
          if (userId == null) {
            debugPrint('缺少用户ID，快捷重命名后无法更新历史记录');
          } else {
            // 批量更新数据库中的历史记录路径
            await DatabaseHelper.instance.batchUpdateHistoricalRecordPaths(
              renameMap: successfulRenames,
              basePath: widget.currentPath,
              userId: userId,
            );
          }

          debugPrint('数据库历史记录更新完成');
        } catch (e) {
          debugPrint('更新数据库历史记录失败: $e');
          // 数据库更新失败不影响文件重命名的成功状态
        }
      }

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();

        // 关闭重命名对话框
        Navigator.of(context).pop();

        // 显示结果
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('快捷重命名完成: 成功 $successCount 个, 失败 $failCount 个'),
            backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }

      // 刷新文件列表
      widget.onRenameComplete();
    } catch (e) {
      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('快捷重命名失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Dialog(
      child: Container(
        width: isSmallScreen ? screenWidth * 0.95 : 800,
        height: isSmallScreen ? MediaQuery.of(context).size.height * 0.8 : 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.find_replace),
                const SizedBox(width: 8),
                const Text(
                  '快捷正则重命名',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 快捷设置区域
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '快捷模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 内置正则模式选择
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < 6; i++)
                        ChoiceChip(
                          label: Text(_getBuiltInPatternDescription(i)),
                          selected: _builtInRegexPattern == i,
                          onSelected: (selected) {
                            setState(() {
                              _builtInRegexPattern = selected ? i : -1;
                              if (selected) {
                                // 使用内置模式时，清空自定义输入
                                _regexController.clear();
                                _replaceController.clear();
                              }
                              _updatePreview();
                            });
                          },
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 自定义正则输入
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _regexController,
                          decoration: const InputDecoration(
                            labelText: '自定义正则表达式',
                            border: OutlineInputBorder(),
                            hintText: '例如: \\[.*?\\]',
                            isDense: true,
                          ),
                          onChanged: (_) {
                            setState(() {
                              _builtInRegexPattern = -1; // 切换到自定义模式
                              _updatePreview();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _replaceController,
                          decoration: const InputDecoration(
                            labelText: '替换为',
                            border: OutlineInputBorder(),
                            hintText: '留空表示删除',
                            isDense: true,
                          ),
                          onChanged: (_) {
                            setState(() {
                              _builtInRegexPattern = -1; // 切换到自定义模式
                              _updatePreview();
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 选项
                  Row(
                    children: [
                      Checkbox(
                        value: _matchCase,
                        onChanged: (value) {
                          setState(() {
                            _matchCase = value!;
                            _updatePreview();
                          });
                        },
                      ),
                      const Text('匹配大小写'),
                      const SizedBox(width: 16),
                      Checkbox(
                        value: _onlyFirstMatch,
                        onChanged: (value) {
                          setState(() {
                            _onlyFirstMatch = value!;
                            _updatePreview();
                          });
                        },
                      ),
                      const Text('仅替换第一个匹配'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 预览区域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '预览结果',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      // 只显示有修改项的切换按钮
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _showOnlyChanged,
                            onChanged: (value) {
                              setState(() {
                                _showOnlyChanged = value!;
                              });
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const Text(
                            '只显示有修改的',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Text(
                          '${_previewList.where((p) => p.hasChanged).length} 个文件将被重命名',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Builder(
                        builder: (context) {
                          // 根据选项过滤预览列表
                          final filteredList = _showOnlyChanged
                              ? _previewList.where((p) => p.hasChanged).toList()
                              : _previewList;

                          if (filteredList.isEmpty) {
                            return Center(
                              child: Text(
                                _showOnlyChanged ? '没有文件需要重命名' : '没有文件',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final preview = filteredList[index];
                              final isLast = index == filteredList.length - 1;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: preview.hasChanged
                                      ? Colors.blue[25]
                                      : Colors.white,
                                  border: Border(
                                    bottom: isLast
                                        ? BorderSide.none
                                        : BorderSide(
                                            color: Colors.grey[200]!,
                                            width: 0.5,
                                          ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preview.originalName,
                                      style: TextStyle(
                                        color: preview.hasChanged
                                            ? Colors.grey[600]
                                            : Colors.black87,
                                        decoration: preview.hasChanged
                                            ? TextDecoration.lineThrough
                                            : null,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (preview.hasChanged) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.arrow_forward,
                                            size: 14,
                                            color: Colors.blue[600],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              preview.newName,
                                              style: TextStyle(
                                                color: Colors.blue[700],
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 底部按钮
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _previewList.any((p) => p.hasChanged)
                      ? _performQuickRename
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('执行重命名'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
