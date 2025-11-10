#!/usr/bin/env bash
#
# 用途:
#   在最小化（-trimpath + -ldflags "-s -w"）的前提下编译 Go 数据库桥。
#   可通过环境变量 GOOS / GOARCH / BIN_NAME 控制目标平台与输出文件名。
#
# 示例:
#   ./build_release.sh                # 本机平台
#   ./build_release.sh linux/amd64    # 指定 linux/amd64
#   ./build_release.sh windows/amd64 go_bridge.exe

usage() {
  cat <<'USAGE'
用法:
  ./build_release.sh [<os/arch> [自定义输出名]]

示例:
  ./build_release.sh                # 本机平台
  ./build_release.sh linux/amd64    # 指定 linux/amd64
  ./build_release.sh windows/amd64 go_bridge.exe
  GOOS=linux GOARCH=arm64 ./build_release.sh  # 仍可使用环境变量
USAGE
}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
GO_BIN="${GO_BIN:-go}"

TARGET_SPEC="${1:-}"
CUSTOM_NAME="${2:-}"
TARGET_OS="${GOOS:-}"
TARGET_ARCH="${GOARCH:-}"

if [[ -n "${TARGET_SPEC}" ]]; then
  IFS='/-' read -r parsed_os parsed_arch _ <<<"${TARGET_SPEC}"
  if [[ -z "${parsed_os}" || -z "${parsed_arch}" ]]; then
    usage
    exit 1
  fi
  TARGET_OS="${parsed_os}"
  TARGET_ARCH="${parsed_arch}"
fi

if [[ -n "${TARGET_OS}" && -z "${TARGET_ARCH}" ]] || [[ -z "${TARGET_OS}" && -n "${TARGET_ARCH}" ]]; then
  echo "GOOS/GOARCH 需要同时指定"
  usage
  exit 1
fi

default_name="go_bridge"
if [[ -n "${TARGET_OS}" && -n "${TARGET_ARCH}" ]]; then
  default_name="go_bridge_${TARGET_OS}_${TARGET_ARCH}"
fi
BIN_NAME="${CUSTOM_NAME:-${BIN_NAME:-${default_name}}}"
OUTPUT="${DIST_DIR}/${BIN_NAME}"

mkdir -p "${DIST_DIR}"

echo "==> 项目根目录: ${PROJECT_ROOT}"
echo "==> Go 工程目录: ${SCRIPT_DIR}"
echo "==> 输出文件: ${OUTPUT}"

pushd "${SCRIPT_DIR}" > /dev/null

echo "==> 同步依赖 go mod tidy"
"${GO_BIN}" mod tidy

declare -a BUILD_ENV=()
if [[ -n "${TARGET_OS}" ]]; then BUILD_ENV+=("GOOS=${TARGET_OS}"); fi
if [[ -n "${TARGET_ARCH}" ]]; then BUILD_ENV+=("GOARCH=${TARGET_ARCH}"); fi

if ((${#BUILD_ENV[@]})); then
  echo "==> 编译参数: ${BUILD_ENV[*]} ${GO_BIN} build -trimpath -ldflags \"-s -w\" -o ${OUTPUT}"
  env "${BUILD_ENV[@]}" "${GO_BIN}" build -trimpath -ldflags "-s -w" -o "${OUTPUT}" ./...
else
  echo "==> 编译参数: 默认本机环境 ${GO_BIN} build -trimpath -ldflags \"-s -w\" -o ${OUTPUT}"
  "${GO_BIN}" build -trimpath -ldflags "-s -w" -o "${OUTPUT}" ./...
fi

popd > /dev/null

echo "==> 构建完成: ${OUTPUT}"
