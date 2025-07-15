#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 预配置参数
DAV_NAME="test"
DAV_URL="http://yy.19885172.xyz:19798/dav"
DAV_USER="root"
DAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
LOG_PATH="/home/user/Downloads/rclone_mount.log"
RCLONE_PATH="/usr/local/bin/rclone"

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用sudo或root权限运行此脚本${NC}" >&2
    exit 1
fi

# 清理旧的挂载状态
echo -e "${YELLOW}清理旧的挂载状态...${NC}"
fusermount -u "$MOUNT_POINT" 2>/dev/null
umount -l "$MOUNT_POINT" 2>/dev/null
pkill -f "rclone mount $DAV_NAME:" 2>/dev/null  # 终止所有相关rclone进程
if [ -d "$MOUNT_POINT" ]; then
    rm -rf "$MOUNT_POINT"
    echo -e "${YELLOW}已删除异常的挂载点目录${NC}"
fi

# 检查并配置fuse（关键修复点）
echo -e "${YELLOW}检查fuse配置...${NC}"
FUSE_CONF="/etc/fuse.conf"
if [ -f "$FUSE_CONF" ]; then
    # 确保允许其他用户访问fuse挂载点
    if ! grep -q "^user_allow_other" "$FUSE_CONF"; then
        echo "user_allow_other" >> "$FUSE_CONF"
        echo -e "${YELLOW}已启用fuse的user_allow_other配置${NC}"
    else
        echo -e "${GREEN}fuse的user_allow_other配置已启用${NC}"
    fi
else
    echo -e "${RED}未找到fuse配置文件，可能导致挂载失败${NC}"
    exit 1
fi

# 安装必要依赖
echo -e "${YELLOW}安装必要依赖...${NC}"
apt update -y
apt install -y fuse3 wget unzip curl grep sed > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}依赖安装失败，请检查网络连接${NC}"
    exit 1
fi

# 确保rclone正确安装
if [ ! -f "$RCLONE_PATH" ]; then
    echo -e "${YELLOW}rclone未安装，开始安装...${NC}"
    RCLONE_VERSION="v1.65.0"
    wget https://github.com/rclone/rclone/releases/download/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-amd64.zip -O /tmp/rclone.zip
    unzip /tmp/rclone.zip -d /tmp
    cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
    chmod 755 "$RCLONE_PATH"
    ln -s "$RCLONE_PATH" /usr/bin/rclone 2>/dev/null
    rm -rf /tmp/rclone.zip /tmp/rclone-*-linux-amd64
    echo -e "${GREEN}rclone安装完成${NC}"
else
    echo -e "${GREEN}rclone已安装，跳过安装步骤${NC}"
fi

# 验证WebDAV连接（关键检查）
echo -e "${YELLOW}测试WebDAV连接...${NC}"
TEST_OUTPUT=$("$RCLONE_PATH" lsd "$DAV_NAME:" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}WebDAV连接失败，错误信息:${NC}"
    echo "$TEST_OUTPUT"
    echo -e "${RED}请先确保WebDAV服务器可访问且凭据正确${NC}"
    exit 1
else
    echo -e "${GREEN}WebDAV连接测试成功${NC}"
fi

# 创建干净的挂载点
echo -e "${YELLOW}创建挂载点: $MOUNT_POINT${NC}"
mkdir -p "$MOUNT_POINT"
chown -R $SUDO_USER:$SUDO_USER "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT"

# 配置rclone
echo -e "${YELLOW}配置rclone...${NC}"
mkdir -p /root/.config/rclone/
cat > /root/.config/rclone/rclone.conf << EOF
[$DAV_NAME]
type = webdav
url = $DAV_URL
vendor = other
user = $DAV_USER
pass = $("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

# 配置日志
mkdir -p $(dirname "$LOG_PATH")
touch "$LOG_PATH"
chown $SUDO_USER:$SUDO_USER "$LOG_PATH"
> "$LOG_PATH"  # 清空旧日志

# 手动挂载并监控（关键修复：前台运行并捕获详细日志）
echo -e "${YELLOW}正在尝试挂载WebDAV（前台模式，30秒后自动后台运行）...${NC}"
"$RCLONE_PATH" mount "$DAV_NAME:" "$MOUNT_POINT" \
    --vfs-cache-mode writes \
    --allow-other \
    --log-file "$LOG_PATH" \
    --log-level DEBUG \
    --daemon-wait 30  # 先前台运行30秒便于观察

# 严格验证挂载状态
echo -e "${YELLOW}验证挂载状态...${NC}"
sleep 5  # 等待挂载完成

# 多种方式验证挂载
MOUNTED=0
if mountpoint -q "$MOUNT_POINT"; then
    MOUNTED=1
elif grep -qs "$MOUNT_POINT" /proc/mounts; then
    MOUNTED=1
elif [ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then
    MOUNTED=1
fi

if [ $MOUNTED -eq 1 ]; then
    echo -e "${GREEN}WebDAV已成功挂载到 $MOUNT_POINT${NC}"
    echo -e "${YELLOW}挂载点内容预览:${NC}"
    ls -la "$MOUNT_POINT" | head -5  # 显示前5项内容
    echo -e "${YELLOW}使用说明:${NC}"
    echo -e "  1. 访问挂载点: cd $MOUNT_POINT"
    echo -e "  2. 查看详细日志: tail -f $LOG_PATH"
    echo -e "  3. 重启服务: systemctl restart rclone-mount"
else
    echo -e "${RED}挂载验证失败，实际未挂载${NC}"
    echo -e "${YELLOW}最后10行错误日志:${NC}"
    tail -n 10 "$LOG_PATH"
    echo -e "${YELLOW}手动挂载命令（前台调试）:${NC}"
    echo "$RCLONE_PATH mount $DAV_NAME: $MOUNT_POINT --vfs-cache-mode writes --allow-other --vv"
    exit 1
fi

# 配置开机自启
echo -e "${YELLOW}配置开机自动挂载...${NC}"
cat > /etc/systemd/system/rclone-mount.service << EOF
[Unit]
Description=RClone WebDAV Mount
After=network.target

[Service]
Type=simple
ExecStart=$RCLONE_PATH mount $DAV_NAME: $MOUNT_POINT --vfs-cache-mode writes --allow-other --log-file $LOG_PATH --log-level INFO
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rclone-mount
