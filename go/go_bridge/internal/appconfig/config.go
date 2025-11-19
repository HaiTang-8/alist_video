package appconfig

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

// Config 描述 Go 桥服务的公共配置，既可用于完整模式，也可用于仅代理模式。
type Config struct {
	Listen        string `yaml:"listen"`
	Driver        string `yaml:"driver"`
	DSN           string `yaml:"dsn"`
	AuthToken     string `yaml:"authToken"`
	MaxOpenConns  int    `yaml:"maxOpenConns"`
	MaxIdleConns  int    `yaml:"maxIdleConns"`
	ConnMaxLife   string `yaml:"connMaxLifetime"`
	ScreenshotDir string `yaml:"screenshotDir"`
}

// Load 从配置文件加载实例；当 requireDatabase=false 时允许省略数据库字段，
// 便于编译仅包含代理功能的精简包。
func Load(requireDatabase bool) (Config, error) {
	cfgPath := os.Getenv("GO_BRIDGE_CONFIG")
	if cfgPath == "" {
		cfgPath = "config.yaml"
	}

	raw, err := os.ReadFile(cfgPath)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}

	if err := cfg.normalize(requireDatabase); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// normalize 填充默认值并视情况校验必填字段。
func (c *Config) normalize(requireDatabase bool) error {
	if c.Listen == "" {
		c.Listen = ":7788"
	}
	if c.MaxOpenConns == 0 {
		c.MaxOpenConns = 5
	}
	if c.MaxIdleConns == 0 {
		c.MaxIdleConns = 2
	}
	if c.ScreenshotDir == "" {
		c.ScreenshotDir = filepath.Join("data", "screenshots")
	}
	c.ScreenshotDir = filepath.Clean(c.ScreenshotDir)

	if requireDatabase {
		if c.Driver == "" {
			return errors.New("driver is required in full mode")
		}
		if c.DSN == "" {
			return errors.New("dsn is required in full mode")
		}
	}
	return nil
}

// EnsureScreenshotDir 确保截图目录存在，跨端部署时可直接复用。
func (c *Config) EnsureScreenshotDir() error {
	abs, err := filepath.Abs(c.ScreenshotDir)
	if err != nil {
		return fmt.Errorf("resolve screenshot dir: %w", err)
	}
	c.ScreenshotDir = abs
	if err := os.MkdirAll(c.ScreenshotDir, 0o755); err != nil {
		return fmt.Errorf("create screenshot dir: %w", err)
	}
	return nil
}

// ConnMaxLifetime 解析连接最大生命周期，便于数据库模块配置连接池。
func (c Config) ConnMaxLifetime() (time.Duration, bool) {
	if c.ConnMaxLife == "" {
		return 0, false
	}
	d, err := time.ParseDuration(c.ConnMaxLife)
	if err != nil {
		return 0, false
	}
	return d, true
}
