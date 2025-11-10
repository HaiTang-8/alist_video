import 'package:alist_player/models/fs_resp/content.dart';
import 'package:alist_player/models/fs_resp/fs_resp.dart';
import 'package:alist_player/utils/woo_http.dart';

class FsApi {
  static const int _twoMegabytes = 2 * 1024 * 1024;

  // 统一过滤掉“更多电视剧集”伪文件，避免任意页面重复实现相同逻辑
  static FsResp _filterPseudoSeriesFiles(FsResp resp) {
    final data = resp.data;
    final items = data?.content;
    if (data == null || items == null) {
      return resp;
    }

    bool _shouldRemove(Content entry) {
      final name = entry.name ?? '';
      final size = entry.size ?? 0;
      final type = entry.type ?? 0;
      return type == 2 && size < _twoMegabytes && name.contains('更多电视剧集');
    }

    data.content = items.where((entry) => !_shouldRemove(entry)).toList();
    return resp;
  }

  static Future<FsResp> list({
    required String path,
    required String password,
    required int page,
    required int perPage,
    required bool refresh,
  }) async {
    var res = await WooHttpUtil().post('/api/fs/list', data: {
      'path': path,
      'password': password,
      'page': page,
      'per_page': perPage,
      'refresh': refresh,
    });
    final resp = FsResp.fromJson(res.data);
    return _filterPseudoSeriesFiles(resp);
  }

  static Future<FsGetResponse> get({
    required String path,
    String password = '',
  }) async {
    var res = await WooHttpUtil().post('/api/fs/get', data: {
      'path': path,
      'password': password,
    });
    return FsGetResponse.fromJson(res.data);
  }

  static Future<FsResp> search({
    required String keyword,
    required String parent,
    required int scope,
    required int page,
    required int per_page,
    required String password,
  }) async {
    var res = await WooHttpUtil().post('/api/fs/search', data: {
      'keywords': keyword,
      'parent': parent,
      'scope': scope,
      'page': page,
      'per_page': per_page,
      'password': password,
    });
    final resp = FsResp.fromJson(res.data);
    return _filterPseudoSeriesFiles(resp);
  }

  static Future<FsResp> rename({
    required String path,
    required String name,
    String password = '',
  }) async {
    var res = await WooHttpUtil().post('/api/fs/rename', data: {
      'path': path,
      'name': name,
      'password': password,
    });
    return FsResp.fromJson(res.data);
  }
}

class FsGetResponse {
  final int code;
  final String? message;
  final FsGetData? data;

  FsGetResponse({
    required this.code,
    this.message,
    this.data,
  });

  factory FsGetResponse.fromJson(Map<String, dynamic> json) {
    return FsGetResponse(
      code: json['code'] as int,
      message: json['message'] as String?,
      data: json['data'] != null ? FsGetData.fromJson(json['data']) : null,
    );
  }
}

class FsGetData {
  final String name;
  final bool isDir;
  final int type;
  final String? rawUrl;

  FsGetData({
    required this.name,
    required this.isDir,
    required this.type,
    this.rawUrl,
  });

  factory FsGetData.fromJson(Map<String, dynamic> json) {
    return FsGetData(
      name: json['name'] as String,
      isDir: json['is_dir'] as bool,
      type: json['type'] as int,
      rawUrl: json['raw_url'] as String?,
    );
  }
}
