import 'package:alist_player/models/proxy_metrics.dart';
import 'package:alist_player/utils/go_proxy_helper.dart';
import 'package:dio/dio.dart';

/// 读取 Go 代理的健康与性能指标，不需要用户手动触发测速。
class ProxyMetricsApi {
  const ProxyMetricsApi._();

  static Future<ProxyMetrics> fetch() async {
    final config = await GoProxyHelper.loadConfig();
    final endpoint = config.endpoint.trim();
    if (endpoint.isEmpty) {
      throw Exception('Go 服务地址为空，无法获取代理指标');
    }

    final url = endpoint.endsWith('/')
        ? '${endpoint}proxy/metrics'
        : '$endpoint/proxy/metrics';

    final options = BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    );
    final dio = Dio(options);
    if (config.authToken.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer ${config.authToken}';
    }

    final resp = await dio.get<Map<String, dynamic>>(url);
    final data = resp.data;
    if (data == null) {
      throw Exception('代理指标响应为空');
    }
    return ProxyMetrics.fromJson(data);
  }
}
