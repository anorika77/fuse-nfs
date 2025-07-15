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
WEBDAV_USER="root"
WEBDAV_PASS="password"

# 验证 user 用户是否存在
if ! id "user" >/dev/null 2>&1; then
  echo "错误：用户 'user' 不存在，请创建用户或修改挂载点"
  exit 1
fi

# 步骤 1: 清理包管理器并安装依赖
echo "正在清理包管理器并安装必要依赖..."
apt-get update
apt-get remove -y --purge fuse || true
apt-get autoremove -y
apt-get clean
apt-get install -f
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
chmod 600 "$RCLONE_CONFIG_DIR"

# 步骤 4: 配置 rclone（WebDAV）
echo "正在配置 rclone for WebDAV..."
OBSCURED_PASS=$(rclone obscure "$WEBDAV_PASS")
cat << EOF > "$RCLONE_CONFIG_FILE"
[$REMOTE_NAME]
type = webdav
url = $REMOTE_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF
chmod 600 "$RCLONE_CONFIG_FILE"

# 验证配置文件
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
  echo "错误：rclone 配置文件创建失败"
  exit 1
fi
echo "rclone 配置文件已生成"

# 步骤 5: 测试 WebDAV 连接
echo "正在测试 WebDAV 服务器连接..."
if curl -s -I --user "$WEBDAV_USER:$WEBDAV_PASS" "$REMOTE_URL" | grep -q "HTTP/[0-9.]* 2[0-9]\{2\}"; then
  echo "WebDAV 服务器可达，认证成功"
else
  echo "错误：无法连接到 WebDAV 服务器 $REMOTE_URL 或认证失败"
  echo "请检查 URL、用户名或密码是否正确"
  echo "尝试手动测试：curl -I --user $WEBDAV_USER:$WEBDAV_PASS $REMOTE_URL"
  exit 1
fi

# 步骤 6: 测试 WebDAV 文件列表
echo "正在测试 WebDAV 文件列表..."
if rclone lsd "$REMOTE_NAME:/" --log-file=/var/log/rclone_test.log --log-level DEBUG; then
  echo "WebDAV 文件列表获取成功"
else
  echo "错误：无法列出 WebDAV 目录，请检查 /var/log/rclone_test.log"
  exit 1
fi

# 步骤 7: 创建挂载点
mkdir -p "$MOUNT_POINT"
chown user:user "$MOUNT_POINT" || {
  echo "警告：无法设置挂载点权限，请手动检查"
  echo "挂载点: $MOUNT_POINT"
}

# 步骤 8: 配置 fuse
echo "正在配置 fuse..."
if [ -f "$FUSE_CONF" ]; then
  sed -i 's/#user_allow_other/user_allow_other/' "$FUSE_CONF" || true
else
  echo "user_allow_other" > "$FUSE_CONF"
fi
chmod 644 "$FUSE_CONF"

# 步骤 9: 创建 systemd 服务以自动挂载
echo "正在创建 systemd 服务以自动挂载..."
cat << EOF > /etc/systemd/system/rclone-mount.service
[Unit]
Description=rclone mount for WebDAV
After=network-online.target

[Service]
Type=simple
User=user
ExecStart=/usr/bin/rclone mount $REMOTE_NAME:/ $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode writes \
  --dir-cache-time 72h \
  --cache-dir /tmp/rclone \
  --vfs-read-chunk-size 32M \
  --vfs-read-chunk-size-limit off \
  --log-file=/var/log/rclone_mount.log \
  --log-level DEBUG
ExecStop=/bin/fusermount3 -u $MOUNT_POINT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 步骤 10: 启用并启动服务
systemctl daemon-reload
systemctl enable rclone-mount.service
if ! systemctl start rclone-mount.service; then
  echo "错误：systemd 服务启动失败，请检查日志"
  echo "运行以下命令查看状态：sudo systemctl status rclone-mount.service"
  exit 1
fi

# 等待挂载完成
sleep 10

# 验证挂载
if mountpoint -q "$MOUNT_POINT"; then
  echo "挂载成功！WebDAV 已挂载到 $MOUNT_POINT"
  ls -l "$MOUNT_POINT" | tee -a "$LOG_FILE"
else
  echo "错误：挂载失败，请检查以下日志："
  echo "- 脚本日志：$LOG_FILE"
  echo "- rclone 挂载日志：/var/log/rclone_mount.log"
  echo "- systemd 服务状态：sudo systemctl status rclone-mount.service"
  echo "尝试手动运行以下命令以调试："
  echo "sudo -u user rclone mount $REMOTE_NAME:/ $MOUNT_POINT --allow-other --vfs-cache-mode writes --dir-cache-time 72h --cache-dir /tmp/rclone --vfs-read-chunk-size 32M --vfs-read-chunk-size-limit off --verbose"
  exit 1
fi

echo "rclone 安装、配置和挂载完成！日志保存在 $LOG_FILE 和 /var/log/rclone_mount.log"
