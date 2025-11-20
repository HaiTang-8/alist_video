package proxy

import (
	"encoding/json"
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
			hopSnapshots = append(hopSnapshots, HopSnapshot{
				Endpoint: endpoint,
				Success:  snap.SuccessRate,
				P50:      snap.P50LatencyMs,
				P90:      snap.P90LatencyMs,
				P99:      snap.P99LatencyMs,
				RPM:      snap.RequestsPerMinute,
				ThroughputKbps: snap.AvgThroughputKbps,
				Error:    snap.LastError,
				Status:   snap.LastStatus,
				StaleSec: stale,
			})
			p.lastFetch[endpoint] = time.Now()
		}()
	}
	p.metrics.AttachHops(hopSnapshots)
}
