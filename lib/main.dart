import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/views/index.dart';
import 'package:alist_player/apis/login.dart';
import 'package:alist_player/views/settings/database_api_settings.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';
import 'package:alist_player/utils/api_config_manager.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:toastification/toastification.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/config_server.dart';
import 'package:alist_player/utils/download_adapter.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:timeago/timeago.dart' as timeago;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  timeago.setLocaleMessages('zh', timeago.ZhMessages());
  timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());

  // 初始化日志系统
  try {
    await AppLogger().initialize();
    await AppLogger().info('App', 'Application starting...');
    await AppLogger().info('App', 'Platform: ${Platform.operatingSystem}');
  } catch (e) {
    print('日志系统初始化失败: $e');
  }

  // 初始化数据库连接
  final prefs = await SharedPreferences.getInstance();
  final dbHost =
      prefs.getString(AppConstants.dbHostKey) ?? AppConstants.defaultDbHost;
  final dbName =
      prefs.getString(AppConstants.dbNameKey) ?? AppConstants.defaultDbName;
  final dbUser =
      prefs.getString(AppConstants.dbUserKey) ?? AppConstants.defaultDbUser;
  final dbPassword = prefs.getString(AppConstants.dbPasswordKey) ??
      AppConstants.defaultDbPassword;
  final dbPort =
      prefs.getInt(AppConstants.dbPortKey) ?? AppConstants.defaultDbPort;

  try {
    await DatabaseHelper.instance.init(
      host: dbHost,
      port: dbPort,
      database: dbName,
      username: dbUser,
      password: dbPassword,
    );
  } catch (e) {
    print('数据库初始化失败: $e');
  }

  // 尝试启动配置服务器（可选）
  final autoStartServer = prefs.getBool('auto_start_config_server') ?? false;
  if (autoStartServer) {
    try {
      await ConfigServer().start();
    } catch (e) {
      print('启动配置服务器失败: $e');
    }
  }

  // 初始化API配置管理器
  try {
    await ApiConfigManager().initialize();
  } catch (e) {
    print('API配置管理器初始化失败: $e');
  }

  // 初始化下载管理器
  try {
    await DownloadAdapter().initialize();
  } catch (e) {
    print('下载管理器初始化失败: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: MaterialApp(
        title: 'AList Player',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: Platform.isWindows ? "微软雅黑" : null,
          textTheme: const TextTheme(
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.25,
            ),
            bodySmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.4,
            ),
          ),
          primaryTextTheme: const TextTheme().apply(
            fontFamily: Platform.isWindows ? "微软雅黑" : null,
          ),
          primarySwatch: Colors.blue,
          primaryColor: const Color(0xFF2C68D5),
          brightness: Brightness.light,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF2C68D5),
            elevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Color(0xFF2C68D5),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            iconTheme: IconThemeData(
              color: Color(0xFF2C68D5),
            ),
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2C68D5)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: const Color(0xFF2C68D5),
              foregroundColor: Colors.white,
            ),
          ),
          iconTheme: const IconThemeData(
            color: Color(0xFF2C68D5),
            size: 24,
          ),
          dividerTheme: DividerThemeData(
            color: Colors.grey[200],
            thickness: 1,
            space: 1,
          ),
          scaffoldBackgroundColor: Colors.white,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2C68D5),
            secondary: Color(0xFF64B5F6),
            surface: Colors.white,
            error: Color(0xFFD32F2F),
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        home: const LoginPage(),
        builder: EasyLoading.init(),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // API配置预设相关
  final ApiConfigManager _configManager = ApiConfigManager();
  List<ApiConfigPreset> _apiPresets = [];
  ApiConfigPreset? _selectedPreset;
  bool _isCustomMode = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _initializeApiConfig();
  }

  /// 初始化API配置
  Future<void> _initializeApiConfig() async {
    await _configManager.initialize();
    final presets = await _configManager.getAllPresets();
    final currentPreset = await _configManager.getCurrentPreset();
    final isCustom = await _configManager.isCustomApiMode();

    if (mounted) {
      setState(() {
        _apiPresets = presets;
        _selectedPreset = currentPreset;
        _isCustomMode = isCustom;
      });
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        _usernameController.text = prefs.getString('username') ?? '';
        _passwordController.text = prefs.getString('password') ?? '';
        // 如果有保存的凭证，自动登录
        if (_usernameController.text.isNotEmpty &&
            _passwordController.text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _login();
          });
        }
      }
    });
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入用户名和密码'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await LoginApi.login(
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (res.code == 200) {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('username', _usernameController.text);
          await prefs.setString('password', _passwordController.text);
        } else {
          await prefs.remove('username');
          await prefs.remove('password');
        }
        await prefs.setBool('remember_me', _rememberMe);
        await prefs.setString('current_username', _usernameController.text);
        await prefs.setString('token', res.data!.token!);

        // 获取并保存 base_path
        try {
          final userInfo = await LoginApi.me();
          await prefs.setString('base_path', userInfo.basePath);
        } catch (e) {
          print('Failed to fetch user info: $e');
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const IndexPage()),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录失败：${res.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('登录失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
              Theme.of(context).primaryColor.withOpacity(0.6),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo and Title
                  const Icon(
                    Icons.play_circle_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AList Player',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Login Form
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '欢迎回来',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请登录您的账号',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Username TextField
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: '用户名',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Password TextField
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Remember Me Checkbox
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                            ),
                            const Text('记住我'),
                            const Spacer(),
                            TextButton(
                              onPressed: () {},
                              child: const Text('忘记密码？'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Login Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  '登录',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                        const SizedBox(height: 16),
                        // API配置预设选择器
                        if (_apiPresets.isNotEmpty && !_isCustomMode)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedPreset?.id,
                                hint: const Text('选择API配置'),
                                isExpanded: true,
                                items: _apiPresets.map((preset) {
                                  return DropdownMenuItem<String>(
                                    value: preset.id,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          preset.name,
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          preset.baseUrl,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) async {
                                  if (newValue != null) {
                                    await _configManager.setCurrentPreset(newValue);
                                    await _initializeApiConfig(); // 重新加载配置
                                  }
                                },
                              ),
                            ),
                          ),
                        if (_apiPresets.isNotEmpty && !_isCustomMode)
                          const SizedBox(height: 16),
                        // Settings Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  DatabaseSettingsDialog.show(context),
                              icon: const Icon(Icons.storage),
                              label: const Text('数据库设置'),
                            ),
                            const SizedBox(width: 16),
                            TextButton.icon(
                              onPressed: () => ApiPresetSettingsDialog.show(context),
                              icon: const Icon(Icons.api_rounded),
                              label: const Text('API 设置'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
