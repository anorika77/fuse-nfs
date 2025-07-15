#!/bin/bash
# Rclone一键安装配置脚本（修复引号错误）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
SERVICE_NAME="rclone.service"
LOG_FILE="/var/log/rclone.log"
CONFIG_DIR="/root/.config/rclone"

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请使用root权限运行此脚本 (sudo bash $0)${NC}"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# 安装依赖
install_deps() {
    echo -e "${YELLOW}[1/6] 安装依赖...${NC}"
    OS=$(detect_os)
    
    case $OS in
        "debian")
            apt-get update -y >/dev/null 2>&1
            apt-get install -y curl fuse3 >/dev/null 2>&1
            ;;
        "rhel")
            yum install -y curl fuse3 >/dev/null 2>&1
            ;;
        "unknown")
            echo -e "${RED}不支持的操作系统！${NC}"
            exit 1
            ;;
    esac
    
    if ! command -v curl &>/dev/null || ! command -v fusermount3 &>/dev/null; then
        echo -e "${RED}依赖安装失败！${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[✓] 依赖安装完成${NC}"
}

# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[2/6] 安装Rclone...${NC}"
    
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | bash >/dev/null 2>&1
        
        if ! command -v rclone &>/dev/null; then
            echo -e "${RED}Rclone安装失败！${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}[✓] Rclone已安装 (版本: $(rclone --version | head -n1))${NC}"
}

# 配置Rclone
configure_rclone() {
    echo -e "${YELLOW}[3/6] 配置Rclone...${NC}"
    
    mkdir -p "$CONFIG_DIR"
    
    # 加密密码
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    
    # 创建配置文件
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF
    
    # 测试配置
    echo -e "${YELLOW}测试WebDAV连接...${NC}"
    if rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] WebDAV连接成功${NC}"
    else
        echo -e "${RED}WebDAV连接失败！请检查URL、用户名和密码${NC}"
        echo -e "${YELLOW}错误详情：${NC}"
        rclone lsd "$REMOTE_NAME:" 2>&1 || true
        exit 1
    fi
}

# 准备挂载点
prepare_mount_point() {
    echo -e "${YELLOW}[4/6] 准备挂载点...${NC}"
    
    # 创建用户（如果不存在）
    if ! id "user" &>/dev/null; then
        useradd -m -s /bin/false user
        echo -e "${GREEN}[✓] 用户'user'已创建${NC}"
    fi
    
    # 创建挂载点目录
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    
    # 启用fuse用户挂载
    if ! grep -q "user_allow_other" /etc/fuse.conf; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi
    
    echo -e "${GREEN}[✓] 挂载点准备完成${NC}"
}

# 创建systemd服务
create_systemd_service() {
    echo -e "${YELLOW}[5/6] 创建systemd服务...${NC}"
    
    cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=Rclone mount for $REMOTE_NAME
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
User=user
Group=user
ExecStart=/usr/bin/rclone mount \\
  --config $CONFIG_DIR/rclone.conf \\
  --allow-other \\
  --vfs-cache-mode full \\
  --vfs-read-chunk-size 64M \\
  --vfs-read-chunk-size-limit off \\
  --buffer-size 256M \\
  --dir-cache-time 168h \\
  --poll-interval 15s \\
  --timeout 1h \\
  --log-level INFO \\
  --log-file $LOG_FILE \\
  $REMOTE_NAME: $MOUNT_POINT
ExecStop=/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=default.target
EOF
    
    # 重载systemd并启用服务
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] Rclone服务已启动并设置为开机自启${NC}"
    else
        echo -e "${RED}Rclone服务启动失败！${NC}"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
}

# 验证安装
verify_installation() {
    echo -e "${YELLOW}[6/6] 验证安装...${NC}"
    
    # 检查挂载点
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 挂载点$MOUNT_POINT已成功挂载${NC}"
    else
        echo -e "${RED}挂载点未挂载！请检查日志：$LOG_FILE${NC}"
        exit 1
    fi
    
    # 列出挂载内容
    echo -e "${YELLOW}挂载内容示例：${NC}"
    sudo -u user ls -l "$MOUNT_POINT" | head -n5 || true
    
    echo -e "${GREEN}[✓] Rclone安装配置完成！${NC}"
}

# 显示使用帮助
show_usage() {
    echo -e "\n${GREEN}===== Rclone使用指南 ====="${NC}
    echo -e "远程名称: ${GREEN}$REMOTE_NAME${NC}"
    echo -e "WebDAV URL: ${GREEN}$WEBDAV_URL${NC}"
    echo -e "挂载点: ${GREEN}$MOUNT_POINT${NC}"
    echo -e "服务管理:"
    echo -e "  ${YELLOW}启动:${NC} systemctl start $SERVICE_NAME"
    echo -e "  ${YELLOW}停止:${NC} systemctl stop $SERVICE_NAME"
    echo -e "  ${YELLOW}重启:${NC} systemctl restart $SERVICE_NAME"
    echo -e "  ${YELLOW}状态:${NC} systemctl status $SERVICE_NAME"
    echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
}

# 主函数（修复引号错误）
main() {
    echo -e "${GREEN}===== Rclone一键安装配置工具 ====${NC}"  # 修复此处引号
    echo -e "${YELLOW}将使用以下配置：${NC}"
    echo -e "  WebDAV URL: ${GREEN}$WEBDAV_URL${NC}"
    echo -e "  用户名: ${GREEN}$WEBDAV_USER${NC}"
    echo -e "  远程名称: ${GREEN}$REMOTE_NAME${NC}"
    echo -e "  挂载路径: ${GREEN}$MOUNT_POINT${NC}"
    echo
    
    check_root
    install_deps
    install_rclone
    configure_rclone
    prepare_mount_point
    create_systemd_service
    verify_installation
    show_usage
}

main
