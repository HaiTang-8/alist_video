#!/usr/bin/env bash
#
# 构建 Linux 平台的全量版与仅代理版二进制，默认 amd64。
#
# 用法示例：
#   ./build_linux_both.sh           # linux/amd64 全量 + proxy_only
#   ./build_linux_both.sh arm64     # linux/arm64 全量 + proxy_only
#   ./build_linux_both.sh amd64 arm64  # 同时构建两个架构

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
  TARGET_ARCHES=(amd64)
else
  TARGET_ARCHES=("$@")
fi

build_one() {
  local arch="$1"
  echo "==> 构建 linux/${arch} 全量包"
  GOOS=linux GOARCH="${arch}" BIN_NAME="go_bridge_linux_${arch}" \
    "${SCRIPT_DIR}/build_release.sh" "linux/${arch}"

  echo "==> 构建 linux/${arch} 仅代理包"
  GOOS=linux GOARCH="${arch}" GO_BUILD_TAGS=proxy_only \
    BIN_NAME="go_bridge_proxy_only_linux_${arch}" \
    "${SCRIPT_DIR}/build_release.sh" "linux/${arch}"
}

for arch in "${TARGET_ARCHES[@]}"; do
  build_one "${arch}"
done

echo "==> 所有目标构建完成"
