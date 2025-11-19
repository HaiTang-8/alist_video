import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 描述 Go 代理相关的运行时配置，方便播放器、下载等模块统一判断是否需要代理。
class GoProxyConfig {
  final bool enableProxy;
  final DatabasePersistenceType driverType;
  final String endpoint;
  final String authToken;
  final bool usingBridgeEndpoint;

  const GoProxyConfig({
    required this.enableProxy,
    required this.driverType,
    required this.endpoint,
    required this.authToken,
    required this.usingBridgeEndpoint,
  });

  /// 只有在用户开启代理、当前持久化驱动为 Go 服务且配置了可访问的端点时才启用。
  bool get shouldUseProxy =>
      endpoint.isNotEmpty &&
      (!usingBridgeEndpoint ||
          driverType == DatabasePersistenceType.localGoBridge);

  /// 将原始播放/下载 URL 包装成 Go 服务提供的代理地址，并在查询参数中附带 access_token（如果存在）。
  String wrapUrl(String originalUrl) {
    if (!shouldUseProxy) {
      return originalUrl;
    }

    final sanitizedEndpoint = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final proxyUri = Uri.parse('$sanitizedEndpoint/proxy/media');
    final params = <String, String>{
      'target': originalUrl,
      if (authToken.isNotEmpty) 'access_token': authToken,
    };
    return proxyUri.replace(queryParameters: params).toString();
  }

  /// 返回需要附带到 HTTP 请求头的鉴权信息，播放器可通过 Media.httpHeaders 传递。
  Map<String, String>? buildAuthHeaders() {
    if (!shouldUseProxy || authToken.isEmpty || !usingBridgeEndpoint) {
      return null;
    }
    return {'Authorization': 'Bearer $authToken'};
  }
}

/// 统一的助手类，负责从 SharedPreferences 中加载 Go 代理配置。
class GoProxyHelper {
  const GoProxyHelper._();

  /// 读取用户偏好与数据库驱动信息，生成可供各模块使用的配置快照。
  static Future<GoProxyConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enableProxy = prefs.getBool(AppConstants.enableGoProxyKey) ??
        AppConstants.defaultEnableGoProxy;
    final driverTypeValue = prefs.getString(AppConstants.dbDriverTypeKey);
    final driverType =
        DatabasePersistenceTypeExtension.fromStorage(driverTypeValue);
    final customEndpoint =
        (prefs.getString(AppConstants.goProxyEndpointKey) ?? '').trim();
    final bridgeEndpoint = (prefs.getString(AppConstants.dbGoBridgeUrlKey) ??
            AppConstants.defaultGoBridgeEndpoint)
        .trim();
    final usingBridgeEndpoint =
        enableProxy && driverType == DatabasePersistenceType.localGoBridge;
    final endpoint = usingBridgeEndpoint ? bridgeEndpoint : customEndpoint;
    final authToken =
        (prefs.getString(AppConstants.dbGoBridgeTokenKey) ?? '').trim();

    return GoProxyConfig(
      enableProxy: enableProxy,
      driverType: driverType,
      endpoint: endpoint,
      authToken: usingBridgeEndpoint ? authToken : '',
      usingBridgeEndpoint: usingBridgeEndpoint,
    );
  }
}
