#!/bin/bash
# 最终版：Rclone WebDAV 一键启动与修复脚本
# 功能：解决服务启动失败、挂载异常、进程冲突等所有问题

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
LOG_FILE="/var/log/rclone.log"

# ==============================================
# 前置检查与环境修复
# ==============================================
# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
        exit 1
    fi
}

# 修复日志文件权限
fix_log() {
    echo -e "${YELLOW}[1/9] 准备日志文件...${NC}"
    sudo touch "$LOG_FILE"
    sudo chown user:user "$LOG_FILE"
    echo -e "${GREEN}[✓] 日志文件就绪${NC}"
}

# 安装fuse3依赖
install_fuse() {
    echo -e "${YELLOW}[2/9] 确保fuse3依赖...${NC}"
    if ! command -v fusermount3 &>/dev/null; then
        if [ -f /etc/debian_version ]; then
            sudo apt-get install -y fuse3 >/dev/null 2>&1
        else
            sudo yum install -y fuse3 >/dev/null 2>&1
        fi
    fi
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3正常${NC}"
    else
        echo -e "${RED}fuse3缺失，无法挂载！${NC}"
        exit 1
    fi
}

# ==============================================
# Rclone安装与环境准备
# ==============================================
# 安装Rclone
install_rclone() {
    echo -e "${YELLOW}[3/9] 确保Rclone安装...${NC}"
    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh | sudo bash >/dev/null 2>&1
    fi
    echo -e "${GREEN}[✓] Rclone已安装${NC}"
}

# 准备用户与挂载点
prepare_env() {
    echo -e "${YELLOW}[4/9] 准备环境...${NC}"
    # 创建user用户
    if ! id "user" &>/dev/null; then
        sudo useradd -m user
    fi
    # 清理并创建挂载点
    sudo mkdir -p "$MOUNT_POINT"
    sudo rm -rf "$MOUNT_POINT"/*
    sudo chown -R user:user "$MOUNT_POINT"
    # 启用fuse权限
    sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null
    echo -e "${GREEN}[✓] 环境就绪${NC}"
}

# 配置WebDAV
configure_webdav() {
    echo -e "${YELLOW}[5/9] 配置WebDAV...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    sudo mkdir -p "$CONFIG_DIR"
    sudo chown -R user:user "$CONFIG_DIR"

    # 生成配置
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
    # 测试连接
    if sudo -u user rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] WebDAV配置正确${NC}"
    else
        echo -e "${RED}WebDAV连接失败！${NC}"
        exit 1
    fi
}

# ==============================================
# 服务配置修复（核心）
# ==============================================
# 修复服务配置（解决启动失败）
fix_service() {
    echo -e "${YELLOW}[6/9] 修复服务配置...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    sudo bash -c "cat > $SERVICE_FILE << EOF
[Unit]
Description=Rclone WebDAV mount ($REMOTE_NAME)
After=network-online.target

[Service]
Type=simple  # 关键：使用simple类型，避免进程冲突
User=user
Group=user
# 移除--daemon，让systemd管理前台进程
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode full \
  --log-level INFO \
  --log-file $LOG_FILE
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure  # 失败时重启
RestartSec=10  # 延长重启间隔，避免systemd限制
TimeoutStartSec=60  # 延长启动超时

[Install]
WantedBy=multi-user.target
EOF"
    echo -e "${GREEN}[✓] 服务配置修复完成${NC}"
}

# ==============================================
# 启动与验证
# ==============================================
# 清理残留进程并启动服务
start_service() {
    echo -e "${YELLOW}[7/9] 启动服务...${NC}"
    # 清理旧进程
    sudo pkill -f "rclone mount $REMOTE_NAME:" >/dev/null 2>&1
    # 重置失败记录
    sudo systemctl reset-failed "$SERVICE_NAME"
    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl start "$SERVICE_NAME"
    sleep 5  # 等待启动

    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${YELLOW}服务状态异常，继续验证实际挂载${NC}"
    fi
}

# 验证挂载
verify_mount() {
    echo -e "${YELLOW}[8/9] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "挂载内容示例："
        ls -l "$MOUNT_POINT" | head -n3  # 显示前3项
    else
        echo -e "${RED}挂载失败！日志：$LOG_FILE${NC}"
        exit 1
    fi
}

# 最终信息
final_info() {
    echo -e "\n${GREEN}===== 一键启动完成！=====${NC}"
    echo -e "1. 挂载目录：$MOUNT_POINT"
    echo -e "2. 服务管理："
    echo -e "   - 状态：sudo systemctl status $SERVICE_NAME"
    echo -e "   - 重启：sudo systemctl restart $SERVICE_NAME"
    echo -e "3. 日志：$LOG_FILE"
}

# 主流程
main() {
    echo -e "${GREEN}===== Rclone WebDAV 一键启动脚本 ====="${NC}
    check_root
    fix_log
    install_fuse
    install_rclone
    prepare_env
    configure_webdav
    fix_service
    start_service
    verify_mount
    final_info
}

main
