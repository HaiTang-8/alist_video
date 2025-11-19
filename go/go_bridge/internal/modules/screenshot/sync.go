package screenshot

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
)

const (
	defaultOrphanPreviewLimit = 50
	maxOrphanPreviewLimit     = 2000
)

// screenshotCleanupResult 汇总一次截图目录同步的关键指标，方便在
// API 响应中展示本次执行的删除数量、耗时及被忽略条目等信息。
type screenshotCleanupResult struct {
	DryRun             bool           `json:"dryRun"`
	TotalCandidates    int            `json:"totalCandidates"`
	OrphanCandidates   int            `json:"orphanCandidates"`
	DeletedFiles       int            `json:"deletedFiles"`
	SkippedEntries     int            `json:"skippedEntries"`
	DurationMillis     int64          `json:"durationMillis"`
	OrphanFiles        []string       `json:"orphanFiles"`
	OrphanDetails      []orphanDetail `json:"orphanDetails"`
	OrphanPreviewLimit int            `json:"orphanPreviewLimit"`
	OrphanOverflow     int            `json:"orphanOverflow"`
	Errors             []string       `json:"errors"`
}

type orphanDetail struct {
	UserID       int64     `json:"userId"`
	VideoSha1    string    `json:"videoSha1"`
	RelativePath string    `json:"relativePath"`
	SizeBytes    int64     `json:"sizeBytes"`
	ModTime      time.Time `json:"modTime"`
}

type screenshotFileMeta struct {
	userID       int64
	videoSha1    string
	absolutePath string
	relativePath string
}

// cleanupOrphanScreenshots 会遍历 screenshotDir 下的每个用户子目录，
// 根据 `userId_sha1.ext` 命名规则解析候选文件，并查询数据库中是否
// 仍存在匹配记录，若没有则在非 DryRun 模式下物理删除对应文件。
func cleanupOrphanScreenshots(
	ctx context.Context,
	db *sqlx.DB,
	screenshotDir string,
	dryRun bool,
	previewLimit int,
) (screenshotCleanupResult, error) {
	start := time.Now()
	limit := normalizePreviewLimit(previewLimit)
	result := screenshotCleanupResult{
		DryRun:             dryRun,
		OrphanPreviewLimit: limit,
		OrphanDetails:      make([]orphanDetail, 0, limit),
		OrphanFiles:        make([]string, 0, limit),
	}

	entries, err := os.ReadDir(screenshotDir)
	if err != nil {
		return result, fmt.Errorf("read screenshot dir: %w", err)
	}

	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		if !entry.IsDir() {
			result.SkippedEntries++
			continue
		}
		userDir := entry.Name()
		files, err := os.ReadDir(filepath.Join(screenshotDir, userDir))
		if err != nil {
			result.Errors = append(
				result.Errors,
				fmt.Sprintf("scan %s: %v", userDir, err),
			)
			continue
		}

		for _, fileEntry := range files {
			if err := ctx.Err(); err != nil {
				return result, err
			}
			meta, ok := parseScreenshotFileMeta(
				screenshotDir,
				userDir,
				fileEntry,
			)
			if !ok {
				result.SkippedEntries++
				continue
			}
			result.TotalCandidates++

			exists, err := screenshotRecordExists(ctx, db, meta.userID, meta.videoSha1)
			if err != nil {
				result.Errors = append(
					result.Errors,
					fmt.Sprintf("lookup %s: %v", meta.relativePath, err),
				)
				continue
			}
			if exists {
				continue
			}

			result.OrphanCandidates++

			if len(result.OrphanDetails) < result.OrphanPreviewLimit {
				detail := orphanDetail{
					UserID:       meta.userID,
					VideoSha1:    meta.videoSha1,
					RelativePath: meta.relativePath,
				}
				if info, err := os.Stat(meta.absolutePath); err == nil {
					detail.SizeBytes = info.Size()
					detail.ModTime = info.ModTime().UTC()
				}
				result.OrphanDetails = append(result.OrphanDetails, detail)
				result.OrphanFiles = append(result.OrphanFiles, meta.relativePath)
			} else {
				result.OrphanOverflow++
			}

			if dryRun {
				continue
			}

			if err := os.Remove(meta.absolutePath); err != nil {
				// 若删除失败，同样记录错误信息，方便调用侧发现异常。
				result.Errors = append(
					result.Errors,
					fmt.Sprintf("remove %s: %v", meta.relativePath, err),
				)
				continue
			}
			result.DeletedFiles++
		}
	}

	result.DurationMillis = time.Since(start).Milliseconds()
	return result, nil
}

// parseScreenshotFileMeta 解析形如 `123_abcdef.png` 的文件名，若结构
// 合法则返回用户 ID、视频 SHA1 及绝对/相对路径，便于后续做数据库比对。
func parseScreenshotFileMeta(
	screenshotDir string,
	userDirName string,
	entry fs.DirEntry,
) (screenshotFileMeta, bool) {
	if entry.IsDir() {
		return screenshotFileMeta{}, false
	}
	fileName := entry.Name()
	ext := filepath.Ext(fileName)
	if ext == "" {
		return screenshotFileMeta{}, false
	}
	base := strings.TrimSuffix(fileName, ext)
	parts := strings.SplitN(base, "_", 2)
	if len(parts) != 2 {
		return screenshotFileMeta{}, false
	}
	if parts[0] != userDirName {
		return screenshotFileMeta{}, false
	}
	userID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return screenshotFileMeta{}, false
	}
	sha1 := strings.TrimSpace(parts[1])
	if sha1 == "" {
		return screenshotFileMeta{}, false
	}
	if !isSupportedScreenshotExt(ext) {
		return screenshotFileMeta{}, false
	}
	return screenshotFileMeta{
		userID:       userID,
		videoSha1:    sha1,
		absolutePath: filepath.Join(screenshotDir, userDirName, fileName),
		relativePath: filepath.Join(userDirName, fileName),
	}, true
}

// isSupportedScreenshotExt 用于限制扫描范围，避免误删落在目录内的其它
// 临时文件或调试输出，目前仅允许 png/jpg 扩展名。
func isSupportedScreenshotExt(ext string) bool {
	if ext == "" {
		return false
	}
	switch strings.ToLower(ext) {
	case ".png", ".jpg", ".jpeg":
		return true
	default:
		return false
	}
}

// screenshotRecordExists 以 COUNT(1) 查询判断指定用户/视频 SHA1 是否依旧
// 存在于历史记录表中，确保兼容不同数据库驱动的 SQL 方言。
func screenshotRecordExists(
	ctx context.Context,
	db *sqlx.DB,
	userID int64,
	videoSha1 string,
) (bool, error) {
	// 使用 COUNT + Rebind 兼容 MySQL/PostgreSQL/Oracle 的占位符差异。
	query := db.Rebind(
		"SELECT COUNT(1) FROM t_historical_records WHERE user_id = ? " +
			"AND video_sha1 = ?",
	)
	var count int
	if err := db.GetContext(ctx, &count, query, userID, videoSha1); err != nil {
		return false, err
	}
	return count > 0, nil
}

// pruneEmptyUserDirs 会在完成删除动作后清理空的用户目录，避免留下
// 多层空文件夹；若 os.RemoveAll 失败则返回 error 交由上层记录。
func pruneEmptyUserDirs(dirPath string) error {
	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return err
	}
	if len(entries) > 0 {
		return nil
	}
	return os.Remove(dirPath)
}

// syncScreenshotsAndPrune 封装一次完整的同步 + 目录清理流程，避免
// 在 handler 中展开过多逻辑，便于后续复用（例如定时任务）。
func syncScreenshotsAndPrune(
	ctx context.Context,
	db *sqlx.DB,
	screenshotDir string,
	dryRun bool,
	previewLimit int,
) (screenshotCleanupResult, error) {
	result, err := cleanupOrphanScreenshots(ctx, db, screenshotDir, dryRun, previewLimit)
	if err != nil {
		return result, err
	}
	if dryRun {
		return result, nil
	}
	// 同步完成后，再次遍历用户目录删除空文件夹，防止目录树无限增长。
	entries, err := os.ReadDir(screenshotDir)
	if err != nil {
		result.Errors = append(result.Errors, fmt.Sprintf("prune scan: %v", err))
		return result, nil
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		dirPath := filepath.Join(screenshotDir, entry.Name())
		if err := pruneEmptyUserDirs(dirPath); err != nil && !errors.Is(err, fs.ErrNotExist) {
			result.Errors = append(
				result.Errors,
				fmt.Sprintf("prune %s: %v", entry.Name(), err),
			)
		}
	}
	return result, nil
}

func normalizePreviewLimit(limit int) int {
	if limit <= 0 {
		return defaultOrphanPreviewLimit
	}
	if limit > maxOrphanPreviewLimit {
		return maxOrphanPreviewLimit
	}
	return limit
}
