import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/models/api_config_preset.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/woo_http.dart';
import 'package:alist_player/utils/logger.dart';

/// API配置管理器
class ApiConfigManager {
  static final ApiConfigManager _instance = ApiConfigManager._internal();
  factory ApiConfigManager() => _instance;
  ApiConfigManager._internal();

  /// API 配置操作日志，方便追踪配置变化
  void _log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    AppLogger().captureConsoleOutput(
      'ApiConfigManager',
      message,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 获取所有API配置预设
  Future<List<ApiConfigPreset>> getAllPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getString(AppConstants.apiPresetsKey) ?? '[]';
      final presets = ApiConfigPreset.fromJsonList(presetsJson);

      // 如果没有预设，创建默认预设
      if (presets.isEmpty) {
        final defaultPreset = _createDefaultPreset();
        await _savePresets([defaultPreset]);
        return [defaultPreset];
      }

      return presets;
    } catch (e, stack) {
      _log(
        '获取API配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// 保存API配置预设
  Future<bool> savePreset(ApiConfigPreset preset) async {
    try {
      final presets = await getAllPresets();

      // 检查是否已存在同名配置
      final existingIndex = presets.indexWhere((p) => p.name == preset.name);
      if (existingIndex != -1) {
        // 更新现有配置
        presets[existingIndex] = preset;
      } else {
        // 添加新配置
        presets.add(preset);
      }

      await _savePresets(presets);
      return true;
    } catch (e, stack) {
      _log(
        '保存API配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 删除API配置预设
  Future<bool> deletePreset(String presetId) async {
    try {
      final presets = await getAllPresets();
      final updatedPresets = presets.where((p) => p.id != presetId).toList();

      // 确保至少保留一个配置
      if (updatedPresets.isEmpty) {
        final defaultPreset = _createDefaultPreset();
        updatedPresets.add(defaultPreset);
      }

      await _savePresets(updatedPresets);

      // 如果删除的是当前使用的配置，切换到第一个配置
      final currentPresetId = await getCurrentPresetId();
      if (currentPresetId == presetId) {
        await setCurrentPreset(updatedPresets.first.id);
      }

      return true;
    } catch (e, stack) {
      _log(
        '删除API配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 获取当前使用的配置预设ID
  Future<String?> getCurrentPresetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.currentApiPresetIdKey);
    } catch (e, stack) {
      _log(
        '获取当前API配置预设ID失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// 获取当前使用的配置预设
  Future<ApiConfigPreset?> getCurrentPreset() async {
    try {
      final currentId = await getCurrentPresetId();
      if (currentId == null) {
        // 如果没有设置当前预设ID，返回第一个预设
        final presets = await getAllPresets();
        return presets.isNotEmpty ? presets.first : null;
      }

      final presets = await getAllPresets();
      try {
        return presets.firstWhere((p) => p.id == currentId);
      } catch (e) {
        // 如果找不到指定ID的预设，返回第一个预设
        return presets.isNotEmpty ? presets.first : null;
      }
    } catch (e, stack) {
      _log(
        '获取当前API配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// 设置当前使用的配置预设
  Future<bool> setCurrentPreset(String presetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.currentApiPresetIdKey, presetId);

      // 应用配置到当前设置
      final preset = await getPresetById(presetId);
      if (preset != null) {
        await _applyPresetToCurrentSettings(preset);
      }

      return true;
    } catch (e, stack) {
      _log(
        '设置当前API配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 根据ID获取配置预设
  Future<ApiConfigPreset?> getPresetById(String presetId) async {
    try {
      final presets = await getAllPresets();
      return presets.firstWhere(
        (p) => p.id == presetId,
        orElse: () => throw Exception('配置预设不存在'),
      );
    } catch (e, stack) {
      _log(
        '根据ID获取配置预设失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// 检查是否使用自定义API模式
  Future<bool> isCustomApiMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppConstants.customApiModeKey) ?? false;
    } catch (e, stack) {
      _log(
        '检查自定义API模式失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 设置自定义API模式
  Future<bool> setCustomApiMode(bool isCustom) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.customApiModeKey, isCustom);
      return true;
    } catch (e, stack) {
      _log(
        '设置自定义API模式失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 从当前设置创建新的配置预设
  Future<ApiConfigPreset> createPresetFromCurrentSettings(String name,
      {String? description}) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl =
        prefs.getString(AppConstants.baseUrlKey) ?? AppConstants.defaultBaseUrl;
    final baseDownloadUrl = prefs.getString(AppConstants.baseDownloadUrlKey) ??
        AppConstants.defaultBaseDownloadUrl;

    return ApiConfigPreset.createDefault(
      name: name,
      baseUrl: baseUrl,
      baseDownloadUrl: baseDownloadUrl,
      description: description,
    );
  }

  /// 初始化API配置管理器
  Future<void> initialize() async {
    try {
      final presets = await getAllPresets();
      final currentId = await getCurrentPresetId();

      // 如果没有当前配置，设置第一个为当前配置
      if (currentId == null && presets.isNotEmpty) {
        await setCurrentPreset(presets.first.id);
      }

      // 如果不是自定义模式，应用当前配置预设
      final isCustom = await isCustomApiMode();
      if (!isCustom) {
        final currentPreset = await getCurrentPreset();
        if (currentPreset != null) {
          await _applyPresetToCurrentSettings(currentPreset);
        }
      }
    } catch (e, stack) {
      _log(
        '初始化API配置管理器失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// 保存配置预设列表到本地存储
  Future<void> _savePresets(List<ApiConfigPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    final presetsJson = ApiConfigPreset.toJsonList(presets);
    await prefs.setString(AppConstants.apiPresetsKey, presetsJson);
  }

  /// 创建默认配置预设
  ApiConfigPreset _createDefaultPreset() {
    return ApiConfigPreset.createDefault(
      name: AppConstants.defaultPresetName,
      baseUrl: AppConstants.defaultBaseUrl,
      baseDownloadUrl: AppConstants.defaultBaseDownloadUrl,
      description: AppConstants.defaultPresetDescription,
    );
  }

  /// 将配置预设应用到当前设置
  Future<void> _applyPresetToCurrentSettings(ApiConfigPreset preset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(AppConstants.baseUrlKey, preset.baseUrl),
        prefs.setString(
            AppConstants.baseDownloadUrlKey, preset.baseDownloadUrl),
      ]);

      // 更新HTTP客户端的baseUrl
      await WooHttpUtil().updateBaseUrl();
    } catch (e, stack) {
      _log(
        '应用配置预设到当前设置失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stack,
      );
    }
  }
}
