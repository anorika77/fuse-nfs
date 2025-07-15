#!/bin/bash
set -e

# 配置变量 - 可根据需要修改
RCLONE_VERSION="current"
MOUNT_POINT="/home/user/rclone"
REMOTE_NAME="test"
REMOTE_TYPE="webdav"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
LOG_FILE="/var/log/rclone-webdav.log"
SERVICE_NAME="rclone-webdav-mount"
MOUNT_USER="user"  # 用于挂载的用户名

# 彩色输出函数
info() { echo -e "\033[1;34m[INFO] $*\033[0m"; }
success() { echo -e "\033[1;32m[SUCCESS] $*\033[0m"; }
error() { echo -e "\033[1;31m[ERROR] $*\033[0m"; exit 1; }

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    error "请使用root权限运行此脚本: sudo $0"
fi

# 检查并安装依赖
info "检查并安装必要依赖"
apt update -y >/dev/null
DEPENDENCIES="curl unzip fuse3"
for dep in $DEPENDENCIES; do
    if ! dpkg -s $dep &> /dev/null; then
        info "安装依赖: $dep"
        apt install -y $dep >/dev/null || error "无法安装依赖 $dep"
    else
        info "依赖已安装: $dep"
    fi
done

# 配置fuse
info "配置fuse环境"
if ! lsmod | grep -q fuse; then
    info "加载fuse模块"
    modprobe fuse || error "无法加载fuse模块"
else
    info "fuse模块已加载"
fi

# 允许非root用户使用--allow-other
FUSE_CONF="/etc/fuse.conf"
if ! grep -q "user_allow_other" "$FUSE_CONF"; then
    info "配置fuse允许--allow-other选项"
    echo "user_allow_other" >> "$FUSE_CONF" || error "无法修改fuse配置"
else
    info "fuse已允许--allow-other"
fi

# 安装rclone
info "安装rclone"
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
else
    error "不支持的架构: $ARCH"
fi

# 使用临时目录处理安装
TMP_DIR=$(mktemp -d)
RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-${ARCH}.zip"
RCLONE_URL="https://downloads.rclone.org/${RCLONE_ZIP}"

info "下载rclone: $RCLONE_URL"
if ! curl -o "$TMP_DIR/$RCLONE_ZIP" --fail -sL "$RCLONE_URL"; then
    rm -rf "$TMP_DIR"
    error "rclone下载失败，请检查网络连接"
fi

info "解压rclone安装包"
unzip -o -q "$TMP_DIR/$RCLONE_ZIP" -d "$TMP_DIR"

# 查找解压目录
RCLONE_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "rclone-*-linux-${ARCH}" | head -n 1)
if [ -z "$RCLONE_DIR" ]; then
    rm -rf "$TMP_DIR"
    error "未找到rclone解压目录"
fi

# 检查可执行文件
if [ ! -f "${RCLONE_DIR}/rclone" ]; then
    rm -rf "$TMP_DIR"
    error "rclone可执行文件不存在"
fi

# 安装rclone
cp "${RCLONE_DIR}/rclone" /usr/bin/
chmod 755 /usr/bin/rclone
rm -rf "$TMP_DIR"

# 验证安装
if ! command -v rclone &> /dev/null; then
    error "rclone安装失败"
fi
RCLONE_VER=$(rclone version | head -n 1 | awk '{print $2}')
info "rclone安装成功，版本: $RCLONE_VER"

# 配置WebDAV远程
info "配置WebDAV远程存储"
mkdir -p "$HOME/.config/rclone"

# 创建配置
rclone config create ${REMOTE_NAME} ${REMOTE_TYPE} \
    url="${WEBDAV_URL}" \
    user="${WEBDAV_USER}" \
    pass="${WEBDAV_PASS}" \
    --non-interactive >/dev/null || error "无法创建rclone配置"

# 测试WebDAV连接
info "测试WebDAV连接"
if ! rclone lsd ${REMOTE_NAME}: &> /dev/null; then
    error "WebDAV连接失败！请检查:
1. 地址是否正确: ${WEBDAV_URL}
2. 用户名/密码是否正确
3. 远程服务是否可用
可手动测试: rclone lsd ${REMOTE_NAME}:"
fi
info "WebDAV连接测试通过"

# 配置挂载点和用户
info "配置挂载点: $MOUNT_POINT"

# 检查并创建用户
if ! id -u "$MOUNT_USER" &> /dev/null; then
    info "用户$MOUNT_USER不存在，创建用户"
    useradd -m "$MOUNT_USER" || error "无法创建用户$MOUNT_USER"
else
    info "用户$MOUNT_USER已存在"
fi

# 创建并设置挂载点权限
mkdir -p ${MOUNT_POINT}
chown -R "$MOUNT_USER:$MOUNT_USER" ${MOUNT_POINT}
chmod 755 ${MOUNT_POINT} || error "无法设置挂载点权限"

# 配置systemd服务
info "配置自动挂载服务"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 提前创建日志文件并设置权限
touch ${LOG_FILE}
chown "$MOUNT_USER:$MOUNT_USER" ${LOG_FILE}
chmod 644 ${LOG_FILE} || error "无法设置日志文件权限"

# 写入服务配置
cat > ${SERVICE_FILE} << EOF
[Unit]
Description=RClone WebDAV Mount Service
After=network.target

[Service]
Type=simple
User=$MOUNT_USER
Group=$MOUNT_USER
ExecStart=/usr/bin/rclone mount ${REMOTE_NAME}: ${MOUNT_POINT} \
  --allow-other \
  --buffer-size 32M \
  --dir-cache-time 1000h \
  --file-cache-duration 1000h \
  --log-level INFO \
  --log-file ${LOG_FILE}

ExecStop=/bin/fusermount3 -u ${MOUNT_POINT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
info "启动并设置开机自启"
systemctl daemon-reload
systemctl start ${SERVICE_NAME}.service || error "服务启动失败"
systemctl enable ${SERVICE_NAME}.service >/dev/null

# 最终状态检查
info "验证服务状态"
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    success "所有操作完成！"
    echo "----------------------------------------"
    echo "rclone已成功挂载WebDAV到:"
    echo "  挂载点: $MOUNT_POINT"
    echo "  远程地址: $WEBDAV_URL"
    echo "----------------------------------------"
    echo "常用命令:"
    echo "  查看状态: systemctl status $SERVICE_NAME"
    echo "  查看日志: tail -f $LOG_FILE"
    echo "  重启服务: systemctl restart $SERVICE_NAME"
else
    error "服务启动失败！详细信息:
$(systemctl status ${SERVICE_NAME}.service --no-pager)
日志内容:
$(cat ${LOG_FILE} 2>/dev/null)"
fi
