import 'dart:async';

import 'package:alist_player/apis/proxy_metrics_api.dart';
import 'package:alist_player/models/proxy_metrics.dart';
import 'package:flutter/material.dart';

/// 视频播放界面右上角的小徽章，持续显示 Go 代理链路质量。
class ProxyQualityBadge extends StatefulWidget {
  final EdgeInsets padding;
  final Duration refreshInterval;

  const ProxyQualityBadge({
    super.key,
    this.padding = const EdgeInsets.all(8),
    this.refreshInterval = const Duration(seconds: 10),
  });

  @override
  State<ProxyQualityBadge> createState() => _ProxyQualityBadgeState();
}

class _ProxyQualityBadgeState extends State<ProxyQualityBadge> {
  ProxyMetrics? _metrics;
  String? _error;
  bool _loading = false;
  double? _clientRttMs;
  Timer? _timer;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _pull();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _pull());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pull() async {
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
    });
    try {
      final data = await ProxyMetricsApi.fetch();
      final rtt = sw.elapsedMilliseconds.toDouble();
      if (!mounted) return;
      setState(() {
        _metrics = data;
        _loading = false;
        _clientRttMs = rtt;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // 不中断展示，保留旧数据，仅标记为正在重试。
      setState(() {
        _loading = false;
        _clientRttMs = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    final success = metrics?.successRate ?? 0;
    final color = success >= 0.99
        ? Colors.green
        : (success >= 0.95 ? Colors.orange : Colors.red);
    final title =
        _loading ? '刷新中...' : '代理 ${(success * 100).toStringAsFixed(1)}%';
    final subtitle = metrics == null
        ? (_error ?? '等待数据')
        : 'RTT ${_clientRttMs?.toStringAsFixed(0) ?? "--"} ms · '
            'P50 ${metrics.p50LatencyMs.toStringAsFixed(0)} ms · '
            'RPM ${metrics.requestsPerMinute.toStringAsFixed(1)}';

    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: Alignment.topRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Material(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.network_check_outlined,
                        color: color,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more,
                          size: 16,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _expanded
                  ? _buildDetailCard(context, metrics, color)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context,
    ProxyMetrics? metrics,
    Color color,
  ) {
    if (metrics == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('detail'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '总体：${(metrics.successRate * 100).toStringAsFixed(2)}% · '
            '本机→Go RTT ${_clientRttMs?.toStringAsFixed(0) ?? "--"} ms · '
            'P50 ${metrics.p50LatencyMs.toStringAsFixed(0)} ms · '
            'P90 ${metrics.p90LatencyMs.toStringAsFixed(0)} ms',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          if (metrics.hops.isEmpty)
            Text(
              '未获取到链路节点数据',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            )
          else
            ...metrics.hops.map((hop) {
              final hopColor = hop.successRate >= 0.99
                  ? Colors.green
                  : (hop.successRate >= 0.95 ? Colors.orange : Colors.red);
              final stale = hop.staleSeconds > 60
                  ? ' (延迟 ${hop.staleSeconds.toStringAsFixed(0)}s)'
                  : '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hop.endpoint,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '成功率 ${(hop.successRate * 100).toStringAsFixed(2)}% · '
                      'P50 ${hop.p50LatencyMs.toStringAsFixed(0)} ms · '
                      'P90 ${hop.p90LatencyMs.toStringAsFixed(0)} ms · '
                      '下行 ${hop.throughputKbps.toStringAsFixed(1)} KB/s · '
                      'RPM ${hop.requestsPerMinute.toStringAsFixed(2)}$stale',
                      style: TextStyle(
                        fontSize: 11,
                        color: hopColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Text(
            '累计 ${metrics.totalRequests} 次 · 错误 ${metrics.totalErrors} · '
            '下行 ${(metrics.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      key: const ValueKey('error'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent),
      ),
      child: SelectableText(
        message,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}
