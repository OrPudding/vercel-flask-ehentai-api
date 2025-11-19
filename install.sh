#!/bin/bash

# Public E-Hentai API Service 智能安装脚本 v2.0
# 特性: 交互式配置, 自动从 GitHub 克隆
#
# Copyright (C) 2025 OrPudding
# This program is licensed under the AGPL-3.0.

# --- 默认配置 (如果用户直接回车，将使用这些值) ---
DEFAULT_PROJECT_DIR="/opt/eh-api-service"
DEFAULT_API_DOMAIN="eh-api.example.com"
GITHUB_REPO="https://github.com/OrPudding/vela-py-eh-api-server.git"

# --- 脚本开始 ---
set -e # 如果任何命令失败 ，则立即退出

# 函数：打印彩色标题
print_header() {
    echo "=================================================="
    echo "  $1"
    echo "=================================================="
}

print_header "🚀 Public E-Hentai API Service 部署向导"

# --- 交互式配置 ---
read -p "请输入项目安装目录 [默认: ${DEFAULT_PROJECT_DIR}]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}

read -p "请输入您的 API 域名 (例如: eh-api.example.com) [默认: ${DEFAULT_API_DOMAIN}]: " API_DOMAIN
API_DOMAIN=${API_DOMAIN:-$DEFAULT_API_DOMAIN}

echo "--------------------------------------------------"
echo "配置确认:"
echo "  - 项目目录: ${PROJECT_DIR}"
echo "  - API 域名:   ${API_DOMAIN}"
echo "--------------------------------------------------"
read -p "确认配置无误，按 [Enter] 键开始安装，或按 [Ctrl+C] 退出。"

# 1. 更新系统包列表
print_header "STEP 1/6: 更新系统包"
sudo apt-get update

# 2. 安装基础依赖
print_header "STEP 2/6: 安装 Nginx, Python, Git, Node.js 和 PM2"
sudo apt-get install -y nginx python3 python3-pip git nodejs npm

# 使用 npm 安装 PM2
sudo npm install pm2 -g

# 3. 准备项目文件
print_header "STEP 3/6: 准备项目文件"
if [ -f "index.py" ]; then
    echo "检测到本地 'index.py' 文件，将使用本地文件进行部署。"
    sudo rm -rf ${PROJECT_DIR}
    sudo mkdir -p ${PROJECT_DIR}
    sudo cp -r ./* ${PROJECT_DIR}/
else
    echo "'index.py' 未在当前目录找到，将从 GitHub 克隆项目..."
    sudo git clone ${GITHUB_REPO} ${PROJECT_DIR}
fi
cd ${PROJECT_DIR}

# 4. 安装 Python 依赖
print_header "STEP 4/6: 安装 Python 依赖库"
# 检查 requirements.txt 是否存在
if [ ! -f "requirements.txt" ]; then
    echo "错误: 'requirements.txt' 文件不存在于项目目录中！"
    exit 1
fi
sudo pip3 install --break-system-packages -r requirements.txt

# 5. 配置 Nginx 反向代理
print_header "STEP 5/6: 配置 Nginx 反向代理"
NGINX_CONF_PATH="/etc/nginx/sites-available/${API_DOMAIN}.conf"

# 创建 Nginx 配置文件
sudo tee ${NGINX_CONF_PATH} > /dev/null <<EOF
server {
    listen 80;
    server_name ${API_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; allow all; }
    location / { return 200 'Nginx is configured. Please run Certbot.'; }
}
EOF

# 创建软链接以启用该站点
sudo ln -sfn ${NGINX_CONF_PATH} /etc/nginx/sites-enabled/

# 测试 Nginx 配置并重启
sudo nginx -t && sudo systemctl restart nginx

echo "--------------------------------------------------"
echo "  ✅ Nginx 初始配置完成！"
echo "  下一步是获取 SSL 证书。请确保您的域名 (${API_DOMAIN}) 已正确解析到本服务器的 IP 地址。"
echo "  解析生效后，请运行以下命令获取证书:"
echo
echo "  sudo apt-get update && sudo apt-get install certbot python3-certbot-nginx -y"
echo "  sudo certbot --nginx -d ${API_DOMAIN}"
echo
read -p "完成证书获取后，按 [Enter] 键继续，脚本将自动完成最终配置。"

# 更新 Nginx 配置以使用 SSL 和反向代理
sudo tee ${NGINX_CONF_PATH} > /dev/null <<EOF
server {
    listen 80;
    server_name ${API_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${API_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${API_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${API_DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    access_log /var/log/nginx/${API_DOMAIN}-access.log;
    error_log /var/log/nginx/${API_DOMAIN}-error.log;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF

# 再次测试 Nginx 配置并重启
sudo nginx -t && sudo systemctl restart nginx

# 6. 使用 PM2 启动应用
print_header "STEP 6/6: 使用 PM2 启动应用"
cd ${PROJECT_DIR}

# 检查 ecosystem.config.js 是否存在
if [ ! -f "ecosystem.config.js" ]; then
    echo "错误: 'ecosystem.config.js' 文件不存在于项目目录中！"
    exit 1
fi

# 启动前确保旧进程已停止
pm2 stop eh-api-service || true
pm2 delete eh-api-service || true

pm2 start ecosystem.config.js
pm2 save

print_header "🎉 部署完成！"
echo "您的 API 服务正在运行 ，并通过 PM2 进行守护。"
echo "您现在可以通过 https://${API_DOMAIN} 访问您的服务 。"
echo
echo "常用命令:"
echo "  - 查看服务状态: pm2 list"
echo "  - 查看实时日志: pm2 logs eh-api-service"
echo "  - 重启服务:     pm2 restart eh-api-service"
echo "  - 停止服务:     pm2 stop eh-api-service"
echo "=================================================="
