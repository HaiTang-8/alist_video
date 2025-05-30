import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/logger.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<File> _logFiles = [];
  File? _selectedLogFile;
  String _logContent = '';
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await AppLogger().getLogFiles();
      setState(() {
        _logFiles = files;
        if (files.isNotEmpty && _selectedLogFile == null) {
          _selectedLogFile = files.first;
          _loadLogContent();
        }
      });
    } catch (e) {
      _showError('加载日志文件失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLogContent() async {
    if (_selectedLogFile == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final content = await AppLogger().readLogFile(_selectedLogFile!);
      setState(() {
        _logContent = content;
      });
    } catch (e) {
      _showError('读取日志内容失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _exportLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final exportedFile = await AppLogger().exportAllLogs();
      if (exportedFile != null) {
        await Share.shareXFiles([XFile(exportedFile.path)], text: '应用日志文件');
        _showSuccess('日志导出成功');
      } else {
        _showError('没有日志可导出');
      }
    } catch (e) {
      _showError('导出日志失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await AppLogger().clearAllLogs();
        await _loadLogFiles();
        _showSuccess('日志已清空');
      } catch (e) {
        _showError('清空日志失败: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _logContent));
    _showSuccess('日志内容已复制到剪贴板');
  }

  List<String> _getFilteredLines() {
    final lines = _logContent.split('\n');
    if (_searchQuery.isEmpty) return lines;
    
    return lines.where((line) => 
      line.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制日志',
            onPressed: _logContent.isNotEmpty ? _copyToClipboard : null,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '导出日志',
            onPressed: _exportLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '清空日志',
            onPressed: _clearLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadLogFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          // 日志文件选择器
          if (_logFiles.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择日志文件:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButton<File>(
                    value: _selectedLogFile,
                    isExpanded: true,
                    items: _logFiles.map((file) {
                      final fileName = file.path.split('/').last;
                      final fileSize = file.lengthSync();
                      final fileSizeStr = _formatFileSize(fileSize);
                      return DropdownMenuItem(
                        value: file,
                        child: Text('$fileName ($fileSizeStr)'),
                      );
                    }).toList(),
                    onChanged: (file) {
                      setState(() {
                        _selectedLogFile = file;
                      });
                      _loadLogContent();
                    },
                  ),
                ],
              ),
            ),
          
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索日志内容...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 日志内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logContent.isEmpty
                    ? const Center(
                        child: Text(
                          '没有日志内容',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          itemCount: _getFilteredLines().length,
                          itemBuilder: (context, index) {
                            final line = _getFilteredLines()[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getLineColor(line),
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: SelectableText(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: _getTextColor(line),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          
          // 底部信息栏
          if (_logContent.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('总行数: ${_logContent.split('\n').length}'),
                  if (_searchQuery.isNotEmpty)
                    Text('匹配: ${_getFilteredLines().length} 行'),
                  Text('日志目录: ${AppLogger().logDirectoryPath ?? '未知'}'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color? _getLineColor(String line) {
    if (line.contains('[ERROR]')) return Colors.red.shade50;
    if (line.contains('[FATAL]')) return Colors.red.shade100;
    if (line.contains('[WARNING]')) return Colors.orange.shade50;
    if (line.contains('[INFO]')) return Colors.blue.shade50;
    if (line.contains('[DEBUG]')) return Colors.grey.shade50;
    return null;
  }

  Color _getTextColor(String line) {
    if (line.contains('[ERROR]')) return Colors.red.shade800;
    if (line.contains('[FATAL]')) return Colors.red.shade900;
    if (line.contains('[WARNING]')) return Colors.orange.shade800;
    if (line.contains('[INFO]')) return Colors.blue.shade800;
    if (line.contains('[DEBUG]')) return Colors.grey.shade600;
    return Colors.black87;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
