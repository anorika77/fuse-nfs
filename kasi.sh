#!/bin/bash
# 强制释放目录占用并修复权限

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

MOUNT_POINT="/home/user/rclone"
USER_NAME="user"

# 步骤1：检查并终止占用进程
kill_using_process() {
    echo -e "${YELLOW}[1/3] 终止占用$MOUNT_POINT的进程...${NC}"
    # 查找占用目录的进程
    PIDS=$(lsof "$MOUNT_POINT" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    if [ -n "$PIDS" ]; then
        echo -e "${YELLOW}发现占用进程：$PIDS，正在终止...${NC}"
        kill -9 $PIDS >/dev/null 2>&1
        sleep 2  # 等待进程终止
    else
        echo -e "${GREEN}无占用进程${NC}"
    fi
}

# 步骤2：检查是否为挂载点并卸载
unmount_if_mounted() {
    echo -e "${YELLOW}[2/3] 检查并卸载挂载点...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${YELLOW}$MOUNT_POINT是挂载点，正在卸载...${NC}"
        fusermount3 -u "$MOUNT_POINT" >/dev/null 2>&1
        # 强制卸载（如果普通卸载失败）
        if mount | grep -q "$MOUNT_POINT"; then
            umount -l "$MOUNT_POINT" >/dev/null 2>&1  # 懒卸载
        fi
    fi
    # 验证是否卸载成功
    if ! mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}已确保$MOUNT_POINT未挂载${NC}"
    else
        echo -e "${RED}卸载失败！请手动执行：fusermount3 -u $MOUNT_POINT${NC}"
        exit 1
    fi
}

# 步骤3：重建目录并设置权限
recreate_set_perms() {
    echo -e "${YELLOW}[3/3] 重建目录并设置权限...${NC}"
    # 删除旧目录（确保无残留文件）
    rm -rf "$MOUNT_POINT"
    # 重建目录
    mkdir -p "$MOUNT_POINT"
    # 强制设置权限
    chown -R "$USER_NAME:$USER_NAME" "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    # 验证权限
    if [ "$(stat -c "%U:%G" "$MOUNT_POINT")" = "$USER_NAME:$USER_NAME" ]; then
        echo -e "${GREEN}[✓] 权限设置成功，$MOUNT_POINT归属$USER_NAME${NC}"
    else
        echo -e "${RED}权限设置仍失败！手动执行：${NC}"
        echo -e "sudo chown -R $USER_NAME:$USER_NAME $MOUNT_POINT"
        exit 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 修复挂载点权限卡死问题 ====="${NC}
    kill_using_process
    unmount_if_mounted
    recreate_set_perms
    echo -e "${GREEN}===== 修复完成！可重新执行原脚本 ====="${NC}
}

main
