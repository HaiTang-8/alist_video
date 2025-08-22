import 'dart:io';
import 'package:flutter/material.dart';

/// Windows平台字体配置优化工具类
/// 专门用于解决Windows下中文字体发虚和繁体显示问题
class WindowsFontConfig {
  /// Windows系统推荐的中文字体列表（按优先级排序）
  static const List<String> _recommendedChineseFonts = [
    'Microsoft YaHei',      // 微软雅黑 - 最佳选择，清晰度高
    'Microsoft YaHei UI',   // 微软雅黑UI - 系统UI字体
    'SimHei',               // 黑体 - 备选方案
    'SimSun',               // 宋体 - 传统字体
    'Microsoft JhengHei',   // 微软正黑体 - 繁体中文
    'PingFang SC',          // 苹方简体 - 如果安装了
    'Noto Sans CJK SC',     // 思源黑体简体 - 开源字体
    'Source Han Sans SC',   // 思源黑体简体 - Adobe版本
  ];

  /// 获取Windows平台优化的字体配置
  static Map<String, dynamic> getOptimizedFontConfig() {
    if (!Platform.isWindows) {
      return {
        'fontFamily': null,
        'fontFamilyFallback': null,
      };
    }

    return {
      'fontFamily': _recommendedChineseFonts.first,
      'fontFamilyFallback': _recommendedChineseFonts,
    };
  }

  /// 创建Windows优化的TextStyle
  static TextStyle createOptimizedTextStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    String? customFontFamily,
    List<String>? customFontFallback,
  }) {
    final config = getOptimizedFontConfig();
    
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      fontFamily: customFontFamily ?? config['fontFamily'],
      fontFamilyFallback: customFontFallback ?? config['fontFamilyFallback'],
      // 添加字体渲染优化
      fontFeatures: Platform.isWindows ? [
        const FontFeature.enable('kern'), // 启用字距调整
        const FontFeature.enable('liga'), // 启用连字
      ] : null,
    );
  }

  /// 获取Windows平台的字体渲染建议
  static Map<String, String> getFontRenderingTips() {
    return {
      'clearType': '确保Windows系统已启用ClearType字体平滑',
      'dpi': '检查系统DPI设置，建议使用100%或125%缩放',
      'fontSmoothing': '在Windows设置中启用"平滑屏幕字体边缘"',
      'registry': '可以通过注册表调整字体渲染参数',
      'fallback': '使用字体回退列表确保在不同Windows版本上的兼容性',
    };
  }

  /// 检查系统是否安装了推荐的字体
  static Future<List<String>> checkAvailableFonts() async {
    // 注意：这个方法需要平台特定的实现
    // 在实际应用中，可能需要使用平台通道来检查字体可用性
    
    // 这里返回一个模拟的结果
    if (Platform.isWindows) {
      return [
        'Microsoft YaHei',
        'SimHei',
        'SimSun',
      ];
    }
    
    return [];
  }



  /// 获取主题配置
  static ThemeData getOptimizedTheme() {
    final config = getOptimizedFontConfig();
    
    return ThemeData(
      useMaterial3: true,
      fontFamily: config['fontFamily'],
      fontFamilyFallback: config['fontFamilyFallback'],
      textTheme: TextTheme(
        titleLarge: createOptimizedTextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
        ),
        titleMedium: createOptimizedTextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
        ),
        bodyLarge: createOptimizedTextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
        ),
        bodyMedium: createOptimizedTextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
        ),
        bodySmall: createOptimizedTextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C68D5),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: ComponentStyles.appBarTitle,
        iconTheme: const IconThemeData(
          color: Color(0xFF2C68D5),
        ),
      ),
    );
  }
}

/// 为特定组件创建优化的字体配置
class ComponentStyles {
  /// AppBar标题样式
  static TextStyle get appBarTitle => WindowsFontConfig.createOptimizedTextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF2C68D5),
  );

  /// 视频标题样式（普通模式）
  static TextStyle get videoTitle => WindowsFontConfig.createOptimizedTextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.black,
  );

  /// 视频标题样式（全屏模式）
  static TextStyle get fullscreenVideoTitle => WindowsFontConfig.createOptimizedTextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );

  /// 列表项标题样式
  static TextStyle get listItemTitle => WindowsFontConfig.createOptimizedTextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black87,
  );

  /// 按钮文字样式
  static TextStyle get buttonText => WindowsFontConfig.createOptimizedTextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );
}
