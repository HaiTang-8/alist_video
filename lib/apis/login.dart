import 'package:alist_player/models/login_resp/login_resp.dart';
import 'package:alist_player/utils/woo_http.dart';

class LoginApi {
  static Future<LoginResp> login(
      {required String username, required String password}) async {
    var res = await WooHttpUtil().post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    return LoginResp.fromJson(res.data);
  }
}
