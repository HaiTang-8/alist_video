package server

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/zhouquan/webdav_video/go_bridge/internal/appconfig"
)

// RouteRegistrar 抽象每个功能模块的路由注册行为。
type RouteRegistrar interface {
	Register(r *gin.Engine)
}

// NewRouter 基于公共配置创建 gin 引擎，并应用鉴权及模块路由。
func NewRouter(cfg appconfig.Config, registrars ...RouteRegistrar) *gin.Engine {
	r := gin.Default()

	if cfg.AuthToken != "" {
		expected := "Bearer " + cfg.AuthToken
		r.Use(func(c *gin.Context) {
			auth := c.GetHeader("Authorization")
			tokenQuery := strings.TrimSpace(c.Query("access_token"))

			if auth == expected || tokenQuery == cfg.AuthToken {
				if tokenQuery == cfg.AuthToken {
					params := c.Request.URL.Query()
					params.Del("access_token")
					c.Request.URL.RawQuery = params.Encode()
				}
				c.Next()
				return
			}

			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		})
	}

	for _, registrar := range registrars {
		if registrar == nil {
			continue
		}
		registrar.Register(r)
	}

	return r
}
