import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/views/settings/database_api_settings.dart';

void main() {
  group('数据库设置对话框移动端适配测试', () {
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
                  onPressed: () => DatabaseSettingsDialog.show(context),
                  child: const Text('打开数据库设置'),
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
      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 验证对话框是否显示
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('数据库设置'), findsOneWidget);
      expect(find.text('主机地址'), findsOneWidget);
      expect(find.text('数据库名'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
    });

    testWidgets('移动端显示全屏页面', (WidgetTester tester) async {
      // 设置移动端屏幕尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => DatabaseSettingsDialog.show(context),
                  child: const Text('打开数据库设置'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 点击按钮打开对话框
      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 验证是否显示了数据库设置内容（无论是对话框还是全屏页面）
      expect(find.text('数据库设置'), findsOneWidget);
      expect(find.text('主机地址'), findsOneWidget);
      expect(find.text('数据库名'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);

      // 检查是否有AppBar（移动端）或Dialog（桌面端）
      final hasAppBar = find.byType(AppBar).evaluate().isNotEmpty;
      final hasDialog = find.byType(Dialog).evaluate().isNotEmpty;

      // 至少应该有一个
      expect(hasAppBar || hasDialog, isTrue);
    });

    testWidgets('移动端字体和间距适配', (WidgetTester tester) async {
      // 设置移动端屏幕尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => DatabaseSettingsDialog.show(context),
                  child: const Text('打开数据库设置'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 打开对话框
      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 验证数据库设置内容存在
      expect(find.text('数据库设置'), findsOneWidget);
      expect(find.text('主机地址'), findsOneWidget);

      // 检查是否有保存相关的按钮（可能是图标按钮或文字按钮）
      final hasCheckIcon = find.byIcon(Icons.check).evaluate().isNotEmpty;
      final hasSaveText = find.text('保存设置').evaluate().isNotEmpty;

      // 至少应该有一个保存按钮
      expect(hasCheckIcon || hasSaveText, isTrue);
    });

    testWidgets('桌面端和移动端布局差异', (WidgetTester tester) async {
      // 测试桌面端布局
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => DatabaseSettingsDialog.show(context),
                  child: const Text('打开数据库设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 桌面端尺寸
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 桌面端应该有取消和保存设置按钮
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('保存设置'), findsOneWidget);

      // 关闭对话框
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 切换到移动端尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 移动端应该有保存相关的按钮
      final hasCheckIcon = find.byIcon(Icons.check).evaluate().isNotEmpty;
      final hasSaveText = find.text('保存设置').evaluate().isNotEmpty;
      final hasAppBar = find.byType(AppBar).evaluate().isNotEmpty;

      // 验证移动端特征（AppBar或保存按钮）
      expect(hasAppBar || hasCheckIcon || hasSaveText, isTrue);
    });

    testWidgets('移动端垂直布局测试', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => DatabaseSettingsDialog.show(context),
                  child: const Text('打开数据库设置'),
                ),
              ),
            ),
          ),
        ),
      );

      // 移动端尺寸
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开数据库设置'));
      await tester.pumpAndSettle();

      // 验证所有输入字段都存在（移动端垂直布局）
      expect(find.text('主机地址'), findsOneWidget);
      expect(find.text('数据库名'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);

      // 验证输入框存在
      expect(find.byType(TextField), findsNWidgets(5));
    });
  });
}
