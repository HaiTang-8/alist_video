//go:build !proxy_only

package main

import (
	"errors"
	"log"
	"net/http"

	"github.com/zhouquan/webdav_video/go_bridge/internal/appconfig"
	"github.com/zhouquan/webdav_video/go_bridge/internal/database"
	"github.com/zhouquan/webdav_video/go_bridge/internal/modules/proxy"
	"github.com/zhouquan/webdav_video/go_bridge/internal/modules/screenshot"
	"github.com/zhouquan/webdav_video/go_bridge/internal/modules/sqlapi"
	"github.com/zhouquan/webdav_video/go_bridge/internal/server"
)

func main() {
	cfg, err := appconfig.Load(true)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	if err := cfg.EnsureScreenshotDir(); err != nil {
		log.Fatalf("ensure screenshot dir: %v", err)
	}

	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer db.Close()

	router := server.NewRouter(
		cfg,
		proxy.NewRegistrar(nil),
		sqlapi.NewRegistrar(db),
		screenshot.NewRegistrar(db, cfg),
	)

	log.Printf("Go bridge listening on %s (driver=%s)", cfg.Listen, cfg.Driver)
	if err := router.Run(cfg.Listen); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}
