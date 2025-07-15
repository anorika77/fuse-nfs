#!/bin/bash
# 功能：全自动安装Rclone并配置WebDAV自动挂载（支持开机启动）
# 适配系统：Ubuntu 18.04+/Debian 10+/CentOS 7+/Rocky Linux

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ==============================================
# 配置参数（可根据需求修改）
# ==============================================
REMOTE_NAME="webdav_remote"       # 自定义远程名称
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"  # WebDAV服务器地址
WEBDAV_USER="root"                # 登录用户名
WEBDAV_PASS="password"            # 登录密码
MOUNT_POINT="/mnt/webdav_mount"   # 本地挂载点路径
SERVICE_NAME="rclone-aut mount.service"  # 系统服务名称
LOG_FILE="/var/log/rclone_mount.log"     # 日志文件路径

# ==============================================
# 阶段1：环境检查与依赖安装
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须使用root权限运行（sudo bash $0）${NC}"
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

# 安装核心依赖
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

    # 验证依赖
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
        # 官方安装脚本
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
# 阶段3：配置WebDAV远程
# ==============================================
configure_remote() {
    echo -e "${YELLOW}[3/8] 配置WebDAV远程...${NC}"
    # 创建配置目录
    CONFIG_DIR="/root/.config/rclone"  # 使用root用户配置（避免权限问题）
    mkdir -p "$CONFIG_DIR"

    # 加密密码
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)

    # 生成配置文件
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other  # 通用WebDAV类型
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF

    # 测试远程连接
    if rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] WebDAV远程配置成功${NC}"
    else
        echo -e "${RED}WebDAV连接失败！请检查URL/账号密码${NC}"
        rclone lsd "$REMOTE_NAME:"  # 显示错误详情
        exit 1
    fi
}

# ==============================================
# 阶段4：准备挂载点
# ==============================================
prepare_mount_point() {
    echo -e "${YELLOW}[4/8] 准备挂载点...${NC}"
    # 创建挂载目录
    mkdir -p "$MOUNT_POINT"
    # 设置权限（允许所有用户访问）
    chmod 777 "$MOUNT_POINT"

    # 启用FUSE允许其他用户访问
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 挂载点$MOUNT_POINT准备完成${NC}"
}

# ==============================================
# 阶段5：配置自动挂载服务（systemd）
# ==============================================
create_systemd_service() {
    echo -e "${YELLOW}[5/8] 创建自动挂载服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

    # 生成服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone automatic mount for WebDAV
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount \
  --allow-other \
  --vfs-cache-mode full \
  --buffer-size 64M \
  --log-level INFO \
  --log-file $LOG_FILE \
  $REMOTE_NAME: $MOUNT_POINT
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1

    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 自动挂载服务启动成功${NC}"
    else
        echo -e "${YELLOW}服务启动警告，状态详情：${NC}"
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
        echo -e "挂载内容示例："
        ls -l "$MOUNT_POINT" | head -n3  # 显示前3个文件/目录
    else
        echo -e "${RED}挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段7：设置开机自启验证
# ==============================================
verify_autostart() {
    echo -e "${YELLOW}[7/8] 验证开机自启...${NC}"
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 已设置开机自启${NC}"
    else
        echo -e "${YELLOW}警告：未设置开机自启，正在修复...${NC}"
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

# ==============================================
# 阶段8：输出使用说明
# ==============================================
show_usage() {
    echo -e "\n${GREEN}===== 配置完成！使用说明 =====${NC}"
    echo -e "1. 挂载目录：$MOUNT_POINT"
    echo -e "2. 服务管理命令："
    echo -e "   - 查看状态：systemctl status $SERVICE_NAME"
    echo -e "   - 重启服务：systemctl restart $SERVICE_NAME"
    echo -e "   - 停止服务：systemctl stop $SERVICE_NAME"
    echo -e "3. 日志查看：tail -f $LOG_FILE"
    echo -e "4. 测试文件操作："
    echo -e "   - 新建文件：touch $MOUNT_POINT/test.txt"
    echo -e "   - 查看文件：ls $MOUNT_POINT/test.txt"
}

# ==============================================
# 主流程
# ==============================================
main() {
    echo -e "${GREEN}===== Rclone 安装与自动挂载配置工具 ====="${NC}
    check_root
    install_deps
    install_rclone
    configure_remote
    prepare_mount_point
    create_systemd_service
    verify_mount
    verify_autostart
    show_usage
    echo -e "\n${GREEN}===== 所有操作完成！=====${NC}"
}

main
