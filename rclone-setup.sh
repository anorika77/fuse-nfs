#!/bin/bash
# 修正Rclone WebDAV的vendor配置，消除"Unknown vendor"警告

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数
REMOTE_NAME="test"
CONFIG_PATH="/home/user/.config/rclone/rclone.conf"
SERVICE_NAME="rclone-webdav.service"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${RED}配置文件不存在：$CONFIG_PATH${NC}"
    exit 1
fi

# 修正vendor为"other"（通用类型）
fix_vendor() {
    echo -e "${YELLOW}[1/3] 修正vendor配置...${NC}"
    # 直接替换配置文件中的vendor值
    sed -i "s/vendor = webdav/vendor = other/" "$CONFIG_PATH"
    # 确保配置文件权限正确（user用户可访问）
    chown user:user "$CONFIG_PATH"
    chmod 600 "$CONFIG_PATH"
    
    # 验证修正结果
    if grep -q "vendor = other" "$CONFIG_PATH"; then
        echo -e "${GREEN}[✓] 配置已修正，vendor设置为other${NC}"
    else
        echo -e "${RED}[×] 配置修正失败，请手动编辑$CONFIG_PATH${NC}"
        exit 1
    fi
}

# 重启Rclone服务
restart_service() {
    echo -e "${YELLOW}[2/3] 重启Rclone服务...${NC}"
    # 停止残留进程
    pkill -f "rclone mount" >/dev/null 2>&1
    # 重启服务
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务重启成功${NC}"
    else
        echo -e "${YELLOW}[!] 服务状态异常，查看详情：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:"
    fi
}

# 验证警告是否消除
verify_warning() {
    echo -e "${YELLOW}[3/3] 验证警告是否消除...${NC}"
    # 查看最新日志（过滤vendor相关信息）
    LOG_FILE="/home/user/.cache/rclone/rclone-test.log"
    if grep -q "Unknown vendor " "$LOG_FILE"; then
        echo -e "${YELLOW}[!] 仍存在警告，查看完整日志：${NC}"
        grep "vendor" "$LOG_FILE"  # 显示相关日志
    else
        echo -e "${GREEN}[✓] 警告已消除，配置正常${NC}"
        # 检查挂载状态
        if mount | grep -q "/home/user/rclone"; then
            echo -e "挂载成功：/home/user/rclone"
        fi
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 修复WebDAV vendor警告 ====="${NC}
    fix_vendor
    restart_service
    verify_warning
    echo -e "${GREEN}===== 操作完成 ====="${NC}
}

main
