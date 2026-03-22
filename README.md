# 在 NVIDIA DGX Spark 上一键部署 NemoClaw + Ollama

本项目提供了一个健壮的一键安装脚本，专为在 **NVIDIA DGX Spark** 等顶级 Linux 本地算力平台上快速部署 [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) 并无缝接入本地 [Ollama](https://ollama.com/) 大语言模型而设计。

## 为什么在 DGX Spark 上部署 NemoClaw？

NVIDIA DGX Spark 搭载了最新的 **GB10 Grace Blackwell Superchip**，拥有 **1 PFLOPS** 的 FP4 AI 算力和 **128GB LPDDR5x 统一内存**。这使得它成为了运行顶级开源大模型（如 Qwen3.5 35B 或 Llama3 70B）的完美载体。

结合 NemoClaw 强大的沙盒（Sandbox）智能体框架，在 DGX Spark 上进行本地部署可以带来：
1. **极致的隐私与安全**：数据和代码完全在本地的物理机器和 Docker 沙盒内流转，零数据外泄风险。
2. **释放硬件潜能**：128GB 的统一内存可以轻松容纳超大参数模型，享受极低的推理延迟和无限的调用次数。
3. **强大的执行能力**：NemoClaw 可以利用本地网络和文件系统，在一个安全隔离的环境中编写代码、操作文件、甚至控制浏览器。

## 项目功能

1. **全自动环境准备**：自动检查 Docker 状态，下载并安装 NemoClaw CLI，并克隆官方源码仓库。
2. **智能 Ollama 集成**：自动检测本地运行的 Ollama 服务，拉取已安装的模型列表供用户交互式选择。
3. **模型预热机制**：在部署核心组件前，提前将选定的大模型加载到内存中，避免首次对话时出现超时。
4. **自动化网络路由配置**：脚本会在部署完成后自动配置网关路由，完美适配 Linux 环境下的 Docker 容器网络隔离机制，确保 Sandbox 内部能够稳定、高效地访问宿主机的 Ollama 服务。
5. **一键换模型支持**：支持通过环境变量快速切换模型并重建 Sandbox，无需繁琐的手动配置。

## 快速开始

### 1. 前置条件
请确保机器上已安装 Docker 并处于运行状态。同时，需提前安装 Ollama 并拉取所需的模型（推荐在 DGX Spark 上使用 30B 以上参数的模型，如 `qwen3.5:35b-a3b`）。

### 2. 运行一键脚本

下载脚本并执行：

```bash
bash nemoclaw-setup.sh
```

**执行流程与终端输出：**

- **模型检测与选择**：脚本会扫描本地 Ollama，并列出可用模型。
  ```text
  Detected local inference option: Ollama
  Local Ollama is running on localhost:11434

  Use local Ollama for inference? [Y/n]: Y

  Ollama models:
    1) qwen3.5:35b-a3b
    2) llama3:8b

  Choose model [1]: 1
  ```
- **网络连通性测试**：脚本会测试容器内部是否能访问宿主机的 Ollama。
  ```text
  Checking Ollama reachability from containers...
  ✓ Ollama is reachable from containers (172.17.0.1:11434)
  ```
- **进入官方 Onboard 流程**：
  - **Step 3**（创建 Sandbox）：输入 `y` 确认创建。
  - **Step 4**（选择推理提供商）：输入 `3` 选择 `Local Ollama`，随后输入模型名称（如 `qwen3.5:35b-a3b`）。
  - **Step 7**（权限策略）：直接回车应用默认建议（pypi/npm）。
- **路由修正与完成**：
  ```text
  Patching gateway inference route...
  ✓ Gateway inference route updated to http://172.17.0.1:11434/v1

  ──────────────────────────────────────────────────
  Browser access:
    http://127.0.0.1:18789/
  ──────────────────────────────────────────────────
  ```

### 3. 访问与使用

如果你在本地机器部署，直接在浏览器打开 `http://127.0.0.1:18789/` 即可。

如果部署在远程服务器（如 DGX Spark，IP 为 `192.168.8.117`），请在你的本地电脑（如 MacBook）上新建一个终端，执行 SSH 端口转发：

```bash
ssh -N -L 18789:127.0.0.1:18789 nvidia@192.168.8.117
```
随后在本地浏览器访问 `http://127.0.0.1:18789/`。

### 4. 常用管理命令

```bash
# 进入 Sandbox 终端
nemoclaw my-assistant connect

# 查看运行状态
nemoclaw my-assistant status

# 实时查看日志
nemoclaw my-assistant logs --follow

# 销毁当前 Sandbox（用于重置）
nemoclaw my-assistant destroy
```

## 高级用法：非交互式一键换模型

如果你想快速切换到另一个模型，比如目前炙手可热的国内推理大模型 **DeepSeek-R1**（DGX Spark 的 128GB 内存可以轻松运行其 70B 版本），只需在命令前加上环境变量：

```bash
NEMOCLAW_MODEL=deepseek-r1:70b NEMOCLAW_RECREATE_SANDBOX=1 bash nemoclaw-setup.sh
```
脚本会自动完成所有配置，全程无需人工干预。

## 作者
Ken He
