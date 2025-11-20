/// 描述 Go 代理服务对外暴露的持续监控数据。
class ProxyMetrics {
  final int windowSamples;
  final int samples;
  final int totalRequests;
  final int totalErrors;
  final int totalBytes;
  final double successRate;
  final double avgLatencyMs;
  final double p50LatencyMs;
  final double p90LatencyMs;
  final double p99LatencyMs;
  final double avgThroughputKbps;
  final List<ProxyHopMetrics> hops;
  final double requestsPerMinute;
  final int lastStatus;
  final String? lastError;
  final DateTime? lastUpdated;
  final double windowDurationSec;
  final double availableSampleSpanSec;

  const ProxyMetrics({
    required this.windowSamples,
    required this.samples,
    required this.totalRequests,
    required this.totalErrors,
    required this.totalBytes,
    required this.successRate,
    required this.avgLatencyMs,
    required this.p50LatencyMs,
    required this.p90LatencyMs,
    required this.p99LatencyMs,
    required this.avgThroughputKbps,
    required this.requestsPerMinute,
    required this.lastStatus,
    required this.lastError,
    required this.lastUpdated,
    required this.windowDurationSec,
    required this.availableSampleSpanSec,
    required this.hops,
  });

  factory ProxyMetrics.fromJson(Map<String, dynamic> json) {
    return ProxyMetrics(
      windowSamples: json['window_samples'] as int? ?? 0,
      samples: json['samples'] as int? ?? 0,
      totalRequests: json['total_requests'] as int? ?? 0,
      totalErrors: json['total_errors'] as int? ?? 0,
      totalBytes: json['total_bytes'] as int? ?? 0,
      successRate: (json['success_rate'] as num?)?.toDouble() ?? 0,
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toDouble() ?? 0,
      p50LatencyMs: (json['p50_latency_ms'] as num?)?.toDouble() ?? 0,
      p90LatencyMs: (json['p90_latency_ms'] as num?)?.toDouble() ?? 0,
      p99LatencyMs: (json['p99_latency_ms'] as num?)?.toDouble() ?? 0,
      avgThroughputKbps: (json['avg_throughput_kbps'] as num?)?.toDouble() ?? 0,
      requestsPerMinute: (json['requests_per_minute'] as num?)?.toDouble() ?? 0,
      lastStatus: json['last_status'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'] as String)
          : null,
      windowDurationSec: (json['window_duration_sec'] as num?)?.toDouble() ?? 0,
      availableSampleSpanSec:
          (json['available_sample_span_sec'] as num?)?.toDouble() ?? 0,
      hops: ((json['hops'] as List<dynamic>?) ?? const [])
          .map(
            (e) => ProxyHopMetrics.fromJson(
              (e as Map<String, dynamic>?) ?? const {},
            ),
          )
          .toList(),
    );
  }
}

/// 单个代理节点的指标
class ProxyHopMetrics {
  final String endpoint;
  final double successRate;
  final double p50LatencyMs;
  final double p90LatencyMs;
  final double p99LatencyMs;
  final double throughputKbps;
  final double requestsPerMinute;
  final String? lastError;
  final int? lastStatus;
  final double staleSeconds;

  const ProxyHopMetrics({
    required this.endpoint,
    required this.successRate,
    required this.p50LatencyMs,
    required this.p90LatencyMs,
    required this.p99LatencyMs,
    required this.throughputKbps,
    required this.requestsPerMinute,
    required this.lastError,
    required this.lastStatus,
    required this.staleSeconds,
  });

  factory ProxyHopMetrics.fromJson(Map<String, dynamic> json) {
    return ProxyHopMetrics(
      endpoint: json['endpoint'] as String? ?? '',
      successRate: (json['success_rate'] as num?)?.toDouble() ?? 0,
      p50LatencyMs: (json['p50_latency_ms'] as num?)?.toDouble() ?? 0,
      p90LatencyMs: (json['p90_latency_ms'] as num?)?.toDouble() ?? 0,
      p99LatencyMs: (json['p99_latency_ms'] as num?)?.toDouble() ?? 0,
      throughputKbps: (json['avg_throughput_kbps'] as num?)?.toDouble() ?? 0,
      requestsPerMinute: (json['requests_per_minute'] as num?)?.toDouble() ?? 0,
      lastError: json['last_error'] as String?,
      lastStatus: json['last_status'] as int?,
      staleSeconds: (json['stale_seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}
