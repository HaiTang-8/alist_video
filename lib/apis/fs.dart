import 'package:webdav_video/models/fs_resp/fs_resp.dart';
import 'package:webdav_video/utils/woo_http.dart';

class FsApi {
  static Future<FsResp> list({
    String? path,
    String? password,
    int? page,
    int? perPage,
    bool? refresh,
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
}
