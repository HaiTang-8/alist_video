import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/utils/font_helper.dart';

class SharedPreferencesViewer extends StatefulWidget {
  const SharedPreferencesViewer({super.key});

  @override
  State<SharedPreferencesViewer> createState() => _SharedPreferencesViewerState();
}

class _SharedPreferencesViewerState extends State<SharedPreferencesViewer> {
  final Map<String, dynamic> _preferences = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    final preferences = <String, dynamic>{};
    for (final key in keys) {
      dynamic value;
      bool valueFound = false;
      
      // 尝试获取布尔值
      try {
        final bool? boolValue = prefs.getBool(key);
        if (boolValue != null) {
          value = boolValue;
          valueFound = true;
        }
      } catch (_) {}
      
      // 尝试获取整数
      if (!valueFound) {
        try {
          final int? intValue = prefs.getInt(key);
          if (intValue != null) {
            value = intValue;
            valueFound = true;
          }
        } catch (_) {}
      }
      
      // 尝试获取双精度浮点数
      if (!valueFound) {
        try {
          final double? doubleValue = prefs.getDouble(key);
          if (doubleValue != null) {
            value = doubleValue;
            valueFound = true;
          }
        } catch (_) {}
      }
      
      // 尝试获取字符串列表
      if (!valueFound) {
        try {
          final List<String>? stringListValue = prefs.getStringList(key);
          if (stringListValue != null) {
            value = stringListValue;
            valueFound = true;
          }
        } catch (_) {}
      }
      
      // 尝试获取字符串
      if (!valueFound) {
        try {
          final String? stringValue = prefs.getString(key);
          if (stringValue != null) {
            value = stringValue;
            valueFound = true;
          }
        } catch (_) {}
      }
      
      // 如果找到值，则添加到 preferences 中
      if (valueFound) {
        preferences[key] = value;
      } else {
        preferences[key] = "未知类型的值";
      }
    }
    
    if (mounted) {
      setState(() {
        _preferences.clear();
        _preferences.addAll(preferences);
        _isLoading = false;
      });
    }
  }

  Future<void> _deletePreference(String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$key" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await _loadPreferences();
    }
  }

  List<MapEntry<String, dynamic>> get _filteredPreferences {
    if (_searchQuery.isEmpty) {
      return _preferences.entries.toList();
    }
    return _preferences.entries
        .where((entry) => entry.key.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                          entry.value.toString().toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  String _getValueType(dynamic value) {
    if (value is String) return '字符串';
    if (value is bool) return '布尔值';
    if (value is int) return '整数';
    if (value is double) return '浮点数';
    if (value is List<String>) return '字符串列表';
    return '未知类型';
  }

  Color _getTypeColor(dynamic value) {
    if (value is String) return Colors.blue;
    if (value is bool) return Colors.green;
    if (value is int) return Colors.orange;
    if (value is double) return Colors.purple;
    if (value is List<String>) return Colors.teal;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SharedPreferences 查看器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPreferences,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索键或值...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPreferences.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.storage_outlined,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _preferences.isEmpty
                                  ? '没有存储的首选项'
                                  : '没有匹配的首选项',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredPreferences.length,
                        itemBuilder: (context, index) {
                          final entry = _filteredPreferences[index];
                          final key = entry.key;
                          final value = entry.value;
                          final valueType = _getValueType(value);
                          final typeColor = _getTypeColor(value);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                title: Text(
                                  key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: BoxDecoration(
                                        color: typeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: typeColor.withOpacity(0.5),
                                        ),
                                      ),
                                      child: Text(
                                        valueType,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: typeColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _deletePreference(key),
                                      tooltip: '删除',
                                    ),
                                    const Icon(Icons.keyboard_arrow_down),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '值:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: SelectableText(
                                            value is List
                                                ? value.join('\n')
                                                : value.toString(),
                                            // 使用 FontHelper 的等宽字体样式，
                                            // 保证在 Windows 等平台上 key/value
                                            // 内容对齐且字体渲染一致。
                                            style: FontHelper
                                                .createMonospaceTextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadPreferences,
        tooltip: '刷新',
        child: const Icon(Icons.refresh),
      ),
    );
  }
} 
