import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';

class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  int _shortSeekDuration = AppConstants.defaultShortSeekDuration.inSeconds;
  int _longSeekDuration = AppConstants.defaultLongSeekDuration.inSeconds;
  List<double> _playbackSpeeds = AppConstants.defaultPlaybackSpeeds;
  double _customPlaybackSpeed = AppConstants.defaultCustomPlaybackSpeed;
  final _shortSeekController = TextEditingController();
  final _longSeekController = TextEditingController();
  final _speedController = TextEditingController();
  final _customSpeedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shortSeekController.text = _shortSeekDuration.toString();
    _longSeekController.text = _longSeekDuration.toString();
    _customSpeedController.text = _customPlaybackSpeed.toString();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final shortSeek = prefs.getInt(AppConstants.shortSeekKey);
    final longSeek = prefs.getInt(AppConstants.longSeekKey);
    final speedsString = prefs.getStringList(AppConstants.playbackSpeedsKey);
    final customSpeed = prefs.getDouble(AppConstants.customPlaybackSpeedKey);

    setState(() {
      if (shortSeek != null) {
        _shortSeekDuration = shortSeek;
        _shortSeekController.text = shortSeek.toString();
      }

      if (longSeek != null) {
        _longSeekDuration = longSeek;
        _longSeekController.text = longSeek.toString();
      }

      if (speedsString != null) {
        _playbackSpeeds = speedsString.map((s) => double.parse(s)).toList()
          ..sort();
      }

      if (customSpeed != null) {
        _customPlaybackSpeed = customSpeed;
        _customSpeedController.text = customSpeed.toString();
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.shortSeekKey, _shortSeekDuration);
    await prefs.setInt(AppConstants.longSeekKey, _longSeekDuration);
  }

  Future<void> _savePlaybackSpeeds() async {
    final prefs = await SharedPreferences.getInstance();
    final speedsString = _playbackSpeeds.map((s) => s.toString()).toList();
    await prefs.setStringList(AppConstants.playbackSpeedsKey, speedsString);
  }

  Future<void> _saveCustomPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
        AppConstants.customPlaybackSpeedKey, _customPlaybackSpeed);
  }

  void _updateShortSeekDuration(String value) {
    final duration =
        int.tryParse(value) ?? AppConstants.defaultShortSeekDuration.inSeconds;
    setState(() {
      _shortSeekDuration = duration.clamp(
        AppConstants.minSeekDuration,
        AppConstants.maxSeekDuration,
      );
      _shortSeekController.text = _shortSeekDuration.toString();
    });
    _saveSettings();
  }

  void _updateLongSeekDuration(String value) {
    final duration =
        int.tryParse(value) ?? AppConstants.defaultLongSeekDuration.inSeconds;
    setState(() {
      _longSeekDuration = duration.clamp(
        AppConstants.minSeekDuration,
        AppConstants.maxSeekDuration,
      );
      _longSeekController.text = _longSeekDuration.toString();
    });
    _saveSettings();
  }

  void _addSpeed(String value) {
    final speed = double.tryParse(value);

    // 验证输入值
    if (speed == null) {
      _showErrorMessage('请输入有效的数字');
      return;
    }

    // 验证速度范围
    if (speed < AppConstants.minPlaybackSpeed ||
        speed > AppConstants.maxPlaybackSpeed) {
      _showErrorMessage(
          '播放速度必须在 ${AppConstants.minPlaybackSpeed}x 到 ${AppConstants.maxPlaybackSpeed}x 之间');
      return;
    }

    // 验证是否重复
    if (_playbackSpeeds.contains(speed)) {
      _showErrorMessage('该播放速度已存在');
      return;
    }

    // 验证数量限制
    if (_playbackSpeeds.length >= AppConstants.maxPlaybackSpeedCount) {
      _showErrorMessage('播放速度数量已达到上限（${AppConstants.maxPlaybackSpeedCount}个）');
      return;
    }

    // 验证步长
    // if ((speed * 100) % (AppConstants.speedStep * 100) != 0) {
    //   _showErrorMessage('播放速度必须是 ${AppConstants.speedStep}x 的倍数');
    //   return;
    // }

    // 所有验证通过，添加新速度
    setState(() {
      _playbackSpeeds = [..._playbackSpeeds, speed]..sort();
      _speedController.clear();
    });
    _savePlaybackSpeeds();

    // 显示成功提示
    _showSuccessMessage('添加成功');
  }

  void _updateCustomPlaybackSpeed(String value) {
    final speed = double.tryParse(value);
    if (speed == null) {
      _showErrorMessage('请输入有效的数字');
      return;
    }

    if (speed < AppConstants.minPlaybackSpeed ||
        speed > AppConstants.maxPlaybackSpeed) {
      _showErrorMessage(
          '播放速度必须在 ${AppConstants.minPlaybackSpeed}x 到 ${AppConstants.maxPlaybackSpeed}x 之间');
      return;
    }

    setState(() {
      _customPlaybackSpeed = speed;
      _customSpeedController.text = speed.toString();
    });
    _saveCustomPlaybackSpeed();
    _showSuccessMessage('保存成功');
  }

  // 添加错误提示方法
  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 添加成功提示方法
  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _removeSpeed(double speed) {
    if (speed != AppConstants.defaultPlaybackSpeed) {
      // 不允许删除 1.0x
      setState(() {
        _playbackSpeeds.remove(speed);
      });
      _savePlaybackSpeeds();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '快进/快退设置',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSeekDurationField(
            label: '短按快进/快退时长（秒）',
            controller: _shortSeekController,
            onChanged: _updateShortSeekDuration,
          ),
          const SizedBox(height: 16),
          _buildSeekDurationField(
            label: '长按快进/快退时长（秒）',
            controller: _longSeekController,
            onChanged: _updateLongSeekDuration,
          ),
          const SizedBox(height: 24),
          const Text(
            '播放速度设置',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customSpeedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '快捷键切换播放速度 (按P键切换)',
              hintText: '输入自定义播放速度',
              suffixText: 'x',
            ),
            onSubmitted: _updateCustomPlaybackSpeed,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _playbackSpeeds.map((speed) {
              return Chip(
                label: Text('${speed}x'),
                deleteIcon: speed == AppConstants.defaultPlaybackSpeed
                    ? null
                    : const Icon(Icons.close, size: 18),
                onDeleted: speed == AppConstants.defaultPlaybackSpeed
                    ? null
                    : () => _removeSpeed(speed),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _speedController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        '添加新的播放速度 (${AppConstants.minPlaybackSpeed}-${AppConstants.maxPlaybackSpeed})',
                    suffixText: 'x',
                  ),
                  onSubmitted: _addSpeed,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => _addSpeed(_speedController.text),
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '提示：点击速度标签可以删除，1.0x 速度不可删除',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekDurationField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText:
                '输入秒数 (${AppConstants.minSeekDuration}-${AppConstants.maxSeekDuration})',
            suffixText: '秒',
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _shortSeekController.dispose();
    _longSeekController.dispose();
    _speedController.dispose();
    _customSpeedController.dispose();
    super.dispose();
  }
}
