package proxy

import (
	"sort"
	"sync"
	"time"
)

// sample 描述一次代理请求的耗时与结果，用于计算窗口统计。
type sample struct {
	latency time.Duration
	bytes   int64
	success bool
	status  int
	err     string
	t       time.Time
}

// Metrics 在内存中维护最近窗口的代理质量数据。
type Metrics struct {
	mu     sync.Mutex
	buf    []sample
	next   int
	filled bool
	hops   []HopSnapshot

	totalRequests int64
	totalErrors   int64
	totalBytes    int64
	lastError     string
	lastStatus    int
	lastUpdated   time.Time
}

// MetricsSnapshot 将内部数据投影为可序列化的结果。
type MetricsSnapshot struct {
	WindowSamples          int           `json:"window_samples"`
	Samples                int           `json:"samples"`
	TotalRequests          int64         `json:"total_requests"`
	TotalErrors            int64         `json:"total_errors"`
	TotalBytes             int64         `json:"total_bytes"`
	SuccessRate            float64       `json:"success_rate"`
	AvgLatencyMs           float64       `json:"avg_latency_ms"`
	P50LatencyMs           float64       `json:"p50_latency_ms"`
	P90LatencyMs           float64       `json:"p90_latency_ms"`
	P99LatencyMs           float64       `json:"p99_latency_ms"`
	AvgThroughputKbps      float64       `json:"avg_throughput_kbps"`
	RequestsPerMinute      float64       `json:"requests_per_minute"`
	LastStatus             int           `json:"last_status"`
	LastError              string        `json:"last_error"`
	LastUpdated            time.Time     `json:"last_updated"`
	WindowDurationSec      float64       `json:"window_duration_sec"`
	AvailableSampleSpanSec float64       `json:"available_sample_span_sec"`
	Hops                   []HopSnapshot `json:"hops"`
}

// HopSnapshot 描述单个链路节点的指标，用于前端逐层呈现。
type HopSnapshot struct {
	Endpoint string  `json:"endpoint"`
	Success  float64 `json:"success_rate"`
	P50      float64 `json:"p50_latency_ms"`
	P90      float64 `json:"p90_latency_ms"`
	P99      float64 `json:"p99_latency_ms"`
	RPM      float64 `json:"requests_per_minute"`
	ThroughputKbps float64 `json:"avg_throughput_kbps"`
	Error    string  `json:"last_error,omitempty"`
	Status   int     `json:"last_status,omitempty"`
	StaleSec float64 `json:"stale_seconds,omitempty"`
}

// NewMetrics 创建定长窗口的内存指标，窗口大小受 bufferSize 控制。
func NewMetrics(bufferSize int) *Metrics {
	if bufferSize <= 0 {
		bufferSize = 120
	}
	return &Metrics{
		buf: make([]sample, bufferSize),
	}
}

// Record 追加一次请求的指标；调用端应确保尽量在请求结束后调用。
func (m *Metrics) Record(
	latency time.Duration,
	bytes int64,
	success bool,
	status int,
	errMsg string,
) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.totalRequests++
	if !success {
		m.totalErrors++
		m.lastError = errMsg
	}
	m.totalBytes += bytes
	m.lastStatus = status
	m.lastUpdated = time.Now()

	m.buf[m.next] = sample{
		latency: latency,
		bytes:   bytes,
		success: success,
		status:  status,
		err:     errMsg,
		t:       m.lastUpdated,
	}

	m.next = (m.next + 1) % len(m.buf)
	if m.next == 0 {
		m.filled = true
	}
}

// Snapshot 返回当前窗口的统计摘要。
func (m *Metrics) Snapshot() MetricsSnapshot {
	m.mu.Lock()
	defer m.mu.Unlock()

	var (
		count     int
		successes int
		latencies []float64
		bytesSum  int64
		earliest  time.Time
	)

	// 按写入顺序聚合有效样本。
	limit := len(m.buf)
	if !m.filled {
		limit = m.next
	}

	for i := 0; i < limit; i++ {
		s := m.buf[i]
		if s.t.IsZero() {
			continue
		}
		if earliest.IsZero() || s.t.Before(earliest) {
			earliest = s.t
		}
		count++
		if s.success {
			successes++
		}
		bytesSum += s.bytes
		latencies = append(latencies, float64(s.latency.Milliseconds()))
	}

	snapshot := MetricsSnapshot{
		WindowSamples: len(m.buf),
		Samples:       count,
		TotalRequests: m.totalRequests,
		TotalErrors:   m.totalErrors,
		TotalBytes:    m.totalBytes,
		LastError:     m.lastError,
		LastStatus:    m.lastStatus,
		LastUpdated:   m.lastUpdated,
		Hops:          append([]HopSnapshot(nil), m.hops...),
	}

	if count == 0 {
		return snapshot
	}

	windowSpan := time.Since(earliest).Seconds()
	if windowSpan <= 0 {
		windowSpan = 1
	}
	snapshot.WindowDurationSec = float64(len(m.buf))
	snapshot.AvailableSampleSpanSec = windowSpan
	snapshot.SuccessRate = float64(successes) / float64(count)
	snapshot.RequestsPerMinute = float64(count) / (windowSpan / 60.0)

	// 计算平均延迟与分位值。
	var sum float64
	for _, l := range latencies {
		sum += l
	}
	snapshot.AvgLatencyMs = sum / float64(len(latencies))

	sort.Float64s(latencies)
	snapshot.P50LatencyMs = percentile(latencies, 50)
	snapshot.P90LatencyMs = percentile(latencies, 90)
	snapshot.P99LatencyMs = percentile(latencies, 99)

	// 平均吞吐，按下载阶段粗略估计。
	snapshot.AvgThroughputKbps = 0
	if sum > 0 {
		// sum 是总的毫秒，bytesSum 是字节。
		snapshot.AvgThroughputKbps = (float64(bytesSum) / 1024.0) / (sum / 1000.0)
	}

	return snapshot
}

// AttachHops 用外部拉取的 hop 指标更新当前快照，线程安全。
func (m *Metrics) AttachHops(hops []HopSnapshot) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.hops = hops
}

func percentile(latencies []float64, p int) float64 {
	if len(latencies) == 0 {
		return 0
	}
	if p <= 0 {
		return latencies[0]
	}
	if p >= 100 {
		return latencies[len(latencies)-1]
	}
	rank := float64(p) / 100.0 * float64(len(latencies)-1)
	lower := int(rank)
	upper := lower + 1
	if upper >= len(latencies) {
		return latencies[lower]
	}
	weight := rank - float64(lower)
	return latencies[lower]*(1-weight) + latencies[upper]*weight
}
