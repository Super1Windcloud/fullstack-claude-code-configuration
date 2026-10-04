# Fullstack Claude Code Configuration 🚀

一套专为全栈工程师（**Android / Kotlin / Gradle / Compose、Rust / Tauri、Web / TypeScript / Tailwind、Python**）量身定制的 Claude Code 生产级全局配置。

提供**最高工程自由度、日常零打扰、高危硬防线、毫秒级状态感知与依赖共享**的极致开发体验。

---

## ✨ 核心特性

### 1. 动静态融合物理硬防线 (PreToolUse & Permissions Hardening)
在 `bypassPermissions`（全自动极速放行）模式下，通过静态权限契约与动态分词解包 Hook 实现**“日常操作 100% 免扰放行，不可逆破坏 100% 物理级强制刹车”**：

* **多层包装器解包与递归深度审计 (`hooks/guard-bash.sh`)**：
  * **剥离前导包装器**：自动识别并剥离 `command`、`builtin`、`sudo`、`xargs`、`nohup`、`exec` 等前缀；
  * **递归解包穿透审查**：遇到 `bash -c "<cmd>"`、`sh -c "<cmd>"`、`zsh -c "<cmd>"` 或 `eval "<cmd>"` 时，自动提取内层真实命令字符串递归送入审计流程，彻底解决套壳绕过；
  * **复合命令智能拆分**：保留单双引号内部边界，按 `;`、`&&`、`||`、`|` 逐段解析，彻底解决多命令拼接（如 `git restore --staged a && git restore b`）的掩护逃逸漏洞。
* **P0 级防线自我保护 (Self-Defense)**：
  * `settings.json` 静态 `deny` 彻底封死 `Edit/Write(~/.claude/settings.json)` 与 `Edit/Write(~/.claude/hooks/**)`；
  * `guard-bash.sh` 动态拦截通过 Bash 试图修改或删除 Claude 核心配置的写命令（`sed -i`、`>`、`>>`、`tee`、`mv`、`cp`、`rm`），**严防大模型自我拆解防线**。
* **P0 级敏感凭据与私钥读写全闭环防御**：
  * 阻断 Bash 与文件工具调取敏感配置：`.env*`、`~/.npmrc`、`~/.netrc`、`~/.config/gh/`、`~/.docker/config.json`、`~/.cargo/credentials*`、`gradle.properties`（私有仓库账密/签名密码）、`*.pem`、`*.p12`、`*.jks`、`*.keystore`；
  * 拦截 `security find-(generic|internet)-password` 读取 macOS Keychain 钥匙串密码。
* **P0 级全栈工程契约强制落地（物理封死违规裸 `cd`）**：
  * 严厉拦截除切换到 `/tmp` 或系统临时目录外的任何裸 `cd` 指令，物理倒逼大模型改用工具自带路径参数（如 `git -C <path>`、`pnpm --filter <pkg>`、`cargo --manifest-path <path>`）。
* **P1 级对外操作与误发布拦截**：
  * 拦截管道执行远程脚本：`curl | sh` 与 `sh <(curl ...)`；
  * 拦截 GitHub CLI 破坏性操作：`gh pr merge`、`gh release create`；
  * 拦截 Git 危险重置：`git checkout .`（无参数丢弃工作区）、`git push --force-with-lease`；
  * 拦截项目级发布脚本：`just (release|release_local|update_hash|upload|push_all)`。
* **PostToolUse 项目级单文件安全格式化 (`hooks/format-edited.sh`)**：
  * 仅使用项目已配置的本地工具（Biome / Prettier / rustfmt / gofmt / ktlint / ruff / black），严禁主观全局强加；
  * 保护存量未格式化历史代码，避免大面积无关 diff；失败时在 `/tmp/claude_format.log` 留存简短诊断。

### 2. 毫秒级异步非阻塞状态栏 (StatusLine)
针对超大型 Monorepo（50,000+ 文件仓库）重构的高性能状态栏（单次执行耗时 < 20ms）：
* **全栈工程生态轻量标签 (Stack Badges)**：
  * 0ms 自动感知当前工作区：`[android]`、`[rust]`、`[pnpm]`、`[bun]`、`[yarn]`、`[python:venv]`，避免全栈开发者用错包管理工具。
* **Git Worktree 隔离沙盒显式标识**：
  * 检测到 Worktree 沙盒时自动增加 `[wt]` 标记（如 `git:feature-xyz [wt]*`），避免混淆主仓库与隔离分支。
* **权限模式双模态实时显式感知**：
  * `⚡bypass`（高亮黄字）：当前处于免确认流式推进模式；
  * `🛡️ask`（安全绿字）：当前处于严格人机交互确认模式，看一眼状态栏末尾即可 100% 确认物理安全水位。
* **彻底根除 I/O 卡顿与并发崩溃**：
  * 采用原子排他锁与进程唯一临时文件重命名机制，彻底杜绝高频并发下的 `mv: No such file or directory`；
  * 脏状态全面感知：同步覆盖暂存区、工作区修改以及**未跟踪文件（Untracked `??`）**。
* **全景 Token、推理、用量倒计时与代码改动感知**：
  * 订阅用量与重置倒计时：当 5h 窗口用量 $\ge 50\%$ 时自动附加剩余重置时间（如 `5h:72%→1h20m`）；
  * 会话变更统计与窄屏自适应：列宽充足时动态呈现会话改动代码行数（如 `+120/-35`），小窗窄屏（列宽 $< 85$）自适应精简，杜绝多行折行；
  * 示例效果：`Blockymods [android] git:main* [wt] ↑2 Claude 3.7 Sonnet·high 剩余:78% 44k/200k 5h:62% +120/-35 ⚡bypass`。
* **异步并发刷新锁死自愈**：
  * 内置 30s 僵死锁回收机制，彻底解决后台刷新子进程被系统杀掉导致的 Git 状态冻结。

### 3. 全栈 Worktree 依赖共享缓存与环境增强
* **依赖软链接隔离与安全共享**：配置 `worktree.symlinkDirectories: ["node_modules"]`。仅共享无状态/符号隔离的 `node_modules`；**坚决不共享 `target`、`.cargo` 与 `.gradle`**，彻底规避多分支并发 `cargo check` 或 Gradle 构建触发的文件锁死锁（File Lock Contention）与产物污染。
* **环境变量强化与防死锁**：
  * `GRADLE_OPTS`: 默认开启 Gradle Daemon、并发编译与构建缓存，消除冷启动等待；
  * `GIT_TERMINAL_PROMPT=0` 与 `GIT_EDITOR=true`: 强制进入非交互式 Git 模式，遇 non-fast-forward merge 或 rebase 自动静默完成，彻底杜绝终端挂起死锁；
  * `PAGER: cat`: 彻底避免 Git 命令进入 `less` 分页导致会话交互死锁；
  * `HOMEBREW_NO_AUTO_UPDATE=1`: 消除 brew 执行时的漫长自动检查等待；
  * 精简无益变量：移除了冗余的 `FORCE_COLOR` 与 `CARGO_TERM_COLOR`（避免 ANSI 转义字符浪费 LLM Token）、移除 macOS 无效的 `DEBIAN_FRONTEND`、移除会导致 `pnpm install` 报 frozen-lockfile 错误的 `CI=1`。

### 4. 全局工程交付契约 (CLAUDE.md)
* **严禁裸 `cd`**：强制使用工具自带路径参数（如 `git -C <path>`、`pnpm --filter <pkg>`、`cargo --manifest-path <path>`），保护执行稳定性；
* **最小化变更集**：恪守解决问题所需的最小代码集，严禁跨模块随意重构或格式化破坏缓存；
* **证据优先自动化验证**：严禁无证据交付，改动后必须执行目标模块最小语法编译或单测；
* **结构化 Commit 规范**：全自动化输出标准的 Conventional Commits 格式日志。

---

## 🛡️ 攻防基准自动化回归测试实测矩阵 (60/60 全项通过)

以下为使用自动化回归测试套件对融合加固版 `guard-bash.sh` 真实执行判定的完整实测输出（覆盖系统毁灭硬核 DENY、包装器穿透、命令替换提取、敏感凭据深度路径匹配、Git/系统层破坏拦截与引号误报消除）：

| 分类 | 测试命令 (Test Command) | 实测判定 | 防御目标与拦截理由 |
| :--- | :--- | :---: | :--- |
| **高危拦截** | `rm -rf ~` / `rm -rf ~/*` | **deny** | ✅ 系统级毁灭性硬拦截（禁止清空主目录） |
| **高危拦截** | `rm -rf "$HOME"` / `rm -rf "${HOME}"` | **deny** | ✅ **引号与变量穿透**：带双引号的 HOME 变量删除精准识别 |
| **高危拦截** | `command rm -rf ~` / `\rm -rf ~` | **deny** | ✅ **包装器穿透**：`command`/反斜杠转义均被 DENY 斩杀 |
| **高危拦截** | `bash -c "rm -rf ~"` / `env rm -rf ~` | **deny** | ✅ **解包穿透**：子 Shell 与 env 包装内层命令递归深度审查 |
| **高危拦截** | `git commit -m "$(rm -rf ~)"` | **deny** | ✅ **命令替换穿透**：提取 `$(...)` 内层命令，绝不因 `-m` 逃逸 |
| **契约执行** | `cd /Users/super/demo` / `builtin cd /` | **deny** | ✅ 物理严禁裸 `cd`，强制使用自带路径参数 |
| **契约误报** | `echo "a; cd b"` | **放行** | ✅ **引号内字面量消除**：字符串内的分号不误报为裸 `cd` |
| **契约执行** | `echo "a"; cd b` | **deny** | ✅ 引号外的命令连接符依然精准捕获裸 `cd` |
| **凭据读取** | `cat ~/.ssh/id_rsa` / `cat ~/.aws/credentials` | **ask** | ✅ 阻止读取 SSH 私钥与 AWS 云厂商核心凭据 |
| **凭据读取** | `cat ~/.kube/config` / `cat ~/.git-credentials` | **ask** | ✅ 阻止读取 Kubernetes 证书与 Git 明文密码 |
| **凭据读取** | `cat ~/.config/gcloud/credentials.db` | **ask** | ✅ 阻止读取 Google Cloud CLI 登录数据库凭据 |
| **凭据读取** | `cat local.properties` / `cat keystore.properties` | **ask** | ✅ 阻止读取 Android 私有 SDK 路径与签名证书密码 |
| **凭据读取** | `cat .env` / `grep -r API_KEY .env.local` | **ask** | ✅ 阻止搜索/读取工具调取敏感环境配置 |
| **凭据读取** | `cat ~/.npmrc` / `cat ~/.config/gh/hosts.yml` | **ask** | ✅ 阻止读取全局 NPM/GitHub CLI 访问 Token 凭证 |
| **凭据读取** | `cat < .env` / `source .env` | **ask** | ✅ 阻止 Shell 输入重定向与环境变量注入外泄 |
| **产物清理** | `rm -rf target` | **放行** | ✅ 本地可再生构建产物目录安全快速清理 |
| **目录删除** | `env rm -rf src` / `\rm -rf src` / `nice rm -rf src` | **ask** | ✅ **包装器统一**：env/nice/反斜杠包装的源码删除需确认 |
| **解包穿透** | `git commit -m "$(git reset --hard)"` | **ask** | ✅ 提取 `-m` 双引号内命令替换子指令送审拦截 |
| **解包穿透** | `sh -c "git reset --hard"` / `eval "rm -rf src"` | **ask** | ✅ 子 Shell 与 eval 内层危险指令精准命中 |
| **对外操作** | `git push` / `git push origin main` | **ask** | ✅ **普通代码推送**：杜绝非明确授权的代码外发 |
| **对外操作** | `gh pr create --title test` / `gh pr merge 12` | **ask** | ✅ 阻止自动化发起或合并 GitHub Pull Request |
| **对外操作** | `docker push my-repo/app:latest` | **ask** | ✅ 阻止容器镜像私自推送至镜像仓库 |
| **对外操作** | `./gradlew publish` / `npm unpublish` | **ask** | ✅ 阻止 Android/Java 库发布与 NPM 包下架 |
| **对外操作** | `cargo owner --add alice` | **ask** | ✅ 阻止修改 Rust Crate 仓库 Owner 权限 |
| **Git 破坏** | `git reflog expire --expire=now --all` | **ask** | ✅ 阻止不可逆清空 Git reflog 操作日志 |
| **Git 破坏** | `git filter-branch` / `git filter-repo` | **ask** | ✅ 阻止重写 Git 历史提交产生不可逆分叉 |
| **Git 破坏** | `git update-ref -d refs/heads/feature` | **ask** | ✅ 阻止直接删除底层 Git 引用点 |
| **Git 破坏** | `git gc --prune=now` | **ask** | ✅ 阻止立即剪枝清空悬空对象 |
| **Git 破坏** | `git worktree remove --force my-wt` | **ask** | ✅ 阻止强制删除隔离工作树 |
| **Git 破坏** | `git config --global user.name evil` | **ask** | ✅ 阻止修改全局 Git 配置或篡改 core.hooksPath |
| **系统底层** | `crontab -r` | **ask** | ✅ 阻止清空系统 crontab 定时任务 |
| **系统底层** | `launchctl unload ...` | **ask** | ✅ 阻止卸载或关闭系统常驻后台守护服务 |
| **系统底层** | `osascript -e 'display dialog ...'` | **ask** | ✅ 阻止通过 AppleScript 执行系统弹窗或宿主提权 |
| **系统底层** | `defaults delete com.apple.finder` | **ask** | ✅ 阻止清除 macOS 用户 Defaults 系统偏好 |
| **系统底层** | `tmutil delete /Volumes/Backup` | **ask** | ✅ 阻止删除 Time Machine 系统快照备份 |
| **0ms 极速** | `git status` / `git -C /path status` / `git log -n 5` | **放行** | ✅ **0ms Fast-Path**：支持带 `-C` 路径参数瞬间放行 |
| **0ms 极速** | `cargo check` | **放行** | ✅ **0ms Fast-Path**：Rust 语法增量检查瞬间放行 |
| **参数拦截** | `git diff --output=/tmp/evil.sh` | **ask** | ✅ **写参数排除**：排除 `--output` 任意文件写入风险 |
| **自保放行** | `cat ~/.claude/settings.json` | **放行** | ✅ **0 误报**：纯读取配置命令正常无感放行 |
| **参数剥离** | `git commit -m "fix: cd to dir and just release"` | **放行** | ✅ **纯字面量剥离**：Commit 消息含关键词 0 误报 |

---

## 📁 目录结构

```text
.
├── settings.json              # 核心配置文件（精简权限、Worktree 共享、全链路写保护）
├── statusline-command.sh      # 毫秒级异步非阻塞定制状态栏脚本（双模态感知/防并发碰撞）
├── CLAUDE.md                  # 全栈工程防线与交付契约
├── install.sh                 # 一键快速安装与热更新脚本
├── hooks/                     # Claude Code 核心安全与格式化生命周期钩子
│   ├── guard-bash.sh          # PreToolUse 递归解包深度审计与高危拦截引擎
│   └── format-edited.sh       # PostToolUse 项目级单文件安全格式化与变更保护
├── .gitignore                 # 忽略运行时会话、缓存与历史数据
└── README.md                  # 详细架构、攻防矩阵与说明文档
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
本开源配置已全面覆盖 `bypassPermissions` 下的命令递归解包、防线自保、密钥防窃与防死锁机制，开箱即支持 Claude Pro 官方订阅与官方 API，严防凭据与工作区破坏。
