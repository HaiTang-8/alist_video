import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:alist_player/utils/platform_download_manager.dart';
import 'package:alist_player/utils/download_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Download Manager Tests', () {
    test('Platform Download Manager initialization', () async {
      final manager = PlatformDownloadManager();

      // 测试初始化
      await manager.initialize();

      // 验证下载方法信息
      final method = manager.getCurrentDownloadMethod();
      expect(method, isNotNull);
      expect(method, isNotEmpty);

      print('Current download method: $method');
    });

    test('Download Adapter initialization', () async {
      final adapter = DownloadAdapter();

      // 测试初始化
      await adapter.initialize();

      // 验证平台检测
      final isMobile = adapter.isMobilePlatform;
      print('Is mobile platform: $isMobile');

      // 验证下载方法信息
      final method = adapter.getCurrentDownloadMethod();
      expect(method, isNotNull);
      expect(method, isNotEmpty);

      print('Current download method: $method');
    });

    test('Download path configuration', () async {
      // 测试获取下载路径
      final path = await PlatformDownloadManager.getDownloadPath();
      expect(path, isNotNull);
      expect(path, isNotEmpty);

      print('Download path: $path');
    });
  });
}
