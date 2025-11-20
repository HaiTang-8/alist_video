package proxy

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// 默认代理客户端与缓冲池，跨端重用时可避免重复创建带来的性能损耗。
var (
	defaultHTTPClient = &http.Client{
		Transport: &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			MaxIdleConns:          256,
			MaxIdleConnsPerHost:   64,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   15 * time.Second,
			ResponseHeaderTimeout: 15 * time.Second,
			ForceAttemptHTTP2:     true,
		},
		Timeout: 0,
	}
	bufferPool = sync.Pool{
		New: func() interface{} { return make([]byte, 1<<20) },
	}
)

// Registrar 将代理处理器注册到主路由，可单独编译为精简包。
type Registrar struct {
	Client *http.Client
	Chain  []ChainHop
	// metrics 用于对代理质量进行持续埋点并对外暴露。
	metrics *Metrics
	// hopPuller 周期拉取上游节点的 metrics，便于前端逐 hop 展示。
	hopPuller *hopMetricsPuller
}

// ChainHop 描述一次代理下一跳的目标地址与访问令牌。
type ChainHop struct {
	Endpoint  string
	AuthToken string
}

// NewRegistrar 创建代理模块，允许调用侧注入自定义 HTTP 客户端（例如桌面端代理链）。
func NewRegistrar(client *http.Client, chain []ChainHop) *Registrar {
	if client == nil {
		client = defaultHTTPClient
	}
	metrics := NewMetrics(120)
	return &Registrar{
		Client:  client,
		Chain:   chain,
		metrics: metrics,
		hopPuller: newHopMetricsPuller(
			metrics,
			chain,
			client,
			time.Second*15,
		),
	}
}

// Register 绑定 /proxy/media，透传 Range/User-Agent 等头保证播放器兼容。
func (r *Registrar) Register(engine *gin.Engine) {
	if engine == nil {
		return
	}
	client := r.Client
	if client == nil {
		client = defaultHTTPClient
	}

	// OPTIONS 便于跨端播放器执行预检请求。
	engine.OPTIONS("/proxy/media", func(c *gin.Context) {
		setCORSHeaders(c)
		c.Status(http.StatusNoContent)
	})

	// 暴露代理质量监控数据，供 Flutter 端展示。
	engine.GET("/proxy/metrics", func(c *gin.Context) {
		c.JSON(http.StatusOK, r.metrics.Snapshot())
	})

	// 启动上游指标轮询。
	r.hopPuller.start()

	engine.HEAD("/proxy/media", r.proxyHandler(client, http.MethodHead, false))
	engine.GET("/proxy/media", r.proxyHandler(client, http.MethodGet, true))
}

// proxyHandler 按方法代理媒体流，可复用 GET/HEAD。
func (r *Registrar) proxyHandler(client *http.Client, method string, withBody bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		setCORSHeaders(c)
		target := c.Query("target")
		if strings.TrimSpace(target) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "target is required"})
			return
		}

		parsed, err := url.Parse(target)
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid target url"})
			return
		}

		forwardTarget, hopHeaders, err := r.buildChainedTarget(parsed.String())
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		req, err := http.NewRequestWithContext(
			c.Request.Context(),
			method,
			forwardTarget,
			nil,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("proxy request build failed: %v", err)})
			return
		}
		for key, values := range hopHeaders {
			for _, value := range values {
				req.Header.Add(key, value)
			}
		}

		forwardHeaders := []string{
			"Range",
			"User-Agent",
			"Accept",
			"Accept-Language",
			"Accept-Encoding",
			"Origin",
			"Referer",
			"Authorization",
			"Cookie",
			"If-None-Match",
			"If-Modified-Since",
			"Cache-Control",
			"Pragma",
			"X-Requested-With",
			"X-Custom-Signature",
			"X-Forwarded-For",
			"X-Forwarded-Proto",
		}
		for _, key := range forwardHeaders {
			if value := c.GetHeader(key); value != "" {
				req.Header.Set(key, value)
			}
		}
		stripHopByHop(req.Header)

		start := time.Now()
		resp, err := client.Do(req)
		if err != nil {
			r.metrics.Record(time.Since(start), 0, false, http.StatusBadGateway, err.Error())
			c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("proxy request failed: %v", err)})
			return
		}
		defer resp.Body.Close()

		copyResponseHeaders(c.Writer.Header(), resp.Header)
		c.Writer.WriteHeader(resp.StatusCode)
		if !withBody {
			success := resp.StatusCode < http.StatusBadRequest
			r.metrics.Record(time.Since(start), 0, success, resp.StatusCode, "")
			return
		}

		buf := bufferPool.Get().([]byte)
		defer bufferPool.Put(buf)

		// MultiWriter 记录响应体大小，便于估算吞吐。
		var byteCount int64
		counter := &writeCounter{target: c.Writer, countPtr: &byteCount}

		// 若下游关闭连接，尽快中断上游读取，避免占用 goroutine。
		stopCh := make(chan struct{})
		go func() {
			select {
			case <-c.Request.Context().Done():
				_ = resp.Body.Close()
			case <-stopCh:
			}
		}()

		if _, err := io.CopyBuffer(counter, resp.Body, buf); err != nil {
			if !errors.Is(err, context.Canceled) && !errors.Is(err, io.EOF) {
				log.Printf("proxy stream interrupted: %v", err)
			}
		}
		close(stopCh)

		success := resp.StatusCode < http.StatusBadRequest
		r.metrics.Record(time.Since(start), byteCount, success, resp.StatusCode, "")
	}
}

func (r *Registrar) buildChainedTarget(original string) (string, http.Header, error) {
	if len(r.Chain) == 0 {
		return original, http.Header{}, nil
	}
	current := original
	headers := http.Header{}
	for i := len(r.Chain) - 1; i >= 0; i-- {
		hop := r.Chain[i]
		endpoint := strings.TrimSpace(hop.Endpoint)
		if endpoint == "" {
			continue
		}
		endpoint = strings.TrimRight(endpoint, "/")
		proxyURL, err := url.Parse(endpoint + "/proxy/media")
		if err != nil {
			return original, nil, fmt.Errorf("invalid chain endpoint: %s", hop.Endpoint)
		}
		params := proxyURL.Query()
		params.Set("target", current)
		if hop.AuthToken != "" {
			params.Set("access_token", hop.AuthToken)
		}
		proxyURL.RawQuery = params.Encode()
		current = proxyURL.String()
		if i == 0 && hop.AuthToken != "" {
			// 第一跳使用头部与查询双通道鉴权，以兼容不同上游配置。
			headers.Set("Authorization", "Bearer "+hop.AuthToken)
		}
	}
	return current, headers, nil
}

// setCORSHeaders 允许跨端播放器发起预检与跨域访问。
func setCORSHeaders(c *gin.Context) {
	origin := c.GetHeader("Origin")
	if origin == "" {
		origin = "*"
	}
	headers := c.Writer.Header()
	headers.Set("Access-Control-Allow-Origin", origin)
	headers.Set("Vary", "Origin")
	headers.Set("Access-Control-Allow-Headers", "*")
	headers.Set("Access-Control-Allow-Methods", "GET,HEAD,OPTIONS")
}

// stripHopByHop 清理 hop-by-hop 头部，避免代理链出现连接升级问题。
func stripHopByHop(h http.Header) {
	hopByHop := []string{
		"Connection",
		"Proxy-Connection",
		"Keep-Alive",
		"Proxy-Authenticate",
		"Proxy-Authorization",
		"TE",
		"Trailer",
		"Transfer-Encoding",
		"Upgrade",
	}
	for _, key := range hopByHop {
		h.Del(key)
	}
}

// copyResponseHeaders 过滤 hop-by-hop 后再复制响应头。
func copyResponseHeaders(dst, src http.Header) {
	for key, values := range src {
		upper := strings.ToLower(key)
		switch upper {
		case "connection", "proxy-connection", "keep-alive",
			"proxy-authenticate", "proxy-authorization",
			"te", "trailer", "transfer-encoding", "upgrade":
			continue
		}
		for _, v := range values {
			dst.Add(key, v)
		}
	}
}

// writeCounter 用于在转发时统计写入字节数，不影响原有响应输出。
type writeCounter struct {
	target   io.Writer
	countPtr *int64
}

func (w *writeCounter) Write(p []byte) (int, error) {
	n, err := w.target.Write(p)
	if w.countPtr != nil {
		*w.countPtr += int64(n)
	}
	return n, err
}
