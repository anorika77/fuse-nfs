#!/bin/bash
# 一键修复Rclone WebDAV挂载问题（解决fusermount3缺失及配置错误）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 配置参数
REMOTE_NAME="test"
WEBDAV_URL="http://yy.19885172.xyz:19798/dav"
USERNAME="root"
PASSWORD="password"
MOUNT_POINT="/home/user/rclone"
SYSTEMD_SERVICE="rclone-webdav.service"

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
    exit 1
fi

# 步骤1：修复fusermount3缺失问题
fix_fusermount() {
    echo -e "${YELLOW}[1/4] 修复fusermount3依赖...${NC}"
    
    # 清理旧版本
    if [ -f /etc/debian_version ]; then
        sudo apt-get purge -y fuse fuse3 >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        sudo yum remove -y fuse fuse3 >/dev/null 2>&1
    fi
    
    # 重新安装fuse3
    if [ -f /etc/debian_version ]; then
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y fuse3 --reinstall >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y fuse3 --refresh >/dev/null 2>&1
    else
        # 通用Linux编译安装
        wget -q https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.xz
        tar xf fuse-3.16.2.tar.xz >/dev/null 2>&1
        (cd fuse-3.16.2 && ./configure >/dev/null 2>&1 && make >/dev/null 2>&1 && sudo make install >/dev/null 2>&1)
        rm -rf fuse-3.16.2*
    fi
    
    # 创建软链接确保可访问
    sudo ln -sf /usr/bin/fusermount3 /usr/local/bin/fusermount3 2>/dev/null
    sudo ln -sf /usr/bin/fusermount3 /usr/bin/fusermount 2>/dev/null
    
    # 验证
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fusermount3修复成功${NC}"
    else
        echo -e "${RED}[×] fusermount3仍缺失，请手动检查！${NC}"
        exit 1
    fi
}

# 步骤2：修正WebDAV配置
fix_webdav_config() {
    echo -e "${YELLOW}[2/4] 修正WebDAV配置...${NC}"
    CONFIG_DIR="/home/user/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    
    # 生成正确配置
    OBSCURED_PASS=$(echo "$PASSWORD" | rclone obscure -)
    sudo bash -c "cat > $CONFIG_DIR/rclone.conf << EOF
[$REMOTE_NAME]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $USERNAME
pass = $OBSCURED_PASS
EOF"
    
    # 修复权限
    sudo chown -R user:user "$CONFIG_DIR"
    sudo chmod 600 "$CONFIG_DIR/rclone.conf"
    echo -e "${GREEN}[✓] 配置文件修正完成${NC}"
}

# 步骤3：重启服务
restart_service() {
    echo -e "${YELLOW}[3/4] 重启Rclone服务...${NC}"
    # 清理残留进程
    sudo pkill -f "rclone mount" >/dev/null 2>&1
    # 重启服务
    sudo systemctl daemon-reload
    sudo systemctl restart "$SYSTEMD_SERVICE"
    sleep 2
    # 检查状态
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        echo -e "${GREEN}[✓] 服务启动成功${NC}"
    else
        echo -e "${YELLOW}[!] 服务启动警告，继续验证挂载${NC}"
    fi
}

# 步骤4：验证挂载结果
verify_mount() {
    echo -e "${YELLOW}[4/4] 验证挂载结果...${NC}"
    if mount | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}[✓] 成功挂载到$MOUNT_POINT${NC}"
        echo -e "${YELLOW}测试访问：ls $MOUNT_POINT${NC}"
    else
        echo -e "${RED}[×] 挂载失败！尝试手动挂载查看错误：${NC}"
        echo -e "sudo -u user rclone mount test: $MOUNT_POINT --allow-other --vfs-cache-mode full --log-level DEBUG"
        exit 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}===== 开始Rclone挂载修复 ====="${NC}
    fix_fusermount
    fix_webdav_config
    restart_service
    verify_mount
    echo -e "${GREEN}===== 修复完成！=====${NC}"
}

main
