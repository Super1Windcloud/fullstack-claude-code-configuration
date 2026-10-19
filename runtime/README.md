# Testkit 运行环境

默认 `install.sh` 使用 `--dependencies full`。安装声明位于 `runtime-dependencies.json`，npm 版本和依赖图分别固定在 `core/`、`full/` 的 package.json / package-lock.json；Python 依赖安装在独立 venv 中。

| 范围 | 自动准备 |
| --- | --- |
| 核心 | Testkit 的 openpyxl、PyYAML、Schemathesis、pytest；mobile-mcp；缺少时安装 Node/npm、ADB |
| 浏览器 | agent-browser、Midscene CLI、Playwright MCP、Playwright Chromium |
| iOS / Android 自动化 | Appium，独立 APPIUM_HOME 下的 XCUITest / UiAutomator2 驱动 |
| 性能 | Locust、JMeter、k6 |
| 视频 | FFmpeg / ffprobe |
| Android 逆向 | JADX、apktool、dex2jar、Vineflower、Androguard、APKiD、apkleaks、YARA、LLVM；需要时准备 SDK 命令行工具和 build-tools 36.0.0 |

系统依赖优先复用本机现有命令；macOS 缺少时通过已安装的 Homebrew 补齐。没有 Homebrew或其他平台缺少系统工具时会明确失败并报告缺口，不自动调用 sudo 或远程脚本安装包管理器。SDK 许可不代替用户接受，命令以非交互方式运行。

## 参数

```bash
/绝对路径/install.sh                       # full，默认完整准备
/绝对路径/install.sh --dependencies core   # 核心 Python + mobile-mcp
/绝对路径/install.sh --dependencies none   # 跳过运行环境/MCP 构建，仍部署配置和所选插件
/绝对路径/install.sh --dry-run             # 只展示计划，不创建文件、不下载
/绝对路径/install.sh --offline             # 部署配置并登记 MCP，不拉取插件/依赖
```

运行目录是 `~/.local/share/harness-testkit/`，其中包含 `venv/`、`node/`、`appium/`、`browsers/`、`env.sh` 和 `installation-report.json`。执行 Testkit 命令前使用：

```bash
source ~/.local/share/harness-testkit/env.sh
```

安装脚本会把这条运行约定加入对应全局指令文件的独立标记块，保留原有内容。重复安装覆盖前保留备份。Playwright MCP 与 Midscene/Puppeteer 使用已准备的浏览器入口，避免 MCP 和稳定 Playwright 使用不同浏览器 revision。

## MCP 登记

- Codex：更新 `~/.codex/config.toml` 的 `mobile-mcp` / `playwright` 表，保留其他服务器和项目信任。
- Claude Code：更新普通 HOME 与显式 CLAUDE_CONFIG_DIR 的用户 MCP 配置，保留其他服务器和凭据。
- Antigravity：合并写入 `~/.gemini/config/mcp_config.json`。
- OpenCode：合并写入 `~/.config/opencode/opencode.json` 的本地 MCP，并登记 Figma 官方远程 MCP。

core 只登记 mobile-mcp，full 另外登记 Playwright MCP。MCP 使用运行目录下的实际可执行路径，并携带 SDK、PATH 和浏览器环境。离线登记不代表对应服务已安装或可连接。

## Figma

插件安装允许列表仅有 Testkit 和 Figma。Claude Code 使用官方 marketplace 的 `figma`；Antigravity 使用 Figma 的官方 Git 仓库；Codex 使用 `figma@openai-curated`，需要对应客户端账号具备安装权限；OpenCode 使用官方远程 MCP。Figma OAuth 登录由用户在客户端完成，仓库不保存凭据。

Xcode 安装、开发者模式、设备信任、WDA 签名、业务环境及 Midscene 模型凭据仍需按目标准备。安装不会创建手机会话、部署 App、启动性能负载或调用付费模型。

来源：[Testkit 安装说明](https://github.com/winhok/testkit/blob/0c80ac38944bb70c6a60305c174dbc2a6a9767f2/docs/installation.md)、[Mobile MCP](https://github.com/mobile-next/mobile-mcp)、[Appium 驱动安装](https://appium.io/docs/en/latest/reference/cli/extensions/)、[Figma MCP](https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/)。
