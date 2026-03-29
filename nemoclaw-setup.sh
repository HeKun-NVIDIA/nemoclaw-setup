#!/usr/bin/env bash
# nemoclaw-setup.sh v22 — NemoClaw 一键部署 (官方交互增强版)
# 适用平台：NVIDIA DGX Spark（Ubuntu）
#
# 特性：
# 1. 保留官方 onboard 的交互流程（用户自行在 Step 4 选择模型）
# 2. 注入 open-network Policy，解决沙盒无法访问外网的问题
# 3. 自动修正 DGX Spark 上的 Ollama 监听地址，确保容器可访问
set -euo pipefail

SCRIPT_VERSION="v22"

# ── 静默前置检查 ──────────────────────────────────────────────────────────────
_fail() { echo "  ✗ $*" >&2; exit 1; }

docker info > /dev/null 2>&1 || _fail "Docker 未运行，请先启动 Docker。"

# ── 安装 NemoClaw CLI（静默，已安装则跳过）────────────────────────────────────
if ! command -v nemoclaw > /dev/null 2>&1; then
    echo "  Installing NemoClaw CLI..."
    INSTALL_TMP="$(mktemp /tmp/nemoclaw-install-XXXXXX.sh)"
    curl -fsSL https://www.nvidia.com/nemoclaw.sh -o "$INSTALL_TMP" \
        || _fail "官方安装脚本下载失败，请检查网络连接。"
    
    # 注释掉末尾的 run_onboard 调用行（有缩进），保留函数定义头（无缩进）
    # 这样安装完成后不会自动进入 onboard 流程，由我们后续手动控制
    sed -i 's/^\(\s\+\)run_onboard\s*$/\1:/' "$INSTALL_TMP"
    
    bash "$INSTALL_TMP" > /dev/null 2>&1
    rm -f "$INSTALL_TMP"
    
    # 刷新 PATH
    [[ -s "$HOME/.nvm/nvm.sh" ]] && \. "$HOME/.nvm/nvm.sh"
    NPM_BIN="$(npm config get prefix 2>/dev/null)/bin" || true
    [[ -n "${NPM_BIN:-}" && -d "$NPM_BIN" ]] && export PATH="$NPM_BIN:$PATH"
    [[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
    
    command -v nemoclaw > /dev/null 2>&1 || _fail "NemoClaw CLI 安装失败，请检查网络。"
fi

# ── 确保 Ollama 可被容器访问 ──────────────────────────────────────────────────
DOCKER_GW=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
if curl -sf "http://localhost:11434/api/tags" > /dev/null 2>&1; then
    if ! curl -sf "http://${DOCKER_GW}:11434/api/tags" > /dev/null 2>&1; then
        echo "  ⚠  Local Ollama is running but not accessible from containers."
        echo "     Reconfiguring Ollama to listen on 0.0.0.0:11434..."
        if systemctl is-active ollama > /dev/null 2>&1; then
            sudo mkdir -p /etc/systemd/system/ollama.service.d
            printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' \
                | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
            sudo systemctl daemon-reload
            sudo systemctl restart ollama
            sleep 2
        else
            sudo pkill -f 'ollama serve' 2>/dev/null || true
            sleep 2
            OLLAMA_HOST=0.0.0.0:11434 ollama serve >> /tmp/ollama.log 2>&1 &
            sleep 2
        fi
    fi
fi

# ── 将 open-network.yaml 注入官方 presets 目录 ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESETS_SRC="${SCRIPT_DIR}/policies/open-network.yaml"
NEMOCLAW_PRESETS_DIR="${HOME}/.nemoclaw/source/nemoclaw-blueprint/policies/presets"

if [[ -f "$PRESETS_SRC" && -d "$NEMOCLAW_PRESETS_DIR" ]]; then
    cp "$PRESETS_SRC" "${NEMOCLAW_PRESETS_DIR}/open-network.yaml"
    echo ""
    echo "  ✓ open-network preset injected into NemoClaw."
    echo ""
fi

# ── 运行官方 NemoClaw onboard ─────────────────────────────────────────────────
export NEMOCLAW_EXPERIMENTAL=1

echo "  ====================================================================="
echo "  🚀 准备启动 NemoClaw 交互式配置 (Onboard)"
echo ""
echo "  IMPORTANT / 重要提示:"
echo "  在到达 【Step 7: Policy presets】 时，系统会询问："
echo "  Apply suggested presets (pypi, npm)? [Y/n/list]:"
echo ""
echo "  👉 请输入: list"
echo "  👉 然后输入: pypi,npm,open-network"
echo ""
echo "  这样才能应用我们注入的网络策略，确保沙盒能正常访问外网！"
echo "  ====================================================================="
echo ""
echo "  按回车键继续..."
read -r

nemoclaw onboard

# ── 打印浏览器访问地址 ────────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-my-assistant}"

echo ""
echo "  ──────────────────────────────────────────────────"
echo "  🎉 NemoClaw 部署完成！"
echo ""
echo "  Browser access (Web UI):"
echo "    http://127.0.0.1:18789/"
echo "    http://${LOCAL_IP}:18789/"
echo ""
echo "  Useful commands:"
echo "    nemoclaw $SANDBOX_NAME connect        # open sandbox terminal"
echo "    nemoclaw $SANDBOX_NAME status         # check status"
echo "    nemoclaw $SANDBOX_NAME logs --follow  # follow logs"
echo "  ──────────────────────────────────────────────────"
echo ""
