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
    final nodes = _buildNodeViews(metrics);
    final bottleneck = _pickBottleneck(nodes);
    final success = bottleneck?.successRate ?? 0;
    final color = success >= 0.99
        ? Colors.green
        : (success >= 0.95 ? Colors.orange : Colors.red);
    final title = _loading ? '刷新中...' : '瓶颈：${bottleneck?.label ?? '等待数据'}';
    final subtitle = bottleneck == null
        ? 'RTT ${_clientRttMs?.toStringAsFixed(0) ?? "--"} ms'
        : 'RTT ${_clientRttMs?.toStringAsFixed(0) ?? "--"} ms · '
            '成功率 ${(success * 100).toStringAsFixed(1)}% · '
            '${bottleneck.throughputLabel} · '
            'P90 ${bottleneck.p90LatencyMs.toStringAsFixed(0)} ms';

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
                  ? _buildDetailCard(context, bottleneck, nodes, color)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context,
    _NodeView? bottleneck,
    List<_NodeView> nodes,
    Color color,
  ) {
    if (nodes.isEmpty) {
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
            '当前最慢：${bottleneck?.label ?? "--"}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          ...nodes.map(
            (node) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.adjust,
                    size: 14,
                    color: node.color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${node.label} · '
                      '成功率 ${(node.successRate * 100).toStringAsFixed(2)}% · '
                      '${node.throughputLabel} · '
                      'P90 ${node.p90LatencyMs.toStringAsFixed(0)} ms',
                      style: TextStyle(fontSize: 11, color: node.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_NodeView> _buildNodeViews(ProxyMetrics? metrics) {
    if (metrics == null) return const [];
    final list = <_NodeView>[
      _NodeView(
        label: '入口(Go)',
        successRate: metrics.successRate,
        p90LatencyMs: metrics.p90LatencyMs,
        throughputKbps: metrics.avgThroughputKbps,
      ),
      ...metrics.hops.map(
        (hop) => _NodeView(
          label: hop.endpoint,
          successRate: hop.successRate,
          p90LatencyMs: hop.p90LatencyMs,
          throughputKbps: hop.throughputKbps,
        ),
      ),
    ];
    return list;
  }

  _NodeView? _pickBottleneck(List<_NodeView> nodes) {
    if (nodes.isEmpty) return null;
    nodes.sort((a, b) {
      final sr = a.successRate.compareTo(b.successRate);
      if (sr != 0) return sr; // 成功率低更差
      final tp = a.throughputKbps.compareTo(b.throughputKbps);
      if (tp != 0) return tp; // 吞吐低更差
      return b.p90LatencyMs.compareTo(a.p90LatencyMs); // 延迟高更差
    });
    return nodes.first;
  }
}

class _NodeView {
  final String label;
  final double successRate;
  final double p90LatencyMs;
  final double throughputKbps;

  _NodeView({
    required this.label,
    required this.successRate,
    required this.p90LatencyMs,
    required this.throughputKbps,
  });

  Color get color => successRate >= 0.99
      ? Colors.green
      : (successRate >= 0.95 ? Colors.orange : Colors.red);

  String get throughputLabel => '${throughputKbps.toStringAsFixed(1)} KB/s';
}
