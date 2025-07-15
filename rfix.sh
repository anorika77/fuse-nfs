#!/bin/bash
# rclone一键安装配置脚本 - 日志路径：/home/user/.cache/rclone

# 颜色与符号定义
SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置参数（日志目录已更新）
DAV_NAME="test"
DAV_URL="http://yy.19885172.xyz:19798/dav"
DAV_USER="root"
DAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
LOG_DIR="/home/user/.cache/rclone"  # 日志目录
LOG_PATH="$LOG_DIR/rclone_mount.log"  # 完整日志路径
RCLONE_PATH="/usr/local/bin/rclone"

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${ERROR} 请使用sudo运行：sudo ./rclone_setup.sh${NC}"
    exit 1
fi

# 后台执行核心逻辑，确保返回终端
(
    # 清理旧挂载状态
    echo -e "${YELLOW}${INFO} 清理旧挂载状态...${NC}"
    fusermount -u "$MOUNT_POINT" 2>/dev/null
    umount -l "$MOUNT_POINT" 2>/dev/null
    pkill -f "rclone mount $DAV_NAME:" 2>/dev/null
    rm -rf "$MOUNT_POINT" 2>/dev/null
    mkdir -p "$MOUNT_POINT"

    # 创建日志目录并设置权限
    echo -e "${YELLOW}${INFO} 配置日志目录...${NC}"
    mkdir -p "$LOG_DIR"
    # 确保日志目录归属当前用户
    chown -R $SUDO_USER:$SUDO_USER "$LOG_DIR"
    chmod 755 "$LOG_DIR"

    # 配置fuse允许其他用户访问
    if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    # 安装必要依赖
    echo -e "${YELLOW}${INFO} 安装必要依赖...${NC}"
    apt update -y >/dev/null 2>&1
    apt install -y fuse3 wget unzip >/dev/null 2>&1

    # 安装rclone（如未安装）
    if [ ! -f "$RCLONE_PATH" ]; then
        echo -e "${YELLOW}${INFO} 安装rclone...${NC}"
        wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
        unzip -q /tmp/rclone.zip -d /tmp
        cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
        chmod 755 "$RCLONE_PATH"
        rm -rf /tmp/rclone*
    fi

    # 配置rclone连接信息
    echo -e "${YELLOW}${INFO} 配置WebDAV连接...${NC}"
    mkdir -p /root/.config/rclone/
    cat > /root/.config/rclone/rclone.conf << EOF
[$DAV_NAME]
type = webdav
url = $DAV_URL
vendor = other
user = $DAV_USER
pass = $("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

    # 清空旧日志（如有）
    > "$LOG_PATH"

    # 后台挂载并将日志写入指定目录
    echo -e "${YELLOW}${INFO} 正在后台挂载WebDAV...${NC}"
    "$RCLONE_PATH" mount \
        "$DAV_NAME:" "$MOUNT_POINT" \
        --vfs-cache-mode writes \
        --allow-other \
        --log-file "$LOG_PATH" \  # 日志输出到新目录
        --log-level INFO \
        --daemon >/dev/null 2>&1

    # 验证挂载状态
    sleep 3
    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "${GREEN}${SUCCESS} 挂载成功！路径：$MOUNT_POINT${NC}"
        echo -e "${YELLOW}${INFO} 日志位置：$LOG_PATH${NC}"
    else
        echo -e "${RED}${ERROR} 挂载失败${NC}"
        echo -e "${YELLOW}${INFO} 查看错误日志：tail -f $LOG_PATH${NC}"
    fi
) &

# 立即返回终端交互
disown
echo -e "${YELLOW}${INFO} 脚本在后台执行中...${NC}"
echo -e "${YELLOW}${INFO} 结果将在几秒后显示，您可继续其他操作${NC}"
sleep 1
exit 0
