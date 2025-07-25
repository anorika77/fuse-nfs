#!/bin/bash
set -e

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 检查操作系统
if ! grep -q -E "Ubuntu|Debian" /etc/os-release; then
    echo "此脚本仅支持Ubuntu/Debian系统"
    exit 1
fi

# 定义变量
BASE_DIR="/opt/115_direct"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
NGINX_CONF="${CONFIG_DIR}/nginx/emby.conf"
DOCKER_COMPOSE="${BASE_DIR}/docker-compose.yml"

# 创建目录
mkdir -p "${DATA_DIR}/clouddrive2"
mkdir -p "${DATA_DIR}/alist"
mkdir -p "${DATA_DIR}/emby"
mkdir -p "${CONFIG_DIR}/nginx"

# 安装依赖
echo "正在安装依赖..."
apt update -y
apt install -y curl wget apt-transport-https ca-certificates software-properties-common

# 安装Docker
if ! command -v docker &> /dev/null; then
    echo "正在安装Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $SUDO_USER
fi

# 安装Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "正在安装Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# 创建Nginx配置
echo "正在配置Nginx..."
cat > "${NGINX_CONF}" << 'EOF'
server {
    listen 8091;
    server_name localhost;

    location / {
        proxy_pass http://emby:8096;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /alist/ {
        proxy_pass http://alist:5244/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# 创建Docker Compose配置
echo "正在创建Docker Compose配置..."
cat > "${DOCKER_COMPOSE}" << 'EOF'
version: '3'

services:
  clouddrive2:
    image: cloudnas/clouddrive2
    container_name: clouddrive2
    restart: always
    network_mode: host
    environment:
      - TZ=Asia/Shanghai
      - CLOUDDRIVE_HOME=/config
    volumes:
      - ./data/clouddrive2:/config
      - ./data/media:/media:shared
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

  alist:
    image: xhofe/alist:latest
    container_name: alist
    restart: always
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ./data/alist:/opt/alist/data
    ports:
      - "5244:5244"

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    network_mode: host
    volumes:
      - ./config/nginx:/etc/nginx/conf.d
    depends_on:
      - emby
      - alist

  emby:
    image: emby/embyserver:latest
    container_name: emby
    restart: always
    environment:
      - TZ=Asia/Shanghai
      - UID=0
      - GID=0
    volumes:
      - ./data/emby:/config
      - ./data/media:/media
    ports:
      - "8096:8096"
EOF

# 启动服务
echo "正在启动服务..."
cd "${BASE_DIR}"
docker-compose up -d

# 显示信息
echo "部署完成！"
echo "----------------------------------------"
echo "CloudDrive2: http://localhost:19798"
echo "Alist: http://localhost:5244 (初始密码可通过 docker logs alist 查看)"
echo "Emby (通过Nginx): http://localhost:8091"
echo "----------------------------------------"
echo "后续步骤:"
echo "1. 访问CloudDrive2添加115网盘并挂载到/media"
echo "2. 访问Alist添加115网盘，WEBDAV策略选择302"
echo "3. 在Alist中配置存储路径与CloudDrive2挂载路径一致"
echo "4. 访问Emby配置媒体库指向/media目录"
