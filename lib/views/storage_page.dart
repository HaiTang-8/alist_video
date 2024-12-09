import 'package:flutter/material.dart';
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

  Future<void> _loadStorages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final storages = await StorageApi.listStorage();
      setState(() {
        _storages = storages;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载存储列表失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStorages,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () async {
              try {
                await StorageApi.reloadAllStorage();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('重新加载所有存储成功')),
                );
                _loadStorages();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('重新加载存储失败: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _storages.length,
              itemBuilder: (context, index) {
                final storage = _storages[index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(storage.mountPath),
                    subtitle: Text(storage.driver),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(storage.status),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () async {
                            if (!mounted) return;

                            final messenger = ScaffoldMessenger.of(context);

                            try {
                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('正在刷新存储...')),
                              );

                              final updatedStorage =
                                  await StorageApi.getStorage(storage.id);
                              await StorageApi.updateStorage(updatedStorage);
                              await _loadStorages();

                              if (!mounted) return;

                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('刷新存储成功')),
                              );
                            } catch (e) {
                              if (!mounted) return;

                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                SnackBar(content: Text('刷新存储失败: $e')),
                              );
                            }
                          },
                        ),
                        Switch(
                          value: !storage.disabled,
                          onChanged: (value) async {
                            try {
                              if (value) {
                                await StorageApi.enableStorage(storage.id);
                              } else {
                                await StorageApi.disableStorage(storage.id);
                              }
                              _loadStorages();
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${value ? "启用" : "禁用"}存储失败: $e',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
