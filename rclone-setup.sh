#!/bin/bash
# Rclone WebDAV 全自动配置脚本（修复版）
# 功能：安装Rclone + 配置WebDAV + 自动挂载 + 解决所有已知错误

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 核心配置（根据需求修改）
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
SERVICE_NAME="rclone-webdav.service"
LOG_FILE="/var/log/rclone.log"  # 统一日志路径，方便排查

# ==============================================
# 前置检查与依赖修复
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 强制安装fuse3（解决fusermount3缺失）
install_fuse3() {
    echo -e "${YELLOW}[1/8] 安装fuse3依赖...${NC}"
    # 检测系统并安装
    if [ -f /etc/debian_version ]; then
        # Ubuntu/Debian
        apt-get update -y >/dev/null 2>&1
        apt-get install -y fuse3 --reinstall -f >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum install -y fuse3 --refresh -y >/dev/null 2>&1
    else
        # 未知系统：手动编译
        echo -e "${YELLOW}未知系统，手动编译fuse3...${NC}"
        apt-get install -y gcc make pkg-config libglib2.0-dev 2>/dev/null || \
        yum install -y gcc make pkgconfig glib2-devel 2>/dev/null
        wget https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.xz -q
        tar xf fuse-3.16.2.tar.xz >/dev/null 2>&1
        (cd fuse-3.16.2 && ./configure --prefix=/usr >/dev/null 2>&1 && make >/dev/null 2>&1 && make install >/dev/null 2>&1)
        rm -rf fuse-3.16.2*
        ln -s /usr/bin/fusermount3 /usr/bin/fusermount 2>/dev/null
    fi

    # 验证
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3安装成功${NC}"
    else
        echo -e "${RED}[×] fuse3安装失败，挂载无法进行！${NC}"
        exit 1
    fi
}

# 安装Rclone
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
# 核心配置与修复
# ==============================================
# 准备用户与目录
prepare_env() {
    echo -e "${YELLOW}[3/8] 准备环境...${NC}"
    # 创建user用户（若不存在）
    if ! id "user" &>/dev/null; then
        useradd -m user
        echo -e "${YELLOW}已创建用户user${NC}"
    fi
    # 创建挂载点
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"
    # 启用fuse普通用户挂载权限
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 环境准备完成${NC}"
}

# 配置WebDAV（修正vendor为other）
configure_webdav() {
    echo -e "${YELLOW}[4/8] 配置WebDAV...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    chown -R user:user "$CONFIG_DIR"

    # 生成配置文件（关键：vendor=other）
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other  # 通用类型，避免Unknown vendor警告
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF
    chown user:user "$CONFIG_DIR/rclone.conf"
    chmod 600 "$CONFIG_DIR/rclone.conf"

    # 测试WebDAV连接
    echo -e "${YELLOW}测试WebDAV连接...${NC}"
    if sudo -u user rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] WebDAV连接成功${NC}"
    else
        echo -e "${RED}[×] WebDAV连接失败！错误详情：${NC}"
        sudo -u user rclone lsd "$REMOTE_NAME:"  # 显示具体错误
        exit 1
    fi
}

# ==============================================
# 服务创建与挂载验证
# ==============================================
# 创建系统服务
create_service() {
    echo -e "${YELLOW}[5/8] 创建系统服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone WebDAV mount ($REMOTE_NAME)
After=network-online.target

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode full \
  --log-level INFO \
  --log-file $LOG_FILE
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${RED}[×] 服务启动失败！状态：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:"
        exit 1
    fi
}

# 验证挂载
verify_mount() {
    echo -e "${YELLOW}[6/8] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "目录权限：$(ls -ld "$MOUNT_POINT")"
    else
        echo -e "${RED}[×] 挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 检查日志中是否有残留警告
check_logs() {
    echo -e "${YELLOW}[7/8] 检查日志警告...${NC}"
    if grep -q "Unknown vendor" "$LOG_FILE"; then
        echo -e "${YELLOW}[!] 日志中仍有vendor警告，但不影响使用${NC}"
    else
        echo -e "${GREEN}[✓] 日志无异常警告${NC}"
    fi
}

# ==============================================
# 主流程
# ==============================================
main() {
    echo -e "${GREEN}===== Rclone WebDAV 修复版配置工具 ====="${NC}
    check_root
    install_fuse3
    install_rclone
    prepare_env
    configure_webdav
    create_service
    verify_mount
    check_logs

    echo -e "\n${GREEN}===== 所有配置完成！=====${NC}"
    echo -e "1. 挂载目录：$MOUNT_POINT"
    echo -e "2. 服务管理："
    echo -e "   - 重启：sudo systemctl restart $SERVICE_NAME"
    echo -e "   - 状态：sudo systemctl status $SERVICE_NAME"
    echo -e "3. 日志文件：$LOG_FILE"
}

main
