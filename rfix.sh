#!/bin/bash
# rclone一键安装配置脚本 - 自动挂载WebDAV并返回终端

# 颜色与符号定义
SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置参数（可根据需要修改）
DAV_NAME="test"
DAV_URL="http://yy.19885172.xyz:19798/dav"
DAV_USER="root"
DAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
LOG_PATH="/home/user/Downloads/rclone_mount.log"
RCLONE_PATH="/usr/local/bin/rclone"

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${ERROR} 请使用sudo运行：sudo ./rclone_setup.sh${NC}"
    exit 1
fi

# 后台执行核心逻辑，确保返回终端
(
    # 清理旧挂载
    echo -e "${YELLOW}${INFO} 清理旧挂载状态...${NC}"
    fusermount -u "$MOUNT_POINT" 2>/dev/null
    umount -l "$MOUNT_POINT" 2>/dev/null
    pkill -f "rclone mount $DAV_NAME:" 2>/dev/null
    rm -rf "$MOUNT_POINT" 2>/dev/null
    mkdir -p "$MOUNT_POINT"

    # 配置fuse
    if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi

    # 安装依赖
    echo -e "${YELLOW}${INFO} 安装必要依赖...${NC}"
    apt update -y >/dev/null 2>&1
    apt install -y fuse3 wget unzip >/dev/null 2>&1

    # 安装rclone
    if [ ! -f "$RCLONE_PATH" ]; then
        echo -e "${YELLOW}${INFO} 安装rclone...${NC}"
        wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
        unzip -q /tmp/rclone.zip -d /tmp
        cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
        chmod 755 "$RCLONE_PATH"
        rm -rf /tmp/rclone*
    fi

    # 配置rclone
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

    # 准备日志
    mkdir -p $(dirname "$LOG_PATH")
    > "$LOG_PATH"

    # 后台挂载
    echo -e "${YELLOW}${INFO} 正在后台挂载...${NC}"
    "$RCLONE_PATH" mount \
        "$DAV_NAME:" "$MOUNT_POINT" \
        --vfs-cache-mode writes \
        --allow-other \
        --log-file "$LOG_PATH" \
        --log-level INFO \
        --daemon >/dev/null 2>&1

    # 验证挂载
    sleep 3
    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "${GREEN}${SUCCESS} 挂载成功！路径：$MOUNT_POINT${NC}"
        echo -e "${YELLOW}${INFO} 可通过 cd $MOUNT_POINT 访问文件${NC}"
    else
        echo -e "${RED}${ERROR} 挂载失败${NC}"
        echo -e "${YELLOW}${INFO} 查看日志：tail -f $LOG_PATH${NC}"
    fi
) &

# 立即返回终端
disown
echo -e "${YELLOW}${INFO} 脚本在后台执行中...${NC}"
echo -e "${YELLOW}${INFO} 几秒后将显示结果，您可继续其他操作${NC}"
sleep 1
exit 0
