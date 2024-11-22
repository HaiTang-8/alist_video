import 'dart:io';

import 'package:alist_player/models/error_message_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String APPLICATION_JSON = "application/json";
const String CONTENT_TYPE = "content-type";
const String ACCEPT = "accept";
const String AUTHORIZATION = "authorization";
const String DEFAULT_LANGUAGE = "en";
const String TOKEN = "Bearer token";
const String BASE_URL = "https://alist.tt1.top";

/// api 请求工具类
class WooHttpUtil {
  static final WooHttpUtil _instance = WooHttpUtil._internal();
  factory WooHttpUtil() => _instance;

  late Dio _dio;

  /// 单例初始
  WooHttpUtil._internal() {
    // header 头
    Map<String, String> headers = {
      CONTENT_TYPE: APPLICATION_JSON,
      ACCEPT: APPLICATION_JSON,
      AUTHORIZATION: TOKEN,
      DEFAULT_LANGUAGE: DEFAULT_LANGUAGE
    };

    // 初始选项
    var options = BaseOptions(
      baseUrl: BASE_URL,
      headers: headers,
      connectTimeout: const Duration(seconds: 5), // 5秒
      receiveTimeout: const Duration(seconds: 3), // 3秒
      responseType: ResponseType.json,
    );

    // 初始 dio
    _dio = Dio(options);

    // 拦截器 - 日志打印
    // if (!kReleaseMode) {
    //   _dio.interceptors.add(PrettyDioLogger(
    //     requestHeader: true,
    //     requestBody: true,
    //     responseHeader: true,
    //   ));
    // }

    // 拦截器
    _dio.interceptors.add(RequestInterceptors());
  }

  /// get 请求
  Future<Response> get(
    String url, {
    Map<String, dynamic>? params,
    Options? options,
    CancelToken? cancelToken,
    String? baseUrl,
  }) async {
    Options requestOptions = options ?? Options();

    // If baseUrl is provided, temporarily update dio's baseUrl
    String? originalBaseUrl;
    if (baseUrl != null) {
      originalBaseUrl = _dio.options.baseUrl;
      _dio.options.baseUrl = baseUrl;
    }

    try {
      Response response = await _dio.get(
        url,
        queryParameters: params,
        options: requestOptions,
        cancelToken: cancelToken,
      );
      return response;
    } finally {
      // Restore original baseUrl if it was changed
      if (baseUrl != null && originalBaseUrl != null) {
        _dio.options.baseUrl = originalBaseUrl;
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
    var requestOptions = options ?? Options();

    // If baseUrl is provided, temporarily update dio's baseUrl
    String? originalBaseUrl;
    if (baseUrl != null) {
      originalBaseUrl = _dio.options.baseUrl;
      _dio.options.baseUrl = baseUrl;
    }

    try {
      Response response = await _dio.post(
        url,
        data: data ?? {},
        options: requestOptions,
        cancelToken: cancelToken,
      );
      return response;
    } finally {
      // Restore original baseUrl if it was changed
      if (baseUrl != null && originalBaseUrl != null) {
        _dio.options.baseUrl = originalBaseUrl;
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
}

/// 拦截
class RequestInterceptors extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    EasyLoading.show(status: '加载中...');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    options.headers['Authorization'] = '${prefs.get('token')}';
    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    EasyLoading.dismiss();

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
      handler.next(response);
    }
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
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
