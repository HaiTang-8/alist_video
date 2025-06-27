import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';

void main() {
  group('API预设设置对话框测试', () {
    setUp(() async {
      // 设置测试环境
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('桌面端显示对话框', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ApiPresetSettingsDialog.show(context),
                  child: const Text('打开API设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 设置桌面端屏幕尺寸
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpAndSettle();

      // 点击按钮打开对话框
      await tester.tap(find.text('打开API设置'));
      await tester.pumpAndSettle();

      // 验证对话框是否显示
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('API 配置设置'), findsOneWidget);
      expect(find.text('配置预设'), findsOneWidget);
      expect(find.text('自定义配置'), findsOneWidget);
    });

    testWidgets('移动端显示全屏页面', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ApiPresetSettingsDialog.show(context),
                  child: const Text('打开API设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 设置移动端屏幕尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await tester.pumpAndSettle();

      // 点击按钮打开对话框
      await tester.tap(find.text('打开API设置'));
      await tester.pumpAndSettle();

      // 验证全屏页面是否显示（移动端使用MaterialPageRoute导航）
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('API 配置设置'), findsOneWidget);
      expect(find.text('配置预设'), findsOneWidget);
      expect(find.text('自定义配置'), findsOneWidget);
    });

    testWidgets('移动端标签页切换', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ApiPresetSettingsDialog.show(context),
                  child: const Text('打开API设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 设置移动端屏幕尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await tester.pumpAndSettle();

      // 打开对话框
      await tester.tap(find.text('打开API设置'));
      await tester.pumpAndSettle();

      // 验证默认在配置预设标签页
      expect(find.text('选择一个配置预设：'), findsOneWidget);

      // 切换到自定义配置标签页
      await tester.tap(find.text('自定义配置'));
      await tester.pumpAndSettle();

      // 验证自定义配置页面内容
      expect(find.text('自定义API配置：'), findsOneWidget);
      expect(find.text('基础 URL'), findsOneWidget);
      expect(find.text('下载 URL'), findsOneWidget);
      expect(find.text('保存为预设'), findsOneWidget);
    });

    testWidgets('桌面端和移动端布局差异', (WidgetTester tester) async {
      // 测试桌面端布局
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ApiPresetSettingsDialog.show(context),
                  child: const Text('打开API设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 桌面端尺寸
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开API设置'));
      await tester.pumpAndSettle();

      // 桌面端应该有关闭按钮和应用配置按钮
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('应用配置'), findsOneWidget);

      // 关闭对话框
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 切换到移动端尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开API设置'));
      await tester.pumpAndSettle();

      // 移动端应该有保存图标按钮在AppBar中
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
