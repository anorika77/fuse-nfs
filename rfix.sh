#!/bin/bash
# 修复Rclone服务用户不存在问题（status=217/USER）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数
USER_NAME="user"
MOUNT_POINT="/home/user/rclone"
SERVICE_NAME="rclone-autmount.service"
REMOTE_NAME="test"

# 步骤1：强制创建并验证user用户
fix_user() {
    echo -e "${YELLOW}[1/4] 验证并创建用户$USER_NAME...${NC}"
    # 彻底删除残留的无效用户（若存在）
    if id "$USER_NAME" &>/dev/null; then
        userdel -r "$USER_NAME" >/dev/null 2>&1  # 递归删除用户及目录
    fi
    # 重新创建用户（确保/home/user目录生成）
    useradd -m "$USER_NAME" >/dev/null 2>&1
    # 验证用户是否存在
    if id "$USER_NAME" &>/dev/null; then
        echo -e "${GREEN}[✓] 用户$USER_NAME创建成功（UID: $(id -u "$USER_NAME")）${NC}"
    else
        echo -e "${RED}用户$USER_NAME创建失败！请手动执行：useradd -m $USER_NAME${NC}"
        exit 1
    fi
}

# 步骤2：修复挂载点权限
fix_mount_perms() {
    echo -e "${YELLOW}[2/4] 修复挂载点权限...${NC}"
    mkdir -p "$MOUNT_POINT"
    # 确保挂载点归user用户所有
    chown -R "$USER_NAME:$USER_NAME" "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    echo -e "${GREEN}[✓] 挂载点$MOUNT_POINT权限修复完成${NC}"
}

# 步骤3：修正服务配置（确保用户正确）
fix_service_user() {
    echo -e "${YELLOW}[3/4] 修正服务用户配置...${NC}"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    # 确保服务中User字段正确
    sed -i "s/^User=.*/User=$USER_NAME/" "$SERVICE_FILE"
    sed -i "s/^Group=.*/Group=$USER_NAME/" "$SERVICE_FILE"
    # 重新加载配置
    systemctl daemon-reload
    echo -e "${GREEN}[✓] 服务用户配置修正完成${NC}"
}

# 步骤4：重启服务并验证
restart_verify() {
    echo -e "${YELLOW}[4/4] 重启服务并验证...${NC}"
    # 清理残留进程
    pkill -f "rclone mount $REMOTE_NAME:" >/dev/null 2>&1
    # 重置失败记录
    systemctl reset-failed "$SERVICE_NAME"
    # 启动服务
    systemctl start "$SERVICE_NAME"
    sleep 3

    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
        # 验证挂载
        if mount | grep -q "$MOUNT_POINT"; then
            echo -e "挂载成功：$MOUNT_POINT"
        else
            echo -e "${YELLOW}服务启动成功，但挂载未生效，查看日志：/var/log/rclone_mount.log${NC}"
        fi
    else
        echo -e "${RED}服务仍启动失败！状态详情：${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | grep -A 10 "Active:"
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 修复服务用户不存在问题 ====="${NC}
    fix_user  # 核心：确保user用户存在
    fix_mount_perms
    fix_service_user
    restart_verify
    echo -e "${GREEN}===== 操作完成 ====="${NC}
}

main
