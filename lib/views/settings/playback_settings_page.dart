import 'package:alist_player/constants/app_constants.dart';
import 'package:alist_player/models/database_persistence_type.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final _proxyEndpointController = TextEditingController();
  bool _goProxyEnabled = AppConstants.defaultEnableGoProxy;
  bool _isGoBridgeDriver = false;
  String _bridgeEndpoint = AppConstants.defaultGoBridgeEndpoint;
  String _customProxyEndpoint = '';
  bool _hasCustomProxyEndpoint = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _shortSeekController.text = _shortSeekDuration.toString();
    _longSeekController.text = _longSeekDuration.toString();
    _customSpeedController.text = _customPlaybackSpeed.toString();
    _proxyEndpointController.text = _customProxyEndpoint;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final shortSeek = prefs.getInt(AppConstants.shortSeekKey);
    final longSeek = prefs.getInt(AppConstants.longSeekKey);
    final speedsString = prefs.getStringList(AppConstants.playbackSpeedsKey);
    final customSpeed = prefs.getDouble(AppConstants.customPlaybackSpeedKey);
    final goProxyPref = prefs.getBool(AppConstants.enableGoProxyKey) ??
        AppConstants.defaultEnableGoProxy;
    final customProxyEndpoint =
        (prefs.getString(AppConstants.goProxyEndpointKey) ?? '').trim();
    final bridgeEndpoint = _resolveBridgeEndpoint(prefs);
    final driverTypeValue = prefs.getString(AppConstants.dbDriverTypeKey);
    final driverType =
        DatabasePersistenceTypeExtension.fromStorage(driverTypeValue);
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
      _goProxyEnabled = goProxyPref;
      _isGoBridgeDriver = driverType == DatabasePersistenceType.localGoBridge;
      _bridgeEndpoint = bridgeEndpoint;
      _customProxyEndpoint = customProxyEndpoint;
      _proxyEndpointController.text = customProxyEndpoint;
      _hasCustomProxyEndpoint = customProxyEndpoint.isNotEmpty;
    });
  }

  Future<void> _updateGoProxy(bool value) async {
    if (!_isGoBridgeDriver) {
      _showErrorMessage('仅在使用本地 Go 服务作为数据库驱动时才能开启代理');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.enableGoProxyKey, value);

    if (!mounted) {
      return;
    }

    setState(() {
      _goProxyEnabled = value;
    });

    _showSuccessMessage(value ? '已启用 Go 服务代理播放' : '已关闭 Go 服务代理播放');
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
    setState(() {
      _statusMessage = message;
      _statusIsError = true;
    });
  }

  // 添加成功提示方法
  void _showSuccessMessage(String message) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = false;
    });
  }

  Future<void> _saveProxyEndpoint(String rawValue) async {
    if (!_isGoBridgeDriver) {
      _showErrorMessage('仅在启用本地 Go 服务驱动后才能编辑代理地址');
      return;
    }
    if (_goProxyEnabled) {
      _showErrorMessage('请先关闭“通过 Go 服务代理播放”后再编辑地址');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sanitized = rawValue.trim();
    if (sanitized.isEmpty) {
      await prefs.remove(AppConstants.goProxyEndpointKey);
      final fallback = _resolveBridgeEndpoint(prefs);
      if (!mounted) {
        return;
      }
      setState(() {
        _customProxyEndpoint = '';
        _bridgeEndpoint = fallback;
        _proxyEndpointController.clear();
        _hasCustomProxyEndpoint = false;
      });
      _showSuccessMessage('已清空自定义代理地址，关闭代理时将直接访问原链接');
      return;
    }

    final uri = Uri.tryParse(sanitized);
    final isValidUri = uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    if (!isValidUri) {
      _showErrorMessage('请输入有效的 http/https 代理地址');
      return;
    }

    final normalized = sanitized.endsWith('/')
        ? sanitized.substring(0, sanitized.length - 1)
        : sanitized;
    await prefs.setString(AppConstants.goProxyEndpointKey, normalized);

    if (!mounted) {
      return;
    }
    setState(() {
      _customProxyEndpoint = normalized;
      _proxyEndpointController.text = normalized;
      _hasCustomProxyEndpoint = true;
    });
    _showSuccessMessage('代理地址已保存');
  }

  Future<void> _resetProxyEndpoint() async {
    await _saveProxyEndpoint('');
  }

  String _resolveBridgeEndpoint(SharedPreferences prefs) {
    final fallback = (prefs.getString(AppConstants.dbGoBridgeUrlKey) ??
            AppConstants.defaultGoBridgeEndpoint)
        .trim();
    return fallback.isEmpty ? AppConstants.defaultGoBridgeEndpoint : fallback;
  }

  bool get _canEditCustomProxy => _isGoBridgeDriver && !_goProxyEnabled;

  String get _effectiveProxyLabel {
    if (_goProxyEnabled) {
      return _bridgeEndpoint;
    }
    if (_customProxyEndpoint.isNotEmpty) {
      return _customProxyEndpoint;
    }
    return '未配置（关闭代理时将直接访问原始链接）';
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
          if (_statusMessage != null) _buildStatusBanner(),
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
          _buildProxySection(),
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
    _proxyEndpointController.dispose();
    super.dispose();
  }

  Widget _buildProxySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '网络代理',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('通过 Go 服务代理播放'),
          subtitle: Text(
            _isGoBridgeDriver
                ? (_goProxyEnabled
                    ? '已启用：使用数据库中的 Go 服务地址'
                    : '关闭后可以改用下方自定义的 Go 服务代理地址')
                : '切换到“本地 Go 服务”数据库驱动后才可启用此代理',
          ),
          value: _goProxyEnabled && _isGoBridgeDriver,
          onChanged: _isGoBridgeDriver ? _updateGoProxy : null,
          secondary: const Icon(Icons.shield_outlined),
        ),
        const SizedBox(height: 8),
        SelectableText.rich(
          TextSpan(
            text: '优先级说明：',
            style: const TextStyle(fontWeight: FontWeight.bold),
            children: [
              TextSpan(
                text:
                    '开启开关时会固定走数据库配置的 Go 服务（$_bridgeEndpoint）；关闭后才使用下方自定义地址，留空则直接访问原始链接。',
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _proxyEndpointController,
                enabled: _canEditCustomProxy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Go 服务代理地址',
                  hintText: AppConstants.defaultGoBridgeEndpoint,
                  helperText: _goProxyEnabled
                      ? '已开启代理开关，当前使用数据库配置，需关闭后才能编辑'
                      : (_hasCustomProxyEndpoint
                          ? '已覆盖数据库配置，可点击“恢复数据库配置”撤销'
                          : '留空时将直接访问原始链接'),
                  prefixIcon: const Icon(Icons.link_outlined),
                ),
                onSubmitted: _canEditCustomProxy
                    ? (value) {
                        _saveProxyEndpoint(value);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _canEditCustomProxy
                  ? () {
                      _saveProxyEndpoint(_proxyEndpointController.text);
                    }
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _canEditCustomProxy && _hasCustomProxyEndpoint
                ? () {
                    _resetProxyEndpoint();
                  }
                : null,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('恢复数据库配置'),
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          '当前生效地址：$_effectiveProxyLabel',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    final color = _statusIsError ? Colors.red : Colors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SelectableText.rich(
        TextSpan(
          text: _statusMessage!,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
