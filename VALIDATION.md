# 安装验证记录

## Scrcpy MCP 还原补缺验证（2026-10-19）

- `python3 -B -m unittest discover -s tests -v`：30 项通过；覆盖 Scrcpy 登记、普通 HOME 与 CLAUDE_CONFIG_DIR 两种路径、其他 MCP/凭据保留和跨 agent 隔离。
- core/full 均锁定 `scrcpy-mcp = 0.5.0`；既有依赖版本未改变，core 最低 Node 版本同步为 24。
- 在本仓库 `runtime/core/` 执行 `npm ci --ignore-scripts --no-audit --no-fund` 成功，安装 155 个包。由该目录实际启动 Scrcpy MCP，JSON-RPC initialize 与 tools/list 成功，返回 39 个工具；其 serverInfo 自报版本为 0.0.0，npm 包版本核对为 0.5.0。
- 未调用设备工具；未在本机 Claude 配置上执行完整安装；测试环境中的安装不代表真实设备能力验收。FFmpeg optional 安装脚本未执行。


## 单 agent 安装隔离验证（2026-10-19）

- `python3 -B -m unittest discover -s /Users/super/super/fullstack-claude-code-configuration/tests`：29 项通过。
- 真实 shell 入口验证：默认仅部署自身配置与 MCP；保留其他 agent、`~/.agents/`、其他 agent 的 Testkit 环境及旧共享运行文件。
- 跨 agent 的 `--only` 在写入前拒绝，混合选择和 `--repo` 中的旧跨 agent 范围均不能扩大操作范围。同步忽略其他 agent 的无效配置；预览不执行其他 agent 的插件 CLI，且不写入。
- 配置部署使用临时 HOME 离线执行；未在用户全局环境重装依赖、执行联网插件安装或验证客户端会话。

以下为此前的依赖与工具验证记录。


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

## mitmproxy MCP 验证（2026-10-20）

- `claude` 本机配置已增量接入 `mitmproxy-mcp==0.6.1`，Python 3.13，附加 `mcp<2` 兼容约束。安装脚本已纳入完整安装流程，也可独立执行。
- `python3 -B -m unittest discover -s tests -q`：37 项通过。其中新增 7 项覆盖配置保留与备份、重复执行、dry-run、依赖失败保护、配置/运行目录软链接防御、缺少 uvx 和所属客户端边界。
- 读取本机真实 MCP 启动配置并执行 stdio `initialize`、`tools/list`、`list_rules`：全部通过，发现 25 个工具。
- 对照修改前备份作结构比较：除新增 MCP 外，原有配置完整保留；备份不入库。
- `claude mcp get mitmproxy-mcp`：用户级服务 Connected。
- 验证未更改系统代理与证书信任；真实设备、HTTPS 信任配置和外部业务抓包不属于本次验收。新客户端会话加载此 MCP。
