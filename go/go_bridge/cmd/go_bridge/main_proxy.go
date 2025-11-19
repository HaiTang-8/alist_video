//go:build proxy_only

package main

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/zhouquan/webdav_video/go_bridge/internal/appconfig"
	"github.com/zhouquan/webdav_video/go_bridge/internal/modules/proxy"
	"github.com/zhouquan/webdav_video/go_bridge/internal/server"
)

// 仅代理模式用于需要轻量代理能力的桌面/移动端节点。
func main() {
	cfg, err := appconfig.Load(false)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	router := server.NewRouter(
		cfg,
		proxy.NewRegistrar(nil, toProxyChain(cfg.ProxyChain)),
	)

	log.Printf("Go bridge (proxy only) listening on %s", cfg.Listen)
	if err := router.Run(cfg.Listen); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}

func toProxyChain(hops []appconfig.ProxyChainHop) []proxy.ChainHop {
	if len(hops) == 0 {
		return nil
	}
	result := make([]proxy.ChainHop, 0, len(hops))
	for _, hop := range hops {
		endpoint := strings.TrimSpace(hop.Endpoint)
		if endpoint == "" {
			continue
		}
		result = append(result, proxy.ChainHop{
			Endpoint:  endpoint,
			AuthToken: strings.TrimSpace(hop.AuthToken),
		})
	}
	return result
}
