#!/bin/bash
# 功能：Rclone安装与WebDAV自动挂载（挂载点：/home/user/rclone）
# 适配系统：Ubuntu/Debian/CentOS

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ==============================================
# 配置参数（挂载点：/home/user/rclone）
# ==============================================
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
MOUNT_POINT="/home/user/rclone"  # 最终挂载点
SERVICE_NAME="rclone-autmount.service"
LOG_FILE="/var/log/rclone_mount.log"

# ==============================================
# 阶段1：环境检查与依赖安装
# ==============================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

detect_os() {
    [ -f /etc/debian_version ] && echo "debian" && return
    [ -f /etc/redhat-release ] && echo "rhel" && return
    echo "unknown"
}

install_deps() {
    echo -e "${YELLOW}[1/8] 安装依赖...${NC}"
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

# ==============================================
# 阶段2：安装Rclone
# ==============================================
install_rclone() {
    echo -e "${YELLOW}[2/8] 安装Rclone...${NC}"
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | bash >/dev/null 2>&1
    fi
    if command -v rclone &>/dev/null; then
        echo -e "${GREEN}[✓] Rclone已安装（版本：$(rclone --version | head -n1 | awk '{print $2}')）${NC}"
    else
        echo -e "${RED}Rclone安装失败！${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段3：配置WebDAV远程（名称：test）
# ==============================================
configure_remote() {
    echo -e "${YELLOW}[3/8] 配置WebDAV远程（名称：$REMOTE_NAME）...${NC}"
    CONFIG_DIR="/root/.config/rclone"
    mkdir -p "$CONFIG_DIR"

    # 加密密码并生成配置
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF

    # 测试连接
    if rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] 远程$REMOTE_NAME配置成功${NC}"
    else
        echo -e "${RED}远程$REMOTE_NAME连接失败！${NC}"
        rclone lsd "$REMOTE_NAME:"  # 显示错误详情
        exit 1
    fi
}

# ==============================================
# 阶段4：准备挂载点（/home/user/rclone）
# ==============================================
prepare_mount_point() {
    echo -e "${YELLOW}[4/8] 准备挂载点$MOUNT_POINT...${NC}"
    # 确保user用户存在
    if ! id "user" &>/dev/null; then
        useradd -m user  # 创建用户并生成/home/user目录
        echo -e "${YELLOW}已创建用户user${NC}"
    fi
    # 创建挂载点并设置权限（归user所有）
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"  # 关键：挂载点归属user
    chmod 755 "$MOUNT_POINT"
    # 启用fuse普通用户挂载权限
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 挂载点$MOUNT_POINT准备完成${NC}"
}

# ==============================================
# 阶段5：配置自动挂载服务
# ==============================================
create_systemd_service() {
    echo -e "${YELLOW}[5/8] 创建自动挂载服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone mount for WebDAV ($REMOTE_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=user  # 与挂载点权限匹配
Group=user
ExecStart=/usr/bin/rclone mount \
  --allow-other \
  --vfs-cache-mode full \
  --log-level INFO \
  --log-file $LOG_FILE \
  $REMOTE_NAME: $MOUNT_POINT
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务$SERVICE_NAME启动成功${NC}"
    else
        echo -e "${YELLOW}服务状态异常：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:"
    fi
}

# ==============================================
# 阶段6：验证挂载
# ==============================================
verify_mount() {
    echo -e "${YELLOW}[6/8] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "挂载点权限：$(ls -ld "$MOUNT_POINT")"
        echo -e "挂载内容示例："
        sudo -u user ls -l "$MOUNT_POINT" | head -n3  # 用user用户访问
    else
        echo -e "${RED}挂载失败！日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段7：验证开机自启
# ==============================================
verify_autostart() {
    echo -e "${YELLOW}[7/8] 验证开机自启...${NC}"
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 已设置开机自启${NC}"
    else
        echo -e "${YELLOW}修复开机自启配置...${NC}"
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

# ==============================================
# 阶段8：输出使用说明
# ==============================================
show_usage() {
    echo -e "\n${GREEN}===== 配置完成！=====${NC}"
    echo -e "1. 远程名称：$REMOTE_NAME"
    echo -e "2. 挂载目录：$MOUNT_POINT"
    echo -e "3. 服务管理："
    echo -e "   - 状态：systemctl status $SERVICE_NAME"
    echo -e "   - 重启：systemctl restart $SERVICE_NAME"
    echo -e "4. 日志路径：$LOG_FILE"
    echo -e "5. 访问方式：sudo -u user ls $MOUNT_POINT"
}

# ==============================================
# 主流程
# ==============================================
main() {
    echo -e "${GREEN}===== Rclone 自动挂载工具（挂载点：$MOUNT_POINT）=====${NC}"
    check_root
    install_deps
    install_rclone
    configure_remote
    prepare_mount_point
    create_systemd_service
    verify_mount
    verify_autostart
    show_usage
    echo -e "\n${GREEN}===== 操作完成！=====${NC}"
}

main
