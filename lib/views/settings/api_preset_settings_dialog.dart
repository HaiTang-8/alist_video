import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:alist_player/utils/api_config_manager.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/woo_http.dart';

/// 新的API配置预设设置对话框
class ApiPresetSettingsDialog extends StatefulWidget {
  const ApiPresetSettingsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    // 检查是否为移动端
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      // 移动端使用全屏页面
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ApiPresetSettingsDialog(),
          fullscreenDialog: true,
        ),
      );
    } else {
      // 桌面端使用对话框
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ApiPresetSettingsDialog(),
      );
    }
  }

  @override
  State<ApiPresetSettingsDialog> createState() => _ApiPresetSettingsDialogState();
}

class _ApiPresetSettingsDialogState extends State<ApiPresetSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiConfigManager _configManager = ApiConfigManager();
  
  // 预设模式相关
  List<ApiConfigPreset> _presets = [];
  ApiConfigPreset? _selectedPreset;
  bool _isLoadingPresets = true;
  
  // 自定义模式相关
  late TextEditingController _baseUrlController;
  late TextEditingController _baseDownloadUrlController;
  bool _isCustomMode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _baseUrlController = TextEditingController();
    _baseDownloadUrlController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _baseUrlController.dispose();
    _baseDownloadUrlController.dispose();
    super.dispose();
  }

  /// 加载数据
  Future<void> _loadData() async {
    try {
      // 加载配置预设
      final presets = await _configManager.getAllPresets();
      final currentPreset = await _configManager.getCurrentPreset();
      final isCustom = await _configManager.isCustomApiMode();
      
      // 加载当前设置
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;
      final baseDownloadUrl = prefs.getString(AppConstants.baseDownloadUrlKey) ?? AppConstants.defaultBaseDownloadUrl;
      
      setState(() {
        _presets = presets;
        _selectedPreset = currentPreset;
        _isCustomMode = isCustom;
        _baseUrlController.text = baseUrl;
        _baseDownloadUrlController.text = baseDownloadUrl;
        _isLoadingPresets = false;
        
        // 根据模式设置初始标签页
        _tabController.index = isCustom ? 1 : 0;
      });
    } catch (e) {
      setState(() {
        _isLoadingPresets = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载配置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 应用配置
  Future<void> _applyConfiguration() async {
    setState(() {
      _isSaving = true;
    });

    try {
      if (_tabController.index == 0) {
        // 预设模式
        if (_selectedPreset != null) {
          await _configManager.setCurrentPreset(_selectedPreset!.id);
          await _configManager.setCustomApiMode(false);
        }
      } else {
        // 自定义模式
        if (_baseUrlController.text.trim().isEmpty || 
            _baseDownloadUrlController.text.trim().isEmpty) {
          throw Exception('请填写完整的API配置信息');
        }
        
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.setString(AppConstants.baseUrlKey, _baseUrlController.text.trim()),
          prefs.setString(AppConstants.baseDownloadUrlKey, _baseDownloadUrlController.text.trim()),
        ]);
        
        await _configManager.setCustomApiMode(true);

        // 更新HTTP客户端
        await WooHttpUtil().updateBaseUrl();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API配置已保存并生效'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 保存当前自定义配置为预设
  Future<void> _saveAsPreset() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存为预设'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                hintText: '请输入预设名称',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                hintText: '请输入预设描述',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final preset = ApiConfigPreset.createDefault(
          name: nameController.text.trim(),
          baseUrl: _baseUrlController.text.trim(),
          baseDownloadUrl: _baseDownloadUrlController.text.trim(),
          description: descController.text.trim().isEmpty ? null : descController.text.trim(),
        );
        
        final success = await _configManager.savePreset(preset);
        if (success) {
          await _loadData(); // 重新加载数据
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('预设保存成功'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存预设失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 删除预设
  Future<void> _deletePreset(ApiConfigPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除预设"${preset.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _configManager.deletePreset(preset.id);
        if (success) {
          await _loadData(); // 重新加载数据
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('预设删除成功'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除预设失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 构建预设标签页
  Widget _buildPresetsTab() {
    if (_isLoadingPresets) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择一个配置预设：',
            style: TextStyle(
              fontSize: isMobile ? 18 : 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: isMobile ? 16 : 12),
          Expanded(
            child: ListView.builder(
              itemCount: _presets.length,
              itemBuilder: (context, index) {
                final preset = _presets[index];
                final isSelected = _selectedPreset?.id == preset.id;

                return Card(
                  margin: EdgeInsets.only(bottom: isMobile ? 12 : 8),
                  elevation: isSelected ? 4 : 1,
                  child: ListTile(
                    contentPadding: EdgeInsets.all(isMobile ? 16 : 12),
                    leading: Radio<String>(
                      value: preset.id,
                      groupValue: _selectedPreset?.id,
                      onChanged: (value) {
                        setState(() {
                          _selectedPreset = preset;
                        });
                      },
                    ),
                    title: Text(
                      preset.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: isMobile ? 16 : 14,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '基础URL: ${preset.baseUrl}',
                          style: TextStyle(fontSize: isMobile ? 14 : 12),
                        ),
                        Text(
                          '下载URL: ${preset.baseDownloadUrl}',
                          style: TextStyle(fontSize: isMobile ? 14 : 12),
                        ),
                        if (preset.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            preset.description!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isMobile ? 12 : 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: _presets.length > 1
                        ? IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: isMobile ? 24 : 20,
                            ),
                            onPressed: () => _deletePreset(preset),
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedPreset = preset;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建自定义标签页
  Widget _buildCustomTab() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            // 移动端标题和保存按钮分开显示
            Text(
              '自定义API配置：',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saveAsPreset,
                icon: const Icon(Icons.save),
                label: const Text('保存为预设'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            // 桌面端标题和按钮在同一行
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '自定义API配置：',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saveAsPreset,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('保存为预设'),
                ),
              ],
            ),
          ],
          SizedBox(height: isMobile ? 20 : 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: '基础 URL',
                      hintText: '例如: https://alist.example.com',
                      prefixIcon: const Icon(Icons.link),
                      border: const OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: isMobile ? 16 : 12,
                      ),
                    ),
                    style: TextStyle(fontSize: isMobile ? 16 : 14),
                  ),
                  SizedBox(height: isMobile ? 20 : 16),
                  TextField(
                    controller: _baseDownloadUrlController,
                    decoration: InputDecoration(
                      labelText: '下载 URL',
                      hintText: '例如: https://alist.example.com/d',
                      prefixIcon: const Icon(Icons.download),
                      border: const OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: isMobile ? 16 : 12,
                      ),
                    ),
                    style: TextStyle(fontSize: isMobile ? 16 : 14),
                  ),
                  SizedBox(height: isMobile ? 20 : 16),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info,
                          color: Colors.blue,
                          size: isMobile ? 24 : 20,
                        ),
                        SizedBox(width: isMobile ? 12 : 8),
                        Expanded(
                          child: Text(
                            '基础URL是AList服务器的主地址，下载URL通常是基础URL加上"/d"路径。',
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return _buildMobileLayout(context);
    } else {
      return _buildDesktopLayout(context);
    }
  }

  /// 构建移动端布局
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 配置设置'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _applyConfiguration,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '配置预设'),
            Tab(text: '自定义配置'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPresetsTab(),
          _buildCustomTab(),
        ],
      ),
    );
  }

  /// 构建桌面端布局
  Widget _buildDesktopLayout(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.api_rounded, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'API 配置设置',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 标签页
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '配置预设'),
                Tab(text: '自定义配置'),
              ],
            ),
            const SizedBox(height: 16),

            // 标签页内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPresetsTab(),
                  _buildCustomTab(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _applyConfiguration,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('应用配置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
