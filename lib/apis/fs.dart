import 'package:alist_player/models/fs_resp/fs_resp.dart';
import 'package:alist_player/utils/woo_http.dart';

class FsApi {
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
    return FsResp.fromJson(res.data);
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

  FsGetData({
    required this.name,
    required this.isDir,
    required this.type,
  });

  factory FsGetData.fromJson(Map<String, dynamic> json) {
    return FsGetData(
      name: json['name'] as String,
      isDir: json['is_dir'] as bool,
      type: json['type'] as int,
    );
  }
}
