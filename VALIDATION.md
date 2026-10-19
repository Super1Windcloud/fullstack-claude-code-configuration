# 安装验证记录

2026-10-19，macOS ARM64，Node 26.3.1，Python 3.14.6。

- 24 项自动化用例通过：配置备份/凭据保留、目标软链接保护、预览无副作用、离线不下载、托管 MCP 更新、TOML 幂等及 trust 保留、旧配置字段不复活、Testkit/Figma 允许列表。
- Antigravity 在临时 HOME 真实执行 `install.sh --dependencies core`：Testkit 26 skills、Figma 16 skills 及插件 MCP 安装成功；29 个 Python 包、118 个 npm 包安装成功。
- 从生成的 MCP 配置启动 mobile-mcp，完成 JSON-RPC initialize 和 tools/list，返回 34 个工具；未调用任何设备操作。
- full 的 Python 依赖在工作区隔离 venv 实际安装 88 个包；核心、Locust、Androguard、APKiD、apkleaks 导入通过。
- full 的 npm 锁文件实际安装 924 个包；agent-browser / Midscene / Appium / Playwright CLI 可运行。
- 在独立 APPIUM_HOME 实际安装并列出 XCUITest 12.19.1、UiAutomator2 8.7.0。
- Playwright Chromium 下载完成，headless 新建页面与 title 断言通过，浏览器已关闭。
- Homebrew 配方元数据已核对；本轮未在用户全局环境实际安装 JMeter、k6 等缺失系统包。
- 其他客户端的 MCP 配置由自动化用例验证；未声明 Codex 远程 Figma 插件的账号授权、Figma OAuth、WDA 签名、真实设备操作或付费模型调用已通过。

验证使用的依赖和浏览器保留在工作区忽略目录中供缓存复用；这些缓存不进入 Git。`--dry-run` 和运行报告显示的是安装计划/结果，不等于端到端设备能力验收。
