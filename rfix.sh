#!/bin/bash
# rclone一键安装配置脚本 - 最终参数错误最终版

# 颜色与符号定义
SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置参数
DAV_NAME="test"
DAV_URL="http://yy.19885172.xyz:19798/dav"
DAV_USER="root"
DAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
LOG_DIR="/home/user/.cache/rclone"
LOG_PATH="$LOG_DIR/rclone_mount.log"
RCLONE_PATH="/usr/local/bin/rclone"

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${ERROR} 请使用sudo运行：sudo ./rclone_setup.sh${NC}"
    exit 1
fi

# 清理函数 - 确保环境干净
cleanup() {
    fusermount -u "$MOUNT_POINT" 2>/dev/null
    umount -l "$MOUNT_POINT" 2>/dev/null
    pkill -f "rclone mount $DAV_NAME:" 2>/dev/null
    rm -rf "$MOUNT_POINT" 2>/dev/null
    mkdir -p "$MOUNT_POINT"
}

# 主挂载函数
mount_webdav() {
    # 配置日志目录
    mkdir -p "$LOG_DIR"
    chown -R $SUDO_USER:$SUDO_USER "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    > "$LOG_PATH"  # 清空日志

    # 配置fuse
    if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    # 安装依赖
    apt update -y >/dev/null 2>&1
    apt install -y fuse3 wget unzip >/dev/null 2>&1

    # 安装rclone
    if [ ! -f "$RCLONE_PATH" ]; then
        wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
        unzip -q /tmp/rclone.zip -d /tmp
        cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
        chmod 755 "$RCLONE_PATH"
        rm -rf /tmp/rclone*
    fi

    # 配置rclone
    mkdir -p /root/.config/rclone/
    cat > /root/.config/rclone/rclone.conf << EOF
[$DAV_NAME]
type = webdav
url = $DAV_URL
vendor = other
user = $DAV_USER
pass = $("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

    # 核心修复：使用紧凑格式避免多余空格，确保参数正确
    local mount_command="$RCLONE_PATH mount \"$DAV_NAME:\" \"$MOUNT_POINT\" --vfs-cache-mode writes --allow-other --log-file \"$LOG_PATH\" --log-level INFO --daemon"
    
    # 执行挂载命令
    eval $mount_command >/dev/null 2>&1
    
    # 验证挂载
    sleep 3
    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "${GREEN}${SUCCESS} 挂载成功！路径：$MOUNT_POINT${NC}"
        echo -e "${YELLOW}${INFO} 日志位置：$LOG_PATH${NC}"
    else
        echo -e "${RED}${ERROR} 挂载失败${NC}"
        echo -e "${YELLOW}${INFO} 查看日志：tail -f $LOG_PATH${NC}"
        echo -e "${YELLOW}${INFO} 尝试手动挂载：$RCLONE_PATH mount $DAV_NAME: $MOUNT_POINT --vfs-cache-mode writes --allow-other${NC}"
    fi
}

# 执行清理
echo -e "${YELLOW}${INFO} 清理旧挂载状态...${NC}"
cleanup

# 后台执行挂载并立即返回终端
echo -e "${YELLOW}${INFO} 脚本在后台执行中...${NC}"
echo -e "${YELLOW}${INFO} 结果将在几秒后显示，您可继续其他操作${NC}"
mount_webdav &
disown
sleep 1
exit 0
