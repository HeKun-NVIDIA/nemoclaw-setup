# NemoClaw 部署脚本 (NemoClaw Setup)

本项目提供了一个增强版的 **NVIDIA NemoClaw** 一键部署脚本 (`nemoclaw-setup.sh`)，专为 NVIDIA DGX Spark 以及受限网络环境下的 Ubuntu 服务器进行了优化。

## ✨ 核心特性

- **Ollama 网络自动修复**：自动检测本地 Ollama 是否运行但无法被 Docker 容器访问，并自动将其重新配置为监听 `0.0.0.0:11434`，确保沙盒内的 Agent 能正常调用本地模型。
- **自定义网络策略注入**：自动将自定义的网络策略（如 `open-network.yaml`）注入到官方 NemoClaw 的预设目录中，彻底解决沙盒无法访问外网的问题（支持 GitHub、PyPI、Docker Hub、HuggingFace 及各类国内镜像站）。
- **保留官方交互式引导**：完美保留了官方 `nemoclaw onboard` 的交互式流程，允许你在部署过程中自由选择偏好的 LLM Provider 和模型。

## 🚀 快速开始

1. **克隆本仓库：**
   ```bash
   git clone https://github.com/HeKun-NVIDIA/nemoclaw-setup.git
   cd nemoclaw-setup
   ```

2. **赋予脚本执行权限：**
   ```bash
   chmod +x nemoclaw-setup.sh
   ```

3. **运行部署脚本：**
   ```bash
   ./nemoclaw-setup.sh
   ```

### ⚠️ 重要提示：策略选择 (Policy Selection)

在运行脚本并进入 `nemoclaw onboard` 的交互式配置流程时，你将到达 **Step 7: Policy presets**（第 7 步：策略预设）。

当系统询问：
`Apply suggested presets (pypi, npm)? [Y/n/list]:`

1. 请输入 `list` 并按回车。
2. 接着输入 `pypi,npm,open-network` 并按回车。

**这一步至关重要！** 只有这样才能应用我们注入的网络策略，确保你的沙盒拥有完整的互联网访问权限。

## 📂 仓库结构

- `nemoclaw-setup.sh`: 核心部署脚本。
- `policies/`: 存放自定义策略 YAML 文件的目录。
  - `open-network.yaml`: 开放网络策略（包含常用开发站点及国内镜像加速）。
  - `news-policy.yaml`: AI 新闻与科技站点访问策略。

## 📝 许可证

本项目基于 MIT 许可证开源 - 详情请查看 [LICENSE](LICENSE) 文件。

---
**作者：** Ken He
