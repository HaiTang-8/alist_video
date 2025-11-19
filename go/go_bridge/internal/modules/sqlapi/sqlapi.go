package sqlapi

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"

	"github.com/zhouquan/webdav_video/go_bridge/internal/server/httpjson"
)

var placeholderPattern = regexp.MustCompile(`@([a-zA-Z0-9_]+)`)

// Registrar 提供 /health 与 SQL CRUD 接口，供完整模式复用。
type Registrar struct {
	DB *sqlx.DB
}

func NewRegistrar(db *sqlx.DB) *Registrar {
	return &Registrar{DB: db}
}

// Register 挂载 SQL API，需要数据库句柄才能工作。
func (r *Registrar) Register(engine *gin.Engine) {
	if engine == nil || r.DB == nil {
		return
	}

	engine.GET("/health", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()
		if err := r.DB.PingContext(ctx); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "details": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	engine.POST("/sql/query", func(c *gin.Context) {
		var req sqlRequest
		if !httpjson.BindJSON(c, &req) {
			return
		}
		if strings.TrimSpace(req.SQL) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "sql is required"})
			return
		}
		normalizedSQL, _ := convertPlaceholders(req.SQL, "")
		rows, err := r.DB.NamedQueryContext(c.Request.Context(), normalizedSQL, req.Parameters)
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

	engine.POST("/sql/insert", func(c *gin.Context) {
		var req insertRequest
		if !httpjson.BindJSON(c, &req) {
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
			placeholder := "val_" + col
			placeholders = append(placeholders, ":"+placeholder)
			namedValues[placeholder] = v
		}
		query := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)", table, strings.Join(columns, ","), strings.Join(placeholders, ","))
		res, err := r.DB.NamedExecContext(c.Request.Context(), query, namedValues)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		lastID, _ := res.LastInsertId()
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"lastInsertId": lastID, "rowsAffected": rowsAffected})
	})

	engine.POST("/sql/update", func(c *gin.Context) {
		var req updateRequest
		if !httpjson.BindJSON(c, &req) {
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
		res, err := r.DB.NamedExecContext(c.Request.Context(), query, params)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"affectedRows": rowsAffected})
	})

	engine.POST("/sql/delete", func(c *gin.Context) {
		var req deleteRequest
		if !httpjson.BindJSON(c, &req) {
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
		res, err := r.DB.NamedExecContext(c.Request.Context(), query, convertedArgs)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		rowsAffected, _ := res.RowsAffected()
		c.JSON(http.StatusOK, gin.H{"affectedRows": rowsAffected})
	})
}

type sqlRequest struct {
	SQL        string         `json:"sql"`
	Parameters map[string]any `json:"parameters"`
}

type insertRequest struct {
	Table  string         `json:"table"`
	Values map[string]any `json:"values"`
}

type updateRequest struct {
	Table    string         `json:"table"`
	Values   map[string]any `json:"values"`
	Where    string         `json:"where"`
	WhereArg map[string]any `json:"whereArgs"`
}

type deleteRequest struct {
	Table    string         `json:"table"`
	Where    string         `json:"where"`
	WhereArg map[string]any `json:"whereArgs"`
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
