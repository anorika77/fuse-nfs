#!/bin/bash
# 分步排查第4/9步骤卡死问题

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

MOUNT_POINT="/home/user/rclone"
USER_NAME="user"

# 分步执行第4/9步骤
step_4_1() {
    echo -e "${YELLOW}[4/9 分步1/4] 检查并创建用户$USER_NAME...${NC}"
    # 超时5秒执行，避免卡死
    if ! timeout 5 id "$USER_NAME" &>/dev/null; then
        echo -e "${YELLOW}用户$USER_NAME不存在，开始创建...${NC}"
        # 创建用户，超时10秒
        if ! timeout 10 useradd -m -s /bin/false "$USER_NAME" &>/dev/null; then
            echo -e "${RED}[错误] 创建用户$USER_NAME失败！可能权限或系统限制${NC}"
            echo -e "${YELLOW}手动创建用户：sudo useradd -m -s /bin/false $USER_NAME${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}[4/9 分步1/4 完成] 用户$USER_NAME已就绪${NC}"
}

step_4_2() {
    echo -e "${YELLOW}[4/9 分步2/4] 创建挂载点$MOUNT_POINT...${NC}"
    # 创建目录，超时10秒
    if ! timeout 10 mkdir -p "$MOUNT_POINT" &>/dev/null; then
        echo -e "${RED}[错误] 创建挂载点失败！检查目录权限或磁盘状态${NC}"
        echo -e "${YELLOW}手动创建：sudo mkdir -p $MOUNT_POINT${NC}"
        exit 1
    fi
    echo -e "${GREEN}[4/9 分步2/4 完成] 挂载点目录已创建${NC}"
}

step_4_3() {
    echo -e "${YELLOW}[4/9 分步3/4] 设置挂载点权限...${NC}"
    # 设置权限，超时10秒（处理大目录可能较慢）
    if ! timeout 10 chown -R "$USER_NAME:$USER_NAME" "$MOUNT_POINT" &>/dev/null; then
        echo -e "${RED}[错误] 设置权限失败！可能目录被占用${NC}"
        echo -e "${YELLOW}手动设置：sudo chown -R $USER_NAME:$USER_NAME $MOUNT_POINT${NC}"
        exit 1
    fi
    echo -e "${GREEN}[4/9 分步3/4 完成] 权限设置成功${NC}"
}

step_4_4() {
    echo -e "${YELLOW}[4/9 分步4/4] 配置fuse权限...${NC}"
    # 检查并修改/etc/fuse.conf，超时10秒
    if ! grep -q "user_allow_other" /etc/fuse.conf; then
        if ! timeout 10 echo "user_allow_other" >> /etc/fuse.conf; then
            echo -e "${RED}[错误] 修改/etc/fuse.conf失败！可能文件只读或被锁定${NC}"
            echo -e "${YELLOW}手动添加：echo 'user_allow_other' | sudo tee -a /etc/fuse.conf${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}[4/9 分步4/4 完成] fuse配置成功${NC}"
}

# 执行分步排查
echo -e "${YELLOW}=== 开始分步执行第4/9步骤（排查卡死问题） ===${NC}"
step_4_1
step_4_2
step_4_3
step_4_4
echo -e "${GREEN}=== 第4/9步骤分步执行完成 ===${NC}"
