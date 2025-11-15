import 'package:alist_player/models/user_info.dart';
import 'package:alist_player/utils/woo_http.dart';

class AdminUserListResponse {
  const AdminUserListResponse({
    required this.content,
    required this.total,
  });

  final List<UserInfo> content;
  final int total;
}

class AdminUserApi {
  AdminUserApi({WooHttpUtil? client}) : _client = client ?? WooHttpUtil();

  final WooHttpUtil _client;

  Future<AdminUserListResponse> listUsers({
    int page = 1,
    int perPage = 30,
  }) async {
    final response = await _client.get(
      '/api/admin/user/list',
      params: {
        'page': '$page',
        'per_page': '$perPage',
      },
    );

    if (response.data['code'] != 200) {
      throw Exception(response.data['message'] ?? '获取用户列表失败');
    }

    final data = response.data['data'] as Map<String, dynamic>?;
    final List<dynamic> rawList = data?['content'] as List<dynamic>? ?? const [];
    final total = (data?['total'] as num?)?.toInt() ?? rawList.length;
    final users = rawList
        .map((entry) => UserInfo.fromJson(entry as Map<String, dynamic>))
        .toList();

    return AdminUserListResponse(content: users, total: total);
  }

  Future<UserInfo?> getUserById(int id) async {
    final response = await _client.get(
      '/api/admin/user/get',
      params: {'id': '$id'},
    );

    if (response.data['code'] != 200) {
      final message = response.data['message'] as String?;
      if (message != null && message.contains('record not found')) {
        return null;
      }
      throw Exception(response.data['message'] ?? '获取用户信息失败');
    }

    final data = response.data['data'] as Map<String, dynamic>?;
    if (data == null) {
      return null;
    }

    return UserInfo.fromJson(data);
  }
}
