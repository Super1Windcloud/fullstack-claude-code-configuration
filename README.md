# Fullstack Claude Code Configuration 🚀

一套专为全栈工程师（**Android / Kotlin / Gradle / Compose、Rust / Tauri、Web / TypeScript / Tailwind、Python**）量身定制的 Claude Code 生产级全局配置。

提供**最高工程自由度、日常零打扰、高危硬防线、毫秒级状态感知与依赖共享**的极致开发体验。

---

## ✨ 核心特性

### 1. 丝滑权限管理与动静态物理硬防线 (Hooks & Permissions)
* **日常操作 100% 免确认放行**：
  * 构建与单测：`./gradlew`、`cargo`、`pnpm/npm/bun`、`python3`、`swift` 等常规编译单测命令秒级放行。
  * 文件操作：常规代码编辑、文件写入、目录创建、全局文本/符号检索全自动流式执行。
* **PreToolUse 安全审计 Hook (`hooks/guard-bash.sh`)**：
  * **复合命令智能拆分**：保留单双引号内部边界，按 `;`、`&&`、`||`、`|` 逐段解析，彻底解决多命令拼接（如 `git restore --staged a && git restore b`）的掩护逃逸漏洞。
  * **Git 全局参数穿透解析**：精准处理 `-C "path with space"`、`--no-pager`、`-c key=value` 等任意 Git 全局前置参数，无死角拦截 `git reset --hard`、`git clean -f`、`git push --force` 与触碰工作区的 `git restore`。
  * **安全目录白名单收紧**：递归删除仅对 basename 严格匹配构建产物（`target`、`dist`、`build`、`.gradle`、`node_modules` 等）或 `/tmp` 临时路径放行，杜绝父级路径包含 `build` 导致误放行的风险。
* **PostToolUse 项目级单文件安全格式化 (`hooks/format-edited.sh`)**：
  * 仅使用项目已配置的本地工具（Biome / Prettier / rustfmt / gofmt / ktlint），严禁主观全局强加；
  * 保护存量未格式化历史代码，避免大面积无关 diff；失败时在 `/tmp/claude_format.log` 留存简短诊断。

### 2. 毫秒级异步非阻塞状态栏 (StatusLine)
针对超大型 Monorepo 重构的高性能状态栏：
* **彻底根除 I/O 卡顿与并发崩溃**：
  * 采用原子排他锁与进程唯一临时文件重命名机制，彻底杜绝高频并发下的 `mv: No such file or directory`；
  * 脏状态全面感知：同步覆盖暂存区、工作区修改以及**未跟踪文件（Untracked `??`）**。
* **子代理协议标准解耦**：
  * 移除容易引起协议不匹配的 `subagentStatusLine`，恢复官方原生子代理任务进度跟踪。
* **全景 Token、推理与费用感知**：
  * 补齐回退路径中的输入、创建与缓存读取 Token 完整和（避免被漏计为极小值）；
  * 示例效果：`hyperscoop  git:main* ↑2  Claude 3.7 Sonnet·medium  剩余:60% 80k/200k  ⚡bypass  ~$1.23`（费用加 `~` 明确估算属性）。

### 3. 全栈 Worktree 依赖共享缓存
* 配置 `worktree.symlinkDirectories: ["node_modules", ".gradle", "target", ".cargo"]`；
* 在 Claude Code 中使用 `--worktree` 或并行分支开发时，多语言大型构建依赖目录通过软链接直接复用，**无需重复 `cargo build` 或 Gradle 重建索引，避免磁盘空间膨胀**。

### 4. 全局工程交付契约 (CLAUDE.md)
* **严禁裸 `cd`**：强制使用工具自带路径参数（如 `git -C <path>`、`pnpm --filter <pkg>`、`cargo --manifest-path <path>`），保护执行稳定性；
* **最小化变更集**：恪守解决问题所需的最小代码集，严禁跨模块随意重构或格式化破坏缓存；
* **证据优先自动化验证**：严禁无证据交付，改动后必须执行目标模块最小语法编译或单测；
* **结构化 Commit 规范**：全自动化输出标准的 Conventional Commits 格式日志。

---

## 📁 目录结构

```text
.
├── settings.json              # 核心配置文件（权限策略、Worktree 共享、IDE 协同）
├── statusline-command.sh      # 毫秒级异步非阻塞定制状态栏脚本（防并发碰撞/全Token感知）
├── CLAUDE.md                  # 全栈工程防线与交付契约
├── install.sh                 # 一键快速安装与热更新脚本
├── hooks/                     # Claude Code 核心安全与格式化生命周期钩子
│   ├── guard-bash.sh          # PreToolUse 复合命令精准阻断与危险拦截引擎
│   └── format-edited.sh       # PostToolUse 项目本地格式化与已有改动保护
├── .gitignore                 # 忽略运行时会话、缓存与历史数据
└── README.md                  # 详细架构与说明文档
```

---

## 🛠️ 安装与快速应用

### 1. 克隆仓库
```bash
git clone git@github.com:Super1Windcloud/fullstack-claude-code-configuration.git ~/.claude-config
```

### 2. 执行一键安装脚本
```bash
bash ~/.claude-config/install.sh
```
> `install.sh` 会自动将配置部署到 `~/.claude/`，并智能展开路径至当前用户主目录。

### 3. 登录与使用
```bash
claude login
# 选择 Claude account with subscription (Pro, Team) 即可开启纯净极速全栈开发！
```

---

## 🔒 安全与隐私声明
本开源配置已剔除所有旧版第三方代理与本地硬件指纹，开箱即支持 Claude Pro 官方订阅与官方 API，严防泄露私有凭据与会话历史。
