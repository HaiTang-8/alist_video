import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 字体帮助类，用于处理不同平台的字体配置。
/// 
/// 当前实现通过 Google Fonts 的 Noto Sans SC 作为统一的基础字体，
/// 再结合一组常用系统字体作为回退，确保在：
/// - Windows / macOS 桌面端
/// - Android / iOS 移动端
/// 上尽可能保持一致的中英文显示效果。
class FontHelper {
  /// 通用无衬线字体回退列表。
  /// 
  /// 顺序按照「更接近 Noto Sans SC」的程度排列，保证在目标字体
  /// 无法加载时仍然有稳定的跨平台体验。
  static const List<String> _commonSansFallback = [
    'Noto Sans CJK SC', // 思源黑体简体
    'Source Han Sans SC', // 思源黑体（Adobe 版本）
    'PingFang SC',      // macOS / iOS 系统中文 UI 字体
    'Microsoft YaHei',  // Windows 常用中文 UI 字体
    'Helvetica Neue',
    'Helvetica',
    'Arial',
    'sans-serif',
  ];

  /// 获取应用统一使用的字体族名。
  ///
  /// 这里通过 GoogleFonts.notoSansSc() 返回的 fontFamily，确保在
  /// 所有平台上使用同一套字体族配置，从而达到「跨平台字体统一」的目标。
  static String? getPlatformFontFamily() {
    // GoogleFonts 会在构建阶段将字体作为资源打包进应用，
    // 结合 main.dart 中的 allowRuntimeFetching=false，可避免运行时拉取网络字体。
    return GoogleFonts.notoSansSc().fontFamily ?? 'NotoSansSC';
  }

  /// 获取统一的字体回退列表。
  ///
  /// 包含 Google Fonts 字体自身以及常见系统无衬线字体，确保在某些
  /// 平台或极端环境下缺少 Noto Sans SC 时仍能有合理的显示效果。
  static List<String>? getPlatformFontFallback() {
    return [
      getPlatformFontFamily() ?? 'NotoSansSC',
      ..._commonSansFallback,
    ];
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
    // 先使用 Noto Sans SC 生成基础样式，保证跨平台的主字体一致，
    // 再叠加调用方传入的字体信息与统一的回退配置。
    final base = GoogleFonts.notoSansSc(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );

    return base.copyWith(
      fontFamily: fontFamily ?? getPlatformFontFamily(),
      fontFamilyFallback: fontFamilyFallback ?? getPlatformFontFallback(),
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
