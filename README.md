# Fullstack Claude Code Configuration 🚀

一套专为全栈工程师（**Android / Kotlin / Gradle / Compose、Rust / Tauri、Web / TypeScript / Tailwind、Python**）量身定制的 Claude Code 生产级全局配置。

提供**最高工程自由度、日常零打扰、高危硬防线、毫秒级状态感知与依赖共享**的极致开发体验。

---

## ✨ 核心特性

### 1. 丝滑权限管理与高危物理防线
* **日常操作 100% 免确认放行**：
  * 构建与单测：`./gradlew`、`cargo`、`pnpm/npm/bun`、`python3`、`swift` 等常规编译单测命令秒级放行。
  * 文件操作：常规代码编辑、文件写入、目录创建、全局文本/符号检索全自动流式执行。
* **物理级高危操作精准拦截（触发 `ask` 强制人类确认）**：
  * **文件破坏**：`rm *`、`rm -rf *`、`rmdir *`、`srm *`
  * **Git 数据抹除**：`git reset --hard`、`git clean -fd`、`git push --force`、`git restore`、`git branch -D`
  * **误发包与高危篡改**：`npm publish`、`cargo publish`、`cargo yank`、`sudo`、`chmod -R 777`、篡改 `/etc` 或 `~/.ssh`
  * **设备与环境重置**：`adb uninstall`、`xcrun simctl erase`
* **跨 SDK / 构建缓存免确认检索 (`additionalDirectories`)**：
  * 预先授权项目父级工作区（如 `~/super`）、Android SDK (`~/Library/Android/sdk`)、Gradle 全局缓存 (`~/.gradle`)、Cargo Crates (`~/.cargo`)、Rustup (`~/.rustup`) 及前端包管理目录，彻底告别“超出工程目录读取确认”的弹窗打扰。

### 2. 毫秒级异步非阻塞状态栏 (StatusLine)
针对超大型 Monorepo（50,000+ 文件仓库如 Android 游戏主线）重构的高性能状态栏：
* **彻底根除 I/O 卡顿（< 20ms）**：
  * 采用直接读取 `.git/HEAD` 内存内容（0ms）；
  * 脏状态扫描与上下游落差检测采用**后台异步刷新（`&!`）+ 缓存机制（3s TTL）**，终端回车即时响应，告别卡顿。
* **Git Smart CWD 智能根锚定**：
  * 处于多模块极深子目录时自动锚定仓库根目录（如 `Blockymods/.../feature`），消除路径刷屏。
* **Git 特殊状态与分支透视**：
  * 变基 `[rebase]`、合并中 `[merge]`、挑拣中 `[cherry-pick]` 显式状态告警，detached HEAD 自动降级为 7 位 commit hash。
* **Token 双维度实时感知**：
  * 紧凑单行展示「余量百分比 + 已消耗绝对量」，如 `ctx:85% (75k)`。
  * 三色阶智能预警：> 40% 沉浸灰字，20%~40% **亮黄提醒**，< 20% **高亮红色告警**（提示及时 `/compact` 防止会话截断）。
* **模式标识**：`⚡bypass` 醒目标记免确认极速放行模式。

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
├── statusline-command.sh      # 毫秒级异步非阻塞定制状态栏脚本
├── CLAUDE.md                  # 全栈工程防线与交付契约
├── install.sh                 # 一键快速安装与热更新脚本
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
