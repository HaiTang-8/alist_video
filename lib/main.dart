import 'dart:async';
import 'dart:io';

import 'package:alist_player/models/database_connection_config.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/views/index.dart';
import 'package:alist_player/apis/login.dart';
import 'package:alist_player/views/settings/database_api_settings.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';
import 'package:alist_player/utils/api_config_manager.dart';
import 'package:alist_player/utils/database_config_manager.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:toastification/toastification.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/config_server.dart';
import 'package:alist_player/utils/download_adapter.dart';
import 'package:alist_player/utils/logger.dart';
import 'package:alist_player/utils/font_helper.dart';
import 'package:timeago/timeago.dart' as timeago;

Future<void> main() async {
  // 通过自定义 Zone 捕获 print 输出，确保日志统一落盘
  final zoneFuture = runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      MediaKit.ensureInitialized();
      timeago.setLocaleMessages('zh', timeago.ZhMessages());
      timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());

      try {
        await AppLogger().initialize();
        _setupGlobalLogInterceptors();
        await AppLogger().info('App', 'Application starting...');
        await AppLogger().info('App', 'Platform: ${Platform.operatingSystem}');
      } catch (e, stack) {
        AppLogger().captureConsoleOutput(
          'Logger',
          '日志系统初始化失败: $e',
          level: LogLevel.fatal,
          error: e,
          stackTrace: stack,
        );
      }

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
      final driverTypeValue = prefs.getString(AppConstants.dbDriverTypeKey) ??
          AppConstants.defaultDbDriverType;
      final sqlitePath = prefs.getString(AppConstants.dbSqlitePathKey);
      final goBridgeUrl = prefs.getString(AppConstants.dbGoBridgeUrlKey);
      final goBridgeToken = prefs.getString(AppConstants.dbGoBridgeTokenKey);

      final dbConfig = DatabaseConnectionConfig(
        type: DatabasePersistenceTypeExtension.fromStorage(driverTypeValue),
        host: dbHost,
        port: dbPort,
        database: dbName,
        username: dbUser,
        password: dbPassword,
        sqlitePath: sqlitePath,
        goBridgeEndpoint: goBridgeUrl,
        goBridgeAuthToken: goBridgeToken,
      );

      try {
        await DatabaseHelper.instance.initWithConfig(dbConfig);
      } catch (e, stack) {
        await AppLogger().error('Database', '数据库初始化失败', e, stack);
      }

      final autoStartServer =
          prefs.getBool('auto_start_config_server') ?? false;
      if (autoStartServer) {
        try {
          await ConfigServer().start();
        } catch (e, stack) {
          await AppLogger().error('ConfigServer', '启动配置服务器失败', e, stack);
        }
      }

      try {
        await ApiConfigManager().initialize();
      } catch (e, stack) {
        await AppLogger().error('ApiConfigManager', 'API配置管理器初始化失败', e, stack);
      }

      try {
        await DatabaseConfigManager().initialize();
      } catch (e, stack) {
        await AppLogger().error(
          'DatabaseConfigManager',
          '数据库配置管理器初始化失败',
          e,
          stack,
        );
      }

      try {
        await DownloadAdapter().initialize();
      } catch (e, stack) {
        await AppLogger().error('DownloadAdapter', '下载管理器初始化失败', e, stack);
      }

      runApp(const MyApp());
    },
    (error, stackTrace) {
      AppLogger().captureConsoleOutput(
        'Zone',
        'Uncaught zone exception: $error',
        level: LogLevel.fatal,
        error: error,
        stackTrace: stackTrace,
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // 先落日志再委托到系统 print，确保调试控制台依旧可见
        AppLogger().captureConsoleOutput('print', line);
        parent.print(zone, line);
      },
    ),
  );

  await zoneFuture;
}

/// 注册全局日志拦截器，覆盖 debugPrint / FlutterError / 平台异常
void _setupGlobalLogInterceptors() {
  final originalDebugPrint = debugPrint;
  final FlutterExceptionHandler? originalFlutterError = FlutterError.onError;
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final originalDispatcherError = dispatcher.onError;

  // 通过拦截 debugPrint 同步写日志并回传给原始实现，兼顾控制台输出
  debugPrint = (String? message, {int? wrapWidth}) {
    final content = message ?? '';
    if (content.isEmpty) {
      return;
    }
    AppLogger().captureConsoleOutput(
      'debugPrint',
      content,
      level: LogLevel.debug,
    );
    originalDebugPrint(content, wrapWidth: wrapWidth);
  };

  // 保留原始 FlutterError 回调行为，避免影响 Flutter 自带红屏提示
  FlutterError.onError = (details) {
    AppLogger().captureConsoleOutput(
      'FlutterError',
      details.exceptionAsString(),
      level: LogLevel.error,
      error: details.exception,
      stackTrace: details.stack,
    );
    if (originalFlutterError != null) {
      originalFlutterError(details);
    } else {
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.empty,
      );
    }
  };

  // 平台异常同样同步到日志并尊重原始回调的处理结果
  dispatcher.onError = (error, stackTrace) {
    AppLogger().captureConsoleOutput(
      'PlatformDispatcher',
      'Uncaught platform error: $error',
      level: LogLevel.fatal,
      error: error,
      stackTrace: stackTrace,
    );
    if (originalDispatcherError != null) {
      return originalDispatcherError(error, stackTrace);
    }
    return true;
  };
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
          fontFamily: FontHelper.getPlatformFontFamily(),
          fontFamilyFallback: FontHelper.getPlatformFontFallback(),
          textTheme: FontHelper.getThemeTextTheme(),
          primaryTextTheme: const TextTheme().apply(
            fontFamily: FontHelper.getPlatformFontFamily(),
          ),
          primarySwatch: Colors.blue,
          primaryColor: const Color(0xFF2C68D5),
          brightness: Brightness.light,
          appBarTheme: FontHelper.getAppBarTheme(),
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
          await prefs.setInt(AppConstants.userRoleKey, userInfo.role);
          await prefs.setInt(
            AppConstants.userPermissionKey,
            userInfo.permission,
          );
        } catch (e, stack) {
          // 统一记录用户信息获取异常，方便排障
          await AppLogger().error(
            'Login',
            'Failed to fetch user info',
            e,
            stack,
          );
          await prefs.remove('base_path');
          await prefs.remove(AppConstants.userRoleKey);
          await prefs.remove(AppConstants.userPermissionKey);
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
    } catch (e, stack) {
      await AppLogger().error('Login', '登录接口调用失败', e, stack);
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
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
        ),
        child: Container(
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.3)),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            preset.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500),
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
                                      await _configManager
                                          .setCurrentPreset(newValue);
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
                                onPressed: () async {
                                  final hasChanged =
                                      await ApiPresetSettingsDialog.show(
                                          context);
                                  if (hasChanged == true) {
                                    // 如果配置有更改，重新初始化API配置
                                    await _initializeApiConfig();
                                  }
                                },
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
