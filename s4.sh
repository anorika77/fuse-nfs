#!/bin/bash
# rclone一键挂载脚本（终极可视化版）
# 功能：自动配置并挂载WebDAV，带完整过程反馈

# 配置区（用户可修改以下参数）
DAV_NAME="test"
DAV_URL="http://yy.19885172.xyz:19798/dav"
DAV_USER="root"
DAV_PASS="password"
MOUNT_POINT="/home/user/rclone"
LOG_DIR="/home/user/.cache/rclone"
LOG_PATH="$LOG_DIR/rclone_mount.log"
RCLONE_PATH="/usr/local/bin/rclone"

# 样式定义
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
CHECK="✓"
ARROW="→"
INFO="ℹ️"
WARNING="⚠️"
ERROR="✗"

# 进度显示函数
show_step() {
    echo -e "\n${BLUE}${BOLD}${1}${NORMAL}"
    echo -n "${YELLOW}${ARROW} ${2}... ${NORMAL}"
}

show_success() {
    echo -e "${GREEN}${CHECK} ${1}${NORMAL}"
}

show_warning() {
    echo -e "${YELLOW}${WARNING} ${1}${NORMAL}"
}

show_error() {
    echo -e "${RED}${ERROR} ${1}${NORMAL}"
}

# 主流程
echo -e "${BOLD}===== rclone WebDAV一键挂载工具 =====${NORMAL}"
echo -e "${INFO} 目标: 将 ${DAV_NAME} 挂载到 ${MOUNT_POINT}"
echo -e "${INFO} 日志: ${LOG_PATH}\n"

# 1. 权限检查
show_step "步骤1/6" "检查运行权限"
if [ "$(id -u)" -ne 0 ]; then
    show_error "需要root权限运行"
    echo -e "${YELLOW}请使用: sudo ./rclone_setup.sh${NORMAL}"
    exit 1
else
    show_success "已获得root权限"
fi

# 2. 清理旧环境
show_step "步骤2/6" "清理旧挂载状态"
fusermount -u "$MOUNT_POINT" 2>/dev/null
umount -l "$MOUNT_POINT" 2>/dev/null
pkill -f "rclone mount" 2>/dev/null

if [ -d "$MOUNT_POINT" ]; then
    rm -rf "$MOUNT_POINT"
    show_success "已清理旧挂载点"
else
    show_warning "未发现旧挂载点，跳过清理"
fi

# 3. 准备目录
show_step "步骤3/6" "创建必要目录"
mkdir -p "$MOUNT_POINT"
mkdir -p "$LOG_DIR"
chown -R $SUDO_USER:$SUDO_USER "$LOG_DIR" "$MOUNT_POINT"
chmod 755 "$LOG_DIR" "$MOUNT_POINT"
show_success "目录准备完成"

# 4. 安装依赖
show_step "步骤4/6" "安装必要组件"
apt update -y >/dev/null 2>&1
apt install -y fuse3 wget unzip >/dev/null 2>&1

# 安装rclone
if [ ! -f "$RCLONE_PATH" ]; then
    echo -n "${YELLOW}${ARROW} 正在安装rclone... ${NORMAL}"
    wget -q https://github.com/rclone/rclone/releases/download/v1.65.0/rclone-v1.65.0-linux-amd64.zip -O /tmp/rclone.zip
    unzip -q /tmp/rclone.zip -d /tmp
    cp /tmp/rclone-v1.65.0-linux-amd64/rclone "$RCLONE_PATH"
    chmod 755 "$RCLONE_PATH"
    rm -rf /tmp/rclone*
    show_success "rclone安装完成"
else
    show_success "rclone已安装，跳过"
fi

# 5. 配置fuse和rclone
show_step "步骤5/6" "配置系统和连接信息"
# 配置fuse
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" >> /etc/fuse.conf
    show_success "fuse配置已更新"
else
    show_success "fuse配置已就绪"
fi

# 配置rclone连接
mkdir -p /root/.config/rclone/
cat >/root/.config/rclone/rclone.conf<<EOF
[$DAV_NAME]
type=webdav
url=$DAV_URL
vendor=other
user=$DAV_USER
pass=$("$RCLONE_PATH" obscure "$DAV_PASS")
EOF
show_success "WebDAV连接配置完成"

# 6. 执行挂载
show_step "步骤6/6" "执行挂载操作"
> "$LOG_PATH"  # 清空日志
$RCLONE_PATH mount "$DAV_NAME:" "$MOUNT_POINT" --vfs-cache-mode writes --allow-other --log-file "$LOG_PATH" --log-level INFO --daemon

# 验证挂载
sleep 3
if mountpoint -q "$MOUNT_POINT"; then
    show_success "挂载成功！"
    echo -e "\n${BOLD}操作完成:${NORMAL}"
    echo -e "  ${GREEN}• 挂载路径: ${MOUNT_POINT}${NORMAL}"
    echo -e "  ${GREEN}• 查看文件: cd ${MOUNT_POINT}${NORMAL}"
    echo -e "  ${GREEN}• 查看日志: tail -f ${LOG_PATH}${NORMAL}"
else
    show_error "挂载失败"
    echo -e "\n${BOLD}错误排查:${NORMAL}"
    echo -e "  ${RED}• 查看详细日志: tail -f ${LOG_PATH}${NORMAL}"
    echo -e "  ${RED}• 手动挂载调试: ${RCLONE_PATH} mount ${DAV_NAME}: ${MOUNT_POINT} --vfs-cache-mode writes --allow-other --vv${NORMAL}"
    exit 1
fi

echo -e "\n${BOLD}=====================================${NORMAL}"
exit 0
