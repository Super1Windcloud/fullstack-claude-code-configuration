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

### 2. 极致性能非阻塞状态栏 (StatusLine v2.6)
经过 Claude Code 2.1.285 深度源码级审计与零子进程响应式重构：
* **零子进程原生 I/O 架构 (Zero-fork Architecture)**：
  * 单次 JQ 流式解析，全流程 0 次命令替换 subshell：Token 格式化全面改用 Zsh 内置 `printf -v`，Git 探测使用原生 `read -r` 消除 `$(head)`，整机执行耗时仅 ~20ms；
  * Git 状态查询使用 `--no-optional-locks` 杜绝写入 `index.lock`，配合用户独立临时目录 `${TMPDIR:-/tmp}`、原子唯一随机临时文件与目录排他锁，彻底消除并发冲突。
* **统一指标心智模型 (Unified Used Percentage)**：
  * 状态栏内所有百分比（`ctx:38%`、`5h:55%`、`7d:85%`）全面统一为**已消耗比例**（越大越危险），杜绝“部分已用、部分剩余”的认知混乱；
  * **上下文常驻保护**：宽屏显示 `ctx:38% 75k/200k`，窄屏平滑降级为 `ctx:38%` 并与目录、分支、5h 限额一同纳入核心常驻指标，绝不丢失。
* **全栈工程生态精准标签 (Stack Badges)**：
  * 精准区分 Android 与 JVM 工程：只有当检测到 `AndroidManifest.xml` 时才标记 `[android]`，纯 Kotlin/JVM 项目标记为 `[gradle]`，彻底杜绝误标；
  * 原生支持 Bun 1.2+ 的文本格式 `bun.lock` 与旧版 `bun.lockb`；同时覆盖 `[rust]`、`[pnpm]`、`[yarn]`、`[npm]`、`[python:venv]`。
* **深度真实遥测字段集成与 Bug 根除 (Telemetry & Awareness)**：
  * **COLUMNS 宽度失效防御**：自动修复子进程中 `COLUMNS=0` 导致的宽度自适应失效，智能回退与重载；
  * **分支排版与 Detached HEAD**：调整为规范排版 `git:main*↑2 [wt:x] [rebase]`；分离头指针状态自动渲染为 `git:(hash)`；
  * **极速模式**：识别真实存在的 `fast_mode` 字段并标记 `⚡fast`；
  * **Prompt Cache 语义升级与低命中率告警**：
    * 仅在**剩余存活不足 10 分钟时黄色预警**（如 `cache:8m`），消除常驻冗余噪音；
    * 统一冷启动与过期显示为 `cache:cold`；
    * 引入官方推荐 `prompt_cache.hit_ratio` 提取：命中率低于 70% 时黄色告警 `hit:62%`，直观反映缓存击穿；
    * 实时捕捉 `prompt_cache.misses` 与击穿原因，高亮显示 `miss:2(tools,sys)`；
  * **7 天用量高阈值展示**：仅在 ≥50% 时浮现（如 `7d:55%`），≥80% 红色高亮并附带重置倒计时（如 `7d:82%→2d3h`），消除低用量噪音；
  * **Agent 标识**：在 `--agent` 模式下自动浮现青色 `@agent_name`（如 `@reviewer`）；
  * **响应式自适应布局引擎 (COLUMNS Responsive Engine)**：
    * 纯 Zsh 零子进程模式匹配 `${plain//${esc}\[[0-9;]#m/}` 与 `${(m)#}` 精确测量可见文本字符与宽字符（中文/Emoji）；
    * 窄屏下按严格优先级平滑自动降级（`session` $\to$ `[rust]` $\to$ `+45/-12` $\to$ `cache` $\to$ `hit` $\to$ `model` $\to$ `7d` $\to$ `miss` $\to$ `@agent` $\to$ `ctx_tokens` $\to$ 5h倒计时 $\to$ 多字节安全目录截断）；
    * 剔除低价值且宽度计算不准的 `⏱️` 耗时字符，核心指标绝对常驻不折行；
  * 完整布局示例：
    ```text
    hyperscoop [rust] git:main*↑1 [wt:feat-auth] @reviewer Opus 3.7·high ctx:38% 75k/200k 5h:55%→1h6m 7d:82%→2d3h cache:8m miss:2(tools,sys) +45/-12 ⚡fast
    ```
* **配套自动化回归测试套件 (`statusline-command.test.sh`)**：
  * 内置独立于被测脚本的宽度与降级断言套件，31 项测试全绿回归交付。

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
| **对外推送** | `git -c k=v push` / `git --git-dir=... push` | **ask** | ✅ **通用选项穿透**：全 options 参数任意穿透均能精确识别并拦截 |
| **外部写入** | `gh api ... -f key=val` | **ask** | ✅ **小写 -f 兼容**：兼容小写 `-f` 隐式 POST 变更拦截 |
| **制品/密钥** | `gh release upload` / `gh secret set` | **ask** | ✅ 阻止未经授权发布制品资产或写入云端密钥 |
| **容器破坏** | `docker system prune -af` / `docker rm -f` | **ask** | ✅ 阻止强制销毁容器、数据卷或批量清空系统镜像 |
| **环境泄露** | `printenv` / 独立 `env` | **ask** | ✅ 阻止导出全量系统环境变量与运行时 Token |
| **落盘执行** | `curl -o i.sh ... && bash i.sh` | **ask** | ✅ 阻止将远程未知脚本落盘后立即执行 |
| **MCP 写防御** | `mcp__figma__use_figma` (写操作) | **ask** | ✅ **MCP 状态变更防护**：拦截模型擅自批量修改设计稿或云端资源 |
| **MCP 读放行** | `mcp__figma__use_figma` (只读操作) | **放行** | ✅ **消除过度防御**：只读检查设计稿或获取图层属性无阻碍放行 |
| **API 读放行** | `gh api graphql -f query='...'` | **放行** | ✅ **消除过度防御**：放行只读 GraphQL 查询，仅在含 mutation 时拦截 |
| **分支安全删** | `git branch -d feat` / `--delete` | **放行** | ✅ **消除过度防御**：放行 Git 原生安全删除，仅拦截大写 `-D` 与 `--force` |
| **文档键放行** | `cat Presentation.key` / `sort.key` | **放行** | ✅ **消除过度防御**：精准收紧私钥正则，放行普通 Keynote 演示与数据键 |
| **本地联调** | `curl -d @req.json http://localhost:3000` | **放行** | ✅ **消除过度防御**：放行 localhost/127.0.0.1 本地回环接口文件测试 |
| **进程急救** | `killall node` / `killall cargo` | **放行** | ✅ **消除过度防御**：放行开发服务与编译进程急救，拦截系统级进程破坏 |
| **产物清理** | `rm -rf coverage` / `rm -rf out` | **放行** | ✅ **消除过度防御**：扩充测试覆盖率、SvelteKit/Nuxt/Python 缓存安全清理 |
| **0ms 极速** | `git status` / `git -C /path status` / `git log` | **放行** | ✅ **0ms Fast-Path**：支持带 `-C` 路径参数瞬间放行 |
| **0ms 极速** | `git blame` / `git ls-files` / `cargo doc` | **放行** | ✅ **Fast-Path 扩充**：扩充代码走查与文档构建只读命令 |
| **0ms 极速** | `cargo build` / `cargo fmt` / `cargo check` | **放行** | ✅ **0 Fork 极速引擎**：耗时从 400ms 降至 20ms，Rust/Gradle 日常开发极速放行 |
| **0ms 极速** | `just test` / `just check` / `just lint` | **放行** | ✅ **本地流程放行**：本地日常辅助开发任务瞬间放行，严格守住 release 发版 |
| **参数拦截** | `git diff --output=/tmp/evil.sh` | **ask** | ✅ **写参数排除**：排除 `--output` 任意文件写入风险 |
| **自保放行** | `cat ~/.claude/settings.json` | **放行** | ✅ **0 误报**：纯读取配置命令正常无感放行 |
| **范例放行** | `cat .env.example` / `cat .env.sample` | **放行** | ✅ **细分凭据防御**：放行无害模板文件，精准阻断真实敏感环境 |
| **参数剥离** | `git commit -m "fix: cd to dir and just release"` | **放行** | ✅ **纯字面量剥离**：Commit 消息含关键词 0 误报 |

---

## 📁 目录结构

```text
.
├── settings.json              # 核心配置文件（精简权限、Worktree 共享、全链路写保护）
├── statusline-command.sh      # 零子进程异步响应式状态栏（Cache Miss 击穿感知/自适应降级/原子锁）
├── CLAUDE.md                  # 全栈工程防线与交付契约
├── install.sh                 # 一键快速安装与热更新脚本
├── hooks/                     # Claude Code 核心安全防护生命周期钩子
│   ├── guard-bash.sh          # PreToolUse 递归解包深度审计与 0 Fork 极速高危拦截引擎
│   └── guard-mcp.sh           # PreToolUse MCP 工具高危写操作与外部资源变更防线
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
