import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_config_preset.dart';
import 'package:alist_player/utils/database_config_manager.dart';
import 'package:alist_player/utils/db.dart';

class DatabasePresetSettingsDialog extends StatefulWidget {
  const DatabasePresetSettingsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    if (isMobile) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const DatabasePresetSettingsDialog(),
          fullscreenDialog: true,
        ),
      );
    } else {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: const RoundedRectangleBorder(),
          insetPadding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 700,
              maxHeight: 650,
            ),
            child: const DatabasePresetSettingsDialog(),
          ),
        ),
      );
    }
  }

  @override
  State<DatabasePresetSettingsDialog> createState() => _DatabasePresetSettingsDialogState();
}

class _DatabasePresetSettingsDialogState extends State<DatabasePresetSettingsDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseConfigManager _configManager = DatabaseConfigManager();
  
  // 预设相关
  List<DatabaseConfigPreset> _presets = [];
  DatabaseConfigPreset? _selectedPreset;
  bool _isLoadingPresets = true;
  
  // 自定义配置控制器
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _databaseController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _enableSqlLogging = AppConstants.defaultEnableSqlLogging;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  /// 加载数据
  Future<void> _loadData() async {
    try {
      // 加载配置预设
      final presets = await _configManager.getAllPresets();
      final currentPreset = await _configManager.getCurrentPreset();
      final isCustom = await _configManager.isCustomDbMode();
      
      // 加载当前设置
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(AppConstants.dbHostKey) ?? AppConstants.defaultDbHost;
      final port = prefs.getInt(AppConstants.dbPortKey) ?? AppConstants.defaultDbPort;
      final database = prefs.getString(AppConstants.dbNameKey) ?? AppConstants.defaultDbName;
      final username = prefs.getString(AppConstants.dbUserKey) ?? AppConstants.defaultDbUser;
      final password = prefs.getString(AppConstants.dbPasswordKey) ?? AppConstants.defaultDbPassword;
      final enableSqlLogging = prefs.getBool(AppConstants.enableSqlLoggingKey) ?? AppConstants.defaultEnableSqlLogging;

      setState(() {
        _presets = presets;
        _selectedPreset = currentPreset;
        _hostController.text = host;
        _portController.text = port.toString();
        _databaseController.text = database;
        _usernameController.text = username;
        _passwordController.text = password;
        _enableSqlLogging = enableSqlLogging;
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

  /// 保存配置
  Future<void> _saveConfig() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (_tabController.index == 0) {
        // 预设模式
        if (_selectedPreset != null) {
          await _configManager.setCurrentPreset(_selectedPreset!.id);
          await _configManager.setCustomDbMode(false);
        }
      } else {
        // 自定义模式
        if (_hostController.text.trim().isEmpty || 
            _portController.text.trim().isEmpty ||
            _databaseController.text.trim().isEmpty ||
            _usernameController.text.trim().isEmpty ||
            _passwordController.text.trim().isEmpty) {
          throw Exception('请填写完整的数据库配置信息');
        }
        
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port <= 0 || port > 65535) {
          throw Exception('请输入有效的端口号 (1-65535)');
        }
        
        // 测试连接
        final tempPreset = DatabaseConfigPreset.createDefault(
          name: '临时配置',
          host: _hostController.text.trim(),
          port: port,
          database: _databaseController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        final connectionSuccess = await _configManager.testConnection(tempPreset);
        if (!connectionSuccess) {
          throw Exception('数据库连接测试失败，请检查配置信息');
        }
        
        // 保存自定义配置
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.setString(AppConstants.dbHostKey, _hostController.text.trim()),
          prefs.setInt(AppConstants.dbPortKey, port),
          prefs.setString(AppConstants.dbNameKey, _databaseController.text.trim()),
          prefs.setString(AppConstants.dbUserKey, _usernameController.text.trim()),
          prefs.setString(AppConstants.dbPasswordKey, _passwordController.text.trim()),
        ]);
        
        await _configManager.setCustomDbMode(true);

        // 重新初始化数据库连接
        await DatabaseHelper.instance.close();
        await DatabaseHelper.instance.init(
          host: _hostController.text.trim(),
          port: port,
          database: _databaseController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据库配置已保存'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存配置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 保存当前配置为预设
  Future<void> _saveAsPreset() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              '保存为预设',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '预设名称',
                  hintText: '输入预设名称',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: '描述（可选）',
                  hintText: '输入预设描述',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port <= 0 || port > 65535) {
          throw Exception('请输入有效的端口号');
        }
        
        final preset = DatabaseConfigPreset.createDefault(
          name: nameController.text.trim(),
          host: _hostController.text.trim(),
          port: port,
          database: _databaseController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
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

  /// 保存SQL日志设置
  Future<void> _saveSqlLoggingSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.enableSqlLoggingKey, _enableSqlLogging);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_enableSqlLogging ? 'SQL日志已启用' : 'SQL日志已禁用'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存设置失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return isMobile ? _buildMobileLayout(context) : _buildDesktopLayout(context);
  }

  /// 构建移动端布局
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        toolbarHeight: 56,
        title: const Text(
          '数据库设置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _saveConfig,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 紧凑的标签栏
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: '预设配置'),
                Tab(text: '自定义配置'),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPresetTab(context, true),
                _buildCustomTab(context, true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建桌面端布局
  Widget _buildDesktopLayout(BuildContext context) {
    return Card(
      elevation: 8,
      shape: const RoundedRectangleBorder(),
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 紧凑的标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Row(
              children: [
                const Icon(Icons.storage_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '数据库设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // 紧凑的标签栏
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(6),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: '预设配置'),
                Tab(text: '自定义配置'),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPresetTab(context, false),
                _buildCustomTab(context, false),
              ],
            ),
          ),
          // 紧凑的底部按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(64, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(64, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建预设配置标签页
  Widget _buildPresetTab(BuildContext context, bool isMobile) {
    if (_isLoadingPresets) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('加载配置中...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
      child: _presets.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              itemCount: _presets.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final preset = _presets[index];
                final isSelected = _selectedPreset?.id == preset.id;

                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  color: isSelected
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
                      : Theme.of(context).colorScheme.surface,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPreset = preset;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // 选择指示器
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).colorScheme.outline,
                                width: 2,
                              ),
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          // 配置信息
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        preset.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (preset.isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.star,
                                              size: 10,
                                              color: Colors.amber,
                                            ),
                                            SizedBox(width: 2),
                                            Text(
                                              '默认',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset.connectionString,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (preset.description != null && preset.description!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    preset.description!,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 操作按钮
                          if (!preset.isDefault) ...[
                            IconButton(
                              onPressed: () => _editPreset(preset),
                              icon: Icon(
                                Icons.edit_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 18,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => _deletePreset(preset),
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 18,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// 构建自定义配置标签页
  Widget _buildCustomTab(BuildContext context, bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 紧凑的标题行
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '数据库连接配置',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saveAsPreset,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('保存为预设'),
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 紧凑的配置表单
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 主机地址和端口一行
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildCompactTextField(
                            controller: _hostController,
                            label: '主机地址',
                            icon: Icons.dns_rounded,
                            hint: 'localhost',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildCompactTextField(
                            controller: _portController,
                            label: '端口',
                            icon: Icons.settings_ethernet_rounded,
                            hint: '5432',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 数据库名和用户名一行
                    Row(
                      children: [
                        Expanded(
                          child: _buildCompactTextField(
                            controller: _databaseController,
                            label: '数据库名',
                            icon: Icons.storage_rounded,
                            hint: 'alist_video',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCompactTextField(
                            controller: _usernameController,
                            label: '用户名',
                            icon: Icons.person_rounded,
                            hint: 'postgres',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 密码单独一行
                    _buildCompactTextField(
                      controller: _passwordController,
                      label: '密码',
                      icon: Icons.lock_rounded,
                      hint: '请输入数据库密码',
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 紧凑的提示信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '保存时将自动测试数据库连接',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 紧凑的SQL日志设置
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.bug_report_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'SQL日志',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _enableSqlLogging,
                      onChanged: (bool value) {
                        setState(() {
                          _enableSqlLogging = value;
                        });
                        _saveSqlLoggingSetting();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑预设
  Future<void> _editPreset(DatabaseConfigPreset preset) async {
    final nameController = TextEditingController(text: preset.name);
    final hostController = TextEditingController(text: preset.host);
    final portController = TextEditingController(text: preset.port.toString());
    final databaseController = TextEditingController(text: preset.database);
    final usernameController = TextEditingController(text: preset.username);
    final passwordController = TextEditingController(text: preset.password);
    final descController = TextEditingController(text: preset.description ?? '');
    final dialogControllers = <TextEditingController>[
      nameController,
      hostController,
      portController,
      databaseController,
      usernameController,
      passwordController,
      descController,
    ];
    bool obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          contentPadding: const EdgeInsets.all(20),
          title: Row(
            children: [
              Icon(
                Icons.edit_outlined,
                color: Theme.of(context).primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                '编辑预设',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 预设名称
                  _buildCompactTextField(
                    controller: nameController,
                    label: '预设名称',
                    icon: Icons.label_outline,
                    hint: '输入预设名称',
                  ),
                  const SizedBox(height: 12),
                  // 主机地址和端口一行
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildCompactTextField(
                          controller: hostController,
                          label: '主机地址',
                          icon: Icons.dns_rounded,
                          hint: 'localhost',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _buildCompactTextField(
                          controller: portController,
                          label: '端口',
                          icon: Icons.settings_ethernet_rounded,
                          hint: '5432',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 数据库名和用户名一行
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactTextField(
                          controller: databaseController,
                          label: '数据库名',
                          icon: Icons.storage_rounded,
                          hint: 'alist_video',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCompactTextField(
                          controller: usernameController,
                          label: '用户名',
                          icon: Icons.person_rounded,
                          hint: 'postgres',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 密码单独一行
                  _buildCompactTextField(
                    controller: passwordController,
                    label: '密码',
                    icon: Icons.lock_rounded,
                    hint: '请输入数据库密码',
                    obscureText: obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 描述
                  _buildCompactTextField(
                    controller: descController,
                    label: '描述（可选）',
                    icon: Icons.description_outlined,
                    hint: '输入预设描述',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final port = int.tryParse(portController.text.trim());
        if (port == null || port <= 0 || port > 65535) {
          throw Exception('请输入有效的端口号');
        }

        // 检查名称是否与其他预设重复（排除自己）
        final allPresets = await _configManager.getAllPresets();
        final nameExists = allPresets.any((p) => p.id != preset.id && p.name == nameController.text.trim());
        if (nameExists) {
          throw Exception('已存在同名的配置预设');
        }

        // 创建更新后的预设，保持原有的ID和创建时间
        final updatedPreset = DatabaseConfigPreset(
          id: preset.id,
          name: nameController.text.trim(),
          host: hostController.text.trim(),
          port: port,
          database: databaseController.text.trim(),
          username: usernameController.text.trim(),
          password: passwordController.text.trim(),
          createdAt: preset.createdAt,
          isDefault: preset.isDefault,
          description: descController.text.trim().isEmpty ? null : descController.text.trim(),
        );

        final success = await _configManager.savePreset(updatedPreset);
        if (success) {
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

    // 清理控制器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 延迟释放控制器，确保对话框在所有平台的关闭动画完成时不再引用已释放的控制器，避免触发 dispose 后使用的异常。
      for (final controller in dialogControllers) {
        controller.dispose();
      }
    });
  }

  /// 删除预设
  Future<void> _deletePreset(DatabaseConfigPreset preset) async {
    if (preset.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('默认配置不能删除'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '确认删除',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要删除预设配置吗？'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bookmark_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此操作无法撤销',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (result == true) {
      final success = await _configManager.deletePreset(preset.id);
      if (success) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('预设删除成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('删除预设失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无预设配置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在自定义配置中创建您的第一个预设',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建紧凑的文本输入框，兼顾桌面端与移动端的紧凑排版需求
  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    int? maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines ?? 1,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 1.5,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }


  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
