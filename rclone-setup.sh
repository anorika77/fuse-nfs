#!/bin/bash
# Rclone 终极修复脚本：解决日志缺失、服务启动失败、权限错误等所有问题
# 配置信息：远程名称test，URL=http://yy.19885172.xyz:19798/dav，挂载到/home/user/rclone

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 核心配置
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
WEBDAV_USER="root"
WEBDAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
SERVICE_NAME="rclone-webdav.service"
LOG_FILE="/var/log/rclone.log"  # 强制生成日志文件

# ==============================================
# 阶段1：基础环境修复（确保日志可生成）
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 强制创建日志文件并授权（解决日志缺失）
fix_log_file() {
    echo -e "${YELLOW}[1/8] 修复日志文件...${NC}"
    # 确保日志文件存在且user用户可写
    sudo touch "$LOG_FILE"
    sudo chown user:user "$LOG_FILE"  # 服务以user身份运行，需赋予权限
    sudo chmod 644 "$LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}[✓] 日志文件$LOG_FILE准备完成${NC}"
    else
        echo -e "${RED}无法创建日志文件！请检查目录权限${NC}"
        exit 1
    fi
}

# 修复fuse3依赖（含fusermount3）
install_fuse3() {
    echo -e "${YELLOW}[2/8] 修复fuse3依赖...${NC}"
    # 卸载旧版本避免冲突
    sudo apt-get purge -y fuse fuse3 2>/dev/null || sudo yum remove -y fuse fuse3 2>/dev/null
    # 重新安装
    if [ -f /etc/debian_version ]; then
        sudo apt-get update -y >/dev/null 2>&1
        sudo apt-get install -y fuse3 --reinstall -f >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y epel-release >/dev/null 2>&1
        sudo yum install -y fuse3 --refresh >/dev/null 2>&1
    else
        # 源码编译（通用方案）
        sudo apt-get install -y gcc make pkg-config libglib2.0-dev 2>/dev/null || \
        sudo yum install -y gcc make pkgconfig glib2-devel 2>/dev/null
        wget https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.xz -q
        tar xf fuse-3.16.2.tar.xz >/dev/null 2>&1
        (cd fuse-3.16.2 && ./configure --prefix=/usr >/dev/null 2>&1 && make >/dev/null 2>&1 && sudo make install >/dev/null 2>&1)
        rm -rf fuse-3.16.2*
        sudo ln -s /usr/bin/fusermount3 /usr/bin/fusermount 2>/dev/null
    fi
    # 验证
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3修复成功${NC}"
    else
        echo -e "${RED}fusermount3仍缺失！${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段2：Rclone安装与环境准备
# ==============================================
# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[3/8] 安装Rclone...${NC}"
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | sudo bash >/dev/null 2>&1
    fi
    if command -v rclone &>/dev/null; then
        echo -e "${GREEN}[✓] Rclone已安装（版本：$(rclone --version | head -n1 | awk '{print $2}')）${NC}"
    else
        echo -e "${RED}Rclone安装失败！${NC}"
        exit 1
    fi
}

# 准备用户与挂载点（解决权限/非空问题）
prepare_env() {
    echo -e "${YELLOW}[4/8] 准备环境...${NC}"
    # 创建user用户
    if ! id "user" &>/dev/null; then
        sudo useradd -m user
        echo -e "${YELLOW}已创建用户user${NC}"
    fi
    # 清空并创建挂载点（确保为空目录）
    sudo mkdir -p "$MOUNT_POINT"
    sudo rm -rf "$MOUNT_POINT"/*  # 强制清空，避免非空挂载失败
    sudo chown -R user:user "$MOUNT_POINT"
    # 启用fuse权限
    sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 环境准备完成${NC}"
}

# ==============================================
# 阶段3：WebDAV配置与连接测试
# ==============================================
# 配置WebDAV（修正vendor）
configure_webdav() {
    echo -e "${YELLOW}[5/8] 配置WebDAV...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    sudo mkdir -p "$CONFIG_DIR"
    sudo chown -R user:user "$CONFIG_DIR"

    # 生成正确配置
    OBSCURED_PASS=$(echo "$WEBDAV_PASS" | rclone obscure -)
    sudo bash -c "cat > $CONFIG_DIR/rclone.conf << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $OBSCURED_PASS
EOF"
    sudo chown user:user "$CONFIG_DIR/rclone.conf"
    sudo chmod 600 "$CONFIG_DIR/rclone.conf"

    # 强制测试连接（提前暴露错误）
    echo -e "${YELLOW}测试WebDAV连接...${NC}"
    if ! sudo -u user rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${RED}WebDAV连接失败！错误详情：${NC}"
        sudo -u user rclone lsd "$REMOTE_NAME:"  # 显示具体错误（URL/密码问题）
        exit 1
    fi
    echo -e "${GREEN}[✓] WebDAV连接成功${NC}"
}

# ==============================================
# 阶段4：服务修复与手动调试
# ==============================================
# 重建服务文件
recreate_service() {
    echo -e "${YELLOW}[6/8] 重建服务文件...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    sudo bash -c "cat > $SERVICE_FILE << EOF
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
  --log-level DEBUG \  # 输出详细日志
  --log-file $LOG_FILE
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload
    echo -e "${GREEN}[✓] 服务文件重建完成${NC}"
}

# 手动调试挂载（强制生成日志）
manual_mount_test() {
    echo -e "${YELLOW}[7/8] 手动测试挂载...${NC}"
    # 先卸载
    sudo fusermount3 -u "$MOUNT_POINT" 2>/dev/null
    # 手动执行挂载命令（与服务一致）
    echo -e "${YELLOW}执行挂载命令（输出将写入日志）...${NC}"
    if sudo -u user rclone mount "$REMOTE_NAME:" "$MOUNT_POINT" \
        --allow-other \
        --vfs-cache-mode full \
        --log-level DEBUG \
        --log-file "$LOG_FILE" \
        --daemon; then
        sleep 2
        if mount | grep -q "$MOUNT_POINT"; then
            echo -e "${GREEN}[✓] 手动挂载成功${NC}"
        else
            echo -e "${RED}手动挂载失败！查看日志：$LOG_FILE${NC}"
            exit 1
        fi
    else
        echo -e "${RED}手动挂载命令执行失败！日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# ==============================================
# 阶段5：最终验证与服务启动
# ==============================================
# 启动服务并验证
start_service() {
    echo -e "${YELLOW}[8/8] 启动服务并验证...${NC}"
    # 停止手动挂载的进程
    sudo pkill -f "rclone mount $REMOTE_NAME:" >/dev/null 2>&1
    sleep 1
    # 启动服务
    sudo systemctl start "$SERVICE_NAME"
    sleep 2

    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${YELLOW}服务状态异常，查看日志：$LOG_FILE${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 10 "Active:"
    fi

    # 最终挂载验证
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}===== 所有修复完成！成功挂载到$MOUNT_POINT ====="${NC}
        echo -e "服务管理：sudo systemctl restart $SERVICE_NAME"
        echo -e "日志路径：$LOG_FILE"
    else
        echo -e "${RED}===== 仍挂载失败！查看日志：$LOG_FILE ====="${NC}
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== Rclone 终极修复脚本 ====="${NC}
    check_root
    fix_log_file  # 优先确保日志可生成
    install_fuse3
    install_rclone
    prepare_env
    configure_webdav
    recreate_service
    manual_mount_test  # 关键：手动测试生成日志
    start_service
}

main
