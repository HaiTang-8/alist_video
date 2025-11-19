package database

import (
	"fmt"

	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	_ "github.com/sijms/go-ora/v2"

	"github.com/zhouquan/webdav_video/go_bridge/internal/appconfig"
)

// Connect 根据配置建立数据库连接，并设置连接池参数。
func Connect(cfg appconfig.Config) (*sqlx.DB, error) {
	db, err := sqlx.Open(cfg.Driver, cfg.DSN)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetMaxIdleConns(cfg.MaxIdleConns)
	if lifetime, ok := cfg.ConnMaxLifetime(); ok {
		db.SetConnMaxLifetime(lifetime)
	}
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return db, nil
}
