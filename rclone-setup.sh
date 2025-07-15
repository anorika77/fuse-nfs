#!/bin/bash
# 重建rclone-webdav.service并修复挂载

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数
REMOTE_NAME="test"
MOUNT_POINT="/home/user/rclone"
SYSTEMD_SERVICE="rclone-webdav.service"
LOG_FILE="/home/user/.cache/rclone/rclone-test.log"

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
    exit 1
fi

# 步骤1：创建systemd服务文件
create_service() {
    echo -e "${YELLOW}[1/4] 重建系统服务文件...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SYSTEMD_SERVICE"
    
    # 生成服务配置
    sudo bash -c "cat > $SERVICE_FILE << EOF
[Unit]
Description=Rclone mount for WebDAV ($REMOTE_NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=user
Group=user
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_POINT \
  --allow-other \
  --vfs-cache-mode full \
  --buffer-size 64M \
  --vfs-read-chunk-size 128M \
  --log-level INFO \
  --log-file $LOG_FILE
ExecStop=/usr/bin/fusermount3 -u $MOUNT_POINT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF"
    
    echo -e "${GREEN}[✓] 服务文件创建完成${NC}"
}

# 步骤2：修复fuse3依赖（再次确认）
fix_fuse() {
    echo -e "${YELLOW}[2/4] 确认fuse3依赖...${NC}"
    if ! command -v fusermount3 &>/dev/null; then
        # 自动安装fuse3
        if [ -f /etc/debian_version ]; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y fuse3 >/dev/null 2>&1
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y fuse3 >/dev/null 2>&1
        else
            echo -e "${RED}不支持的系统，需手动安装fuse3${NC}"
            exit 1
        fi
    fi
    
    # 验证
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3依赖正常${NC}"
    else
        echo -e "${RED}fuse3仍缺失，请手动安装！${NC}"
        exit 1
    fi
}

# 步骤3：重启服务
restart_service() {
    echo -e "${YELLOW}[3/4] 启动服务...${NC}"
    # 清理残留进程
    sudo pkill -f "rclone mount" >/dev/null 2>&1
    # 重新加载并启动
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SYSTEMD_SERVICE"
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${YELLOW}[!] 服务状态异常，查看详情：${NC}"
        systemctl status "$SYSTEMD_SERVICE" --no-pager | grep -A 10 "Active:"
    fi
}

# 步骤4：验证挂载
verify_mount() {
    echo -e "${YELLOW}[4/4] 验证挂载...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "测试命令：ls $MOUNT_POINT"
    else
        echo -e "${RED}[×] 挂载失败！查看日志：${LOG_FILE}${NC}"
        echo -e "手动挂载命令："
        echo -e "sudo -u user rclone mount $REMOTE_NAME: $MOUNT_POINT --allow-other --vfs-cache-mode full --log-level DEBUG"
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 开始重建Rclone服务 ====="${NC}
    create_service
    fix_fuse
    restart_service
    verify_mount
    echo -e "${GREEN}===== 操作完成 ====="${NC}
}

main
