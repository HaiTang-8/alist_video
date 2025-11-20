#!/usr/bin/env bash
# go_proxy_service.sh
# 说明: 在 Linux(systemd) 上一键管理 Go 代理服务:
#   - 安装为 systemd 服务并设置开机自启
#   - 启动 / 停止 / 重启服务
#   - 查看服务状态与日志
# 默认从脚本所在目录运行指定名称的 Go 可执行文件

#使用步骤建议
#
#  1. 在 Linux 服务器上放置文件
#      - 将 go_proxy_service.sh 和你的 Go 可执行文件（如 go-proxy）放在同一个目录。
#      - 如需使用不同名称或不同目录，在脚本顶部修改：
#          - SERVICE_NAME
#          - EXECUTABLE_NAME
#          - SERVICE_USER
#          - 如有需要可改 WORK_DIR 为你希望的工作目录。
#  2. 赋予执行权限
#
#     chmod +x go_proxy_service.sh
#  3. 安装为开机自启服务
#
#     sudo ./go_proxy_service.sh install
#  4. 日常运维常用命令
#
#     sudo ./go_proxy_service.sh start      # 启动
#     sudo ./go_proxy_service.sh stop       # 停止
#     sudo ./go_proxy_service.sh restart    # 重启
#     sudo ./go_proxy_service.sh status     # 查看状态
#     sudo ./go_proxy_service.sh logs       # 实时日志

set -euo pipefail

#============= 可按需修改的配置区域 =============#

# systemd 服务名称, 会生成:
# /etc/systemd/system/${SERVICE_NAME}.service
SERVICE_NAME="go-proxy"

# Go 编译生成的可执行文件名:
#   - 默认认为可执行文件与本脚本位于同一目录
#   - 例如: go build -o go-proxy main.go
EXECUTABLE_NAME="go_bridge_linux_amd64"

# 运行服务的 Linux 用户/用户组:
#   - 生产环境推荐指定普通用户, 并用专属组限制权限
#   - SERVICE_GROUP 可通过环境变量覆盖, 默认为 SERVICE_USER
SERVICE_USER="root"
SERVICE_GROUP="${SERVICE_GROUP:-${SERVICE_USER}}"

#============= 以下逻辑一般不需要修改 =============#

# 获取当前脚本所在目录, 保证无论从哪里调用都能定位到可执行文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Go 可执行文件完整路径, 默认在脚本同级目录
EXECUTABLE_PATH="${SCRIPT_DIR}/${EXECUTABLE_NAME}"

# 作为服务运行时的工作目录, 通常就是脚本所在目录
WORK_DIR="${SCRIPT_DIR}"

# 预先转义 systemd 需要的路径, 避免路径包含空格或特殊字符导致失败
ESCAPED_EXECUTABLE_PATH="$(printf '%q' "${EXECUTABLE_PATH}")"
ESCAPED_WORK_DIR="$(printf '%q' "${WORK_DIR}")"

# systemd 服务单元文件路径
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 日志落盘位置，默认与可执行文件同级目录
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/${SERVICE_NAME}.log"

#------------- 通用辅助函数 -------------#

# 打印使用说明, 便于运维或自己快速查看支持的子命令
usage() {
  cat <<EOF
用法: $0 <命令>

可用命令:
  install    安装 systemd 服务并设为开机自启 (需要 root)
  uninstall  卸载 systemd 服务并取消开机自启 (需要 root)
  start      启动服务 (需要 root)
  stop       停止服务 (需要 root)
  restart    重启服务 (需要 root)
  reload     重新加载 unit 文件并尝试重启服务 (需要 root)
  status     查看服务当前状态
  logs       查看服务日志 (实时跟随)

示例:
  sudo $0 install
  sudo $0 start
  $0 status
  sudo $0 logs
EOF
}

# 检查当前是否为 root 用户;
# 写 /etc/systemd 以及操作 systemctl 通常需要 root
ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "本操作需要 root 权限, 请使用 sudo 执行:"
    echo "  sudo $0 $*"
    exit 1
  fi
}

# 检查 Go 可执行文件是否存在且可执行,
# 避免 systemd 启动时才报错
check_executable() {
  if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "错误: 未找到可执行文件或无执行权限:"
    echo "  ${EXECUTABLE_PATH}"
    echo "请先在该目录下执行例如:"
    echo "  go build -o ${EXECUTABLE_NAME} main.go"
    exit 1
  fi
}

#------------- 核心操作函数 -------------#

# 创建或更新 systemd 服务单元文件, 并设置开机自启
install_service() {
  ensure_root install
  check_executable

  echo "正在写入 systemd 服务文件: ${UNIT_FILE}"

  # 生成 systemd 服务配置:
  # - WorkingDirectory 指定工作目录
  # - ExecStart 指定 Go 可执行文件路径
  # - Restart on-failure 保障服务异常退出后自动重启
  cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=Go Proxy Service (${SERVICE_NAME})
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${ESCAPED_WORK_DIR}
PermissionsStartOnly=true
ExecStartPre=/bin/mkdir -p ${LOG_DIR}
ExecStart=/bin/sh -c '${ESCAPED_EXECUTABLE_PATH} >> ${LOG_FILE} 2>&1'
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

  echo "重新加载 systemd 配置并启用服务开机自启..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service"

  echo "安装完成, 当前服务状态如下:"
  systemctl status "${SERVICE_NAME}.service" --no-pager
}

# 卸载服务并删除 unit 文件
uninstall_service() {
  ensure_root uninstall

  echo "停止并禁用服务: ${SERVICE_NAME}.service (如存在)"
  # 使用 || true 避免服务不存在时脚本直接退出
  systemctl stop "${SERVICE_NAME}.service" || true
  systemctl disable "${SERVICE_NAME}.service" || true

  if [[ -f "${UNIT_FILE}" ]]; then
    echo "删除服务文件: ${UNIT_FILE}"
    rm -f "${UNIT_FILE}"
    systemctl daemon-reload
  else
    echo "未找到服务文件: ${UNIT_FILE}, 可能已经删除."
  fi

  echo "卸载操作完成."
}

# 启动服务
start_service() {
  ensure_root start

  systemctl start "${SERVICE_NAME}.service"
  echo "服务已启动."
  systemctl status "${SERVICE_NAME}.service" --no-pager
}

# 停止服务
stop_service() {
  ensure_root stop

  systemctl stop "${SERVICE_NAME}.service"
  echo "服务已停止."
}

# 重启服务
restart_service() {
  ensure_root restart

  systemctl restart "${SERVICE_NAME}.service"
  echo "服务已重启."
  systemctl status "${SERVICE_NAME}.service" --no-pager
}

# 仅重新加载 unit 文件, 适合替换二进制或修改配置后的场景
reload_service() {
  ensure_root reload

  systemctl daemon-reload
  # try-restart 在服务运行时重启, 未运行则忽略错误, 提升可维护性
  systemctl try-restart "${SERVICE_NAME}.service"
  echo "已重新加载 unit 文件并尝试重启服务."
  systemctl status "${SERVICE_NAME}.service" --no-pager
}

# 查看服务状态
status_service() {
  # 查看状态通常允许普通用户执行, 方便排查
  systemctl status "${SERVICE_NAME}.service"
}

# 查看实时日志, 便于调试线上问题
logs_service() {
  local unit_name="${SERVICE_NAME}.service"

  if ! systemctl --quiet is-active "${unit_name}"; then
    echo "提示: 服务当前非运行状态, 仍会尝试读取历史日志."
  fi

  echo "最近 200 行日志 (Ctrl+C 退出):"

  # journalctl 对非特权用户可能拒绝访问, 这里主动检测并提示
  if ! journalctl -u "${unit_name}" -n 200 -f; then
    echo "无法读取日志, 请使用 sudo 运行或将用户加入 systemd-journal 组." >&2
    exit 1
  fi
}

#------------- 命令分发入口 -------------#

main() {
  local cmd="${1:-}"

  if [[ -z "${cmd}" ]]; then
    usage
    exit 1
  fi

  case "${cmd}" in
    install)
      install_service
      ;;
    uninstall)
      uninstall_service
      ;;
    start)
      start_service
      ;;
    stop)
      stop_service
      ;;
    restart)
      restart_service
      ;;
    reload)
      reload_service
      ;;
    status)
      status_service
      ;;
    logs)
      logs_service
      ;;
    *)
      echo "未知命令: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
