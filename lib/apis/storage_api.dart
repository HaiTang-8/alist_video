import 'package:alist_player/models/storage_model.dart';
import 'package:alist_player/utils/woo_http.dart';

class StorageApi {
  // 列出存储列表
  static Future<List<StorageModel>> listStorage({
    int page = 1,
    int perPage = 10,
  }) async {
    try {
      final response = await WooHttpUtil().get(
        '/api/admin/storage/list',
        params: {
          'page': page.toString(),
          'per_page': perPage.toString(),
        },
      );

      if (response.data['code'] == 200) {
        final List<dynamic> content = response.data['data']['content'];
        return content.map((item) => StorageModel.fromJson(item)).toList();
      }
      throw Exception(response.data['message'] ?? '获取存储列表失败');
    } catch (e) {
      rethrow;
    }
  }

  // 启用存储
  static Future<void> enableStorage(int id) async {
    try {
      final response = await WooHttpUtil().post(
        '/api/admin/storage/enable?id=$id',
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['message'] ?? '启用存储失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 禁用存储
  static Future<void> disableStorage(int id) async {
    try {
      final response = await WooHttpUtil().post(
        '/api/admin/storage/disable?id=$id',
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['message'] ?? '禁用存储失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 重新加载所有存储
  static Future<void> reloadAllStorage() async {
    try {
      final response = await WooHttpUtil().post('/api/admin/storage/reload');

      if (response.data['code'] != 200) {
        throw Exception(response.data['message'] ?? '重新加载存储失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 获取单个存储信息
  static Future<StorageModel> getStorage(int id) async {
    try {
      final response = await WooHttpUtil().get(
        '/api/admin/storage/get',
        params: {'id': id.toString()},
      );

      if (response.data['code'] == 200) {
        return StorageModel.fromJson(response.data['data']);
      }
      throw Exception(response.data['message'] ?? '获取存储信息失败');
    } catch (e) {
      rethrow;
    }
  }

  // 更新存储信息
  static Future<void> updateStorage(StorageModel storage) async {
    try {
      final response = await WooHttpUtil().post(
        '/api/admin/storage/update',
        data: storage.toJson(),
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['message'] ?? '更新存储失败');
      }
    } catch (e) {
      rethrow;
    }
  }
}
