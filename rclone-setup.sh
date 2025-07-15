#!/bin/bash
# 修复版：解决日志无输出和挂载失败问题
# 配置信息：名称test，URL=http://yy.19885172.xyz:19798/dav，挂载到/home/user/rclone

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 核心配置（根据你的需求）
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
VENDOR="webdav"
USERNAME="root"
PASSWORD="password"
MOUNT_POINT="/home/user/rclone"
# 日志路径修改为user有权限的目录（避免/var/log权限问题）
LOG_FILE="/home/user/.cache/rclone/rclone-test.log"
SYSTEMD_SERVICE="rclone-webdav.service"

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
    exit 1
fi

# 确保user用户存在并创建必要目录
prepare_user() {
    if ! id "user" &>/dev/null; then
        echo -e "${YELLOW}创建用户user...${NC}"
        useradd -m user  # -m自动创建/home/user
    fi
    # 创建日志目录（user有权限）
    mkdir -p "$(dirname $LOG_FILE)"
    chown -R user:user "$(dirname $LOG_FILE)"
}

# 安装Rclone并检查
install_rclone() {
    echo -e "${YELLOW}[1/6] 安装Rclone...${NC}"
    if ! command -v rclone &>/dev/null; then
        # 安装依赖
        if [ -f /etc/debian_version ]; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y curl fuse >/dev/null 2>&1
        elif [ -f /etc/redhat-release ]; then
            yum install -y curl fuse >/dev/null 2>&1
        else
            echo -e "${RED}不支持的系统！仅支持Ubuntu/Debian/CentOS${NC}"
            exit 1
        fi
        # 安装Rclone
        curl https://rclone.org/install.sh | bash >/dev/null 2>&1
    fi
    if ! command -v rclone &>/dev/null; then
        echo -e "${RED}Rclone安装失败！${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] Rclone已安装${NC}"
}

# 配置WebDAV并测试连接
configure_webdav() {
    echo -e "${YELLOW}[2/6] 配置WebDAV远程...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    chown -R user:user "$CONFIG_DIR"

    # 加密密码并生成配置文件
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
    chmod 600 "$CONFIG_DIR/rclone.conf"

    # 测试WebDAV连接（关键检查）
    echo -e "${YELLOW}测试WebDAV连接...${NC}"
    if ! sudo -u user rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${RED}WebDAV连接失败！请检查URL、账号密码是否正确${NC}"
        echo -e "${YELLOW}错误详情：${NC}"
        sudo -u user rclone lsd "$REMOTE_NAME:"  # 显示具体错误
        exit 1
    fi
    echo -e "${GREEN}[✓] WebDAV配置正确，连接成功${NC}"
}

# 准备挂载点
prepare_mount_point() {
    echo -e "${YELLOW}[3/6] 准备挂载点$MOUNT_POINT...${NC}"
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"
    # 确保fuse允许普通用户挂载（关键配置）
    if grep -q "^#user_allow_other" /etc/fuse.conf; then
        sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
        echo -e "${YELLOW}已启用fuse普通用户挂载权限${NC}"
    fi
    echo -e "${GREEN}[✓] 挂载点准备完成${NC}"
}

# 手动测试挂载（排查服务启动问题）
test_mount() {
    echo -e "${YELLOW}[4/6] 手动测试挂载...${NC}"
    # 先卸载可能存在的挂载
    fusermount -u "$MOUNT_POINT" >/dev/null 2>&1
    # 用user用户手动挂载，输出详细日志
    if ! sudo -u user rclone mount \
        "$REMOTE_NAME:" "$MOUNT_POINT" \
        --allow-other \
        --vfs-cache-mode full \
        --log-level DEBUG \
        --log-file "$LOG_FILE" \
        --daemon; then
        echo -e "${RED}手动挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
    # 检查是否挂载成功
    if mount | grep -q "$MOUNT_POINT"; then
        fusermount -u "$MOUNT_POINT"  # 临时卸载，留给systemd管理
        echo -e "${GREEN}[✓] 手动挂载测试成功${NC}"
    else
        echo -e "${RED}手动挂载测试失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 配置systemd服务
setup_systemd() {
    echo -e "${YELLOW}[5/6] 配置系统服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SYSTEMD_SERVICE"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone WebDAV mount (test)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/rclone mount \
  "$REMOTE_NAME:" "$MOUNT_POINT" \
  --allow-other \
  --vfs-cache-mode full \
  --buffer-size 64M \
  --vfs-read-chunk-size 128M \
  --log-level INFO \
  --log-file "$LOG_FILE"
ExecStop=/usr/bin/fusermount -u "$MOUNT_POINT"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now "$SYSTEMD_SERVICE" >/dev/null 2>&1

    # 检查服务状态
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        echo -e "${GREEN}[✓] 系统服务启动成功${NC}"
    else
        echo -e "${RED}服务启动失败！查看状态：systemctl status $SYSTEMD_SERVICE${NC}"
        exit 1
    fi
}

# 最终验证
verify_final() {
    echo -e "${YELLOW}[5/6] 验证最终挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "${YELLOW}挂载信息：${NC}"
        mount | grep "$MOUNT_POINT"
    else
        echo -e "${RED}最终挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== Rclone WebDAV自动化配置（修复版）=====${NC}"
    prepare_user
    install_rclone
    configure_webdav
    prepare_mount_point
    test_mount  # 关键步骤：提前发现挂载问题
    setup_systemd
    verify_final
    echo -e "${GREEN}===== 全部完成！=====${NC}"
    echo -e "挂载目录：$MOUNT_POINT"
    echo -e "日志文件：$LOG_FILE"
    echo -e "服务管理："
    echo -e "  状态：sudo systemctl status $SYSTEMD_SERVICE"
    echo -e "  重启：sudo systemctl restart $SYSTEMD_SERVICE"
}

main
