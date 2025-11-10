#!/usr/bin/env bash
#
# 用途:
#   在最小化（-trimpath + -ldflags "-s -w"）的前提下编译 Go 数据库桥。
#   可通过环境变量 GOOS / GOARCH / BIN_NAME 控制目标平台与输出文件名。
#
# 示例:
#   # 本机构建
#   ./build_release.sh
#   # 构建 Linux/amd64 版本
#   GOOS=linux GOARCH=amd64 ./build_release.sh
#   # 自定义输出名称
#   BIN_NAME=go_bridge_linux ./build_release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
GO_BIN="${GO_BIN:-go}"
BIN_NAME="${BIN_NAME:-go_bridge}"
OUTPUT="${DIST_DIR}/${BIN_NAME}"

mkdir -p "${DIST_DIR}"

echo "==> 项目根目录: ${PROJECT_ROOT}"
echo "==> Go 工程目录: ${SCRIPT_DIR}"
echo "==> 输出文件: ${OUTPUT}"

pushd "${SCRIPT_DIR}" > /dev/null

echo "==> 同步依赖 go mod tidy"
"${GO_BIN}" mod tidy

BUILD_ENV=()
if [[ -n "${GOOS:-}" ]]; then BUILD_ENV+=("GOOS=${GOOS}"); fi
if [[ -n "${GOARCH:-}" ]]; then BUILD_ENV+=("GOARCH=${GOARCH}"); fi

echo "==> 编译参数: ${BUILD_ENV[*]} ${GO_BIN} build -trimpath -ldflags \"-s -w\" -o ${OUTPUT}"
env "${BUILD_ENV[@]}" "${GO_BIN}" build -trimpath -ldflags "-s -w" -o "${OUTPUT}" ./...

popd > /dev/null

echo "==> 构建完成: ${OUTPUT}"
