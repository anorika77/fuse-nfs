#!/bin/bash
# 强制安装fuse3及其他基础依赖（解决"依赖fuse3安装失败"问题）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请用root权限运行（sudo bash $0）${NC}"
    exit 1
fi

# 识别系统类型
detect_system() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# 强制安装fuse3（核心修复）
install_fuse3_force() {
    echo -e "${YELLOW}[1/2] 强制安装fuse3...${NC}"
    SYSTEM=$(detect_system)

    case $SYSTEM in
        "debian")
            # Ubuntu/Debian：启用universe仓库（fuse3通常在此仓库）
            sudo add-apt-repository universe -y >/dev/null 2>&1
            sudo apt-get update -y >/dev/null 2>&1
            # 强制安装，忽略依赖冲突
            sudo apt-get install -y fuse3 --reinstall -f >/dev/null 2>&1
            ;;
        "rhel")
            # CentOS/RHEL：启用epel仓库（fuse3可能在此）
            sudo yum install -y epel-release >/dev/null 2>&1
            sudo yum install -y fuse3 --refresh -y >/dev/null 2>&1
            ;;
        "unknown")
            # 其他系统：手动编译安装fuse3（通用方法）
            echo -e "${YELLOW}未知系统，手动编译fuse3...${NC}"
            # 安装编译依赖
            sudo apt-get install -y gcc make pkg-config libglib2.0-dev 2>/dev/null || \
            sudo yum install -y gcc make pkgconfig glib2-devel 2>/dev/null
            # 下载源码
            wget https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.xz -q
            tar xf fuse-3.16.2.tar.xz >/dev/null 2>&1
            cd fuse-3.16.2 || exit 1
            ./configure --prefix=/usr >/dev/null 2>&1
            make -j$(nproc) >/dev/null 2>&1
            sudo make install >/dev/null 2>&1
            cd .. && rm -rf fuse-3.16.2*
            # 创建系统链接
            sudo ln -sf /usr/lib/pkgconfig/fuse3.pc /usr/lib64/pkgconfig/fuse3.pc 2>/dev/null
            ;;
    esac

    # 验证fuse3是否安装成功
    if command -v fusermount3 &>/dev/null; then
        echo -e "${GREEN}[✓] fuse3安装成功${NC}"
        return 0
    else
        echo -e "${RED}[×] fuse3仍安装失败！${NC}"
        return 1
    fi
}

# 安装其他基础依赖
install_other_deps() {
    echo -e "${YELLOW}[2/2] 安装其他基础依赖...${NC}"
    SYSTEM=$(detect_system)
    if [ "$SYSTEM" = "debian" ]; then
        sudo apt-get install -y curl sudo openssh-server >/dev/null 2>&1
    elif [ "$SYSTEM" = "rhel" ]; then
        sudo yum install -y curl sudo openssh-server >/dev/null 2>&1
    else
        sudo apt-get install -y curl sudo openssh-server 2>/dev/null || \
        sudo yum install -y curl sudo openssh-server 2>/dev/null
    fi

    # 验证关键命令
    for cmd in curl sudo sshd; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${YELLOW}警告：依赖$cmd未安装${NC}"
        fi
    done
    echo -e "${GREEN}[✓] 基础依赖处理完成${NC}"
}

# 主流程
main() {
    echo -e "${GREEN}===== 基础依赖修复工具 ====="${NC}
    install_fuse3_force
    # 即使fuse3安装失败，仍尝试安装其他依赖
    install_other_deps
    echo -e "\n${YELLOW}修复完成！请重新运行主脚本${NC}"
}

main
