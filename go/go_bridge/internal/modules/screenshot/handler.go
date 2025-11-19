package screenshot

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"

	"github.com/zhouquan/webdav_video/go_bridge/internal/appconfig"
	"github.com/zhouquan/webdav_video/go_bridge/internal/server/httpjson"
)

// Registrar 负责截图上传与目录同步相关的 REST 接口。
type Registrar struct {
	DB     *sqlx.DB
	Config appconfig.Config
}

func NewRegistrar(db *sqlx.DB, cfg appconfig.Config) *Registrar {
	return &Registrar{DB: db, Config: cfg}
}

// Register 将上传与清理接口注入 gin，引擎会在跨端场景下共用。
func (r *Registrar) Register(engine *gin.Engine) {
	if engine == nil || r.DB == nil {
		return
	}

	engine.POST("/history/screenshot", func(c *gin.Context) {
		var req screenshotUploadRequest
		if !httpjson.BindJSON(c, &req) {
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
		destDir := filepath.Join(r.Config.ScreenshotDir, userDir)
		if err := os.MkdirAll(destDir, 0o755); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("mkdir: %v", err)})
			return
		}
		ext := "png"
		contentType := "image/png"
		if req.IsJpeg {
			ext = "jpg"
			contentType = "image/jpeg"
		}
		fileName := fmt.Sprintf("%s_%s.%s", userDir, sha1, ext)
		destPath := filepath.Join(destDir, fileName)
		if err := os.WriteFile(destPath, imageBytes, 0o644); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("write file: %v", err)})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"status":      "ok",
			"contentType": contentType,
			"file":        fileName,
		})
	})

	engine.GET("/history/screenshot", func(c *gin.Context) {
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
		targetDir := filepath.Join(r.Config.ScreenshotDir, userDir)

		candidates := []struct {
			path        string
			contentType string
		}{
			{filepath.Join(targetDir, fmt.Sprintf("%s_%s.jpg", userDir, sha1)), "image/jpeg"},
			{filepath.Join(targetDir, fmt.Sprintf("%s_%s.png", userDir, sha1)), "image/png"},
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

	engine.POST("/history/screenshot/sync", func(c *gin.Context) {
		var bodyReq screenshotSyncRequest
		hasBody := c.Request.ContentLength != 0
		if hasBody {
			if !httpjson.BindJSON(c, &bodyReq) {
				return
			}
		}

		dryRun := true
		if raw := strings.TrimSpace(c.Query("dryRun")); raw != "" {
			parsed, err := strconv.ParseBool(raw)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid dryRun"})
				return
			}
			dryRun = parsed
		} else if hasBody {
			dryRun = bodyReq.DryRun
		}

		previewLimit := 0
		if rawLimit := strings.TrimSpace(c.Query("previewLimit")); rawLimit != "" {
			val, err := strconv.Atoi(rawLimit)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid previewLimit"})
				return
			}
			previewLimit = val
		} else if hasBody {
			previewLimit = bodyReq.PreviewLimit
		}
		previewLimit = normalizePreviewLimit(previewLimit)

		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
		defer cancel()

		result, err := syncScreenshotsAndPrune(ctx, r.DB, r.Config.ScreenshotDir, dryRun, previewLimit)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	})
}

type screenshotUploadRequest struct {
	VideoSha1   string `json:"videoSha1"`
	UserID      int64  `json:"userId"`
	VideoName   string `json:"videoName"`
	VideoPath   string `json:"videoPath"`
	IsJpeg      bool   `json:"isJpeg"`
	ImageBase64 string `json:"imageBase64"`
}

type screenshotSyncRequest struct {
	DryRun       bool `json:"dryRun"`
	PreviewLimit int  `json:"previewLimit"`
}

// sanitizeIdentifier 仅在截图模块内部复制一份，避免直接导出 SQL 层实现。
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
