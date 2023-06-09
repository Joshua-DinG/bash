#!/bin/bash

# 检查系统是否已安装 Docker 和 docker-compose
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，开始安装..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker 安装完成！"
else
    echo "Docker 已安装，跳过安装步骤。"
fi

if ! command -v docker-compose &> /dev/null; then
    echo "docker-compose 未安装，开始安装..."
    if curl -Is https://www.baidu.com | grep "200 OK" > /dev/null; then
        echo "检测到服务器位于国内，使用国内镜像下载 docker-compose。"
        curl -L "https://ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    else
        echo "检测到服务器位于国外，使用官方镜像下载 docker-compose。"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    fi
    echo "docker-compose 安装完成！"
else
    echo "docker-compose 已安装，跳过安装步骤。"
fi

# 更换 Docker 镜像加速器
echo "开始更换 Docker 镜像加速器..."
if [ ! -f /etc/docker/daemon.json ]; then
    echo "{\"registry-mirrors\": [\"https://your-mirror-accelerator\"]}" | sudo tee /etc/docker/daemon.json
else
    sudo sed -i 's@\"registry-mirrors\": \[@\"registry-mirrors\": \[\"https://your-mirror-accelerator\", @' /etc/docker/daemon.json
fi
sudo systemctl daemon-reload
sudo systemctl restart docker
echo "Docker 镜像加速器已设置完成！"
