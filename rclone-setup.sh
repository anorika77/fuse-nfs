#!/bin/bash
# Rclone 全自动化安装与 WebDAV 配置脚本
# 配置信息：远程名称=test，URL=http://yy.19885172.xyz:19798/dav，自动挂载到/home/user/rclone

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 配置参数（根据你的需求预设置）
REMOTE_NAME="test"                   # 远程名称
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"  # WebDAV服务器URL
VENDOR="webdav"                      # 服务器类型
USERNAME="root"                      # 用户名
PASSWORD="password"                  # 密码
MOUNT_POINT="/home/user/rclone"      # 本地挂载目录
SYSTEMD_SERVICE="rclone-webdav.service"  # 系统服务名

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行脚本（sudo bash $0）${NC}"
    exit 1
fi

# 检查目标用户是否存在（确保/home/user目录存在）
if ! id "user" &>/dev/null; then
    echo -e "${YELLOW}警告：用户user不存在，将自动创建...${NC}"
    useradd -m user  # 创建user用户并生成/home/user目录
fi

# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[1/5] 正在安装Rclone...${NC}"
    # 安装依赖
    if [ -f /etc/debian_version ]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl fuse >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl fuse >/dev/null 2>&1
    else
        echo -e "${RED}不支持的操作系统！仅支持Ubuntu/Debian/CentOS${NC}"
        exit 1
    fi
    # 下载并安装Rclone
    curl https://rclone.org/install.sh | bash >/dev/null 2>&1
    if ! command -v rclone &>/dev/null; then
        echo -e "${RED}Rclone安装失败！${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] Rclone安装完成${NC}"
}

# 配置WebDAV远程
configure_webdav() {
    echo -e "${YELLOW}[2/5] 正在配置WebDAV远程（名称：test）...${NC}"
    # 创建Rclone配置目录
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    chown -R user:user "$CONFIG_DIR"  # 赋予user用户权限

    # 生成配置文件（密码自动加密）
    OBSCURED_PASS=$(echo "$PASSWORD" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = $VENDOR
user = $USERNAME
pass = $OBSCURED_PASS
EOF
    chown user:user "$CONFIG_DIR/rclone.conf"
    chmod 600 "$CONFIG_DIR/rclone.conf"  # 限制权限，提高安全性
    echo -e "${GREEN}[✓] WebDAV配置完成${NC}"
}

# 创建本地挂载目录并设置权限
create_mount_point() {
    echo -e "${YELLOW}[3/5] 正在创建本地挂载目录（$MOUNT_POINT）...${NC}"
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"  # 确保user用户有读写权限
    echo -e "${GREEN}[✓] 挂载目录创建完成${NC}"
}

# 配置systemd服务实现自动挂载（开机启动）
setup_systemd_service() {
    echo -e "${YELLOW}[4/5] 正在配置自动挂载服务...${NC}"
    # 创建系统服务文件
    SERVICE_FILE="/etc/systemd/system/$SYSTEMD_SERVICE"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone mount for WebDAV (test)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode full \
  --buffer-size 64M \
  --vfs-read-chunk-size 128M \
  --log-level INFO \
  --log-file /var/log/rclone-test.log
ExecStop=/usr/bin/fusermount -u $MOUNT_POINT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务并设置开机自启
    systemctl daemon-reload
    systemctl enable --now "$SYSTEMD_SERVICE" >/dev/null 2>&1

    # 检查服务状态
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        echo -e "${GREEN}[✓] 自动挂载服务启动成功${NC}"
    else
        echo -e "${RED}[×] 自动挂载服务启动失败，请查看日志：/var/log/rclone-test.log${NC}"
        exit 1
    fi
}

# 验证挂载结果
verify_mount() {
    echo -e "${YELLOW}[5/5] 正在验证挂载结果...${NC}"
    # 检查目录是否挂载成功
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] WebDAV已成功挂载到：$MOUNT_POINT${NC}"
        echo -e "${YELLOW}测试访问挂载目录：${NC}"
        ls -ld "$MOUNT_POINT"  # 显示目录权限
    else
        echo -e "${RED}[×] 挂载失败！请检查日志：/var/log/rclone-test.log${NC}"
        exit 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 开始Rclone全自动化配置 =====${NC}"
    install_rclone
    configure_webdav
    create_mount_point
    setup_systemd_service
    verify_mount
    echo -e "${GREEN}===== 所有操作完成！=====${NC}"
    echo -e "1. 远程名称：$REMOTE_NAME"
    echo -e "2. WebDAV地址：$WEBDAV_URL"
    echo -e "3. 本地挂载目录：$MOUNT_POINT"
    echo -e "4. 服务管理命令："
    echo -e "   - 重启服务：sudo systemctl restart $SYSTEMD_SERVICE"
    echo -e "   - 查看状态：sudo systemctl status $SYSTEMD_SERVICE"
    echo -e "   - 停止服务：sudo systemctl stop $SYSTEMD_SERVICE"
}

# 执行主流程
main
