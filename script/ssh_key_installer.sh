#!/bin/sh
# ==============================================================================
# SSH 公钥自动添加脚本 (v3 - 经典输出格式)
# 特性:
# - 兼容 sh 和 bash
# - 兼容 Ubuntu, Debian, Alpine
# - 智能检测 root/普通用户，执行不同操作
# - 智能检测系统是否安装了sudo 确保sudo 能使用
# - 不创建配置文件备份
# - 从云端获取公钥，添加到authorized_keys 里
# ==============================================================================

# 配置变量
PUBKEY_URL="https://cdn.jsdmirror.com/gh/Jianfei-DinG/bash/script/id_rsa.pub"
SSH_DIR=""
AUTH_KEYS=""
SSHD_CONFIG="/etc/ssh/sshd_config"
HOSTNAME=""
SUDO_AVAILABLE=0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检测系统信息
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION"
    else
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
    fi
}

# 设置SSH目录和文件路径
setup_paths() {
    if [ "$(id -u)" -eq 0 ]; then
        SSH_DIR="/root/.ssh"
        CURRENT_USER="root"
    else
        SSH_DIR="$HOME/.ssh"
        CURRENT_USER="$(whoami)"
    fi
    AUTH_KEYS="$SSH_DIR/authorized_keys"
    
    # 获取主机名
    HOSTNAME=$(hostname 2>/dev/null || echo "Unknown")
}

# 检查sudo是否可用
check_sudo() {
    SUDO_AVAILABLE=0
    
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_AVAILABLE=1  # root用户不需要sudo
        return 0
    fi
    
    if command -v sudo >/dev/null 2>&1; then
        # 测试sudo权限
        if sudo -n true 2>/dev/null; then
            SUDO_AVAILABLE=1
        else
            # 尝试让用户输入密码验证sudo
            echo -e "${YELLOW}检测到需要sudo权限来配置SSH服务，请输入密码验证...${NC}"
            if sudo true 2>/dev/null; then
                SUDO_AVAILABLE=1
            else
                echo -e "${RED}警告: sudo权限验证失败，无法自动配置SSH服务${NC}"
                SUDO_AVAILABLE=0
            fi
        fi
    else
        echo -e "${YELLOW}警告: 系统未安装sudo，将尝试安装...${NC}"
        # 尝试安装sudo
        if command -v apt-get >/dev/null 2>&1; then
            echo "正在安装 sudo..."
            su -c "apt-get update -qq && apt-get install -y sudo" || echo -e "${RED}安装sudo失败${NC}"
        elif command -v apk >/dev/null 2>&1; then
            echo "正在安装 sudo..."
            su -c "apk add --no-cache sudo" || echo -e "${RED}安装sudo失败${NC}"
        else
            echo -e "${RED}错误: 无法自动安装sudo，且当前非root用户${NC}"
        fi
        
        # 再次检查sudo
        if command -v sudo >/dev/null 2>&1; then
            echo -e "${YELLOW}sudo安装成功，请重新运行脚本${NC}"
            exit 1
        else
            echo -e "${RED}错误: 普通用户需要sudo权限来配置SSH服务${NC}"
            SUDO_AVAILABLE=0
        fi
    fi
}

# 检查并安装必要工具
check_tools() {
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "${RED}错误: 系统需要 curl 或 wget 来下载公钥${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            echo "正在安装 curl..."
            if [ "$(id -u)" -eq 0 ]; then
                apt-get update -qq && apt-get install -y curl
            else
                if command -v sudo >/dev/null 2>&1; then
                    sudo apt-get update -qq && sudo apt-get install -y curl
                else
                    echo -e "${RED}错误: 需要 sudo 权限或 root 用户来安装 curl${NC}"
                    exit 1
                fi
            fi
        elif command -v apk >/dev/null 2>&1; then
            echo "正在安装 curl..."
            if [ "$(id -u)" -eq 0 ]; then
                apk add --no-cache curl
            else
                if command -v sudo >/dev/null 2>&1; then
                    sudo apk add --no-cache curl
                else
                    echo -e "${RED}错误: 需要 sudo 权限或 root 用户来安装 curl${NC}"
                    exit 1
                fi
            fi
        else
            echo -e "${RED}错误: 无法自动安装 curl，请手动安装${NC}"
            exit 1
        fi
    fi
}

# 下载公钥
download_pubkey() {
    if command -v curl >/dev/null 2>&1; then
        REMOTE_PUBKEY=$(curl -s --connect-timeout 10 "$PUBKEY_URL" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        REMOTE_PUBKEY=$(wget -q --timeout=10 -O - "$PUBKEY_URL" 2>/dev/null)
    else
        echo -e "${RED}错误: 无法下载公钥${NC}"
        exit 1
    fi
    
    if [ -z "$REMOTE_PUBKEY" ]; then
        echo -e "${RED}错误: 无法从云端获取公钥，请检查网络连接${NC}"
        exit 1
    fi
}

# 检查公钥是否已存在
check_existing_key() {
    if [ -f "$AUTH_KEYS" ]; then
        if grep -Fq "$REMOTE_PUBKEY" "$AUTH_KEYS"; then
            return 0  # 公钥已存在
        fi
    fi
    return 1  # 公钥不存在
}

# 统计当前密钥数量
count_keys() {
    if [ -f "$AUTH_KEYS" ]; then
        grep -c "^ssh-" "$AUTH_KEYS" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# 检查SSH配置
check_ssh_config() {
    SSH_KEY_AUTH="未知"
    PASSWORD_AUTH="未知"
    
    if [ -f "$SSHD_CONFIG" ]; then
        # 检查密钥登录状态
        if grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG"; then
            SSH_KEY_AUTH="已开启"
        elif grep -q "^PubkeyAuthentication no" "$SSHD_CONFIG"; then
            SSH_KEY_AUTH="已禁用"
        else
            SSH_KEY_AUTH="已开启"  # 默认开启
        fi
        
        # 检查密码登录状态
        if grep -q "^PasswordAuthentication no" "$SSHD_CONFIG"; then
            PASSWORD_AUTH="已禁用"
        elif grep -q "^PasswordAuthentication yes" "$SSHD_CONFIG"; then
            PASSWORD_AUTH="已开启"
        else
            PASSWORD_AUTH="已开启"  # 默认开启
        fi
    fi
}

# 配置SSH服务
configure_ssh() {
    local need_restart=0
    
    # 检查是否有权限修改SSH配置
    if [ "$(id -u)" -ne 0 ] && [ "$SUDO_AVAILABLE" -eq 0 ]; then
        echo -e "${RED}警告: 无sudo权限，无法自动配置SSH服务${NC}"
        return 0
    fi
    
    # 启用密钥认证
    if [ "$SSH_KEY_AUTH" != "已开启" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        else
            sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        fi
        SSH_KEY_AUTH="已开启"
        need_restart=1
    fi
    
    # 禁用密码认证
    if [ "$PASSWORD_AUTH" != "已禁用" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        else
            sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        fi
        PASSWORD_AUTH="已禁用"
        need_restart=1
    fi
    
    return $need_restart
}

# 重启SSH服务
restart_ssh() {
    SSH_STATUS="重启失败"
    
    # 检查是否有权限重启SSH服务
    if [ "$(id -u)" -ne 0 ] && [ "$SUDO_AVAILABLE" -eq 0 ]; then
        SSH_STATUS="权限不足"
        return 1
    fi
    
    if [ "$(id -u)" -eq 0 ]; then
        if systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1 || service sshd restart >/dev/null 2>&1 || service ssh restart >/dev/null 2>&1; then
            SSH_STATUS="已重启"
        fi
    else
        if sudo systemctl restart sshd >/dev/null 2>&1 || sudo systemctl restart ssh >/dev/null 2>&1 || sudo service sshd restart >/dev/null 2>&1 || sudo service ssh restart >/dev/null 2>&1; then
            SSH_STATUS="已重启"
        fi
    fi
}

# 添加公钥
add_pubkey() {
    # 创建.ssh目录
    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
    
    # 获取公钥注释 - 在脚本外部处理输入显示
    echo ""
    echo -e "${YELLOW}请输入公钥注释 (如: 5656656): ${NC}" >/dev/tty
    read -r KEY_COMMENT </dev/tty
    
    # 清屏重新显示状态信息到当前位置
    clear
    
    # 重新显示标题和状态信息
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━ 【 SSH 部署助手 】━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}💻 系统平台${NC} : $OS_NAME"
    echo -e "${GREEN}👤 当前用户${NC} : $CURRENT_USER       共有密钥数 : $INITIAL_KEY_COUNT"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}🔐 密钥登录状态${NC}      : $SSH_KEY_AUTH"
    echo -e "${GREEN}🚫 密码登录状态${NC}      : $PASSWORD_AUTH"
    
    # 添加注释到公钥
    if [ -n "$KEY_COMMENT" ]; then
        COMMENTED_KEY="$REMOTE_PUBKEY $KEY_COMMENT@$HOSTNAME"
    else
        COMMENTED_KEY="$REMOTE_PUBKEY @$HOSTNAME"
    fi
    
    # 添加公钥到authorized_keys
    echo "$COMMENTED_KEY" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    
    if [ -n "$KEY_COMMENT" ]; then
        PUBKEY_STATUS="公钥已注释 $KEY_COMMENT@$HOSTNAME"
    else
        PUBKEY_STATUS="公钥已注释 @$HOSTNAME"
    fi
}

# 主函数
main() {
    # 系统检测
    detect_system
    setup_paths
    check_sudo
    check_tools
    
    # 显示标题
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━ 【 SSH 部署助手 】━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}💻 系统平台${NC} : $OS_NAME"
    
    # 获取初始密钥数量
    INITIAL_KEY_COUNT=$(count_keys)
    echo -e "${GREEN}👤 当前用户${NC} : $CURRENT_USER       共有密钥数 : $INITIAL_KEY_COUNT"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    
    # 检查SSH配置
    check_ssh_config
    echo -e "${GREEN}🔐 密钥登录状态${NC}      : $SSH_KEY_AUTH"
    echo -e "${GREEN}🚫 密码登录状态${NC}      : $PASSWORD_AUTH"
    
    # 下载公钥
    download_pubkey
    
    # 检查公钥是否已存在
    if check_existing_key; then
        echo -e "${YELLOW}➕ 公钥添加结果${NC}      : 公钥已添加过，无需重复添加"
        FINAL_KEY_COUNT=$(count_keys)
        echo -e "${GREEN}🔑 当前密钥总数${NC}      : $FINAL_KEY_COUNT"
        echo -e "${GREEN}♻️ SSH 服务状态${NC}      : 无需重启"
        echo -e "${BLUE}# ===============================================================${NC}"
        echo -e "${GREEN}🎉 检查完成！公钥已存在，密码登录已禁用！${NC}"
        echo -e "${BLUE}# ===============================================================${NC}"
    else
        # 添加公钥
        add_pubkey
        echo -e "${GREEN}➕ 公钥添加成功${NC}      : $PUBKEY_STATUS"
        
        # 更新密钥数量
        FINAL_KEY_COUNT=$(count_keys)
        echo -e "${GREEN}🔑 当前密钥总数${NC}      : $FINAL_KEY_COUNT"
        
        # 配置SSH并重启
        if configure_ssh; then
            restart_ssh
            echo -e "${GREEN}♻️ SSH 服务状态${NC}      : $SSH_STATUS"
        else
            echo -e "${GREEN}♻️ SSH 服务状态${NC}      : 无需重启"
        fi
        
        echo -e "${BLUE}# ===============================================================${NC}"
        if [ "$SSH_STATUS" = "重启失败" ] || [ "$SSH_STATUS" = "权限不足" ]; then
            if [ "$SSH_STATUS" = "权限不足" ]; then
                echo -e "${RED}⚠️ sudo权限不足，请手动重启SSH服务或重新运行脚本！${NC}"
            else
                echo -e "${RED}⚠️ SSH服务重启失败，请手动重启SSH服务！${NC}"
            fi
        else
            echo -e "${GREEN}🎉 添加完成！请使用【私钥】连接，密码登录已禁用！${NC}"
        fi
        echo -e "${BLUE}# ===============================================================${NC}"
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 执行主函数
main
