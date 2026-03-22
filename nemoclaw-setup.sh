#!/usr/bin/env bash
# nemoclaw-setup.sh v13 — NemoClaw + 本地 Ollama 一键安装
# 适用平台：NVIDIA DGX Spark（Ubuntu）
#
# 用法：
#   bash nemoclaw-setup.sh
#   NEMOCLAW_MODEL=qwen3.5:35b-a3b bash nemoclaw-setup.sh   # 跳过模型选择
set -euo pipefail

SCRIPT_VERSION="v13"
OLLAMA_API="http://localhost:11434/api/tags"
NEMOCLAW_SRC="${HOME}/.nemoclaw/source"

# ── 静默前置检查（出错才报）────────────────────────────────────────────────────
_fail() { echo "  ✗ $*" >&2; exit 1; }

docker info > /dev/null 2>&1 || _fail "Docker 未运行，请先启动 Docker。"
command -v openshell > /dev/null 2>&1 || _fail "未找到 openshell 命令。"

# ── 安装 NemoClaw CLI（静默，已安装则跳过）────────────────────────────────────
if ! command -v nemoclaw > /dev/null 2>&1; then
    INSTALL_TMP="$(mktemp /tmp/nemoclaw-install-XXXXXX.sh)"
    curl -fsSL https://www.nvidia.com/nemoclaw.sh -o "$INSTALL_TMP" \
        || _fail "官方安装脚本下载失败，请检查网络连接。"
    # 删除官方脚本末尾的 run_onboard，由本脚本统一控制
    sed -i 's/^\s*run_onboard\b.*$/  :/' "$INSTALL_TMP"
    bash "$INSTALL_TMP" > /dev/null 2>&1
    rm -f "$INSTALL_TMP"
    # 刷新 PATH
    [[ -s "$HOME/.nvm/nvm.sh" ]] && \. "$HOME/.nvm/nvm.sh"
    NPM_BIN="$(npm config get prefix 2>/dev/null)/bin" || true
    [[ -n "${NPM_BIN:-}" && -d "$NPM_BIN" ]] && export PATH="$NPM_BIN:$PATH"
    [[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
    command -v nemoclaw > /dev/null 2>&1 || _fail "NemoClaw CLI 安装失败，请检查网络。"
fi

# 确保源码存在
if [[ ! -d "$NEMOCLAW_SRC/.git" ]]; then
    mkdir -p "$(dirname "$NEMOCLAW_SRC")"
    git clone --quiet --depth 1 https://github.com/NVIDIA/NemoClaw.git "$NEMOCLAW_SRC" \
        || _fail "NemoClaw 源码克隆失败，请检查网络。"
fi

# ── Ollama 检测与模型选择（模仿官方风格）──────────────────────────────────────
echo ""

OLLAMA_RUNNING=false
if curl -sf "$OLLAMA_API" > /dev/null 2>&1; then
    OLLAMA_RUNNING=true
fi

SELECTED_MODEL=""

if [[ -n "${NEMOCLAW_MODEL:-}" ]]; then
    # 环境变量已指定模型，静默跳过选择
    SELECTED_MODEL="$NEMOCLAW_MODEL"
else
    # 模仿官方风格的检测提示
    echo "  Detected local inference option: Ollama"
    if [[ "$OLLAMA_RUNNING" == "true" ]]; then
        echo "  Local Ollama is running on localhost:11434"
    else
        echo "  Local Ollama is not running on localhost:11434"
    fi
    echo ""

    read -rp "  Use local Ollama for inference? [Y/n]: " USE_OLLAMA
    USE_OLLAMA="${USE_OLLAMA:-Y}"

    if [[ "$USE_OLLAMA" =~ ^[Yy]$ ]]; then
        if [[ "$OLLAMA_RUNNING" == "false" ]]; then
            echo ""
            echo "  ✗ Ollama is not running. Please start it first:"
            echo "    OLLAMA_HOST=0.0.0.0:11434 ollama serve &"
            echo ""
            exit 1
        fi

        # 列出可用模型（模仿官方风格）
        MODELS_JSON=$(curl -sf "$OLLAMA_API" 2>/dev/null || echo '{"models":[]}')
        if command -v jq > /dev/null 2>&1; then
            mapfile -t MODELS < <(echo "$MODELS_JSON" | jq -r '.models[].name' 2>/dev/null || true)
        else
            mapfile -t MODELS < <(echo "$MODELS_JSON" | grep -oP '"name"\s*:\s*"\K[^"]+' 2>/dev/null || true)
        fi

        if [[ ${#MODELS[@]} -eq 0 ]]; then
            echo "  ✗ No models found in Ollama. Please run: ollama pull <model>"
            exit 1
        fi

        echo ""
        echo "  Ollama models:"
        for i in "${!MODELS[@]}"; do
            echo "    $((i+1))) ${MODELS[$i]}"
        done
        echo ""

        read -rp "  Choose model [1]: " CHOICE
        CHOICE="${CHOICE:-1}"
        IDX=$(( CHOICE - 1 ))
        if [[ $IDX -lt 0 || $IDX -ge ${#MODELS[@]} ]]; then
            IDX=0
        fi

        SELECTED_MODEL="${MODELS[$IDX]}"

        # 检查 Ollama 是否可从 Docker 容器内部访问（使用 Docker bridge 网关 IP）
        DOCKER_GW=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
        OLLAMA_CONTAINER_URL="http://${DOCKER_GW}:11434/api/tags"

        echo ""
        echo "  Checking Ollama reachability from containers..."
        if ! curl -sf "$OLLAMA_CONTAINER_URL" > /dev/null 2>&1; then
            echo "  ⚠  Ollama is not reachable from containers. Reconfiguring to listen on 0.0.0.0:11434..."

            if systemctl is-active ollama > /dev/null 2>&1; then
                echo "  Detected Ollama systemd service. Applying override..."
                sudo mkdir -p /etc/systemd/system/ollama.service.d
                printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' \
                    | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
                sudo systemctl daemon-reload
                sudo systemctl restart ollama
                echo "  Waiting for Ollama to restart..."
                for i in $(seq 1 30); do
                    sleep 1
                    if curl -sf "$OLLAMA_CONTAINER_URL" > /dev/null 2>&1; then
                        break
                    fi
                done
            else
                echo "  Restarting Ollama process..."
                sudo pkill -f 'ollama serve' 2>/dev/null || true
                sleep 2
                OLLAMA_HOST=0.0.0.0:11434 ollama serve >> /tmp/ollama.log 2>&1 &
                echo "  Waiting for Ollama to start..."
                for i in $(seq 1 30); do
                    sleep 1
                    if curl -sf "$OLLAMA_CONTAINER_URL" > /dev/null 2>&1; then
                        break
                    fi
                done
            fi

            if ! curl -sf "$OLLAMA_CONTAINER_URL" > /dev/null 2>&1; then
                echo ""
                echo "  ✗ Ollama is still not reachable from containers (${DOCKER_GW}:11434)."
                echo "    Try manually:"
                echo "    sudo mkdir -p /etc/systemd/system/ollama.service.d"
                echo "    printf '[Service]\nEnvironment=\"OLLAMA_HOST=0.0.0.0:11434\"\n' | sudo tee /etc/systemd/system/ollama.service.d/override.conf"
                echo "    sudo systemctl daemon-reload && sudo systemctl restart ollama"
                echo ""
                exit 1
            fi
        fi
        echo "  ✓ Ollama is reachable from containers (${DOCKER_GW}:11434)"

        echo ""
        echo "  ✓ Selected model: $SELECTED_MODEL"
        echo ""
        echo "  ──────────────────────────────────────────────────"
        echo "  Note: In the next step, please select:"
        echo "    • Provider:  Local Ollama (localhost:11434)"
        echo "    • Model:     $SELECTED_MODEL"
        echo "  ──────────────────────────────────────────────────"
        echo ""
    fi
fi

# ── 恢复并修补 Dockerfile ────────────────────────────────────────────────────
if [[ -n "${SELECTED_MODEL:-}" ]]; then
    DOCKERFILE="$NEMOCLAW_SRC/Dockerfile"
    
    # 核心修复(v13)：必须先恢复 Dockerfile 到原始状态！
    # 之前版本的脚本错误地替换了 Dockerfile 中的 URL，导致 sandbox 内部网络配置损坏。
    # 我们需要丢弃所有本地修改，确保使用官方原始的 inference.local 路由。
    cd "$NEMOCLAW_SRC"
    git checkout -- Dockerfile 2>/dev/null || true
    
    # 仅修改 ARG NEMOCLAW_MODEL，不再修改任何 URL
    sed -i "s|ARG NEMOCLAW_MODEL=.*|ARG NEMOCLAW_MODEL=${SELECTED_MODEL}|" "$DOCKERFILE"
fi

# ── 清除旧的 Docker 镜像缓存 ──────────────────────────────────────────────────
# 防止旧版本脚本生成的错误 baseUrl 被 Docker 层缓存复用
OLD_IMAGES=$(docker images --filter "reference=openshell/sandbox-from" -q 2>/dev/null || true)
if [[ -n "$OLD_IMAGES" ]]; then
    echo "$OLD_IMAGES" | xargs docker rmi -f > /dev/null 2>&1 || true
fi

# ── 预热 Ollama 模型（确保在 onboard 探测前已加载到内存）────────────────────
if [[ -n "${SELECTED_MODEL:-}" ]]; then
    echo "  Warming up Ollama model: $SELECTED_MODEL ..."
    # 发送一个空请求让模型加载到内存，并保持 30 分钟
    WARM_RESP=$(curl -sf http://localhost:11434/api/generate \
        -d "{\"model\":\"${SELECTED_MODEL}\",\"keep_alive\":\"30m\",\"prompt\":\"\"}" \
        --max-time 300 2>/dev/null | tail -1 || true)
    if echo "$WARM_RESP" | grep -q '"done":true'; then
        echo "  ✓ Model loaded into memory"
    else
        echo "  ⚠  Model warm-up timed out. Proceeding anyway (model may still be loading)."
    fi
    echo ""
fi

# ── 进入官方完整交互式 onboard ────────────────────────────────────
export NEMOCLAW_EXPERIMENTAL=1
[[ -n "${SELECTED_MODEL:-}" ]] && export NEMOCLAW_MODEL="$SELECTED_MODEL"

cd "$NEMOCLAW_SRC"
nemoclaw onboard

# ── 修复网关推理路由 (Gateway Inference Route) ────────────────────────────────
# 核心问题：onboard 第5步会使用 host.openshell.internal 创建推理 provider，
# 在部分环境（如 DGX Spark）中网关容器无法解析该域名，导致浏览器 UI 请求 LLM 时超时。
# 修复：将网关级别的 provider URL 强制替换为 Docker Bridge IP (172.17.0.1)。
if [[ -n "${SELECTED_MODEL:-}" ]]; then
    echo "  Patching gateway inference route..."
    DOCKER_GW="${DOCKER_GW:-172.17.0.1}"
    openshell provider update ollama-local --config "OPENAI_BASE_URL=http://${DOCKER_GW}:11434/v1" >/dev/null 2>&1 || true
    echo "  ✓ Gateway inference route updated to http://${DOCKER_GW}:11434/v1"
fi

# ── 打印浏览器访问地址 ────────────────────────────────────────────────────────
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-my-assistant}"

# 确保端口转发已启动
openshell forward start --background 18789 "$SANDBOX_NAME" 2>/dev/null || true

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

echo ""
echo "  ──────────────────────────────────────────────────"
echo "  Browser access:"
echo "    http://127.0.0.1:18789/"
echo ""
echo "  LAN access:"
echo "    http://${LOCAL_IP}:18789/"
echo ""
echo "  Useful commands:"
echo "    nemoclaw $SANDBOX_NAME connect        # open sandbox terminal"
echo "    nemoclaw $SANDBOX_NAME status         # check status"
echo "    nemoclaw $SANDBOX_NAME logs --follow  # follow logs"
echo ""
echo "  To switch model:"
echo "    NEMOCLAW_MODEL=llama3.3:70b NEMOCLAW_RECREATE_SANDBOX=1 bash nemoclaw-setup.sh"
echo "  ──────────────────────────────────────────────────"
echo ""
