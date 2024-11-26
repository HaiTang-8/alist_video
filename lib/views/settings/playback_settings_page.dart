import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alist_player/constants/app_constants.dart';

class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  late int _shortSeekDuration;
  late int _longSeekDuration;
  final _shortSeekController = TextEditingController();
  final _longSeekController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shortSeekDuration = prefs.getInt(AppConstants.shortSeekKey) ??
          AppConstants.defaultShortSeekDuration.inSeconds;
      _longSeekDuration = prefs.getInt(AppConstants.longSeekKey) ??
          AppConstants.defaultLongSeekDuration.inSeconds;

      _shortSeekController.text = _shortSeekDuration.toString();
      _longSeekController.text = _longSeekDuration.toString();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.shortSeekKey, _shortSeekDuration);
    await prefs.setInt(AppConstants.longSeekKey, _longSeekDuration);
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
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
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
    super.dispose();
  }
}
