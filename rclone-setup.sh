#!/bin/bash
# 修复FUSE依赖并重新配置Rclone挂载

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置信息（与之前一致）
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
VENDOR="other"  # 修正服务器类型（原webdav改为other，避免Unknown vendor警告）
USERNAME="root"
PASSWORD="password"
MOUNT_POINT="/home/user/rclone"
LOG_FILE="/home/user/.cache/rclone/rclone-test.log"
SYSTEMD_SERVICE="rclone-webdav.service"

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
    exit 1
fi

# 安装缺失的FUSE依赖
install_fuse() {
    echo -e "${YELLOW}[1/5] 安装FUSE依赖（解决fusermount3缺失）...${NC}"
    if [ -f /etc/debian_version ]; then
        # Ubuntu/Debian
        apt-get update -y >/dev/null 2>&1
        apt-get install -y fuse3 >/dev/null 2>&1  # 包含fusermount3
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum install -y fuse3 >/dev/null 2>&1
    fi
    # 验证安装
    if ! command -v fusermount3 &>/dev/null; then
        echo -e "${RED}安装fusermount3失败！请手动安装fuse3包${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] fusermount3已安装${NC}"
}

# 修正Rclone配置（服务器类型从webdav改为other，避免警告）
fix_webdav_config() {
    echo -e "${YELLOW}[2/5] 修正WebDAV配置...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    OBSCURED_PASS=$(echo "$PASSWORD" | rclone obscure -)
    # 重新生成配置文件，将vendor改为other（通用类型）
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = $VENDOR
user = $USERNAME
pass = $OBSCURED_PASS
EOF
    chown user:user "$CONFIG_DIR/rclone.conf"
    echo -e "${GREEN}[✓] 配置已修正${NC}"
}

# 重启服务并验证
restart_and_verify() {
    echo -e "${YELLOW}[3/5] 重启Rclone服务...${NC}"
    # 停止现有服务
    systemctl stop "$SYSTEMD_SERVICE" >/dev/null 2>&1
    # 重新启动
    systemctl daemon-reload
    systemctl start "$SYSTEMD_SERVICE"

    # 验证状态
    sleep 2
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
        echo -e "${YELLOW}挂载信息：${NC}"
        mount | grep "$MOUNT_POINT"
        echo -e "${YELLOW}可访问目录：$MOUNT_POINT${NC}"
    else
        echo -e "${RED}服务仍启动失败！查看详细日志：${LOG_FILE}${NC}"
        echo -e "状态信息："
        systemctl status "$SYSTEMD_SERVICE" --no-pager
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 开始修复挂载问题 ====="${NC}
    install_fuse
    fix_webdav_config
    restart_and_verify
    echo -e "${GREEN}===== 修复完成 ====="${NC}
}

main
