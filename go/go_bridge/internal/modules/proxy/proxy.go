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
}

// NewRegistrar 创建代理模块，允许调用侧注入自定义 HTTP 客户端（例如桌面端代理链）。
func NewRegistrar(client *http.Client) *Registrar {
	if client == nil {
		client = defaultHTTPClient
	}
	return &Registrar{Client: client}
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

		req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, parsed.String(), nil)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("proxy request build failed: %v", err)})
			return
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
