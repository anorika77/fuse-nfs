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

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用sudo或root权限运行此脚本${NC}" >&2
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

# 检查rclone是否已安装
if ! command -v rclone &> /dev/null; then
    echo -e "${YELLOW}rclone未安装，开始安装...${NC}"
    
    # 下载最新版rclone
    echo -e "${YELLOW}正在获取最新rclone版本...${NC}"
    RCLONE_VERSION=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$RCLONE_VERSION" ]; then
        echo -e "${RED}无法获取rclone版本信息，使用备用版本v1.65.0${NC}"
        RCLONE_VERSION="v1.65.0"
    fi
    
    echo -e "${YELLOW}正在下载rclone $RCLONE_VERSION...${NC}"
    wget https://github.com/rclone/rclone/releases/download/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-amd64.zip -O /tmp/rclone.zip
    if [ $? -ne 0 ]; then
        echo -e "${RED}rclone下载失败，请检查网络连接${NC}"
        exit 1
    fi
    
    # 解压并安装
    echo -e "${YELLOW}正在安装rclone...${NC}"
    unzip /tmp/rclone.zip -d /tmp
    if [ $? -ne 0 ]; then
        echo -e "${RED}rclone解压失败${NC}"
        exit 1
    fi
    
    cp /tmp/rclone-*-linux-amd64/rclone /usr/bin/
    chmod 755 /usr/bin/rclone
    
    # 验证安装
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}rclone安装失败，请手动安装${NC}"
        exit 1
    fi
    
    # 清理临时文件
    rm -rf /tmp/rclone.zip /tmp/rclone-*-linux-amd64
    
    echo -e "${GREEN}rclone安装完成${NC}"
else
    echo -e "${GREEN}rclone已安装，跳过安装步骤${NC}"
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
pass = $(echo -n "$DAV_PASS" | rclone obscure -)
EOF

# 创建挂载点
echo -e "${YELLOW}创建挂载点: $MOUNT_POINT${NC}"
mkdir -p $MOUNT_POINT
# 设置权限，确保普通用户可访问
chown -R $SUDO_USER:$SUDO_USER $MOUNT_POINT

# 创建日志文件目录
mkdir -p $(dirname $LOG_PATH)
touch $LOG_PATH
chown $SUDO_USER:$SUDO_USER $LOG_PATH

# 创建自动挂载脚本
echo -e "${YELLOW}创建自动挂载脚本...${NC}"
cat > /usr/local/bin/mount_webdav.sh << EOF
#!/bin/bash
# 检查是否已挂载
if ! mountpoint -q $MOUNT_POINT; then
    rclone mount $DAV_NAME: $MOUNT_POINT --daemon --vfs-cache-mode writes --allow-other
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

# 设置开机自动挂载
echo -e "${YELLOW}配置开机自动挂载...${NC}"
# 添加到rc.local（如果存在）
if [ -f /etc/rc.local ]; then
    sed -i '/exit 0/i /usr/local/bin/mount_webdav.sh' /etc/rc.local
else
    # 创建systemd服务
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

    systemctl enable rclone-mount
    systemctl start rclone-mount
fi

# 立即挂载
echo -e "${YELLOW}正在挂载WebDAV...${NC}"
/usr/local/bin/mount_webdav.sh

# 检查挂载状态
if mountpoint -q $MOUNT_POINT; then
    echo -e "${GREEN}WebDAV已成功挂载到 $MOUNT_POINT${NC}"
    echo -e "${GREEN}rclone配置完成！${NC}"
    echo -e "${YELLOW}使用说明:${NC}"
    echo -e "  1. 访问挂载点: cd $MOUNT_POINT"
    echo -e "  2. 查看日志: tail -f $LOG_PATH"
    echo -e "  3. 重启服务: systemctl restart rclone-mount"
else
    echo -e "${RED}WebDAV挂载失败，请检查配置信息和网络连接${NC}"
    echo -e "${YELLOW}尝试手动挂载以查看详细错误: rclone mount $DAV_NAME: $MOUNT_POINT --vfs-cache-mode writes --allow-other${NC}"
    echo -e "${YELLOW}查看日志获取更多信息: tail -f $LOG_PATH${NC}"
    exit 1
fi
