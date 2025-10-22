import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:alist_player/utils/api_config_manager.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/woo_http.dart';

/// 新的API配置预设设置对话框
class ApiPresetSettingsDialog extends StatefulWidget {
  const ApiPresetSettingsDialog({super.key});

  static Future<bool?> show(BuildContext context) async {
    // 检查是否为移动端
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      // 移动端使用全屏页面
      return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => const ApiPresetSettingsDialog(),
          fullscreenDialog: true,
        ),
      );
    } else {
      // 桌面端使用对话框
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final size = MediaQuery.of(context).size;
          final width = (size.width * 0.85).clamp(720.0, 1100.0);
          final height = (size.height * 0.85).clamp(520.0, 900.0);

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: width,
              height: height,
              child: const ApiPresetSettingsDialog(),
            ),
          );
        },
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
  late final ScrollController _presetsScrollController;

  // 预设模式相关
  List<ApiConfigPreset> _presets = [];
  ApiConfigPreset? _selectedPreset;
  bool _isLoadingPresets = true;

  // 自定义模式相关
  late TextEditingController _baseUrlController;
  late TextEditingController _baseDownloadUrlController;
  bool _isSaving = false;

  // 配置更改标志
  bool _hasConfigChanged = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _presetsScrollController = ScrollController();
    _baseUrlController = TextEditingController();
    _baseDownloadUrlController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _presetsScrollController.dispose();
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

      _hasConfigChanged = true;
      if (mounted) {
        Navigator.pop(context, true);
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
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) => _SavePresetDialog(
        baseUrl: _baseUrlController.text.trim(),
        baseDownloadUrl: _baseDownloadUrlController.text.trim(),
      ),
    );

    if (result != null) {
      try {
        final preset = ApiConfigPreset.createDefault(
          name: result['name']!,
          baseUrl: result['baseUrl']!,
          baseDownloadUrl: result['baseDownloadUrl']!,
          description: result['description']?.isEmpty == true ? null : result['description'],
        );

        final success = await _configManager.savePreset(preset);
        if (success) {
          _hasConfigChanged = true;
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
          _hasConfigChanged = true;
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

    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 28,
          vertical: isMobile ? 12 : 24,
        );

        return Scrollbar(
          controller: _presetsScrollController,
          thumbVisibility: !isMobile,
          radius: const Radius.circular(12),
          child: CustomScrollView(
            controller: _presetsScrollController,
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.bookmark_rounded, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '选择预设配置',
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (!isMobile && _selectedPreset != null)
                        _buildTagChip('当前使用', colorScheme.primary, icon: Icons.radio_button_checked),
                    ],
                  ),
                ),
              ),
              if (_presets.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding.horizontal / 2,
                    0,
                    padding.horizontal / 2,
                    padding.bottom,
                  ),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        Expanded(child: _buildEmptyState()),
                        const SizedBox(height: 18),
                        _buildPrimaryActionButton(
                          label: '添加新预设',
                          icon: Icons.add_rounded,
                          onPressed: _showAddPresetDialog,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 28,
                    vertical: 0,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final preset = _presets[index];
                        final isSelected = _selectedPreset?.id == preset.id;
                        return Padding(
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 14),
                          child: _buildPresetCard(preset, isSelected, isMobile),
                        );
                      },
                      childCount: _presets.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 28,
                    18,
                    isMobile ? 16 : 28,
                    padding.bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _buildPrimaryActionButton(
                      label: '添加新预设',
                      icon: Icons.add_rounded,
                      onPressed: _showAddPresetDialog,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 构建自定义标签页
  Widget _buildCustomTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 760;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 28,
            vertical: isMobile ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自定义 API 配置',
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '自定义基础访问地址与下载地址，可灵活适配自建或第三方服务。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile)
                    FilledButton.icon(
                      onPressed: _saveAsPreset,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('保存为预设'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isMobile ? 18 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '基础信息',
                      style: TextStyle(
                        fontSize: isMobile ? 15 : 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isWide)
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _baseUrlController,
                              label: '基础 URL',
                              icon: Icons.link_rounded,
                              hint: '例如: https://alist.example.com',
                              isMobile: false,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildTextField(
                              controller: _baseDownloadUrlController,
                              label: '下载 URL',
                              icon: Icons.download_rounded,
                              hint: '例如: https://alist.example.com/d',
                              isMobile: false,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildTextField(
                        controller: _baseUrlController,
                        label: '基础 URL',
                        icon: Icons.link_rounded,
                        hint: '例如: https://alist.example.com',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _baseDownloadUrlController,
                        label: '下载 URL',
                        icon: Icons.download_rounded,
                        hint: '例如: https://alist.example.com/d',
                        isMobile: isMobile,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withValues(alpha: 0.12),
                            ),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '基础 URL 与下载 URL 应指向同一服务的不同入口。多数情况下下载地址为基础地址加 "/d"。配置后可选择保存为预设，以便下次快速使用。',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isMobile) ...[
                const SizedBox(height: 24),
                _buildPrimaryActionButton(
                  label: '保存为预设',
                  icon: Icons.save_rounded,
                  onPressed: _saveAsPreset,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 构建文本输入框
  Widget _buildTagChip(String label, Color color, {IconData? icon, Color? textColor}) {
    final resolvedTextColor = textColor ??
        (ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolvedTextColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: resolvedTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetMetaRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool expand = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );

    if (!expand) {
      return button;
    }

    return Row(
      children: [
        Expanded(child: button),
      ],
    );
  }

  Widget _buildPresetCard(ApiConfigPreset preset, bool isSelected, bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardRadius = BorderRadius.circular(12);
    final baseColor = colorScheme.surface;
    final selectedColor = colorScheme.primary.withValues(alpha: 0.08);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected ? selectedColor : baseColor,
        borderRadius: cardRadius,
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: cardRadius,
        onTap: () {
          setState(() {
            _selectedPreset = preset;
          });
        },
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      color: isSelected ? colorScheme.primary : Colors.transparent,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 12,
                            color: colorScheme.onPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                preset.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isMobile ? 15 : 16,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (isSelected)
                                  _buildTagChip('当前使用', colorScheme.primary, icon: Icons.radio_button_checked),
                                if (preset.isDefault)
                                  _buildTagChip(
                                    '默认',
                                    colorScheme.secondary,
                                    icon: Icons.star_rounded,
                                    textColor: colorScheme.onSecondary,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPresetMetaRow(
                          icon: Icons.link_rounded,
                          label: '基础地址',
                          value: preset.baseUrl,
                        ),
                        const SizedBox(height: 8),
                        _buildPresetMetaRow(
                          icon: Icons.download_rounded,
                          label: '下载地址',
                          value: preset.baseDownloadUrl,
                        ),
                        if (preset.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceVariant.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 16,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    preset.description!,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                      height: 1.4,
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
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editPreset(preset);
                          break;
                        case 'delete':
                          _deletePreset(preset);
                          break;
                        case 'setDefault':
                          _setAsDefault(preset);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 16),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      if (!preset.isDefault)
                        const PopupMenuItem(
                          value: 'setDefault',
                          child: Row(
                            children: [
                              Icon(Icons.star_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('设为默认'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: const [
                            Icon(Icons.delete_rounded, size: 16, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text(
                              '删除',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    required bool isMobile,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: TextStyle(
            fontSize: isMobile ? 16 : 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(
              icon,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isMobile ? 16 : 12,
            ),
          ),
        ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'API 配置设置',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '快速切换预设或定制专属 API',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context, _hasConfigChanged),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close_rounded, size: 20),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _applyConfiguration,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                _isSaving ? '保存中...' : '应用配置',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: colorScheme.surface,
          child: Column(
            children: [
              // 标签页选择器
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: colorScheme.primary,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: colorScheme.onPrimary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.layers_rounded, size: 18),
                      text: '预设配置',
                    ),
                    Tab(
                      icon: Icon(Icons.tune_rounded, size: 18),
                      text: '自定义配置',
                    ),
                  ],
                ),
              ),
              // 内容区域
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPresetsTab(),
                    _buildCustomTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建桌面端布局
  Widget _buildDesktopLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: colorScheme.surface,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.api_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'API 配置设置',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '集中管理预设并支持快捷切换，适配桌面端操作体验。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _hasConfigChanged),
                    tooltip: '关闭',
                    icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: colorScheme.primary,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: colorScheme.onPrimary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.layers_rounded, size: 18),
                      text: '预设配置',
                    ),
                    Tab(
                      icon: Icon(Icons.tune_rounded, size: 18),
                      text: '自定义配置',
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPresetsTab(),
                  _buildCustomTab(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, _hasConfigChanged),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _applyConfiguration,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      _isSaving ? '保存中...' : '应用配置',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无配置预设',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮添加第一个预设配置',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示添加预设对话框
  Future<void> _showAddPresetDialog() async {
    // 这里可以实现添加预设的逻辑
    // 暂时显示一个提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('添加预设功能待实现'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// 编辑预设
  Future<void> _editPreset(ApiConfigPreset preset) async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) => _EditPresetDialog(preset: preset),
    );

    if (result != null) {
      try {
        final updatedPreset = preset.copyWith(
          name: result['name']!,
          baseUrl: result['baseUrl']!,
          baseDownloadUrl: result['baseDownloadUrl']!,
          description: result['description']?.isEmpty == true ? null : result['description'],
        );

        final success = await _configManager.savePreset(updatedPreset);
        if (success) {
          _hasConfigChanged = true;
          await _loadData(); // 重新加载数据
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('预设更新成功'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('更新预设失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 设置为默认预设
  Future<void> _setAsDefault(ApiConfigPreset preset) async {
    try {
      final success = await _configManager.setCurrentPreset(preset.id);
      if (success) {
        _hasConfigChanged = true;
        await _loadData(); // 重新加载数据
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已将 "${preset.name}" 设为默认配置'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('设置默认配置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// 编辑预设对话框
class _EditPresetDialog extends StatefulWidget {
  final ApiConfigPreset preset;

  const _EditPresetDialog({required this.preset});

  @override
  State<_EditPresetDialog> createState() => _EditPresetDialogState();
}

class _EditPresetDialogState extends State<_EditPresetDialog> {
  late TextEditingController _nameController;
  late TextEditingController _baseUrlController;
  late TextEditingController _baseDownloadUrlController;
  late TextEditingController _descController;

  InputDecoration _dialogInputDecoration(String label, {String? hint}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset.name);
    _baseUrlController = TextEditingController(text: widget.preset.baseUrl);
    _baseDownloadUrlController = TextEditingController(text: widget.preset.baseDownloadUrl);
    _descController = TextEditingController(text: widget.preset.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _baseDownloadUrlController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty ||
        _baseUrlController.text.trim().isEmpty ||
        _baseDownloadUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写完整的配置信息'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'baseUrl': _baseUrlController.text.trim(),
      'baseDownloadUrl': _baseDownloadUrlController.text.trim(),
      'description': _descController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.edit_rounded, color: colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          const Text(
            '编辑 API 配置预设',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '基础信息',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: _dialogInputDecoration('配置名称', hint: '例如: 生产环境'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseUrlController,
                  decoration: _dialogInputDecoration(
                    '基础 URL',
                    hint: '例如: https://alist.example.com',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseDownloadUrlController,
                  decoration: _dialogInputDecoration(
                    '下载 URL',
                    hint: '例如: https://alist.example.com/d',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descController,
                  decoration: _dialogInputDecoration('描述（可选）'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 保存预设对话框
class _SavePresetDialog extends StatefulWidget {
  final String baseUrl;
  final String baseDownloadUrl;

  const _SavePresetDialog({
    required this.baseUrl,
    required this.baseDownloadUrl,
  });

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descController;

  InputDecoration _dialogInputDecoration(String label, {String? hint}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入预设名称'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'baseUrl': widget.baseUrl,
      'baseDownloadUrl': widget.baseDownloadUrl,
      'description': _descController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.save_rounded, color: colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          const Text(
            '保存为 API 预设',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '填写名称与可选描述，方便快速识别。',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: _dialogInputDecoration('预设名称', hint: '例如: 内网服务器'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                decoration: _dialogInputDecoration('描述（可选）', hint: '例如: 仅限办公网络访问'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
