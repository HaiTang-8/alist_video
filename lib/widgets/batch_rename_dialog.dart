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

class BatchRenameDialog extends StatefulWidget {
  final List<FileItem> files;
  final String currentPath;
  final VoidCallback onRenameComplete;

  const BatchRenameDialog({
    super.key,
    required this.files,
    required this.currentPath,
    required this.onRenameComplete,
  });

  @override
  State<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<BatchRenameDialog> {
  // 重命名规则类型
  int _renameRuleType = 0; // 0: 查找替换, 1: 正则替换, 2: 常规查找

  // 查找替换
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  // 替换为
  final TextEditingController _replaceToController = TextEditingController();

  // 选项
  bool _matchCase = false;
  bool _onlyFirstMatch = false;

  // 内置正则模式
  int _builtInRegexPattern =
      -1; // -1: 自定义, 0: 删除[]内容, 1: 删除()内容, 2: 删除【】内容, 3: 删除所有括号内容

  // 预览结果
  List<RenamePreview> _previewList = [];

  @override
  void initState() {
    super.initState();
    _updatePreview();
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _replaceToController.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      _previewList = widget.files.map((file) {
        String newName = _applyRenameRule(file.name);
        return RenamePreview(
          originalName: file.name,
          newName: newName,
          hasChanged: newName != file.name,
        );
      }).toList();
    });
  }

  String _applyRenameRule(String originalName) {
    if (_renameRuleType == 0) {
      // 查找替换
      String findText = _findController.text;
      String replaceText = _replaceController.text;

      if (findText.isEmpty) return originalName;

      String result = originalName;
      if (_matchCase) {
        if (_onlyFirstMatch) {
          result = result.replaceFirst(findText, replaceText);
        } else {
          result = result.replaceAll(findText, replaceText);
        }
      } else {
        if (_onlyFirstMatch) {
          result = result.replaceFirst(
              RegExp(RegExp.escape(findText), caseSensitive: false),
              replaceText);
        } else {
          result = result.replaceAll(
              RegExp(RegExp.escape(findText), caseSensitive: false),
              replaceText);
        }
      }
      return result;
    } else if (_renameRuleType == 1) {
      // 正则替换
      String findText = _findController.text;
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
    } else {
      // 常规查找 - 直接替换为指定名称，保留扩展名
      String replaceText = _replaceToController.text;
      if (replaceText.isEmpty) return originalName;

      // 获取文件扩展名
      int lastDotIndex = originalName.lastIndexOf('.');
      String extension =
          lastDotIndex != -1 ? originalName.substring(lastDotIndex) : '';

      return replaceText + extension;
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
        return '将删除文件名中所有 [方括号] 及其内容，如 "电影[1080p].mp4" → "电影.mp4"';
      case 1:
        return '将删除文件名中所有 (圆括号) 及其内容，如 "电影(2023).mp4" → "电影.mp4"';
      case 2:
        return '将删除文件名中所有 【中文括号】 及其内容，如 "电影【高清】.mp4" → "电影.mp4"';
      case 3:
        return '将删除文件名中所有类型的括号及其内容，包括 []、()、【】';
      case 4:
        return '将多个连续空格替换为单个空格，如 "电影  名称.mp4" → "电影 名称.mp4"';
      case 5:
        return '将连续的点、下划线、横线替换为单个字符，如 "电影...名称.mp4" → "电影.名称.mp4"';
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

  Future<void> _performBatchRename() async {
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
              // 包含文件类型信息以便正确更新数据库
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
            debugPrint('缺少用户ID，批量重命名后无法更新历史记录');
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
            content: Text('重命名完成: 成功 $successCount 个, 失败 $failCount 个'),
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
            content: Text('批量重命名失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 800;

    return Dialog(
      child: Container(
        width: isSmallScreen ? screenWidth * 0.95 : 1000,
        height: isSmallScreen ? MediaQuery.of(context).size.height * 0.9 : 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.drive_file_rename_outline),
                const SizedBox(width: 8),
                const Text(
                  '批量重命名',
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

            // 主要内容区域
            Expanded(
              child:
                  isSmallScreen ? _buildMobileLayout() : _buildDesktopLayout(),
            ),

            // 底部按钮
            const Divider(),
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
                      ? _performBatchRename
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // 规则设置区域
        SizedBox(
          height: 300,
          child: SingleChildScrollView(
            child: _buildRuleSettings(),
          ),
        ),
        const SizedBox(height: 16),
        // 预览区域
        Expanded(child: _buildPreviewSection()),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // 左侧规则设置
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _buildRuleSettings(),
          ),
        ),
        Container(
          width: 1,
          color: Colors.grey[300],
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
        ),
        // 右侧预览
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: _buildPreviewSection(),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          '重命名规则',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),

        // 规则类型选择
        DropdownButtonFormField<int>(
          value: _renameRuleType,
          decoration: const InputDecoration(
            labelText: '选择重命名规则',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('查找替换')),
            DropdownMenuItem(value: 1, child: Text('正则替换')),
            DropdownMenuItem(value: 2, child: Text('常规查找')),
          ],
          onChanged: (value) {
            setState(() {
              _renameRuleType = value!;
              _builtInRegexPattern = -1; // 重置内置模式
              _updatePreview();
            });
          },
        ),
        const SizedBox(height: 24),

        // 根据规则类型显示不同的设置
        if (_renameRuleType == 0) ...[
          // 查找替换设置
          TextField(
            controller: _findController,
            decoration: const InputDecoration(
              labelText: '查找字符',
              border: OutlineInputBorder(),
              hintText: '最多输入255个字符',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            maxLength: 255,
            onChanged: (_) => _updatePreview(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(
              labelText: '替换为',
              border: OutlineInputBorder(),
              hintText: '最多输入255个字符',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            maxLength: 255,
            onChanged: (_) => _updatePreview(),
          ),
        ] else if (_renameRuleType == 1) ...[
          // 正则替换设置
          // 内置正则模式选择
          DropdownButtonFormField<int>(
            value: _builtInRegexPattern,
            decoration: const InputDecoration(
              labelText: '内置正则模式',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: const [
              DropdownMenuItem(value: -1, child: Text('自定义正则')),
              DropdownMenuItem(value: 0, child: Text('删除 [方括号] 内容')),
              DropdownMenuItem(value: 1, child: Text('删除 (圆括号) 内容')),
              DropdownMenuItem(value: 2, child: Text('删除 【中文括号】 内容')),
              DropdownMenuItem(value: 3, child: Text('删除所有括号内容')),
              DropdownMenuItem(value: 4, child: Text('删除多余空格')),
              DropdownMenuItem(value: 5, child: Text('删除连续符号 (._-)')),
            ],
            onChanged: (value) {
              setState(() {
                _builtInRegexPattern = value!;
                if (value >= 0) {
                  // 使用内置模式时，清空自定义输入
                  _findController.clear();
                  _replaceController.clear();
                }
                _updatePreview();
              });
            },
          ),
          const SizedBox(height: 20),

          // 只有选择自定义时才显示输入框
          if (_builtInRegexPattern == -1) ...[
            TextField(
              controller: _findController,
              decoration: const InputDecoration(
                labelText: '正则表达式',
                border: OutlineInputBorder(),
                hintText: '例如: \\[.*?\\] 匹配方括号内容',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                helperText: '支持标准正则表达式语法',
              ),
              maxLength: 255,
              onChanged: (_) => _updatePreview(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                labelText: '替换为',
                border: OutlineInputBorder(),
                hintText: '留空表示删除匹配内容',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLength: 255,
              onChanged: (_) => _updatePreview(),
            ),
          ] else ...[
            // 显示内置模式的说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getBuiltInPatternDescription(_builtInRegexPattern),
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ] else ...[
          // 常规查找设置
          TextField(
            controller: _replaceToController,
            decoration: const InputDecoration(
              labelText: '替换为',
              border: OutlineInputBorder(),
              hintText: '最多输入255个字符',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            maxLength: 255,
            onChanged: (_) => _updatePreview(),
          ),
        ],

        const SizedBox(height: 24),

        // 选项设置
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              if (_renameRuleType != 2) ...[
                CheckboxListTile(
                  title: const Text('匹配大小写'),
                  value: _matchCase,
                  onChanged: (value) {
                    setState(() {
                      _matchCase = value!;
                      _updatePreview();
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                CheckboxListTile(
                  title: Text(
                      _renameRuleType == 1 ? '仅替换第一个匹配项' : '仅匹配第一个文件名中的多个'),
                  value: _onlyFirstMatch,
                  onChanged: (value) {
                    setState(() {
                      _onlyFirstMatch = value!;
                      _updatePreview();
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
              if (_renameRuleType == 2)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '常规查找模式将直接替换为指定名称，并保留文件扩展名',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              '实时预览',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7), // 稍小于外层圆角，避免边框被遮挡
              child: ListView.builder(
                itemCount: _previewList.length,
                itemBuilder: (context, index) {
                  final preview = _previewList[index];
                  final isLast = index == _previewList.length - 1;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          preview.hasChanged ? Colors.blue[25] : Colors.white,
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
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: preview.hasChanged
                                    ? Colors.blue
                                    : Colors.grey[400],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                preview.originalName,
                                style: TextStyle(
                                  color: preview.hasChanged
                                      ? Colors.grey[600]
                                      : Colors.black87,
                                  decoration: preview.hasChanged
                                      ? TextDecoration.lineThrough
                                      : null,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (preview.hasChanged) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(width: 22),
                              Icon(
                                Icons.arrow_downward,
                                size: 16,
                                color: Colors.blue[600],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  preview.newName,
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}
