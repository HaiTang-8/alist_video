import 'dart:io';
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart';

import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/error_message_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/apis/login.dart';

/// api 请求工具类
class WooHttpUtil {
  static final WooHttpUtil _instance = WooHttpUtil._internal();
  factory WooHttpUtil() => _instance;

  late Dio _dio;
  // 添加一个初始化完成的标志
  bool _initialized = false;
  // 添加一个初始化完成的Future
  Future<void>? _initializationFuture;

  /// 单例初始
  WooHttpUtil._internal() {
    _initializationFuture = _initDio();
  }

  /// 打开日志文件夹
  static Future<void> openLogDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/alist_player/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      if (Platform.isWindows) {
        await Process.run('explorer', [logDir.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [logDir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [logDir.path]);
      }
    } catch (e) {
      EasyLoading.showError('打开日志文件夹失败: $e');
    }
  }

  /// 清除日志文件
  static Future<void> clearLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/alist_player/logs');
      if (await logDir.exists()) {
        await logDir.delete(recursive: true);
        EasyLoading.showSuccess('日志清除成功');
      }
    } catch (e) {
      EasyLoading.showError('清除日志失败: $e');
    }
  }

  Future<void> _initDio() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final baseUrl =
        prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;

    // header 头
    Map<String, String> headers = {
      AppConstants.contentType: AppConstants.applicationJson,
      AppConstants.accept: AppConstants.applicationJson,
      AppConstants.authorization: '${AppConstants.tokenPrefix} token',
      AppConstants.defaultLanguage: AppConstants.defaultLanguage
    };

    // 初始选项
    var options = BaseOptions(
      baseUrl: baseUrl,
      headers: headers,
      connectTimeout: AppConstants.apiConnectTimeout,
      receiveTimeout: AppConstants.apiReceiveTimeout,
      responseType: ResponseType.json,
    );

    // 初始 dio
    _dio = Dio(options);

    // 拦截器
    _dio.interceptors.add(RequestInterceptors());

    _initialized = true;
  }

  // 确保初始化完成的方法
  Future<Dio> _getDio() async {
    await _initializationFuture;
    return _dio;
  }

  /// get 请求
  Future<Response> get(
    String url, {
    Map<String, dynamic>? params,
    Options? options,
    CancelToken? cancelToken,
    String? baseUrl,
  }) async {
    final dio = await _getDio();
    Options requestOptions = options ?? Options();

    String? originalBaseUrl;
    if (baseUrl != null) {
      originalBaseUrl = dio.options.baseUrl;
      dio.options.baseUrl = baseUrl;
    }

    try {
      Response response = await dio.get(
        url,
        queryParameters: params,
        options: requestOptions,
        cancelToken: cancelToken,
      );
      return response;
    } finally {
      if (baseUrl != null && originalBaseUrl != null) {
        dio.options.baseUrl = originalBaseUrl;
      }
    }
  }

  /// post 请求
  Future<Response> post(
    String url, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    String? baseUrl,
  }) async {
    final dio = await _getDio();
    Options requestOptions = options ?? Options();

    String? originalBaseUrl;
    if (baseUrl != null) {
      originalBaseUrl = dio.options.baseUrl;
      dio.options.baseUrl = baseUrl;
    }

    try {
      Response response = await dio.post(
        url,
        data: data ?? {},
        options: requestOptions,
        cancelToken: cancelToken,
      );
      return response;
    } finally {
      if (baseUrl != null && originalBaseUrl != null) {
        dio.options.baseUrl = originalBaseUrl;
      }
    }
  }

  /// put 请求
  Future<Response> put(
    String url, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    var requestOptions = options ?? Options();
    Response response = await _dio.put(
      url,
      data: data ?? {},
      options: requestOptions,
      cancelToken: cancelToken,
    );
    return response;
  }

  /// delete 请求
  Future<Response> delete(
    String url, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    var requestOptions = options ?? Options();
    Response response = await _dio.delete(
      url,
      data: data ?? {},
      options: requestOptions,
      cancelToken: cancelToken,
    );
    return response;
  }

  // 更新 baseUrl 的方法
  Future<void> updateBaseUrl() async {
    final dio = await _getDio();
    final prefs = await SharedPreferences.getInstance();
    final baseUrl =
        prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;
    dio.options.baseUrl = baseUrl;
  }
}

/// 拦截
class RequestInterceptors extends Interceptor {
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // 添加重试登录方法
  Future<bool> _retryLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('saved_username') ?? '';
      final password = prefs.getString('saved_password') ?? '';

      if (username.isEmpty || password.isEmpty) {
        return false;
      }

      final response =
          await LoginApi.login(username: username, password: password);
      if (response.data?.token != null) {
        await prefs.setString('token', response.data!.token!);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 添加日志记录方法
  Future<void> _logRequest(String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/alist_player/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logFile = File('${logDir.path}/api_$today.log');

      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await logFile.writeAsString('[$timestamp] $content\n',
          mode: FileMode.append);
    } catch (e) {
      print('写入日志失败: $e');
    }
  }

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // 记录请求日志
    await _logRequest('REQUEST: ${options.method} ${options.uri}\n'
        'HEADERS: ${options.headers}\n'
        'DATA: ${options.data}');

    // 原有代码
    EasyLoading.show(status: '加载中...');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    options.headers['Authorization'] = '${prefs.get('token')}';
    return handler.next(options);
  }

  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    // 记录响应日志
    await _logRequest(
        'RESPONSE: ${response.statusCode} ${response.requestOptions.uri}\n'
        'DATA: ${response.data}');

    // 原有代码
    EasyLoading.dismiss();

    if (response.data['code'] == 401 && _retryCount < _maxRetries) {
      _retryCount++;
      if (await _retryLogin()) {
        // 重新发起原始请求
        final dio = Dio();
        try {
          final retryResponse = await dio.request(
            response.requestOptions.path,
            data: response.requestOptions.data,
            queryParameters: response.requestOptions.queryParameters,
            options: Options(
              method: response.requestOptions.method,
              headers: response.requestOptions.headers,
            ),
          );
          _retryCount = 0; // 重置计数
          return handler.next(retryResponse);
        } catch (e) {
          // 重试失败，继续处理401错误
        }
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        ),
        true,
      );
    } else {
      _retryCount = 0; // 重置计数
      handler.next(response);
    }
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    // 记录错误日志
    await _logRequest('ERROR: ${err.type} ${err.requestOptions.uri}\n'
        'MESSAGE: ${err.message}\n'
        'STACK: ${err.stackTrace}');

    // 原有代码保持不变
    EasyLoading.dismiss();

    final exception = HttpException(err.message ?? "error message");
    switch (err.type) {
      case DioExceptionType.badResponse:
        {
          final response = err.response;
          final errorMessage = ErrorMessageModel.fromJson(response?.data);
          switch (errorMessage.statusCode) {
            case 401:
              EasyLoading.showError('未登录或登录已过期');
              break;
            case 404:
              EasyLoading.showError('请求的资源不存在');
              break;
            case 500:
              EasyLoading.showError('服务器内部错误');
              break;
            case 502:
              EasyLoading.showError('网关错误');
              break;
            default:
              if (errorMessage.message != null) {
                EasyLoading.showError(errorMessage.message!);
              }
              break;
          }
        }
        break;
      case DioExceptionType.unknown:
        EasyLoading.showError('网络连接错误');
        break;
      case DioExceptionType.cancel:
        EasyLoading.showInfo('请求已取消');
        break;
      case DioExceptionType.connectionTimeout:
        EasyLoading.showError('连接超时');
        break;
      default:
        EasyLoading.showError('请求失败');
        break;
    }

    DioException errNext = err.copyWith(error: exception);
    handler.next(errNext);
  }
}
