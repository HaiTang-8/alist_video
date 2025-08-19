import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/download_settings_manager.dart';
import '../../utils/download_manager.dart';
import '../../utils/download_adapter.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final DownloadSettingsManager _settingsManager = DownloadSettingsManager();
  
  // 控制器
  final TextEditingController _maxConcurrentController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryDelayController = TextEditingController();

  // 设置值
  int _maxConcurrentDownloads = DownloadSettingsManager.defaultMaxConcurrentDownloads;
  int _autoRetryCount = DownloadSettingsManager.defaultAutoRetryCount;
  int _retryDelay = DownloadSettingsManager.defaultRetryDelay;
  bool _enableNotifications = DownloadSettingsManager.defaultEnableNotifications;
  bool _autoStartDownload = DownloadSettingsManager.defaultAutoStartDownload;
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _maxConcurrentController.dispose();
    _retryCountController.dispose();
    _retryDelayController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsManager.getSettingsSummary();
      
      setState(() {
        _maxConcurrentDownloads = settings['maxConcurrentDownloads'];
        _autoRetryCount = settings['autoRetryCount'];
        _retryDelay = settings['retryDelay'];
        _enableNotifications = settings['enableNotifications'];
        _autoStartDownload = settings['autoStartDownload'];

        _maxConcurrentController.text = _maxConcurrentDownloads.toString();
        _retryCountController.text = _autoRetryCount.toString();
        _retryDelayController.text = _retryDelay.toString();
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('加载设置失败: $e');
    }
  }

  Future<void> _saveMaxConcurrentDownloads(int value) async {
    try {
      await _settingsManager.setMaxConcurrentDownloads(value);
      setState(() {
        _maxConcurrentDownloads = value;
      });
      _showSuccessSnackBar('并发下载数量已更新');
    } catch (e) {
      _showErrorSnackBar('保存失败: $e');
      _maxConcurrentController.text = _maxConcurrentDownloads.toString();
    }
  }



  Future<void> _saveAutoRetryCount(int value) async {
    try {
      await _settingsManager.setAutoRetryCount(value);
      setState(() {
        _autoRetryCount = value;
      });
      _showSuccessSnackBar('自动重试次数已更新');
    } catch (e) {
      _showErrorSnackBar('保存失败: $e');
      _retryCountController.text = _autoRetryCount.toString();
    }
  }

  Future<void> _saveRetryDelay(int value) async {
    try {
      await _settingsManager.setRetryDelay(value);
      setState(() {
        _retryDelay = value;
      });
      _showSuccessSnackBar('重试延迟时间已更新');
    } catch (e) {
      _showErrorSnackBar('保存失败: $e');
      _retryDelayController.text = _retryDelay.toString();
    }
  }

  Future<void> _saveEnableNotifications(bool value) async {
    try {
      await _settingsManager.setEnableNotifications(value);
      setState(() {
        _enableNotifications = value;
      });
      _showSuccessSnackBar('通知设置已更新');
    } catch (e) {
      _showErrorSnackBar('保存失败: $e');
    }
  }

  Future<void> _saveAutoStartDownload(bool value) async {
    try {
      await _settingsManager.setAutoStartDownload(value);
      setState(() {
        _autoStartDownload = value;
      });
      _showSuccessSnackBar('自动开始下载设置已更新');
    } catch (e) {
      _showErrorSnackBar('保存失败: $e');
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置设置'),
        content: const Text('确定要将所有下载设置重置为默认值吗？'),
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
      try {
        await _settingsManager.resetToDefaults();
        await _loadSettings();
        _showSuccessSnackBar('设置已重置为默认值');
      } catch (e) {
        _showErrorSnackBar('重置失败: $e');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('下载设置'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '下载设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置为默认值',
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('下载管理'),
          _buildDownloadManagementCard(),
          const SizedBox(height: 16),

          _buildSectionHeader('并发控制'),
          _buildConcurrentDownloadsCard(),
          const SizedBox(height: 16),
          
          _buildSectionHeader('重试设置'),
          _buildRetrySettingsCard(),
          const SizedBox(height: 16),
          
          _buildSectionHeader('其他设置'),
          _buildOtherSettingsCard(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildConcurrentDownloadsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.download_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '同时下载数量',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '设置同时进行下载的最大任务数量（1-10）',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _maxConcurrentDownloads.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _maxConcurrentDownloads.toString(),
                    onChanged: (value) {
                      setState(() {
                        _maxConcurrentDownloads = value.round();
                        _maxConcurrentController.text = _maxConcurrentDownloads.toString();
                      });
                    },
                    onChangeEnd: (value) {
                      _saveMaxConcurrentDownloads(value.round());
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _maxConcurrentController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (value) {
                      final intValue = int.tryParse(value);
                      if (intValue != null && intValue >= 1 && intValue <= 10) {
                        _saveMaxConcurrentDownloads(intValue);
                      } else {
                        _maxConcurrentController.text = _maxConcurrentDownloads.toString();
                        _showErrorSnackBar('请输入1-10之间的数字');
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildRetrySettingsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.refresh_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '重试设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _retryCountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: InputDecoration(
                      labelText: '重试次数',
                      hintText: '0-10',
                      border: const OutlineInputBorder(),
                      helperText: '当前：$_autoRetryCount 次',
                    ),
                    onSubmitted: (value) {
                      final intValue = int.tryParse(value);
                      if (intValue != null && intValue >= 0 && intValue <= 10) {
                        _saveAutoRetryCount(intValue);
                      } else {
                        _retryCountController.text = _autoRetryCount.toString();
                        _showErrorSnackBar('请输入0-10之间的数字');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _retryDelayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      labelText: '重试延迟',
                      hintText: '1-300',
                      border: const OutlineInputBorder(),
                      suffixText: '秒',
                      helperText: '当前：$_retryDelay 秒',
                    ),
                    onSubmitted: (value) {
                      final intValue = int.tryParse(value);
                      if (intValue != null && intValue >= 1 && intValue <= 300) {
                        _saveRetryDelay(intValue);
                      } else {
                        _retryDelayController.text = _retryDelay.toString();
                        _showErrorSnackBar('请输入1-300之间的数字');
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherSettingsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '其他设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('启用下载通知'),
              subtitle: const Text('下载完成时显示系统通知'),
              value: _enableNotifications,
              onChanged: _saveEnableNotifications,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('自动开始下载'),
              subtitle: const Text('添加任务后立即开始下载'),
              value: _autoStartDownload,
              onChanged: _saveAutoStartDownload,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadManagementCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 下载方法显示
            _buildDownloadMethodInfo(),
            const SizedBox(height: 16),

            // 下载路径管理
            _buildDownloadPathSection(),
            const SizedBox(height: 16),

            // 文件扫描功能
            _buildFileScanSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadMethodInfo() {
    final downloadMethod = DownloadAdapter().getCurrentDownloadMethod();

    return Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前下载方法',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  downloadMethod,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadPathSection() {
    return FutureBuilder<String>(
      future: DownloadManager.getCustomDownloadPath(),
      builder: (context, snapshot) {
        final currentPath = snapshot.data ?? '加载中...';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '下载位置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
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
                      _showSuccessSnackBar('已复制路径到剪贴板');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重置为默认'),
                    onPressed: () async {
                      try {
                        await DownloadManager.resetToDefaultDownloadPath();
                        setState(() {}); // 刷新UI
                        _showSuccessSnackBar('已重置为默认下载位置');
                      } catch (e) {
                        _showErrorSnackBar('重置失败: $e');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('选择文件夹'),
                    onPressed: () async {
                      try {
                        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                        if (selectedDirectory != null) {
                          final success = await DownloadManager.setCustomDownloadPath(selectedDirectory);
                          if (success) {
                            setState(() {}); // 刷新UI
                            _showSuccessSnackBar('下载位置已更新');
                          } else {
                            _showErrorSnackBar('设置下载位置失败');
                          }
                        }
                      } catch (e) {
                        _showErrorSnackBar('选择文件夹失败: $e');
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildFileScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '文件管理',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.search),
          label: const Text('扫描文件夹并导入视频'),
          onPressed: () async {
            await _scanAndImportVideos();
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
      ],
    );
  }

  Future<void> _scanAndImportVideos() async {
    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('扫描文件夹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('正在递归扫描所有子目录...'),
            const SizedBox(height: 8),
            Text(
              '这可能需要一些时间，请耐心等待',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // 执行扫描
      final importedCount = await DownloadManager().scanDownloadFolder();

      // 关闭加载对话框
      if (mounted) Navigator.pop(context);

      // 显示详细结果
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  importedCount > 0 ? Icons.check_circle : Icons.info,
                  color: importedCount > 0 ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 8),
                const Text('扫描完成'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  importedCount > 0
                      ? '成功导入 $importedCount 个视频文件到下载记录'
                      : '没有找到新的视频文件',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '扫描范围：下载目录及其所有子目录',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                if (importedCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '导入的文件将保持原有的目录结构',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 出错时关闭加载对话框
      if (mounted) Navigator.pop(context);

      // 显示错误
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                const Text('扫描失败'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('扫描过程中发生错误：'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }
}
