package screenshot

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/jmoiron/sqlx"
)

func TestCleanupOrphanScreenshotsDeletesDanglingFile(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	sqlxDB := sqlx.NewDb(db, "sqlmock")
	t.Cleanup(func() { _ = sqlxDB.Close() })

	root := t.TempDir()
	userDir := filepath.Join(root, "1")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	filePath := filepath.Join(userDir, "1_deadbeef.png")
	if err := os.WriteFile(filePath, []byte("foo"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	mock.ExpectQuery(`SELECT COUNT\(1\) FROM t_historical_records WHERE user_id = \? AND video_sha1 = \?`).
		WithArgs(int64(1), "deadbeef").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	res, err := cleanupOrphanScreenshots(context.Background(), sqlxDB, root, false, 5)
	if err != nil {
		t.Fatalf("cleanup: %v", err)
	}
	if res.DeletedFiles != 1 {
		t.Fatalf("expected 1 deleted file, got %+v", res)
	}
	if _, err := os.Stat(filePath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected file removed, got %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func TestCleanupOrphanScreenshotsDryRunKeepsDisk(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	sqlxDB := sqlx.NewDb(db, "sqlmock")
	t.Cleanup(func() { _ = sqlxDB.Close() })

	root := t.TempDir()
	userDir := filepath.Join(root, "2")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	filePath := filepath.Join(userDir, "2_deadbeef.png")
	if err := os.WriteFile(filePath, []byte("foo"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	mock.ExpectQuery(`SELECT COUNT\(1\) FROM t_historical_records WHERE user_id = \? AND video_sha1 = \?`).
		WithArgs(int64(2), "deadbeef").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	res, err := cleanupOrphanScreenshots(context.Background(), sqlxDB, root, true, 5)
	if len(res.OrphanDetails) != 1 {
		t.Fatalf("expected orphan details to be recorded, got %+v", res.OrphanDetails)
	}
	if err != nil {
		t.Fatalf("cleanup: %v", err)
	}
	if res.DeletedFiles != 0 {
		t.Fatalf("dryRun should not delete files, got %+v", res)
	}
	if res.OrphanCandidates != 1 {
		t.Fatalf("expected single orphan candidate, got %+v", res)
	}
	if _, err := os.Stat(filePath); err != nil {
		t.Fatalf("file should remain on disk, got %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func TestParseScreenshotFileMeta(t *testing.T) {
	root := t.TempDir()
	userDir := filepath.Join(root, "3")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	filePath := filepath.Join(userDir, "3_deadbeef.jpg")
	if err := os.WriteFile(filePath, []byte(""), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	entry, err := os.ReadDir(userDir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	meta, ok := parseScreenshotFileMeta(root, "3", entry[0])
	if !ok {
		t.Fatalf("expected valid meta")
	}
	if meta.videoSha1 != "deadbeef" || meta.userID != 3 {
		t.Fatalf("unexpected meta: %+v", meta)
	}
}
