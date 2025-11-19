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
			Proxy:               http.ProxyFromEnvironment,
			MaxIdleConns:        256,
			MaxIdleConnsPerHost: 64,
			IdleConnTimeout:     90 * time.Second,
			ForceAttemptHTTP2:   true,
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
	return &Registrar{Client: client, Chain: chain}
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

	engine.GET("/proxy/media", func(c *gin.Context) {
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

		req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, forwardTarget, nil)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("proxy request build failed: %v", err)})
			return
		}
		for key, values := range hopHeaders {
			for _, value := range values {
				req.Header.Add(key, value)
			}
		}

		forwardHeaders := []string{"Range", "User-Agent", "Accept", "Referer"}
		for _, key := range forwardHeaders {
			if value := c.GetHeader(key); value != "" {
				req.Header.Set(key, value)
			}
		}

		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("proxy request failed: %v", err)})
			return
		}
		defer resp.Body.Close()

		for key, values := range resp.Header {
			for _, value := range values {
				c.Writer.Header().Add(key, value)
			}
		}
		c.Writer.WriteHeader(resp.StatusCode)

		buf := bufferPool.Get().([]byte)
		defer bufferPool.Put(buf)

		if _, err := io.CopyBuffer(c.Writer, resp.Body, buf); err != nil {
			if !errors.Is(err, context.Canceled) && !errors.Is(err, io.EOF) {
				log.Printf("proxy stream interrupted: %v", err)
			}
		}
	})
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
			headers.Set("Authorization", "Bearer "+hop.AuthToken)
		}
	}
	return current, headers, nil
}
