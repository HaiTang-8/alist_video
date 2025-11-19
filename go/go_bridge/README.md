# Go 持久化桥接服务

该服务用于在本地运行一个中间层，将 Flutter 客户端的 SQL 指令转发到任意 `database/sql` 支持的数据库（目前默认包含 MySQL、PostgreSQL、Oracle）。

## 目录结构

```
go/go_bridge/
├── cmd/go_bridge/     # 主程序入口（支持多构建标签）
├── internal/          # 路由、模块与配置拆分实现
├── config.yaml        # 示例配置
├── go.mod
└── go.sum
```

## 配置说明

`config.yaml` 支持以下字段：

| 字段 | 含义 |
| --- | --- |
| `listen` | 监听地址，默认 `:7788` |
| `driver` | `mysql` / `postgres` / `oracle`（使用 go-ora 驱动） |
| `dsn` | 数据源字符串，示例：`user=postgres password=wasd..123 host=127.0.0.1 port=5432 dbname=alist_video sslmode=disable` |
| `authToken` | 可选，设置后 Flutter 端需要携带 `Authorization: Bearer <token>` |
| `maxOpenConns` | 最大连接数，默认 5 |
| `maxIdleConns` | 最大空闲连接，默认 2 |
| `connMaxLifetime` | 连接最大生命周期，Go duration 字符串，例如 `30m` |
| `screenshotDir` | 历史截图落盘目录，默认 `data/screenshots` |

也可以通过环境变量指定配置路径：`GO_BRIDGE_CONFIG=/path/to/config.yaml`。

## 运行模式

为了兼顾跨平台（移动端本地代理、桌面端客户端、服务器全量服务），Go 桥支持两种构建方式：

1. **完整模式（默认）**：包含 SQL、截图与代理能力，适合服务器或需要所有功能的桌面端。直接执行 `go build ./cmd/go_bridge`；配置文件必须提供 `driver`、`dsn` 等数据库字段。
2. **仅代理模式**：移除数据库相关逻辑，仅保留 `/proxy/media`，体积更小，便于在移动端或局域网桌面代理中分发。构建时附加 `-tags proxy_only` 或设置 `GO_BUILD_TAGS=proxy_only`。

两种模式共享同一份鉴权逻辑与配置文件，方便在多端统一管理 Token 与监听端口，只是对数据库字段的校验不同。

## 启动

```bash
cd go/go_bridge
go run ./cmd/go_bridge          # 完整模式
go run -tags proxy_only ./cmd/go_bridge   # 仅代理模式
```

首次运行会自动安装所需依赖（gin、sqlx、go-ora 等）。启动后可通过 `http://127.0.0.1:7788/health` 探活。

## 接口契约

| 方法 | 路径 | 说明 | 请求示例 |
| --- | --- | --- | --- |
| `GET` | `/health` | DB 探活 | - |
| `POST` | `/sql/query` | 通用查询 | `{ "sql": "SELECT * FROM t_historical_records WHERE user_id = @id", "parameters": {"id": 1} }` |
| `POST` | `/sql/insert` | 插入 | `{ "table": "t_favorite_directories", "values": {"path": "/home", "name": "Home", "user_id": 1} }` |
| `POST` | `/sql/update` | 更新 | `{ "table": "t_historical_records", "values": {"video_seek": 10}, "where": "video_sha1 = @sha1 AND user_id = @uid", "whereArgs": {"sha1": "abc", "uid": 1} }` |
| `POST` | `/sql/delete` | 删除 | `{ "table": "t_favorite_directories", "where": "user_id = @uid", "whereArgs": {"uid": 1} }` |
| `POST` | `/history/screenshot` | 上传/覆盖指定用户的历史截图 | `{ "videoSha1": "abc123", "userId": 1, "videoName": "movie.mp4", "videoPath": "/media", "isJpeg": true, "imageBase64": "<...>" }` |
| `GET` | `/history/screenshot` | 获取用户历史截图二进制 | `?videoSha1=abc123&userId=1` |
| `POST` | `/history/screenshot/sync` | 默认 `dryRun=true` 仅做预览，可配合 `previewLimit` 查询参数/JSON 提前拉取全部孤儿截图，显式传 `dryRun=false` 才会物理删除 | `{"dryRun": false, "previewLimit": 500}` |
| `GET` | `/proxy/media` | 代理任意可访问的 HTTP/HTTPS 媒体流，透传 Range 头 | `?target=https://alist.example.com/d/video.mp4&access_token=<token>` |

注意：Flutter 端沿用 `@param` 占位符，Go 服务会自动转换成指定驱动可识别的命名参数。

截图接口会将文件写入 `screenshotDir` 目录（以 `userId/videoSha1` 做键），Flutter 历史页在本地缺图时会调用 `GET /history/screenshot` 自动补齐并缓存，确保跨端历史记录缩略图一致。

若数据库删除了某条历史记录，可通过 `POST /history/screenshot/sync` 在 Go 服务侧触发一次同步：

1. 针对每个用户子目录比对 `userId_videoSha1` 命名规则的文件；
2. 查询数据库中是否仍存在对应的历史记录；
3. 对不存在的记录执行物理删除，并尝试移除已经空掉的子目录；
4. 返回统计信息（已扫描数量、删除数量、耗时、预览被删除的文件列表等）。

若未携带任何参数，请求会默认启用 `dryRun=true` 并返回预览；可以通过 `previewLimit`（范围 1-2000）控制返回多少条 `orphanDetails` 供前端展示确认。只有在确认无误后，通过 query/body 传 `dryRun=false` 才会实际删除并回收磁盘空间。

媒体代理接口会使用 Go 进程主动拉取目标 URL，并透传 `Range`、`User-Agent` 等头部，播放器只需要访问本地可达的 `/proxy/media` 即可绕过被屏蔽的存储域名。若配置了 `authToken`，可通过 `Authorization: Bearer <token>` 或在查询参数附带 `access_token=<token>` 进行鉴权。

## 配合 Flutter 使用

1. 在 `config.yaml` 中配置实际数据库。
2. 启动 Go 服务后，在 Flutter 应用的数据库设置中选择 “本地 Go 服务” 模式，填入 `http://127.0.0.1:7788` 及 Token。
3. 即可通过 Go 中间层完成历史记录、收藏等读写。

## 生产构建

使用同目录下的 `build_release.sh` 可生成最小化二进制（`-trimpath -ldflags "-s -w"`），支持交叉编译：

```bash
# 本机构建
./build_release.sh

# 构建 Linux/amd64
GOOS=linux GOARCH=amd64 ./build_release.sh

# 指定输出文件名
BIN_NAME=go_bridge_linux ./build_release.sh

# 生成仅代理包
GO_BUILD_TAGS=proxy_only ./build_release.sh
```

脚本会将结果输出到仓库根目录的 `dist/` 目录，方便打包发布；通过 `GO_BUILD_TAGS` 可以在 CI/桌面端脚本里控制打出的模式。
