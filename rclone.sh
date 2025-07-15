#!/bin/bash
# 终端友好型rclone一键配置脚本 - 确保执行后返回终端

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
LOG_PATH="/home/user/Downloads/rclone_mount.log"
RCLONE_PATH="/usr/local/bin/rclone"

# 确保在子进程中运行核心逻辑，避免阻塞终端
(
    # 清理旧挂载（静默执行）
    echo -e "${YELLOW}${INFO} 清理旧挂载状态...${NC}"
    fusermount -u "$MOUNT_POINT" 2>/dev/null
    umount -l "$MOUNT_POINT" 2>/dev/null
    pkill -f "rclone mount $DAV_NAME:" 2>/dev/null
    rm -rf "$MOUNT_POINT" 2>/dev/null
    mkdir -p "$MOUNT_POINT"

    # 配置fuse（关键配置）
    if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    # 安装依赖（静默快速安装）
    apt update -y >/dev/null 2>&1
    apt install -y fuse3 wget unzip >/dev/null 2>&1

    # 安装rclone（若未安装）
    if [ ! -f "$RCLONE_PATH" ]; then
        echo -e "${YELLOW}${INFO} 安装rclone...${NC}"
        wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
        unzip -q /tmp/rclone.zip -d /tmp
        cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
        chmod 755 "$RCLONE_PATH"
        rm -rf /tmp/rclone*
    fi

    # 配置rclone连接
    mkdir -p /root/.config/rclone/
    cat > /root/.config/rclone/rclone.conf << EOF
[$DAV_NAME]
type = webdav
url = $DAV_URL
vendor = other
user = $DAV_USER
pass = $("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

    # 准备日志
    mkdir -p $(dirname "$LOG_PATH")
    > "$LOG_PATH"  # 清空旧日志

    # 后台挂载（核心：立即后台运行）
    echo -e "${YELLOW}${INFO} 正在后台挂载中...${NC}"
    "$RCLONE_PATH" mount \
        "$DAV_NAME:" "$MOUNT_POINT" \
        --vfs-cache-mode writes \
        --allow-other \
        --log-file "$LOG_PATH" \
        --log-level INFO \
        --daemon >/dev/null 2>&1

    # 简短验证（不阻塞终端）
    sleep 2
    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "${GREEN}${SUCCESS} 挂载成功: $MOUNT_POINT${NC}"
        echo -e "${YELLOW}${INFO} 已返回终端，可正常操作${NC}"
    else
        echo -e "${RED}${ERROR} 挂载失败${NC}"
        echo -e "${YELLOW}${INFO} 查看日志: tail -f $LOG_PATH${NC}"
    fi
) &  # 整个逻辑放入后台子进程

# 立即返回终端（脚本瞬间完成）
disown  # 脱离终端控制，确保不阻塞
echo -e "${YELLOW}${INFO} 脚本在后台执行，正在配置rclone...${NC}"
echo -e "${YELLOW}${INFO} 稍等片刻即可完成，您可继续其他操作${NC}"
sleep 1  # 给后台进程一点启动时间
exit 0  # 强制脚本退出，立即返回终端
