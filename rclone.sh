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
# 强制卸载可能残留的挂载
fusermount -u "$MOUNT_POINT" 2>/dev/null
umount -l "$MOUNT_POINT" 2>/dev/null  # 懒卸载，即使设备未响应
# 删除异常的挂载点目录
if [ -d "$MOUNT_POINT" ]; then
    rm -rf "$MOUNT_POINT"
    echo -e "${YELLOW}已删除异常的挂载点目录${NC}"
fi

# 安装必要依赖
echo -e "${YELLOW}安装必要依赖...${NC}"
apt update -y
apt install -y fuse3 wget unzip curl grep sed > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}依赖安装失败，请检查网络连接${NC}"
    exit 1
fi

# 检查rclone是否已安装
if [ ! -f "$RCLONE_PATH" ]; then
    echo -e "${YELLOW}rclone未安装，开始安装...${NC}"
    
    RCLONE_VERSION="v1.65.0"
    echo -e "${YELLOW}正在下载rclone $RCLONE_VERSION...${NC}"
    wget https://github.com/rclone/rclone/releases/download/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-amd64.zip -O /tmp/rclone.zip
    if [ $? -ne 0 ]; then
        echo -e "${RED}rclone下载失败，请检查网络连接${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}正在安装rclone...${NC}"
    unzip /tmp/rclone.zip -d /tmp
    if [ $? -ne 0 ]; then
        echo -e "${RED}rclone解压失败${NC}"
        exit 1
    fi
    
    cp /tmp/rclone-*-linux-amd64/rclone "$RCLONE_PATH"
    chmod 755 "$RCLONE_PATH"
    ln -s "$RCLONE_PATH" /usr/bin/rclone 2>/dev/null
    
    if [ ! -f "$RCLONE_PATH" ]; then
        echo -e "${RED}rclone安装失败，请手动安装${NC}"
        exit 1
    fi
    
    rm -rf /tmp/rclone.zip /tmp/rclone-*-linux-amd64
    echo -e "${GREEN}rclone安装完成${NC}"
else
    echo -e "${GREEN}rclone已安装，跳过安装步骤${NC}"
fi

# 验证WebDAV连接
echo -e "${YELLOW}测试WebDAV连接...${NC}"
TEST_OUTPUT=$("$RCLONE_PATH" lsd "$DAV_NAME:" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}WebDAV连接测试失败，错误信息:${NC}"
    echo "$TEST_OUTPUT"
    read -p "是否继续配置？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}用户取消了操作${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}WebDAV连接测试成功${NC}"
fi

# 显示预配置信息供用户确认
echo -e "${YELLOW}以下是预配置的WebDAV信息:${NC}"
echo -e "  名称: $DAV_NAME"
echo -e "  URL: $DAV_URL"
echo -e "  用户名: $DAV_USER"
echo -e "  挂载点: $MOUNT_POINT"
echo -e "  日志路径: $LOG_PATH"
read -p "是否使用以上配置? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${RED}用户取消了操作${NC}"
    exit 1
fi

# 创建rclone配置目录
mkdir -p /root/.config/rclone/

# 生成rclone配置文件
echo -e "${YELLOW}配置rclone...${NC}"
cat > /root/.config/rclone/rclone.conf << EOF
[$DAV_NAME]
type = webdav
url = $DAV_URL
vendor = other
user = $DAV_USER
pass = $("$RCLONE_PATH" obscure "$DAV_PASS")
EOF

# 重新创建干净的挂载点
echo -e "${YELLOW}创建挂载点: $MOUNT_POINT${NC}"
mkdir -p "$MOUNT_POINT"
# 确保目录权限正确
chown -R $SUDO_USER:$SUDO_USER "$MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo -e "${RED}挂载点权限设置失败，请手动检查目录权限${NC}"
    exit 1
fi

# 创建日志文件目录
mkdir -p $(dirname "$LOG_PATH")
touch "$LOG_PATH"
chown $SUDO_USER:$SUDO_USER "$LOG_PATH"

# 创建自动挂载脚本（增加调试输出）
echo -e "${YELLOW}创建自动挂载脚本...${NC}"
cat > /usr/local/bin/mount_webdav.sh << EOF
#!/bin/bash
# 检查是否已挂载
if ! mountpoint -q $MOUNT_POINT; then
    # 增加详细日志输出
    $RCLONE_PATH mount $DAV_NAME: $MOUNT_POINT --daemon --vfs-cache-mode writes --allow-other --log-file $LOG_PATH --log-level INFO
    if [ \$? -eq 0 ]; then
        echo "$(date): 成功挂载 $DAV_NAME 到 $MOUNT_POINT" >> $LOG_PATH
    else
        echo "$(date): 挂载 $DAV_NAME 失败" >> $LOG_PATH
    fi
else
    echo "$(date): $DAV_NAME 已挂载到 $MOUNT_POINT" >> $LOG_PATH
fi
EOF

chmod +x /usr/local/bin/mount_webdav.sh

# 重新配置systemd服务
echo -e "${YELLOW}重新配置开机自动挂载...${NC}"
cat > /etc/systemd/system/rclone-mount.service << EOF
[Unit]
Description=RClone WebDAV Mount
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mount_webdav.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rclone-mount
systemctl restart rclone-mount

# 立即挂载（带调试信息）
echo -e "${YELLOW}正在挂载WebDAV（带调试信息）...${NC}"
$RCLONE_PATH mount "$DAV_NAME:" "$MOUNT_POINT" --vfs-cache-mode writes --allow-other --log-file "$LOG_PATH" --log-level INFO &
sleep 5  # 等待挂载完成

# 检查挂载状态
if mountpoint -q "$MOUNT_POINT"; then
    echo -e "${GREEN}WebDAV已成功挂载到 $MOUNT_POINT${NC}"
    echo -e "${GREEN}rclone配置完成！${NC}"
    echo -e "${YELLOW}使用说明:${NC}"
    echo -e "  1. 访问挂载点: cd $MOUNT_POINT"
    echo -e "  2. 查看详细日志: tail -f $LOG_PATH"
    echo -e "  3. 重启服务: systemctl restart rclone-mount"
else
    echo -e "${RED}WebDAV挂载失败，请检查配置信息和网络连接${NC}"
    echo -e "${YELLOW}详细错误日志已记录到: $LOG_PATH${NC}"
    echo -e "${YELLOW}尝试手动挂载（带详细调试）: $RCLONE_PATH mount $DAV_NAME: $MOUNT_POINT --vfs-cache-mode writes --allow-other --vv${NC}"
    exit 1
fi
