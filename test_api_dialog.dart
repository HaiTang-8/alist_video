import 'package:flutter/material.dart';
import 'package:alist_player/views/settings/api_preset_settings_dialog.dart';

void main() {
  runApp(const TestApiDialogApp());
}

class TestApiDialogApp extends StatelessWidget {
  const TestApiDialogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Dialog Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TestApiDialogPage(),
    );
  }
}

class TestApiDialogPage extends StatelessWidget {
  const TestApiDialogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Dialog Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                ApiPresetSettingsDialog.show(context);
              },
              child: const Text('显示 API 设置对话框'),
            ),
            const SizedBox(height: 20),
            Text(
              '点击按钮测试API设置对话框\n'
              '桌面端应该显示为固定尺寸的对话框\n'
              '移动端应该显示为全屏页面',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
