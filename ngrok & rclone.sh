#!/usr/bin/env bash
# 整合脚本：自动配置ngrok SSH隧道 + rclone WebDAV挂载
# 版本：1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ==============================================
# 配置参数（可根据需求修改）
# ==============================================
# ngrok配置
NGROK_TOKEN="2LOavNAh6AsUHCU6AOZhfVMgx32_6mHSA88CTSMK2E4rb4c8c"  # ngrok token
SSH_ROOT_PASSWORD="Yanchen517200@"                             # SSH root密码

# rclone WebDAV配置
RCLONE_REMOTE_NAME="test"                                       # 远程名称
RCLONE_WEBDAV_URL="http://yy.19885172.xyz:19798/dav"            # WebDAV地址
RCLONE_USER="root"                                              # WebDAV用户名
RCLONE_PASS="password"                                          # WebDAV密码
RCLONE_MOUNT_POINT="/home/user/rclone"                          # 挂载点
RCLONE_SERVICE="rclone-webdav.service"                          # rclone服务名

# ==============================================
# 通用工具函数
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 安装基础依赖（curl、fuse3等共用依赖）
install_common_deps() {
    echo -e "${YELLOW}[1/10] 安装基础依赖...${NC}"
    if [ -f /etc/debian_version ]; then
        # Ubuntu/Debian
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl fuse3 sudo openssh-server >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum install -y curl fuse3 sudo openssh-server >/dev/null 2>&1
    else
        echo -e "${RED}不支持的Linux发行版！${NC}"
        exit 1
    fi

    # 验证关键依赖
    for cmd in curl fuse3 sudo sshd; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}依赖$cmd安装失败！${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}[✓] 基础依赖安装完成${NC}"
}

# ==============================================
# ngrok 相关配置（SSH隧道）
# ==============================================
# 配置SSH服务
configure_ssh() {
    echo -e "${YELLOW}[2/10] 配置SSH服务...${NC}"
    # 设置root密码
    echo "root:$SSH_ROOT_PASSWORD" | chpasswd

    # 允许root登录和密码认证
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd >/dev/null 2>&1

    if systemctl is-active --quiet sshd; then
        echo -e "${GREEN}[✓] SSH服务配置完成${NC}"
    else
        echo -e "${RED}SSH服务启动失败！${NC}"
        exit 1
    fi
}

# 安装并配置ngrok
install_ngrok() {
    echo -e "${YELLOW}[3/10] 安装配置ngrok...${NC}"
    # 下载ngrok客户端
    wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -qO- | tar xz -C /usr/local/bin
    chmod +x /usr/local/bin/ngrok

    # 测试ngrok连接
    TEST_LOG="/tmp/ngrok_test.log"
    ngrok tcp 22 --authtoken="$NGROK_TOKEN" > "$TEST_LOG" 2>&1 &
    TEST_PID=$!
    sleep 3

    # 检查测试结果
    if grep -q "You must add a credit or debit card" "$TEST_LOG"; then
        kill $TEST_PID >/dev/null 2>&1
        echo -e "${RED}ngrok错误：免费账户需绑定信用卡验证！${NC}"
        rm -f "$TEST_LOG"
        # 不退出，继续执行rclone部分
    elif grep -q "failed to start tunnel" "$TEST_LOG"; then
        kill $TEST_PID >/dev/null 2>&1
        echo -e "${RED}ngrok连接失败，检查token是否有效！${NC}"
        rm -f "$TEST_LOG"
    else
        kill $TEST_PID >/dev/null 2>&1
        echo -e "${GREEN}[✓] ngrok测试通过${NC}"
    fi
    rm -f "$TEST_LOG"

    # 后台启动ngrok
    pkill -f "ngrok tcp 22" >/dev/null 2>&1
    nohup ngrok tcp 22 --authtoken="$NGROK_TOKEN" >/var/log/ngrok.log 2>&1 &
    sleep 5
    echo -e "${YELLOW}ngrok已后台运行，日志：/var/log/ngrok.log${NC}"
}

# 获取ngrok隧道信息
get_ngrok_info() {
    echo -e "${YELLOW}[4/10] 获取ngrok隧道信息...${NC}"
    NGROK_PID=$(pgrep -f "ngrok tcp 22")
    if [ -z "$NGROK_PID" ]; then
        echo -e "${RED}ngrok未运行！${NC}"
        return
    fi

    # 获取API端口
    NGROK_API_PORT=$(lsof -p "$NGROK_PID" 2>/dev/null | grep "LISTEN" | grep "localhost:" | awk -F":" '{print $2}' | awk '{print $1}')
    NGROK_API_PORT=${NGROK_API_PORT:-4040}

    # 获取隧道地址
    NGROK_INFO=$(curl -s "http://localhost:$NGROK_API_PORT/api/tunnels")
    NGROK_URL=$(echo "$NGROK_INFO" | grep -oP 'tcp://\K[^"]+')
    if [ -n "$NGROK_URL" ]; then
        NGROK_HOST=$(echo "$NGROK_URL" | cut -d: -f1)
        NGROK_PORT=$(echo "$NGROK_URL" | cut -d: -f2)
        echo -e "${GREEN}[✓] ngrok隧道信息：${NC}"
        echo -e "  SSH地址：$NGROK_HOST"
        echo -e "  SSH端口：$NGROK_PORT"
        echo -e "  连接命令：ssh root@$NGROK_HOST -p $NGROK_PORT"
        echo -e "  密码：$SSH_ROOT_PASSWORD"
    else
        echo -e "${YELLOW}暂未获取到ngrok隧道信息，稍后查看日志：/var/log/ngrok.log${NC}"
    fi
}

# ==============================================
# rclone 相关配置（WebDAV挂载）
# ==============================================
# 安装rclone
install_rclone() {
    echo -e "\n${YELLOW}[5/10] 安装rclone...${NC}"
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | bash >/dev/null 2>&1
    fi
    if command -v rclone &>/dev/null; then
        echo -e "${GREEN}[✓] rclone安装完成（版本：$(rclone --version | head -n1 | awk '{print $2}')）${NC}"
    else
        echo -e "${RED}rclone安装失败！${NC}"
        exit 1
    fi
}

# 配置WebDAV远程
configure_rclone_webdav() {
    echo -e "${YELLOW}[6/10] 配置WebDAV远程...${NC}"
    # 创建user用户（rclone用）
    if ! id "user" &>/dev/null; then
        useradd -m user
    fi

    # 配置文件
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    chown -R user:user "$CONFIG_DIR"

    OBSCURED_PASS=$(echo "$RCLONE_PASS" | rclone obscure -)
    cat > "$CONFIG_DIR/rclone.conf" << EOF
[$RCLONE_REMOTE_NAME]
type = webdav
url = $RCLONE_WEBDAV_URL
vendor = other
user = $RCLONE_USER
pass = $OBSCURED_PASS
EOF
    chown user:user "$CONFIG_DIR/rclone.conf"
    chmod 600 "$CONFIG_DIR/rclone.conf"

    # 测试WebDAV连接
    if ! sudo -u user rclone lsd "$RCLONE_REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${RED}WebDAV连接失败，检查URL/账号密码！${NC}"
        sudo -u user rclone lsd "$RCLONE_REMOTE_NAME:"  # 显示错误
        # 不退出，继续配置
    else
        echo -e "${GREEN}[✓] WebDAV配置完成${NC}"
    fi
}

# 准备rclone挂载点
prepare_rclone_mount() {
    echo -e "${YELLOW}[7/10] 准备rclone挂载点...${NC}"
    mkdir -p "$RCLONE_MOUNT_POINT"
    chown -R user:user "$RCLONE_MOUNT_POINT"

    # 启用fuse权限
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 挂载点$RCLONE_MOUNT_POINT准备完成${NC}"
}

# 创建rclone系统服务
create_rclone_service() {
    echo -e "${YELLOW}[8/10] 创建rclone服务...${NC}"
    SERVICE_FILE="/etc/systemd/system/$RCLONE_SERVICE"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone WebDAV mount ($RCLONE_REMOTE_NAME)
After=network-online.target

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/rclone mount $RCLONE_REMOTE_NAME: $RCLONE_MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode full \
  --log-file /var/log/rclone.log
ExecStop=/usr/bin/fusermount3 -u $RCLONE_MOUNT_POINT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$RCLONE_SERVICE" >/dev/null 2>&1
    sleep 3

    if systemctl is-active --quiet "$RCLONE_SERVICE"; then
        echo -e "${GREEN}[✓] rclone服务启动成功${NC}"
    else
        echo -e "${RED}rclone服务启动失败！${NC}"
        systemctl status "$RCLONE_SERVICE" --no-pager | grep -A 5 "Active:"
    fi
}

# 验证rclone挂载
verify_rclone_mount() {
    echo -e "${YELLOW}[9/10] 验证rclone挂载...${NC}"
    if mount | grep -q "$RCLONE_MOUNT_POINT"; then
        echo -e "${GREEN}[✓] rclone成功挂载到$RCLONE_MOUNT_POINT${NC}"
    else
        echo -e "${YELLOW}rclone挂载未生效，日志：/var/log/rclone.log${NC}"
    fi
}

# ==============================================
# 主流程
# ==============================================
main() {
    echo -e "${GREEN}===== ngrok + rclone 一站式配置工具 ====="${NC}
    check_root
    install_common_deps

    # 配置ngrok部分
    echo -e "\n${GREEN}===== 开始配置ngrok SSH隧道 ====="${NC}
    configure_ssh
    install_ngrok
    get_ngrok_info

    # 配置rclone部分
    echo -e "\n${GREEN}===== 开始配置rclone WebDAV ====="${NC}
    install_rclone
    configure_rclone_webdav
    prepare_rclone_mount
    create_rclone_service
    verify_rclone_mount

    # 最终提示
    echo -e "\n${GREEN}===== 所有配置完成！=====${NC}"
    echo -e "1. ngrok管理："
    echo -e "   - 状态：pgrep -f ngrok || echo '未运行'"
    echo -e "   - 日志：cat /var/log/ngrok.log"
    echo -e "2. rclone管理："
    echo -e "   - 状态：sudo systemctl status $RCLONE_SERVICE"
    echo -e "   - 日志：cat /var/log/rclone.log"
    echo -e "   - 挂载点：$RCLONE_MOUNT_POINT"
}

main
