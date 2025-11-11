import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_config_preset.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:alist_player/utils/database_config_manager.dart';
import 'package:alist_player/utils/db.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  State<DatabasePresetSettingsDialog> createState() =>
      _DatabasePresetSettingsDialogState();
}

class _DatabasePresetSettingsDialogState
    extends State<DatabasePresetSettingsDialog> with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseConfigManager _configManager = DatabaseConfigManager();
  /// 局部化的 ScaffoldMessenger，确保桌面弹窗内也能展示 Snackbar
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

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
  final TextEditingController _sqlitePathController = TextEditingController();
  final TextEditingController _goEndpointController = TextEditingController();
  final TextEditingController _goTokenController = TextEditingController();
  DatabasePersistenceType _customDriverType =
      DatabasePersistenceType.remotePostgres;

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
      final host =
          prefs.getString(AppConstants.dbHostKey) ?? AppConstants.defaultDbHost;
      final port =
          prefs.getInt(AppConstants.dbPortKey) ?? AppConstants.defaultDbPort;
      final database =
          prefs.getString(AppConstants.dbNameKey) ?? AppConstants.defaultDbName;
      final username =
          prefs.getString(AppConstants.dbUserKey) ?? AppConstants.defaultDbUser;
      final password = prefs.getString(AppConstants.dbPasswordKey) ??
          AppConstants.defaultDbPassword;
      final enableSqlLogging =
          prefs.getBool(AppConstants.enableSqlLoggingKey) ??
              AppConstants.defaultEnableSqlLogging;
      final driverTypeValue = prefs.getString(AppConstants.dbDriverTypeKey) ??
          AppConstants.defaultDbDriverType;
      final sqlitePath = prefs.getString(AppConstants.dbSqlitePathKey) ?? '';
      final goEndpoint = prefs.getString(AppConstants.dbGoBridgeUrlKey) ?? '';
      final goToken = prefs.getString(AppConstants.dbGoBridgeTokenKey) ?? '';

      setState(() {
        _presets = presets;
        _selectedPreset = currentPreset;
        _hostController.text = host;
        _portController.text = port.toString();
        _databaseController.text = database;
        _usernameController.text = username;
        _passwordController.text = password;
        _sqlitePathController.text = sqlitePath;
        _goEndpointController.text = goEndpoint;
        _goTokenController.text = goToken;
        _customDriverType =
            DatabasePersistenceTypeExtension.fromStorage(driverTypeValue);
        _enableSqlLogging = enableSqlLogging;
        _isLoadingPresets = false;

        // 根据模式设置初始标签页
        _tabController.index = isCustom ? 1 : 0;
      });
    } catch (e) {
      setState(() {
        _isLoadingPresets = false;
      });
      _showSnackBar(
        SnackBar(
          content: Text('加载配置失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 统一封装 Snackbar 展示，防止桌面弹窗的提示出现在外层 Scaffold
  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(snackBar);
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
        _validateCustomInputs();
        final preset = _composePreset(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          name: '自定义配置',
          driverType: _customDriverType,
          host: _hostController.text,
          portText: _portController.text,
          database: _databaseController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          sqlitePath: _sqlitePathController.text,
          goEndpoint: _goEndpointController.text,
          goToken: _goTokenController.text,
        );

        final connectionSuccess = await _configManager.testConnection(preset);
        if (!connectionSuccess) {
          throw Exception('持久化连接测试失败，请检查配置');
        }

        await _persistActiveConfig(preset);
        await _configManager.setCustomDbMode(true);

        await DatabaseHelper.instance.close();
        await DatabaseHelper.instance.initWithConfig(
          preset.toConnectionConfig(),
        );
      }

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar(
          const SnackBar(
            content: Text('数据库配置已保存'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
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
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactTextField(
                controller: nameController,
                label: '预设名称',
                icon: Icons.label_rounded,
                hint: '例如：本地SQLite',
              ),
              const SizedBox(height: 12),
              _buildCompactTextField(
                controller: descController,
                label: '描述（可选）',
                icon: Icons.short_text_rounded,
                hint: '输入预设描述',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '将复用当前自定义配置 (${_customDriverType.displayName})',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == true) {
      final presetName = nameController.text.trim();
      if (presetName.isEmpty) {
        if (mounted) {
          _showSnackBar(
            const SnackBar(
              content: Text('请填写预设名称'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 本地SQLite配置只能保留一个，先做前置校验避免无意义的持久化操作
      if (_customDriverType == DatabasePersistenceType.localSqlite) {
        final hasSqlitePreset =
            await _configManager.hasLocalSqlitePreset();
        if (hasSqlitePreset) {
          if (mounted) {
            _showSnackBar(
              const SnackBar(
                content: Text('已存在本地SQLite预设，请先删除后再创建新的本地SQLite配置'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      final preset = _composePreset(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: presetName,
        driverType: _customDriverType,
        host: _hostController.text,
        portText: _portController.text,
        database: _databaseController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        sqlitePath: _sqlitePathController.text,
        goEndpoint: _goEndpointController.text,
        goToken: _goTokenController.text,
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );

      final success = await _configManager.savePreset(preset);
      if (!success) {
        if (mounted) {
          _showSnackBar(
            const SnackBar(
              content: Text('保存预设失败，请稍后重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final connectionOk = await _configManager.testConnection(preset);
      if (!connectionOk && mounted) {
        _showSnackBar(
          const SnackBar(
            content: Text('预设保存成功，但连接测试失败'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('预设 "$presetName" 保存成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    }
  }

  /// 保存SQL日志设置
  Future<void> _saveSqlLoggingSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.enableSqlLoggingKey, _enableSqlLogging);

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(_enableSqlLogging ? 'SQL日志已启用' : 'SQL日志已禁用'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('保存设置失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 根据不同输入构建通用的数据库预设对象，方便多处复用
  DatabaseConfigPreset _composePreset({
    required String id,
    required String name,
    required DatabasePersistenceType driverType,
    required String host,
    required String portText,
    required String database,
    required String username,
    required String password,
    required String sqlitePath,
    required String goEndpoint,
    required String goToken,
    DateTime? createdAt,
    bool isDefault = false,
    String? description,
  }) {
    final parsedPort = int.tryParse(portText.trim());
    final resolvedPort =
        parsedPort == null || parsedPort <= 0 || parsedPort > 65535
            ? AppConstants.defaultDbPort
            : parsedPort;
    return DatabaseConfigPreset(
      id: id,
      name: name,
      driverType: driverType,
      host: host.trim().isEmpty ? AppConstants.defaultDbHost : host.trim(),
      port: resolvedPort,
      database: database.trim().isEmpty
          ? AppConstants.defaultDbName
          : database.trim(),
      username: username.trim().isEmpty
          ? AppConstants.defaultDbUser
          : username.trim(),
      password: password.trim().isEmpty
          ? AppConstants.defaultDbPassword
          : password.trim(),
      sqlitePath: sqlitePath.trim().isEmpty ? null : sqlitePath.trim(),
      goBridgeEndpoint: goEndpoint.trim().isEmpty ? null : goEndpoint.trim(),
      goBridgeAuthToken: goToken.trim().isEmpty ? null : goToken.trim(),
      createdAt: createdAt ?? DateTime.now(),
      isDefault: isDefault,
      description: description,
    );
  }

  /// 将当前自定义配置落地到 SharedPreferences，确保跨端一致
  Future<void> _persistActiveConfig(DatabaseConfigPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.dbDriverTypeKey,
      preset.driverType.storageValue,
    );
    await prefs.setString(AppConstants.dbHostKey, preset.host);
    await prefs.setInt(AppConstants.dbPortKey, preset.port);
    await prefs.setString(AppConstants.dbNameKey, preset.database);
    await prefs.setString(AppConstants.dbUserKey, preset.username);
    await prefs.setString(AppConstants.dbPasswordKey, preset.password);

    if (preset.sqlitePath != null) {
      await prefs.setString(AppConstants.dbSqlitePathKey, preset.sqlitePath!);
    } else {
      await prefs.remove(AppConstants.dbSqlitePathKey);
    }

    if (preset.goBridgeEndpoint != null) {
      await prefs.setString(
        AppConstants.dbGoBridgeUrlKey,
        preset.goBridgeEndpoint!,
      );
    } else {
      await prefs.remove(AppConstants.dbGoBridgeUrlKey);
    }

    if (preset.goBridgeAuthToken != null) {
      await prefs.setString(
        AppConstants.dbGoBridgeTokenKey,
        preset.goBridgeAuthToken!,
      );
    } else {
      await prefs.remove(AppConstants.dbGoBridgeTokenKey);
    }
  }

  /// 针对不同驱动做输入合法性校验，提前给出可读错误
  void _validateCustomInputs() {
    switch (_customDriverType) {
      case DatabasePersistenceType.remotePostgres:
        if (_hostController.text.trim().isEmpty ||
            _databaseController.text.trim().isEmpty ||
            _usernameController.text.trim().isEmpty ||
            _passwordController.text.trim().isEmpty) {
          throw Exception('请完善远程数据库的主机、数据库、用户名与密码');
        }
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port <= 0 || port > 65535) {
          throw Exception('请输入有效的端口号 (1-65535)');
        }
        break;
      case DatabasePersistenceType.localSqlite:
        // SQLite 允许留空路径，驱动会在内部回落到默认目录
        break;
      case DatabasePersistenceType.localGoBridge:
        if (_goEndpointController.text.trim().isEmpty) {
          throw Exception('请填写本地 Go 服务的访问地址');
        }
        break;
    }
  }

  /// 自定义模式的持久化方式选择器
  Widget _buildDriverTypeSelector() {
    return DropdownButtonFormField<DatabasePersistenceType>(
      value: _customDriverType,
      decoration: InputDecoration(
        labelText: '持久化方式',
        prefixIcon: Icon(_customDriverType.icon, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: DatabasePersistenceType.values
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(type.displayName),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _customDriverType = value;
        });
      },
    );
  }

  /// 远程PostgreSQL专用字段集合
  Widget _buildRemoteConfigFields() {
    return Column(
      children: [
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
        _buildCompactTextField(
          controller: _passwordController,
          label: '密码',
          icon: Icons.lock_rounded,
          hint: '请输入数据库密码',
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),
      ],
    );
  }

  /// 本地SQLite字段集合
  Widget _buildSqliteConfigFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCompactTextField(
          controller: _sqlitePathController,
          label: 'SQLite 文件路径',
          icon: Icons.folder_open_rounded,
          hint: '留空将使用默认应用目录/${AppConstants.defaultSqliteFilename}',
        ),
        const SizedBox(height: 8),
        Text(
          '跨端会自动创建数据文件，桌面端可指向任意目录便于手动备份。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Go 本地服务字段集合
  Widget _buildGoBridgeConfigFields() {
    return Column(
      children: [
        _buildCompactTextField(
          controller: _goEndpointController,
          label: 'Go 服务地址',
          icon: Icons.http_rounded,
          hint: 'http://127.0.0.1:7788',
        ),
        const SizedBox(height: 12),
        _buildCompactTextField(
          controller: _goTokenController,
          label: '访问令牌 (可选)',
          icon: Icons.vpn_key_rounded,
          hint: '用于与本地Go进程安全通信',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final layout = isMobile
        ? _buildMobileLayout(context)
        : _buildDesktopLayout(context);

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: layout,
    );
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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
              unselectedLabelColor:
                  Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Card(
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
                  const Icon(Icons.storage_rounded,
                      color: Colors.white, size: 20),
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
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
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
                unselectedLabelColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                        : const Text(
                            '保存',
                            style: TextStyle(fontWeight: FontWeight.w600),
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
                          : Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
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
                                          color: Colors.amber
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(6),
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
                                  preset.driverType.displayName,
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset.connectionString,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (preset.description != null &&
                                    preset.description!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    preset.description!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1),
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
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.1),
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
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDriverTypeSelector(),
                    const SizedBox(height: 12),
                    if (_customDriverType ==
                        DatabasePersistenceType.remotePostgres)
                      _buildRemoteConfigFields()
                    else if (_customDriverType ==
                        DatabasePersistenceType.localSqlite)
                      _buildSqliteConfigFields()
                    else
                      _buildGoBridgeConfigFields(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 紧凑的提示信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
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
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    final sqlitePathController =
        TextEditingController(text: preset.sqlitePath ?? '');
    final goEndpointController =
        TextEditingController(text: preset.goBridgeEndpoint ?? '');
    final goTokenController =
        TextEditingController(text: preset.goBridgeAuthToken ?? '');
    final descController =
        TextEditingController(text: preset.description ?? '');
    final dialogControllers = <TextEditingController>[
      nameController,
      hostController,
      portController,
      databaseController,
      usernameController,
      passwordController,
      sqlitePathController,
      goEndpointController,
      goTokenController,
      descController,
    ];
    bool obscurePassword = true;
    var dialogDriverType = preset.driverType;

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
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompactTextField(
                    controller: nameController,
                    label: '预设名称',
                    icon: Icons.label_outline,
                    hint: '输入预设名称',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DatabasePersistenceType>(
                    value: dialogDriverType,
                    decoration: InputDecoration(
                      labelText: '持久化方式',
                      prefixIcon: Icon(dialogDriverType.icon, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: DatabasePersistenceType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        dialogDriverType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (dialogDriverType ==
                      DatabasePersistenceType.remotePostgres) ...[
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
                    _buildCompactTextField(
                      controller: passwordController,
                      label: '密码',
                      icon: Icons.lock_rounded,
                      hint: '请输入数据库密码',
                      obscureText: obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                  ] else if (dialogDriverType ==
                      DatabasePersistenceType.localSqlite) ...[
                    _buildCompactTextField(
                      controller: sqlitePathController,
                      label: 'SQLite 文件路径',
                      icon: Icons.folder_open_rounded,
                      hint: '留空使用默认路径',
                    ),
                  ] else ...[
                    _buildCompactTextField(
                      controller: goEndpointController,
                      label: 'Go 服务地址',
                      icon: Icons.http_rounded,
                      hint: 'http://127.0.0.1:7788',
                    ),
                    const SizedBox(height: 12),
                    _buildCompactTextField(
                      controller: goTokenController,
                      label: '访问令牌 (可选)',
                      icon: Icons.vpn_key_rounded,
                      hint: '如需鉴权可填写',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildCompactTextField(
                    controller: descController,
                    label: '描述（可选）',
                    icon: Icons.short_text_rounded,
                    hint: '输入描述信息',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存变更'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final allPresets = await _configManager.getAllPresets();
        final nameExists = allPresets.any(
          (p) => p.id != preset.id && p.name == nameController.text.trim(),
        );
        if (nameExists) {
          throw Exception('已存在同名的配置预设');
        }

        final updatedPreset = _composePreset(
          id: preset.id,
          name: nameController.text.trim(),
          driverType: dialogDriverType,
          host: hostController.text,
          portText: portController.text,
          database: databaseController.text,
          username: usernameController.text,
          password: passwordController.text,
          sqlitePath: sqlitePathController.text,
          goEndpoint: goEndpointController.text,
          goToken: goTokenController.text,
          createdAt: preset.createdAt,
          isDefault: preset.isDefault,
          description: descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
        );

        // 编辑为本地SQLite时也需要保证全局唯一
        if (dialogDriverType == DatabasePersistenceType.localSqlite) {
          final hasOtherSqlite = await _configManager.hasLocalSqlitePreset(
            excludePresetId: preset.id,
          );
          if (hasOtherSqlite) {
            if (mounted) {
              _showSnackBar(
                const SnackBar(
                  content: Text('本地SQLite预设只能存在一个，请先删除其他本地SQLite配置'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        }

        final success = await _configManager.savePreset(updatedPreset);
        if (success) {
          await _loadData();
          if (mounted) {
            _showSnackBar(
              const SnackBar(
                content: Text('预设更新成功'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          _showSnackBar(
            SnackBar(
              content: Text('更新预设失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in dialogControllers) {
        controller.dispose();
      }
    });
  }

  /// 删除预设
  Future<void> _deletePreset(DatabaseConfigPreset preset) async {
    if (preset.isDefault) {
      _showSnackBar(
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
          _showSnackBar(
            const SnackBar(
              content: Text('预设删除成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          _showSnackBar(
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
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
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
    _sqlitePathController.dispose();
    _goEndpointController.dispose();
    _goTokenController.dispose();
    super.dispose();
  }
}
