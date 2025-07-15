#!/bin/bash
set -e

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行此脚本 (sudo $0)"
    exit 1
fi

# 配置变量 - 根据需求设置
RCLONE_VERSION="current"  # 使用最新版本
MOUNT_POINT="/home/user/rclone"  # 挂载点
REMOTE_NAME="test"         # 远程存储名称
REMOTE_TYPE="webdav"       # 远程存储类型为webdav
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"  # 远程webdav URL
WEBDAV_USER="root"         # webdav用户名
WEBDAV_PASS="password"     # webdav密码

# 检查并安装依赖
echo "=== 检查并安装必要依赖 ==="

# 更新包列表
apt update -y

# 定义需要安装的依赖
DEPENDENCIES="curl unzip fuse3"

# 检查并安装每个依赖
for dep in $DEPENDENCIES; do
    if ! dpkg -s $dep &> /dev/null; then
        echo "安装依赖: $dep"
        apt install -y $dep
    else
        echo "依赖已安装: $dep"
    fi
done

# 检查fuse3模块是否加载
if ! lsmod | grep -q fuse; then
    echo "加载fuse模块..."
    modprobe fuse
else
    echo "fuse模块已加载"
fi

# 安装rclone
echo "=== 安装rclone ==="
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 下载并安装rclone，使用更可靠的方法
RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-${ARCH}.zip"
RCLONE_URL="https://downloads.rclone.org/${RCLONE_ZIP}"

echo "下载rclone: $RCLONE_URL"
if ! curl -O --fail "$RCLONE_URL"; then
    echo "下载rclone失败，请检查网络连接或URL是否正确"
    exit 1
fi

# 检查zip文件是否存在
if [ ! -f "$RCLONE_ZIP" ]; then
    echo "rclone安装包不存在: $RCLONE_ZIP"
    exit 1
fi

# 解压并查找rclone可执行文件
echo "解压rclone安装包..."
unzip -q "$RCLONE_ZIP"

# 查找解压后的目录（处理可能的版本号变化）
RCLONE_DIR=$(find . -type d -name "rclone-*-linux-${ARCH}" | head -n 1)

if [ -z "$RCLONE_DIR" ]; then
    echo "找不到rclone解压目录"
    exit 1
fi

echo "找到rclone目录: $RCLONE_DIR"

# 检查rclone可执行文件是否存在
if [ ! -f "${RCLONE_DIR}/rclone" ]; then
    echo "rclone可执行文件不存在于解压目录中"
    exit 1
fi

# 安装rclone
cp "${RCLONE_DIR}/rclone" /usr/bin/
chmod 755 /usr/bin/rclone
rm -rf "$RCLONE_ZIP" "$RCLONE_DIR"

# 检查安装是否成功
if ! command -v rclone &> /dev/null; then
    echo "rclone安装失败"
    exit 1
fi

echo "rclone安装成功，版本: $(rclone version | head -n 1)"

# 配置rclone webdav远程存储
echo "=== 配置rclone webdav远程存储 ==="
# 确保配置目录存在
mkdir -p "$HOME/.config/rclone"

# 创建或更新配置
rclone config create ${REMOTE_NAME} ${REMOTE_TYPE} \
    url="${WEBDAV_URL}" \
    user="${WEBDAV_USER}" \
    pass="${WEBDAV_PASS}" \
    --non-interactive

# 创建挂载点并设置权限
echo "=== 配置挂载点 ==="
mkdir -p ${MOUNT_POINT}
# 确保用户对挂载点有访问权限
chown -R $SUDO_USER:$SUDO_USER ${MOUNT_POINT}
chmod 755 ${MOUNT_POINT}

# 创建systemd服务实现自动挂载和开机启动
echo "=== 配置自动挂载 ==="
SERVICE_FILE="/etc/systemd/system/rclone-webdav-mount.service"

cat > ${SERVICE_FILE} << EOF
[Unit]
Description=RClone WebDAV Mount Service
After=network.target

[Service]
Type=simple
User=$SUDO_USER
Group=$SUDO_USER
ExecStart=/usr/bin/rclone mount ${REMOTE_NAME}: ${MOUNT_POINT} \
  --allow-other \
  --allow-non-empty \
  --buffer-size 32M \
  --dir-cache-time 1000h \
  --file-cache-duration 1000h \
  --log-level INFO \
  --log-file /var/log/rclone-webdav.log

ExecStop=/bin/fusermount3 -u ${MOUNT_POINT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机自启
systemctl daemon-reload
systemctl start rclone-webdav-mount.service
systemctl enable rclone-webdav-mount.service

# 检查挂载状态
echo "=== 安装结果 ==="
if systemctl is-active --quiet rclone-webdav-mount.service; then
    echo "rclone已成功安装并将webdav挂载到 ${MOUNT_POINT}"
    echo "可以通过以下命令检查状态: systemctl status rclone-webdav-mount.service"
    echo "日志文件: /var/log/rclone-webdav.log"
else
    echo "rclone服务启动失败，请检查日志: /var/log/rclone-webdav.log"
    exit 1
fi
