package proxy

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"
)

// hopMetricsPuller 定时向链路上游节点的 /proxy/metrics 拉取指标，用于前端分层展示。
type hopMetricsPuller struct {
	metrics   *Metrics
	hops      []ChainHop
	client    *http.Client
	interval  time.Duration
	stopCh    chan struct{}
	lastFetch map[string]time.Time
	lastWarn  map[string]time.Time
}

func newHopMetricsPuller(
	metrics *Metrics,
	hops []ChainHop,
	client *http.Client,
	interval time.Duration,
) *hopMetricsPuller {
	if interval <= 0 {
		interval = 15 * time.Second
	}
	if client == nil {
		client = defaultHTTPClient
	}
	return &hopMetricsPuller{
		metrics:   metrics,
		hops:      hops,
		client:    client,
		interval:  interval,
		stopCh:    make(chan struct{}),
		lastFetch: map[string]time.Time{},
		lastWarn:  map[string]time.Time{},
	}
}

func (p *hopMetricsPuller) start() {
	if len(p.hops) == 0 {
		return
	}
	go func() {
		ticker := time.NewTicker(p.interval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				p.pull()
			case <-p.stopCh:
				return
			}
		}
	}()
}

func (p *hopMetricsPuller) stop() {
	select {
	case <-p.stopCh:
		return
	default:
		close(p.stopCh)
	}
}

// pull 拉取每个 hop 的 /proxy/metrics，失败时保留错误信息。
func (p *hopMetricsPuller) pull() {
	if p.metrics == nil {
		return
	}
	hopSnapshots := make([]HopSnapshot, 0, len(p.hops))
	rootLogged := false // 同一批次仅关注首个疑似瓶颈节点，避免全链路重复告警。
	for _, hop := range p.hops {
		endpoint := strings.TrimRight(hop.Endpoint, "/")
		if endpoint == "" {
			continue
		}
		url := endpoint + "/proxy/metrics"

		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			hopSnapshots = append(hopSnapshots, HopSnapshot{
				Endpoint: endpoint,
				Error:    err.Error(),
				Status:   http.StatusBadRequest,
			})
			continue
		}
		if hop.AuthToken != "" {
			req.Header.Set("Authorization", "Bearer "+hop.AuthToken)
		}

		resp, err := p.client.Do(req)
		if err != nil {
			hopSnapshots = append(hopSnapshots, HopSnapshot{
				Endpoint: endpoint,
				Error:    err.Error(),
				Status:   http.StatusBadGateway,
			})
			continue
		}
		func() {
			defer resp.Body.Close()
			var snap MetricsSnapshot
			if err := json.NewDecoder(resp.Body).Decode(&snap); err != nil {
				hopSnapshots = append(hopSnapshots, HopSnapshot{
					Endpoint: endpoint,
					Error:    err.Error(),
					Status:   http.StatusBadGateway,
				})
				return
			}
			last := snap.LastUpdated
			stale := time.Since(last).Seconds()
			hopSnap := HopSnapshot{
				Endpoint:       endpoint,
				Success:        snap.SuccessRate,
				P50:            snap.P50LatencyMs,
				P90:            snap.P90LatencyMs,
				P99:            snap.P99LatencyMs,
				RPM:            snap.RequestsPerMinute,
				ThroughputKbps: snap.AvgThroughputKbps,
				Error:          snap.LastError,
				Status:         snap.LastStatus,
				StaleSec:       stale,
			}
			hopSnapshots = append(hopSnapshots, hopSnap)
			if p.isSlow(hopSnap) && !rootLogged {
				p.maybeWarnSlow(endpoint, hopSnap)
				rootLogged = true
			}
			p.lastFetch[endpoint] = time.Now()
		}()
	}
	p.metrics.AttachHops(hopSnapshots)
}

// isSlow 基于阈值判定节点是否疑似瓶颈。
func (p *hopMetricsPuller) isSlow(snap HopSnapshot) bool {
	const (
		minThroughputKbps = 512  // 判定瓶颈的下限，约 0.5 MB/s。
		maxP90LatencyMs   = 2000 // P90 超过 2s 认为过慢。
	)
	if snap.ThroughputKbps > 0 && snap.ThroughputKbps < minThroughputKbps {
		return true
	}
	if snap.P90 > maxP90LatencyMs {
		return true
	}
	return false
}

// maybeWarnSlow 持续监控单节点性能，低速时节流打印日志。
func (p *hopMetricsPuller) maybeWarnSlow(endpoint string, snap HopSnapshot) {
	const warnCooldown = 60 * time.Second
	if endpoint == "" {
		return
	}
	last := p.lastWarn[endpoint]
	if time.Since(last) < warnCooldown {
		return
	}
	if p.isSlow(snap) {
		log.Printf(
			"proxy hop slow: endpoint=%s throughput=%.1f kbps p90=%.0fms p50=%.0fms success=%.2f status=%d error=%s",
			endpoint,
			snap.ThroughputKbps,
			snap.P90,
			snap.P50,
			snap.Success,
			snap.Status,
			snap.Error,
		)
		p.lastWarn[endpoint] = time.Now()
	}
}
