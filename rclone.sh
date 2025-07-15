#!/bin/bash

# 设置错误处理
set -e

# 日志文件
LOG_FILE="/var/log/rclone_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "开始执行 rclone 一键安装脚本 - $(date)"

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "错误：请以 root 权限运行此脚本 (sudo $0)"
  exit 1
fi

# 定义变量
RCLONE_CONFIG_DIR="/root/.config/rclone"
RCLONE_CONFIG_FILE="$RCLONE_CONFIG_DIR/rclone.conf"
MOUNT_POINT="/home/user/rclone"
REMOTE_NAME="test"
REMOTE_URL="http://yy.19885172.xyz:19798/dav"
FUSE_CONF="/etc/fuse.conf"

# 步骤 1: 清理包管理器并安装依赖
echo "正在清理包管理器并安装必要依赖..."
# 清理可能导致冲突的包
apt-get update
apt-get remove -y --purge fuse || true
apt-get autoremove -y
apt-get clean
# 修复可能损坏的依赖
apt-get install -f
# 安装依赖
apt-get install -y curl unzip fuse3

# 验证依赖安装
if ! command -v fusermount3 &> /dev/null; then
  echo "错误：fuse3 安装失败"
  exit 1
fi
echo "依赖安装成功：curl, unzip, fuse3"

# 步骤 2: 安装 rclone
echo "正在安装 rclone..."
curl https://rclone.org/install.sh | bash

# 验证 rclone 安装
if ! command -v rclone &> /dev/null; then
  echo "错误：rclone 安装失败"
  exit 1
fi
echo "rclone 安装成功，版本：$(rclone version | head -n 1)"

# 步骤 3: 创建 rclone 配置文件目录
mkdir -p "$RCLONE_CONFIG_DIR"

# 步骤 4: 配置 rclone（WebDAV）
echo "正在配置 rclone for WebDAV..."
cat << EOF > "$RCLONE_CONFIG_FILE"
[$REMOTE_NAME]
type = webdav
url = $REMOTE_URL
vendor = other
EOF

# 验证配置文件
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
  echo "错误：rclone 配置文件创建失败"
  exit 1
fi
echo "rclone 配置文件已生成"

# 步骤 5: 创建挂载点
mkdir -p "$MOUNT_POINT"
chown user:user "$MOUNT_POINT" || echo "警告：无法设置挂载点权限，请手动检查"

# 步骤 6: 配置 fuse
echo "正在配置 fuse..."
if [ -f "$FUSE_CONF" ]; then
  sed -i 's/#user_allow_other/user_allow_other/' "$FUSE_CONF" || true
else
  echo "user_allow_other" > "$FUSE_CONF"
fi
chmod 644 "$FUSE_CONF"

# 步骤 7: 创建 systemd 服务以自动挂载
echo "正在创建 systemd 服务以自动挂载..."
cat << EOF > /etc/systemd/system/rclone-mount.service
[Unit]
Description=rclone mount for WebDAV
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount $REMOTE_NAME:/ $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode writes \
  --dir-cache-time 72h \
  --cache-dir /tmp/rclone \
  --vfs-read-chunk-size lardır

System: 32M \
  --vfs-read-chunk-size-limit off
ExecStop=/bin/fusermount3 -u $MOUNT_POINT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 步骤 8: 启用并启动服务
systemctl daemon-reload
systemctl enable rclone-mount.service
systemctl start rclone-mount.service

# 验证挂载
if mountpoint -q "$MOUNT_POINT"; then
  echo "挂载成功！WebDAV 已挂载到 $MOUNT_POINT"
else
  echo "错误：挂载失败，请检查日志 $LOG_FILE"
  exit 1
fi

echo "rclone 安装、配置和挂载完成！日志保存在 $LOG_FILE"
