package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	_ "github.com/sijms/go-ora/v2"
	"gopkg.in/yaml.v3"
)

var placeholderPattern = regexp.MustCompile(`@([a-zA-Z0-9_]+)`) // matches @param

// Config describes Go bridge settings.
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

func loadConfig() (Config, error) {
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

	if cfg.Listen == "" {
		cfg.Listen = ":7788"
	}
	if cfg.Driver == "" {
		return Config{}, errors.New("driver is required (mysql|postgres|oracle)")
	}
	if cfg.DSN == "" {
		return Config{}, errors.New("dsn is required")
	}
	if cfg.MaxOpenConns == 0 {
		cfg.MaxOpenConns = 5
	}
	if cfg.MaxIdleConns == 0 {
		cfg.MaxIdleConns = 2
	}
	if cfg.ScreenshotDir == "" {
		cfg.ScreenshotDir = filepath.Join("data", "screenshots")
	}
	cfg.ScreenshotDir = filepath.Clean(cfg.ScreenshotDir)
	return cfg, nil
}

func connectDatabase(cfg Config) (*sqlx.DB, error) {
	db, err := sqlx.Open(cfg.Driver, cfg.DSN)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetMaxIdleConns(cfg.MaxIdleConns)
	if cfg.ConnMaxLife != "" {
		if d, err := time.ParseDuration(cfg.ConnMaxLife); err == nil {
			db.SetConnMaxLifetime(d)
		}
	}
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return db, nil
}

func convertPlaceholders(sqlText, prefix string) (string, []string) {
	var names []string
	converted := placeholderPattern.ReplaceAllStringFunc(sqlText, func(match string) string {
		name := strings.TrimPrefix(match, "@")
		names = append(names, name)
		if prefix != "" {
			name = prefix + name
		}
		return ":" + name
	})
	return converted, names
}

func convertNamed(whereClause string, prefix string, args map[string]any) (string, map[string]any, error) {
	converted := placeholderPattern.ReplaceAllStringFunc(whereClause, func(match string) string {
		key := strings.TrimPrefix(match, "@")
		return ":" + prefix + key
	})
	convertedArgs := make(map[string]any, len(args))
	for k, v := range args {
		convertedArgs[prefix+k] = v
	}
	return converted, convertedArgs, nil
}

func sanitizeIdentifier(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", errors.New("identifier is empty")
	}
	for _, r := range trimmed {
		if !(r == '_' || r == '.' || (r >= '0' && r <= '9') || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
			return "", fmt.Errorf("invalid identifier: %s", value)
		}
	}
	return trimmed, nil
}

func bindJSON[T any](c *gin.Context, dest *T) bool {
	if err := c.ShouldBindJSON(dest); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return false
	}
	return true
}

func newRouter(db *sqlx.DB, cfg Config) *gin.Engine {
	r := gin.Default()

	if cfg.AuthToken != "" {
		r.Use(func(c *gin.Context) {
			auth := c.GetHeader("Authorization")
			if auth != "Bearer "+cfg.AuthToken {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
				return
			}
		})
	}

	r.GET("/health", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()
		if err := db.PingContext(ctx); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "details": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	type sqlRequest struct {
		SQL        string         `json:"sql"`
		Parameters map[string]any `json:"parameters"`
	}

	r.POST("/sql/query", func(c *gin.Context) {
		var req sqlRequest
		if !bindJSON(c, &req) {
			return
		}
		if strings.TrimSpace(req.SQL) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "sql is required"})
			return
		}
		normalizedSQL, _ := convertPlaceholders(req.SQL, "")
		rows, err := db.NamedQueryContext(c.Request.Context(), normalizedSQL, req.Parameters)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()
		var result []map[string]any
		for rows.Next() {
			row := map[string]any{}
			if err := rows.MapScan(row); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			for k, v := range row {
				if b, ok := v.([]byte); ok {
					row[k] = string(b)
				}
			}
			result = append(result, row)
		}
		c.JSON(http.StatusOK, gin.H{"rows": result})
	})

	type insertRequest struct {
		Table  string         `json:"table"`
		Values map[string]any `json:"values"`
	}

	r.POST("/sql/insert", func(c *gin.Context) {
		var req insertRequest
		if !bindJSON(c, &req) {
			return
		}
		table, err := sanitizeIdentifier(req.Table)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if len(req.Values) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "values is required"})
			return
		}
		columns := make([]string, 0, len(req.Values))
		placeholders := make([]string, 0, len(req.Values))
		namedValues := make(map[string]any, len(req.Values))
		for k, v := range req.Values {
			col, err := sanitizeIdentifier(k)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}
			columns = append(columns, col)
			placeholders = append(placeholders, ":val_"+col)
			namedValues["val_"+col] = v
		}
		query := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)", table, strings.Join(columns, ","), strings.Join(placeholders, ","))
		res, err := db.NamedExecContext(c.Request.Context(), query, namedValues)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		lastID, _ := res.LastInsertId()
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"lastInsertId": lastID, "rowsAffected": rowsAffected})
	})

	type updateRequest struct {
		Table    string         `json:"table"`
		Values   map[string]any `json:"values"`
		Where    string         `json:"where"`
		WhereArg map[string]any `json:"whereArgs"`
	}

	r.POST("/sql/update", func(c *gin.Context) {
		var req updateRequest
		if !bindJSON(c, &req) {
			return
		}
		table, err := sanitizeIdentifier(req.Table)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if len(req.Values) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "values is required"})
			return
		}
		setParts := make([]string, 0, len(req.Values))
		params := make(map[string]any, len(req.Values)+(len(req.WhereArg)*2))
		for k, v := range req.Values {
			col, err := sanitizeIdentifier(k)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}
			key := "set_" + col
			setParts = append(setParts, fmt.Sprintf("%s = :%s", col, key))
			params[key] = v
		}
		whereClause, convertedArgs, err := convertNamed(req.Where, "cond_", req.WhereArg)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		for k, v := range convertedArgs {
			params[k] = v
		}
		query := fmt.Sprintf("UPDATE %s SET %s WHERE %s", table, strings.Join(setParts, ","), whereClause)
		res, err := db.NamedExecContext(c.Request.Context(), query, params)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"affectedRows": rowsAffected})
	})

	type deleteRequest struct {
		Table    string         `json:"table"`
		Where    string         `json:"where"`
		WhereArg map[string]any `json:"whereArgs"`
	}

	r.POST("/sql/delete", func(c *gin.Context) {
		var req deleteRequest
		if !bindJSON(c, &req) {
			return
		}
		table, err := sanitizeIdentifier(req.Table)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		whereClause, convertedArgs, err := convertNamed(req.Where, "cond_", req.WhereArg)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		query := fmt.Sprintf("DELETE FROM %s WHERE %s", table, whereClause)
		res, err := db.NamedExecContext(c.Request.Context(), query, convertedArgs)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"affectedRows": rowsAffected})
	})

	type screenshotUploadRequest struct {
		VideoSha1   string `json:"videoSha1"`
		UserID      int64  `json:"userId"`
		VideoName   string `json:"videoName"`
		VideoPath   string `json:"videoPath"`
		IsJpeg      bool   `json:"isJpeg"`
		ImageBase64 string `json:"imageBase64"`
	}

	r.POST("/history/screenshot", func(c *gin.Context) {
		var req screenshotUploadRequest
		if !bindJSON(c, &req) {
			return
		}
		req.VideoSha1 = strings.TrimSpace(req.VideoSha1)
		if req.VideoSha1 == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "videoSha1 is required"})
			return
		}
		if strings.TrimSpace(req.ImageBase64) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "imageBase64 is required"})
			return
		}
		sha1, err := sanitizeIdentifier(req.VideoSha1)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		imageBytes, err := base64.StdEncoding.DecodeString(req.ImageBase64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid imageBase64"})
			return
		}
		if len(imageBytes) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "image is empty"})
			return
		}

		userDir := fmt.Sprintf("%d", req.UserID)
		targetDir := filepath.Join(cfg.ScreenshotDir, userDir)
		if err := os.MkdirAll(targetDir, 0o755); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		ext := "png"
		contentType := "image/png"
		if req.IsJpeg {
			ext = "jpg"
			contentType = "image/jpeg"
		}

		fileName := fmt.Sprintf("%s_%s.%s", userDir, sha1, ext)
		fullPath := filepath.Join(targetDir, fileName)
		if err := os.WriteFile(fullPath, imageBytes, 0o644); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"status":      "ok",
			"contentType": contentType,
			"file":        fileName,
		})
	})

	r.GET("/history/screenshot", func(c *gin.Context) {
		videoSha1 := strings.TrimSpace(c.Query("videoSha1"))
		if videoSha1 == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "videoSha1 is required"})
			return
		}
		sha1, err := sanitizeIdentifier(videoSha1)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		userIDStr := strings.TrimSpace(c.Query("userId"))
		if userIDStr == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "userId is required"})
			return
		}
		userID, err := strconv.ParseInt(userIDStr, 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid userId"})
			return
		}
		userDir := fmt.Sprintf("%d", userID)
		targetDir := filepath.Join(cfg.ScreenshotDir, userDir)

		type candidate struct {
			path        string
			contentType string
		}

		candidates := []candidate{
			{
				path:        filepath.Join(targetDir, fmt.Sprintf("%s_%s.jpg", userDir, sha1)),
				contentType: "image/jpeg",
			},
			{
				path:        filepath.Join(targetDir, fmt.Sprintf("%s_%s.png", userDir, sha1)),
				contentType: "image/png",
			},
		}

		for _, cand := range candidates {
			data, err := os.ReadFile(cand.path)
			if err == nil {
				c.Data(http.StatusOK, cand.contentType, data)
				return
			}
			if !errors.Is(err, fs.ErrNotExist) {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
		}

		c.JSON(http.StatusNotFound, gin.H{"error": "screenshot not found"})
	})

	return r
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	absScreenshotDir, err := filepath.Abs(cfg.ScreenshotDir)
	if err != nil {
		log.Fatalf("resolve screenshot dir: %v", err)
	}
	cfg.ScreenshotDir = absScreenshotDir
	if err := os.MkdirAll(cfg.ScreenshotDir, 0o755); err != nil {
		log.Fatalf("create screenshot dir: %v", err)
	}

	db, err := connectDatabase(cfg)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer db.Close()

	router := newRouter(db, cfg)
	log.Printf("Go bridge listening on %s (driver=%s)", cfg.Listen, cfg.Driver)
	if err := router.Run(cfg.Listen); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}
