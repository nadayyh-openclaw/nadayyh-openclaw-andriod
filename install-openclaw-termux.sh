#!/bin/bash
# OpenClaw Termux 部署脚本 - 零容错版
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# 1. 核心：确保 .bashrc 存在（修复截图中的致命错误）
touch ~/.bashrc 2>/dev/null

# 2. 基础依赖与路径配置
echo -e "${YELLOW}[1/6] 配置环境...${NC}"
pkg update && pkg upgrade -y
pkg install nodejs git openssh tmux golang python -y

mkdir -p ~/.npm-global ~/tmp ~/openclaw-logs
npm config set prefix ~/.npm-global

# 写入环境变量（带容错检查）
grep -qxF 'export PATH=$HOME/.npm-global/bin:$PATH' ~/.bashrc 2>/dev/null || \
    echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
grep -qxF 'export TERMUX_VERSION=1' ~/.bashrc 2>/dev/null || \
    echo 'export TERMUX_VERSION=1' >> ~/.bashrc
grep -qxF 'export TMPDIR=$HOME/tmp' ~/.bashrc 2>/dev/null || \
    echo 'export TMPDIR=$HOME/tmp' >> ~/.bashrc

source ~/.bashrc

# 3. 强制建立 npm 软链接（解决插件安装时的 /bin/npm 报错）
mkdir -p $PREFIX/bin
ln -sf $(which npm) $PREFIX/bin/npm

# 4. 安装 OpenClaw（带重试与国内镜像）
echo -e "${YELLOW}[2/6] 安装 OpenClaw...${NC}"
npm i -g openclaw --registry=https://registry.npmmirror.com || {
    echo -e "${RED}首次安装失败，重试中...${NC}"
    npm i -g openclaw --registry=https://registry.npmmirror.com
}

BASE_DIR="$HOME/.npm-global/lib/node_modules/openclaw"

# 5. 核心补丁（用循环增强容错，避免 find 中断）
echo -e "${YELLOW}[3/6] 应用 Android 补丁...${NC}"
find "$BASE_DIR" -type f -name "*.js" 2>/dev/null | while read -r file; do
    sed -i 's/\/bin\/npm/npm/g' "$file" 2>/dev/null
    sed -i 's/process.platform === "linux"/false/g' "$file" 2>/dev/null
    sed -i "s/process.platform === 'linux'/false/g" "$file" 2>/dev/null
done

# 6. 配置检查与强制写入（解决残留无效配置问题）
echo -e "${YELLOW}[4/6] 配置 OpenClaw...${NC}"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
mkdir -p "$(dirname "$CONFIG_FILE")"

# 如果配置不存在或无效，强制覆盖
if [[ ! -f "$CONFIG_FILE" ]] || ! grep -q '"gateway"' "$CONFIG_FILE"; then
    cat > "$CONFIG_FILE" <<EOF
{
  "gateway": {
    "host": "127.0.0.1",
    "port": 18789,
    "auth": { "type": "none" }
  },
  "providers": {
    "anthropic": { "apiKey": "" },
    "openai": { "apiKey": "" }
  }
}
EOF
fi

# 7. 创建快捷命令
echo -e "${YELLOW}[5/6] 创建管理别名...${NC}"
sed -i '/# --- OpenClaw Start ---/,/# --- OpenClaw End ---/d' ~/.bashrc
cat << 'EOF' >> ~/.bashrc
# --- OpenClaw Start ---
alias ocr='pkill -9 node 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null; sleep 1; tmux new -d -s openclaw "export PATH=$HOME/.npm-global/bin:$PATH; openclaw gateway --port 18789 --allow-unconfigured || read"'
alias oclog='tmux attach -t openclaw'
alias ockill='pkill -9 node 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null'
# --- OpenClaw End ---
EOF

source ~/.bashrc

# 8. 激活唤醒锁（带可用性检查）
if command -v termux-wake-lock >/dev/null; then
    termux-wake-lock
    echo -e "${GREEN}✅ Wake-lock 已激活${NC}"
else
    echo -e "${YELLOW}⚠️  termux-api 未安装，建议: pkg install termux-api${NC}"
fi

# 9. 启动
echo -e "${YELLOW}[6/6] 启动服务...${NC}"
ocr
sleep 3

echo -e "${GREEN}部署完成！运行 'oclog' 查看日志${NC}"
