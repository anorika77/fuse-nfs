#!/bin/bash
# Rclone WebDAV 一键安装配置脚本（彻底修复引号错误）
# 适配系统：Ubuntu/Debian/CentOS/Rocky Linux

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'  # 重置颜色

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
        echo -e "${RED}错误：必须使用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    [ -f /etc/debian_version ] && echo "debian" && return
    [ -f /etc/redhat-release ] && echo "rhel" && return
    echo "unknown"
}

# 安装依赖
install_deps() {
    echo -e "${YELLOW}[1/9] 安装依赖...${NC}"
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

    for cmd in curl fusermount3; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}依赖$cmd安装失败！${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}[✓] 依赖安装完成${NC}"
}

# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[2/9] 安装Rclone...${NC}"
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | bash >/dev/null 2>&1
        
        # 备用安装方法
        if ! command -v rclone &>/dev/null; then
            echo -e "${YELLOW}尝试备用安装方法...${NC}"
            ARCH=$(uname -m)
            case $ARCH in
                x86_64) ARCH="amd64" ;;
                aarch64) ARCH="arm64" ;;
                *) echo -e "${RED}不支持的架构：$ARCH${NC}"; exit 1 ;;
            esac
            RCLONE_VERSION=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep "tag_name" | cut -d'"' -f4 | tr -d 'v')
            wget -q https://downloads.rclone.org/v$RCLONE_VERSION/rclone-v$RCLONE_VERSION-linux-$ARCH.deb -O /tmp/rclone.deb
            dpkg -i /tmp/rclone.deb >/dev/null 2>&1
            rm /tmp/rclone.deb
        fi
    fi
    
    if command -v rclone &>/dev/null; then
        echo -e "${GREEN}[✓] Rclone已安装（版本：$(rclone --version | head -n1 | awk '{print $2}')）${NC}"
    else
        echo -e "${RED}Rclone安装失败！请手动安装：https://rclone.org/install/${NC}"
        exit 1
    fi
}

# 配置WebDAV远程
configure_remote() {
    echo -e "${YELLOW}[3/9] 配置WebDAV远程（名称：$REMOTE_NAME）...${NC}"
    mkdir -p "$CONFIG_DIR"
    
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF
    
    if rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] 远程$REMOTE_NAME配置成功${NC}"
    else
        echo -e "${RED}远程$REMOTE_NAME连接失败！${NC}"
        rclone lsd "$REMOTE_NAME:"
        exit 1
    fi
}

# 准备挂载点
prepare_mount_point() {
    echo -e "${YELLOW}[4/9] 准备挂载点$MOUNT_POINT...${NC}"
    
    if ! id "user" &>/dev/null; then
        useradd -m -s /bin/false user
        echo -e "${YELLOW}已创建用户user${NC}"
    fi
    
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    
    if ! grep -q "user_allow_other" /etc/fuse.conf; then
        echo "user_allow_other" >> /etc/fuse.conf
    fi
    
    echo -e "${GREEN}[✓] 挂载点准备完成${NC}"
}

# 配置自动挂载服务
create_systemd_service() {
    echo -e "${YELLOW}[5/9] 创建自动挂载服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    
    cat > "$SERVICE_FILE" << EOF
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
    
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${YELLOW}服务状态异常：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:"
    fi
}

# 验证挂载
verify_mount() {
    echo -e "${YELLOW}[6/9] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "挂载内容示例："
        sudo -u user ls -l "$MOUNT_POINT" | head -n3
    else
        echo -e "${RED}挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 验证开机自启
verify_autostart() {
    echo -e "${YELLOW}[7/9] 验证开机自启...${NC}"
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 已设置开机自启${NC}"
    else
        echo -e "${YELLOW}修复开机自启配置...${NC}"
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

# 优化系统参数
optimize_system() {
    echo -e "${YELLOW}[8/9] 优化系统参数...${NC}"
    
    if ! grep -q "user hard nofile 65535" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << EOF
user hard nofile 65535
user soft nofile 65535
EOF
    fi
    
    if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf << EOF
vm.max_map_count=262144
vm.swappiness=10
net.core.rmem_max=2500000
EOF
        sysctl -p >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}[✓] 系统参数优化完成${NC}"
}

# 输出使用说明
show_usage() {
    echo -e "\n${GREEN}===== 配置完成！=====${NC}"
    echo -e "1. 远程名称：$REMOTE_NAME"
    echo -e "2. 挂载目录：$MOUNT_POINT"
    echo -e "3. 服务管理："
    echo -e "   - 状态：systemctl status $SERVICE_NAME"
    echo -e "   - 重启：systemctl restart $SERVICE_NAME"
    echo -e "4. 日志路径：$LOG_FILE"
}

# 主流程（彻底修复引号错误）
main() {
    echo -e "${GREEN}===== Rclone WebDAV 一键安装配置工具 ====="${NC}
    check_root
    install_deps
    install_rclone
    configure_remote
    prepare_mount_point
    create_systemd_service
    verify_mount
    verify_autostart
    optimize_system
    show_usage
    echo -e "\n${GREEN}===== 操作完成！=====${NC}"
}

main
