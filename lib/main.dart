import 'package:alist_player/apis/login.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/db.dart';
import 'package:alist_player/views/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_svg/svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:timeago/timeago.dart' as timeago;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 添加中文语言支持
  timeago.setLocaleMessages('zh', timeago.ZhMessages());
  timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());

  try {
    final db = DatabaseHelper.instance;
    await db.init(
      host: AppConstants.defaultDbHost,
      port: AppConstants.defaultDbPort,
      database: AppConstants.defaultDbName,
      username: AppConstants.defaultDbUser,
      password: AppConstants.defaultDbPassword,
    );

    // 测试连接
    await db.query('SELECT 1');
    print('Database connection test successful');
  } catch (e) {
    print('Database initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: MaterialApp(
        title: 'AList Video',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
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
            fontFamily: 'Microsoft YaHei',
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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString('saved_username');
    final savedPassword = prefs.getString('saved_password');
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (savedUsername != null && savedPassword != null && rememberMe) {
      setState(() {
        _usernameController.text = savedUsername;
        _passwordController.text = savedPassword;
        _rememberMe = rememberMe;
      });
      // Auto login if credentials are saved
      _login();
    }
  }

  Future<void> _login() async {
    var username = _usernameController.text;
    var password = _passwordController.text;

    var res = await LoginApi.login(username: username, password: password);

    if (res.code != 200) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: Text(res.message ?? '登录失败'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } else {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', res.data!.token!);

      // Save credentials if remember me is checked
      if (_rememberMe) {
        await prefs.setString('saved_username', username);
        await prefs.setString('saved_password', password);
        await prefs.setBool('remember_me', true);
      } else {
        // Clear saved credentials if remember me is unchecked
        await prefs.remove('saved_username');
        await prefs.remove('saved_password');
        await prefs.setBool('remember_me', false);
      }

      // 保存当前登录的用户名
      await prefs.setString('current_username', username);

      // 获取并保存 base_path
      try {
        final userInfo = await LoginApi.me();
        await prefs.setString('base_path', userInfo.basePath);
      } catch (e) {
        print('Failed to fetch user info: $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const IndexPage()),
        (route) => false,
      );
    }
  }

  void _clear() async {
    _usernameController.clear();
    _passwordController.clear();
    setState(() {
      _rememberMe = false;
    });
    // Clear saved credentials
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await prefs.setBool('remember_me', false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF2C68D5), // 主色调
                  Color(0xFF64B5F6), // 次色调
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24.0),
              margin: const EdgeInsets.symmetric(horizontal: 24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20.0,
                    spreadRadius: 5.0,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/images/logo.svg',
                        width: 32,
                        height: 32,
                      ),
                      const SizedBox(width: 8.0),
                      const Text(
                        '登录到 AList',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value!;
                          });
                        },
                      ),
                      const Text('记住账号'),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _clear,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: const Color(0xFF2C68D5),
                            padding: const EdgeInsets.all(15.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('清除'),
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C68D5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(15.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _login,
                          child: const Text('登录'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
