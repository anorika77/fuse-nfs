#!/bin/bash
# 一站式脚本：修复fuse3依赖 + 安装Rclone + 配置WebDAV自动挂载
# 配置信息：远程名称test，URL=http://yy.19885172.xyz:19798/dav，挂载到/home/user/rclone

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数（可根据需求修改）
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
SERVICE_NAME="rclone-webdav.service"
LOG_FILE="/var/log/rclone.log"

# ==============================================
# 阶段1：修复fuse3依赖（核心基础）
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 强制安装fuse3（支持多系统）
install_fuse3() {
    echo -e "${YELLOW}[1/7] 修复fuse3依赖...${NC}"
    # 检测系统类型
    if [ -f /etc/debian_version ]; then
        # Ubuntu/Debian：启用universe仓库（fuse3所在）
        apt-get update -y >/dev/null 2>&1
        apt-get install -y fuse3 --reinstall -f >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL：启用epel仓库
        yum install -y epel-release >/dev/null 2>&1
        yum install -y fuse3 --refresh >/dev/null 2>&1
    else
        # 未知系统：源码编译安装（通用方案）
        echo -e "${YELLOW}未知系统，手动编译fuse3...${NC}"
        # 安装编译依赖
        apt-get install -y gcc make pkg-config libglib2.0-dev 2>/dev/null || \
        yum install -y gcc make pkgconfig glib2-devel 2>/dev/null
        # 下载并编译fuse3
        wget https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.xz -q
        tar xf fuse-3.16.2.tar.xz >/dev/null 2>&1
        (cd fuse-3.16.2 && ./configure --prefix=/usr >/dev/null 2>&1 && make >/dev/null 2>&1 && make install >/dev/null 2>&1)
        rm -rf fuse-3.16.2*
        # 创建软链接确保可调用
        ln -s /usr/bin/fusermount3 /usr/bin/fusermount 2>/dev/null
    fi

    # 验证fusermount3是否存在
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3修复成功${NC}"
    else
        echo -e "${RED}[×] fuse3安装失败，无法挂载！${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段2：安装Rclone并配置WebDAV
# ==============================================
# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[2/7] 安装Rclone...${NC}"
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

# 准备环境（用户、目录）
prepare_env() {
    echo -e "${YELLOW}[3/7] 准备环境...${NC}"
    # 创建user用户（若不存在）
    if ! id "user" &>/dev/null; then
        useradd -m user
        echo -e "${YELLOW}已创建用户user${NC}"
    fi
    # 创建挂载点并设置权限
    mkdir -p "$MOUNT_POINT"
    chown -R user:user "$MOUNT_POINT"
    # 启用fuse普通用户挂载权限
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 环境准备完成${NC}"
}

# 配置WebDAV（修正vendor参数）
configure_webdav() {
    echo -e "${YELLOW}[4/7] 配置WebDAV...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    chown -R user:user "$CONFIG_DIR"

    # 生成配置文件（关键：vendor=other，避免识别警告）
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF
    chown user:user "$CONFIG_DIR/rclone.conf"
    chmod 600 "$CONFIG_DIR/rclone.conf"

    # 测试WebDAV连接（提前排查错误）
    echo -e "${YELLOW}测试WebDAV连接...${NC}"
    if sudo -u user rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] WebDAV连接成功${NC}"
    else
        echo -e "${RED}[×] WebDAV连接失败！错误详情：${NC}"
        sudo -u user rclone lsd "$REMOTE_NAME:"  # 显示具体错误（URL/账号问题）
        exit 1
    fi
}

# ==============================================
# 阶段3：创建服务并验证挂载
# ==============================================
# 创建系统服务（自动挂载）
create_service() {
    echo -e "${YELLOW}[5/7] 创建自动挂载服务...${NC}"
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

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1
    sleep 2

    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${RED}[×] 服务启动失败！状态：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:"
        exit 1
    fi
}

# 验证挂载结果
verify_mount() {
    echo -e "${YELLOW}[6/7] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "目录信息：$(ls -ld "$MOUNT_POINT")"
    else
        echo -e "${RED}[×] 挂载失败！查看日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 最终检查
final_check() {
    echo -e "${YELLOW}[7/7] 最终检查...${NC}"
    echo -e "${GREEN}===== 所有操作完成！=====${NC}"
    echo -e "1. 远程名称：$REMOTE_NAME"
    echo -e "2. WebDAV地址：$WEBDAV_URL"
    echo -e "3. 本地挂载：$MOUNT_POINT"
    echo -e "4. 服务命令："
    echo -e "   - 重启：sudo systemctl restart $SERVICE_NAME"
    echo -e "   - 日志：cat $LOG_FILE"
}

# 主流程
main() {
    echo -e "${GREEN}===== fuse3 + Rclone + WebDAV 一站式配置 ====="${NC}
    check_root
    install_fuse3
    install_rclone
    prepare_env
    configure_webdav
    create_service
    verify_mount
    final_check
}

main
