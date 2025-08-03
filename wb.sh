#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 自定义配置 - 根据需求修改
PORT=5006  # 服务器端口
TELEGRAM_TOKEN="5382715107:AAHj2WrBlH8X9Ul1fKxuWLF9CV7CyMm7Cks"  # 预填的TG Token
CHAT_ID="5186798697"  # 预填的TG ID

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本 (sudo ./deploy.sh)${NC}" >&2
    exit 1
fi

# 欢迎信息
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}      Clouddrive2 Telegram通知服务一键部署      ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "${YELLOW}已配置端口: $PORT${NC}"
echo -e "${YELLOW}已预填Telegram信息${NC}"
echo ""

# 检查操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    echo -e "${RED}无法识别操作系统，仅支持Ubuntu/Debian系统${NC}"
    exit 1
fi

# 安装Docker和Docker Compose
install_docker() {
    echo -e "${YELLOW}开始安装Docker和Docker Compose...${NC}"
    
    # 更新包索引
    apt update -y
    
    # 安装依赖
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    
    # 添加Docker GPG密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    
    # 添加Docker源
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    # 再次更新包索引
    apt update -y
    
    # 安装Docker
    apt install -y docker-ce
    
    # 安装Docker Compose
    apt install -y docker-compose
    
    # 启动Docker服务
    systemctl start docker
    systemctl enable docker
    
    echo -e "${GREEN}Docker和Docker Compose安装完成${NC}"
}

# 检查Docker是否已安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        install_docker
    else
        echo -e "${GREEN}Docker已安装，跳过安装步骤${NC}"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}安装Docker Compose...${NC}"
        apt install -y docker-compose
    else
        echo -e "${GREEN}Docker Compose已安装，跳过安装步骤${NC}"
    fi
}

# 创建项目目录
create_project_dir() {
    echo -e "\n${YELLOW}设置项目目录...${NC}"
    PROJECT_DIR="/opt/clouddrive-notifier"
    
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${YELLOW}项目目录已存在，将使用现有目录${NC}"
    else
        mkdir -p "$PROJECT_DIR"
        echo -e "${GREEN}项目目录创建成功: $PROJECT_DIR${NC}"
    fi
    
    # 创建日志目录
    mkdir -p "$PROJECT_DIR/logs"
    chmod 777 "$PROJECT_DIR/logs"  # 确保容器有写入权限
}

# 创建配置文件
create_config_files() {
    echo -e "\n${YELLOW}创建配置文件...${NC}"
    
    # 生成或使用自定义的验证令牌
    read -p "请输入Webhook验证令牌(回车自动生成): " VERIFY_TOKEN
    if [ -z "$VERIFY_TOKEN" ]; then
        VERIFY_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        echo -e "${YELLOW}自动生成的验证令牌: $VERIFY_TOKEN${NC}"
    fi
    
    # 创建.env文件（使用预填的TG信息）
    echo "TELEGRAM_TOKEN=$TELEGRAM_TOKEN" > "$PROJECT_DIR/.env"
    echo "CHAT_ID=$CHAT_ID" >> "$PROJECT_DIR/.env"
    echo "VERIFY_TOKEN=$VERIFY_TOKEN" >> "$PROJECT_DIR/.env"
    echo -e "${GREEN}.env配置文件创建成功${NC}"
    
    # 创建requirements.txt
    cat > "$PROJECT_DIR/requirements.txt" << EOF
flask==2.3.3
requests==2.31.0
python-dotenv==1.0.0
gunicorn==21.2.0
EOF
    echo -e "${GREEN}requirements.txt创建成功${NC}"
    
    # 创建app.py
    cat > "$PROJECT_DIR/app.py" << 'EOF'
import os
import logging
from datetime import datetime
from flask import Flask, request, jsonify
import requests
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

# 初始化Flask应用
app = Flask(__name__)

# 配置日志
log_dir = "logs"
if not os.path.exists(log_dir):
    os.makedirs(log_dir)
log_filename = os.path.join(log_dir, f"app_{datetime.now().strftime('%Y%m%d')}.log")

logging.basicConfig(
    filename=log_filename,
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 从环境变量获取配置
TELEGRAM_TOKEN = os.getenv('TELEGRAM_TOKEN')
CHAT_ID = os.getenv('CHAT_ID')
VERIFY_TOKEN = os.getenv('VERIFY_TOKEN')

# 验证Webhook订阅
@app.route('/clouddrive-webhook', methods=['GET'])
def verify_webhook():
    mode = request.args.get('hub.mode')
    token = request.args.get('hub.verify_token')
    challenge = request.args.get('hub.challenge')
    
    if mode == 'subscribe' and token == VERIFY_TOKEN:
        logger.info("Webhook验证成功")
        return challenge, 200
    else:
        logger.warning("Webhook验证失败")
        return "验证失败", 403

# 处理Clouddrive2发送的事件
@app.route('/clouddrive-webhook', methods=['POST'])
def handle_webhook():
    try:
        data = request.json
        logger.info(f"收到事件: {data}")
        
        # 检查是否是文件上传完成事件
        if data.get('event') == 'file_uploaded':
            file_info = data.get('file', {})
            send_telegram_notification(file_info)
        
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logger.error(f"处理Webhook出错: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

# 发送Telegram通知
def send_telegram_notification(file_info):
    try:
        # 格式化通知内容
        message = (
            f"📁 文件上传完成!\n"
            f"名称: {file_info.get('name', '未知')}\n"
            f"大小: {format_size(file_info.get('size', 0))}\n"
            f"路径: {file_info.get('path', '未知')}\n"
            f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        )
        
        # 调用Telegram API发送消息
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        params = {
            "chat_id": CHAT_ID,
            "text": message,
            "parse_mode": "HTML"
        }
        
        response = requests.get(url, params=params)
        response.raise_for_status()
        logger.info("Telegram通知发送成功")
    except Exception as e:
        logger.error(f"发送Telegram通知失败: {str(e)}")

# 格式化文件大小（字节转人类可读格式）
def format_size(bytes, decimals=2):
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    if bytes == 0:
        return '0 B'
    bytes = float(bytes)
    i = 0
    while bytes >= 1024 and i < len(units) - 1:
        bytes /= 1024
        i += 1
    return f"{bytes:.{decimals}f} {units[i]}"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
    echo -e "${GREEN}app.py创建成功${NC}"
    
    # 创建Dockerfile
    cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim

# 设置工作目录
WORKDIR /app

# 复制依赖文件并安装
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY app.py .

# 创建日志目录
RUN mkdir -p /app/logs

# 暴露端口（容器内部端口固定为5000）
EXPOSE 5000

# 启动命令
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "app:app"]
EOF
    echo -e "${GREEN}Dockerfile创建成功${NC}"
    
    # 创建docker-compose.yml（使用自定义端口）
    cat > "$PROJECT_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  clouddrive-notifier:
    build: .
    container_name: clouddrive-notifier
    restart: always
    ports:
      - "$PORT:5000"  # 使用自定义端口
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF
    echo -e "${GREEN}docker-compose.yml创建成功（端口: $PORT）${NC}"
}

# 启动服务
start_service() {
    echo -e "\n${YELLOW}启动服务...${NC}"
    cd "$PROJECT_DIR"
    docker-compose up -d --build
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        echo -e "${GREEN}服务启动成功！${NC}"
    else
        echo -e "${RED}服务启动失败，请查看日志: docker-compose logs${NC}"
        exit 1
    fi
}

# 配置Nginx（可选）
configure_nginx() {
    echo -e "\n${YELLOW}是否需要配置Nginx反向代理？(y/n)${NC}"
    read -p "请选择: " CONFIG_NGINX
    
    if [ "$CONFIG_NGINX" = "y" ] || [ "$CONFIG_NGINX" = "Y" ]; then
        read -p "请输入你的域名或服务器IP: " SERVER_DOMAIN
        
        # 安装Nginx
        if ! command -v nginx &> /dev/null; then
            echo -e "${YELLOW}安装Nginx...${NC}"
            apt install -y nginx
            systemctl start nginx
            systemctl enable nginx
        fi
        
        # 创建Nginx配置（使用自定义端口）
        NGINX_CONF="/etc/nginx/sites-available/clouddrive-notifier"
        cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name $SERVER_DOMAIN;

    location /clouddrive-webhook {
        proxy_pass http://127.0.0.1:$PORT;  # 使用自定义端口
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        
        # 启用配置
        ln -sfn "$NGINX_CONF" "/etc/nginx/sites-enabled/clouddrive-notifier"
        
        # 测试配置并重启
        if nginx -t; then
            systemctl restart nginx
            echo -e "${GREEN}Nginx配置完成，反向代理已启用${NC}"
            echo -e "${GREEN}Webhook地址: http://$SERVER_DOMAIN/clouddrive-webhook${NC}"
        else
            echo -e "${RED}Nginx配置有误，请检查后手动配置${NC}"
        fi
    else
        echo -e "${YELLOW}跳过Nginx配置${NC}"
        echo -e "${GREEN}Webhook地址: http://服务器IP:$PORT/clouddrive-webhook${NC}"
    fi
}

# 显示完成信息
show_completion() {
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}            部署完成！${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "服务已部署到: /opt/clouddrive-notifier"
    echo -e "使用端口: $PORT"
    echo -e "验证令牌: $(grep VERIFY_TOKEN $PROJECT_DIR/.env | cut -d'=' -f2)"
    echo -e "管理命令:"
    echo -e "  查看状态: docker-compose -f $PROJECT_DIR/docker-compose.yml ps"
    echo -e "  查看日志: docker-compose -f $PROJECT_DIR/docker-compose.yml logs -f"
    echo -e "  重启服务: docker-compose -f $PROJECT_DIR/docker-compose.yml restart"
    echo -e "  停止服务: docker-compose -f $PROJECT_DIR/docker-compose.yml down"
    echo -e "${YELLOW}请在Clouddrive2中配置Webhook地址和验证令牌${NC}"
}

# 主流程
main() {
    check_docker
    create_project_dir
    create_config_files
    start_service
    configure_nginx
    show_completion
}

# 启动主流程
main
