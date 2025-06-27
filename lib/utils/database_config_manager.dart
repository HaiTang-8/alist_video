import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/models/database_config_preset.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/utils/db.dart';

/// 数据库配置管理器
class DatabaseConfigManager {
  static final DatabaseConfigManager _instance = DatabaseConfigManager._internal();
  factory DatabaseConfigManager() => _instance;
  DatabaseConfigManager._internal();

  /// 获取所有数据库配置预设
  Future<List<DatabaseConfigPreset>> getAllPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetsJson = prefs.getString(AppConstants.dbPresetsKey) ?? '[]';
      final presets = DatabaseConfigPreset.fromJsonList(presetsJson);
      
      // 如果没有预设，创建默认预设
      if (presets.isEmpty) {
        final defaultPreset = _createDefaultPreset();
        await _savePresets([defaultPreset]);
        return [defaultPreset];
      }
      
      return presets;
    } catch (e) {
      print('获取数据库配置预设失败: $e');
      return [];
    }
  }

  /// 保存数据库配置预设
  Future<bool> savePreset(DatabaseConfigPreset preset) async {
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
    } catch (e) {
      print('保存数据库配置预设失败: $e');
      return false;
    }
  }

  /// 删除数据库配置预设
  Future<bool> deletePreset(String presetId) async {
    try {
      final presets = await getAllPresets();
      final originalLength = presets.length;
      
      // 不能删除默认配置
      presets.removeWhere((p) => p.id == presetId && !p.isDefault);
      
      if (presets.length < originalLength) {
        await _savePresets(presets);
        
        // 如果删除的是当前使用的配置，切换到第一个配置
        final currentId = await getCurrentPresetId();
        if (currentId == presetId && presets.isNotEmpty) {
          await setCurrentPreset(presets.first.id);
        }
        
        return true;
      }
      
      return false;
    } catch (e) {
      print('删除数据库配置预设失败: $e');
      return false;
    }
  }

  /// 获取当前使用的配置预设ID
  Future<String?> getCurrentPresetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.currentDbPresetIdKey);
    } catch (e) {
      print('获取当前数据库配置预设ID失败: $e');
      return null;
    }
  }

  /// 获取当前使用的配置预设
  Future<DatabaseConfigPreset?> getCurrentPreset() async {
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
    } catch (e) {
      print('获取当前数据库配置预设失败: $e');
      return null;
    }
  }

  /// 设置当前使用的配置预设
  Future<bool> setCurrentPreset(String presetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.currentDbPresetIdKey, presetId);
      
      // 应用配置到当前设置
      final preset = await getPresetById(presetId);
      if (preset != null) {
        await _applyPresetToCurrentSettings(preset);
      }
      
      return true;
    } catch (e) {
      print('设置当前数据库配置预设失败: $e');
      return false;
    }
  }

  /// 根据ID获取配置预设
  Future<DatabaseConfigPreset?> getPresetById(String presetId) async {
    try {
      final presets = await getAllPresets();
      return presets.firstWhere(
        (p) => p.id == presetId,
        orElse: () => throw Exception('配置预设不存在'),
      );
    } catch (e) {
      print('根据ID获取配置预设失败: $e');
      return null;
    }
  }

  /// 检查是否使用自定义数据库模式
  Future<bool> isCustomDbMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(AppConstants.customDbModeKey) ?? false;
    } catch (e) {
      print('检查自定义数据库模式失败: $e');
      return false;
    }
  }

  /// 设置自定义数据库模式
  Future<bool> setCustomDbMode(bool isCustom) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.customDbModeKey, isCustom);
      return true;
    } catch (e) {
      print('设置自定义数据库模式失败: $e');
      return false;
    }
  }

  /// 测试数据库连接
  Future<bool> testConnection(DatabaseConfigPreset preset) async {
    try {
      // 创建临时数据库连接进行测试
      final tempDb = DatabaseHelper.instance;
      await tempDb.init(
        host: preset.host,
        port: preset.port,
        database: preset.database,
        username: preset.username,
        password: preset.password,
      );

      // 测试连接
      await tempDb.query('SELECT 1');
      return true;
    } catch (e) {
      print('测试数据库连接失败: $e');
      return false;
    }
  }

  /// 初始化数据库配置管理器
  Future<void> initialize() async {
    try {
      final presets = await getAllPresets();
      final currentId = await getCurrentPresetId();
      
      // 如果没有当前配置，设置第一个为当前配置
      if (currentId == null && presets.isNotEmpty) {
        await setCurrentPreset(presets.first.id);
      }
      
      // 如果不是自定义模式，应用当前配置预设
      final isCustom = await isCustomDbMode();
      if (!isCustom) {
        final currentPreset = await getCurrentPreset();
        if (currentPreset != null) {
          await _applyPresetToCurrentSettings(currentPreset);
        }
      }
    } catch (e) {
      print('初始化数据库配置管理器失败: $e');
    }
  }

  /// 保存配置预设列表到本地存储
  Future<void> _savePresets(List<DatabaseConfigPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    final presetsJson = DatabaseConfigPreset.toJsonList(presets);
    await prefs.setString(AppConstants.dbPresetsKey, presetsJson);
  }

  /// 创建默认配置预设
  DatabaseConfigPreset _createDefaultPreset() {
    return DatabaseConfigPreset.createDefault(
      name: AppConstants.defaultDbPresetName,
      host: AppConstants.defaultDbHost,
      port: AppConstants.defaultDbPort,
      database: AppConstants.defaultDbName,
      username: AppConstants.defaultDbUser,
      password: AppConstants.defaultDbPassword,
      description: AppConstants.defaultDbPresetDescription,
    );
  }

  /// 将配置预设应用到当前设置
  Future<void> _applyPresetToCurrentSettings(DatabaseConfigPreset preset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(AppConstants.dbHostKey, preset.host),
        prefs.setInt(AppConstants.dbPortKey, preset.port),
        prefs.setString(AppConstants.dbNameKey, preset.database),
        prefs.setString(AppConstants.dbUserKey, preset.username),
        prefs.setString(AppConstants.dbPasswordKey, preset.password),
      ]);
      
      // 重新初始化数据库连接
      await DatabaseHelper.instance.close();
      await DatabaseHelper.instance.init(
        host: preset.host,
        port: preset.port,
        database: preset.database,
        username: preset.username,
        password: preset.password,
      );
    } catch (e) {
      print('应用配置预设到当前设置失败: $e');
    }
  }
}
