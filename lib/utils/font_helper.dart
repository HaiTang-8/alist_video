import 'dart:io';
import 'package:flutter/material.dart';

/// 字体帮助类，用于处理不同平台的字体配置。
class FontHelper {
  /// Windows平台的字体回退列表
  static const List<String> _windowsFontFallback = [
    'Microsoft YaHei',  // 微软雅黑
    'SimHei',           // 黑体
    'SimSun',           // 宋体
    'Microsoft JhengHei', // 微软正黑体
    'PingFang SC',      // 苹方简体
    'Noto Sans CJK SC', // 思源黑体简体
  ];

  /// Windows平台的等宽字体回退列表。
  ///
  /// 优先选择 Consolas / Cascadia 系列，其次回退到 Courier New，
  /// 最后回退到通用的 monospace，尽可能保证日志等内容在 Windows
  /// 下也有清晰、统一的显示效果。
  static const List<String> _windowsMonospaceFallback = [
    'Consolas',
    'Cascadia Code',
    'Cascadia Mono',
    'Courier New',
    'monospace',
  ];

  /// 获取适合当前平台的字体族名
  static String? getPlatformFontFamily() {
    if (Platform.isWindows) {
      return 'Microsoft YaHei';
    }
    return null;
  }

  /// 获取适合当前平台的字体回退列表
  static List<String>? getPlatformFontFallback() {
    if (Platform.isWindows) {
      return _windowsFontFallback;
    }
    return null;
  }

  /// 创建带有平台优化的TextStyle
  static TextStyle createTextStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      fontFamily: fontFamily ?? getPlatformFontFamily(),
      fontFamilyFallback: fontFamilyFallback ?? getPlatformFontFallback(),
    );
  }

  /// 创建等宽字体的 TextStyle。
  ///
  /// - Windows 下显式指定等宽字体家族，避免默认字体对中文日志渲染不佳；
  /// - 其他平台保持使用通用的 'monospace'，交由系统映射到适配字体。
  static TextStyle createMonospaceTextStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    if (Platform.isWindows) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
        fontFamily: _windowsMonospaceFallback.first,
        fontFamilyFallback: _windowsMonospaceFallback,
      );
    }

    // 非 Windows 平台使用通用等宽族名，让系统自行选择合适的等宽字体。
    return const TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: ['monospace'],
    ).copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  /// 为AppBar标题创建优化的TextStyle
  static TextStyle createAppBarTitleStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
  }) {
    return createTextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// 为视频标题创建优化的TextStyle
  static TextStyle createVideoTitleStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
    Color color = Colors.black,
  }) {
    return createTextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// 为全屏模式视频标题创建优化的TextStyle
  static TextStyle createFullscreenVideoTitleStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
    Color color = Colors.white,
  }) {
    return createTextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// 获取主题的TextTheme配置
  static TextTheme getThemeTextTheme() {
    return TextTheme(
      titleLarge: createTextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleMedium: createTextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      bodyLarge: createTextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
      bodyMedium: createTextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodySmall: createTextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
    );
  }

  /// 获取AppBar主题配置
  static AppBarTheme getAppBarTheme() {
    return AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF2C68D5),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: createTextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF2C68D5),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF2C68D5),
      ),
    );
  }
}
