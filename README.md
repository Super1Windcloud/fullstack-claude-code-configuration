# Fullstack Claude Code Configuration 🚀

一套专为多技术栈（**Rust、TypeScript、Java / Kotlin Android、Swift / iOS**）量身定制的 Claude Code 生产级配置，旨在提供**最高自由度、日常零打扰、高危硬刹车、高性能状态感知**的极致开发体验。

---

## ✨ 核心特性

### 1. 丝滑权限管理（兼顾自由与底线）
* **日常操作 100% 免确认**：
  * 构建调试：`cargo`、`pnpm/npm/yarn`、`./gradlew`、`swift`、`xcodebuild` 等命令秒级自动放行。
  * 文件操作：常规代码编辑、文件写入、目录创建、全局文本/文件检索全自动流式执行。
* **物理级高危操作精准拦截（`ask` 暂停确认）**：
  * **文件破坏**：`rm *`、`rm -rf *`、`rmdir *`、`srm *`
  * **Git 数据抹除**：`git reset --hard`、`git clean -f`、`git push --force`、`git restore`、`git branch -D`
  * **生产误发包**：`npm publish`、`pnpm publish`、`cargo yank`、`cargo publish`
  * **设备与环境重置**：`adb uninstall`、`xcrun simctl erase`、`pod deintegrate`
  * **系统特权破坏**：`sudo`、`chmod -R 777`、`killall`、`dd`、`mkfs`、篡改 `/etc` 或 `~/.ssh`
* **跨 SDK/工程无感检索 (`additionalDirectories`)**：
  * 预先授权跨项目根目录（如 `~/super`）、Android SDK (`~/Library/Android/sdk`)、Gradle 缓存 (`~/.gradle`)、Cargo Crates (`~/.cargo`)、Rustup (`~/.rustup`)、Xcode 衍生目录 (`~/Library/Developer`) 及全局包管理目录，彻底告别“超出工程目录读取确认”的弹窗打扰。

### 2. 高性能状态栏（StatusLine）
* **极速渲染**：采用单次批量 `jq` 提取 + 纯 Zsh 原生切片，性能比多子进程传统脚本提升 **5.5 倍**（单次渲染 < 10ms），彻底消除打字与高频输出时的 TUI 闪烁。
* **路径规整**：智能折叠深层目录结构，规范紧凑显示 `~/.../repo/module`。
* **Git 状态全面感知**：
  * 实时感知本地未提交改动（脏工作区）：`git:branch*`
  * 自动追踪与远程分支的超前/落后提交量：`↑N` / `↓N`（如 `git:main*↑1`）
* **上下文健康色阶预警**：
  * `> 40%`：低对比度常态灰字 `ctx:85%`；
  * `20% ~ 40%`：**亮黄提醒** `ctx:35%`；
  * `< 20%`：**高亮红色告警** `ctx:15%`，直观警示及时执行 `/compact`，防止会话爆满被强制截断。
* **模式与成本监控**：
  * `⚡bypass`：醒目标记当前会话处于无阻碍极速放行模式。
  * `💲成本实时追踪`：当会话产生花费时显示当前累计费用（如 `$0.08`），便于监控中转与 API 消耗。

### 3. 开箱即用的 Agents 与 Skills
* **Agents**：内置定制的团队多模型智能体（`ocx-gpt-5-5`, `ocx-gpt-5-6-luna`, `ocx-gpt-5-6-sol`, `ocx-gpt-5-6-terra`, `ocx-gpt-6-astra`）。
* **Skills**：集成常用生产级工具技能库（`find-skills`, `rongcloud-im`, `screenshot-to-html`）。

---

## 📁 目录结构

```text
.
├── settings.json              # 核心配置文件（已脱敏 API Token）
├── statusline-command.sh      # 高性能定制状态栏脚本
├── install.sh                 # 一键快速安装与热更新脚本
├── agents/                    # 自定义 Agent 配置集合
├── skills/                    # 扩展技能插件集合
├── .gitignore                 # 忽略运行时会话、缓存与历史数据
└── README.md                  # 详细说明文档
```

---

## 🛠️ 安装与快速应用

### 1. 克隆仓库
```bash
git clone git@github.com:Super1Windcloud/fullstack-claude-code-configuration.git ~/.claude-config
cd ~/.claude-config
```

### 2. 执行一键安装脚本
```bash
chmod +x install.sh
./install.sh
```
> `install.sh` 会自动将配置部署到 `~/.claude/`，并智能保留你本地现有的 `ANTHROPIC_AUTH_TOKEN`。

### 3. 配置你的 Token（如首次配置）
编辑 `~/.claude/settings.json`：
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://your-api-endpoint",
    "ANTHROPIC_AUTH_TOKEN": "your-real-token-here",
    "ANTHROPIC_MODEL": "claude-opus-5-5"
  }
}
```

---

## 🔒 安全与隐私声明
本开源配置中的 `settings.json` 已对私有敏感凭证（如 `ANTHROPIC_AUTH_TOKEN`）进行了脱敏占位处理。在向 GitHub 推送改动时，已配置 `.gitignore` 严防泄露会话历史、项目上下文与运行时凭证。
