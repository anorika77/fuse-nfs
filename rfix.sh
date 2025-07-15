#!/bin/bash
# 极简版rclone挂载脚本 - 彻底解决参数错误

# 配置参数（确保变量后无空格）
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
    echo "请用sudo运行：sudo ./rclone_setup.sh"
    exit 1
fi

# 强制清理旧环境
fusermount -u "$MOUNT_POINT" 2>/dev/null
umount -l "$MOUNT_POINT" 2>/dev/null
pkill -f "rclone mount" 2>/dev/null
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
mkdir -p "$LOG_DIR"
chown -R $SUDO_USER:$SUDO_USER "$LOG_DIR" "$MOUNT_POINT"

# 安装基础组件（极简版）
apt update -y >/dev/null 2>&1
apt install -y fuse3 wget unzip >/dev/null 2>&1

# 安装rclone（直接指定版本）
if [ ! -f "$RCLONE_PATH" ]; then
    wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
    unzip -q /tmp/rclone.zip -d /tmp
    cp /tmp/rclone-v1.65.0-linux-amd64/rclone "$RCLONE_PATH"
    chmod 755 "$RCLONE_PATH"
    rm -rf /tmp/rclone*
fi

# 写入配置（无多余空格）
mkdir -p /root/.config/rclone/
cat >/root/.config/rclone/rclone.conf<<EOF
[$DAV_NAME]
type=webdav
url=$DAV_URL
vendor=other
user=$DAV_USER
pass=$("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

# 核心修复：用单行命令避免换行导致的多余参数，无任何多余空格
echo "正在挂载..."
$RCLONE_PATH mount "$DAV_NAME:" "$MOUNT_POINT" --vfs-cache-mode writes --allow-other --log-file "$LOG_PATH" --log-level INFO --daemon

# 验证
sleep 3
if mountpoint -q "$MOUNT_POINT"; then
    echo "挂载成功！路径：$MOUNT_POINT"
    echo "日志：$LOG_PATH"
else
    echo "挂载失败，查看日志：tail -f $LOG_PATH"
    # 输出实际执行的命令供调试
    echo "实际执行的命令："
    echo "$RCLONE_PATH mount \"$DAV_NAME:\" \"$MOUNT_POINT\" --vfs-cache-mode writes --allow-other --log-file \"$LOG_PATH\" --log-level INFO --daemon"
fi

exit 0
