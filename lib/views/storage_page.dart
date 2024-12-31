import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/apis/storage_api.dart';
import 'package:alist_player/models/storage_model.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  List<StorageModel> _storages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStorages();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadStorages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final storages = await StorageApi.listStorage();
      if (!mounted) return;
      setState(() {
        _storages = storages;
      });
    } catch (e) {
      _showMessage('加载存储列表失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final baseUrl = prefs.getString(AppConstants.baseUrlKey) ??
                  AppConstants.defaultBaseUrl;
              final token = prefs.getString(AppConstants.tokenKey) ?? '';
              final uri = Uri.parse('$baseUrl/@manage/storages?token=$token');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (!mounted) return;
                _showMessage('无法打开链接: $baseUrl');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStorages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: DataTable(
                        columnSpacing: 24.0,
                        horizontalMargin: 12.0,
                        columns: const [
                          DataColumn(
                              label: Expanded(
                            child: Text('挂载路径',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          )),
                          DataColumn(
                              label: Expanded(
                            child: Text('存储类型',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          )),
                          DataColumn(
                              label: Expanded(
                            child: Text('备注',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          )),
                          DataColumn(
                              label: Expanded(
                            child: Text('状态',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          )),
                          DataColumn(
                              label: Expanded(
                            child: Text('操作',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          )),
                        ],
                        rows: _storages.map((storage) {
                          return DataRow(
                            cells: [
                              DataCell(Text(storage.mountPath)),
                              DataCell(Text(storage.driver)),
                              DataCell(Text(storage.remark)),
                              DataCell(Text(storage.status)),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 20),
                                      onPressed: () async {
                                        if (!mounted) return;
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        try {
                                          messenger.clearSnackBars();
                                          messenger.showSnackBar(
                                            const SnackBar(
                                                content: Text('正在刷新存储...')),
                                          );
                                          final updatedStorage =
                                              await StorageApi.getStorage(
                                                  storage.id);
                                          await StorageApi.updateStorage(
                                              updatedStorage);
                                          await _loadStorages();
                                          if (!mounted) return;
                                          messenger.clearSnackBars();
                                          messenger.showSnackBar(
                                            const SnackBar(
                                                content: Text('刷新存储成功')),
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          messenger.clearSnackBars();
                                          messenger.showSnackBar(
                                            SnackBar(
                                                content: Text('刷新存储失败: $e')),
                                          );
                                        }
                                      },
                                    ),
                                    Switch(
                                      value: !storage.disabled,
                                      onChanged: (value) async {
                                        try {
                                          if (value) {
                                            await StorageApi.enableStorage(
                                                storage.id);
                                          } else {
                                            await StorageApi.disableStorage(
                                                storage.id);
                                          }
                                          _loadStorages();
                                        } catch (e) {
                                          _showMessage(
                                              '${value ? "启用" : "禁用"}存储失败: $e');
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
