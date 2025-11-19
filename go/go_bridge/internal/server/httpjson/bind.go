package httpjson

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// BindJSON 封装 gin 的 JSON 解析逻辑，统一错误响应格式。
func BindJSON[T any](c *gin.Context, dest *T) bool {
	if err := c.ShouldBindJSON(dest); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return false
	}
	return true
}
