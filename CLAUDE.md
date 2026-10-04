# 全局开发规范与工作偏好 (Fullstack Claude Code Guide)

## 1. 沟通与交互风格
- **简洁高效**：直接切入问题实质，避免冗长寒暄、模板套话和过度说教。
- **语言规范**：除代码标识符、专用英文术语外，优先使用自然流畅的中文进行解释、分析与交付。
- **改动明确**：对代码修改清晰说明原因与风险，避免一次性做大跨度无关重构。
- **链接规范**：引用工程中的文件与代码符号时，优先使用带有行号的点击式 Markdown 链接（如 `[PageManager.kt](file:///path/to/PageManager.kt#L10-L20)`）。

## 2. 命令执行与全栈包管理防线
- **严禁裸 `cd`**：执行任何命令行指令时，**绝对禁止使用裸 `cd` 命令**。必须始终使用工具自带路径参数（如 `git -C <path>`、`pnpm --filter <pkg>`、`cargo --manifest-path <path>`）或显式绝对路径。
- **严格尊重既有包管理器锁文件**：
  - 前端项目：存在 `pnpm-lock.yaml` 时严禁调用 `npm install` 或 `yarn`；存在 `bun.lockb` 优先使用 `bun`；
  - Android 工程：统一使用项目根目录的 `./gradlew` 驱动目标模块局部编译，避免全包 assemble；
  - Rust 工程：优先使用 `cargo check` 或针对具体 crate 进行 `cargo test -p <pkg>`，避免无缓存全量构建。
- **破坏性操作绝对防御**：严禁未经用户明确授权执行 `rm -rf`、`git reset --hard`、`git clean -fd`、`git push --force` 等不可逆指令。

## 3. 代码演进与最小代码集原则
- **最小化变更**：恪守解决问题所需的最小代码集，严禁无故大面积格式化、批量重排导入或移动既有代码位置。
- **保护既有风格与注释**：严格保留原有注释、文档与代码风格（Java 按 Java 风格，Kotlin 按 Kotlin 风格，Rust 按 Rust 风格等）。
- **增量构建友好**：遵循工程依赖隔离原则，优先通过稳定接口协作，避免增加不必要的跨层强依赖，保护工程增量编译缓存。

## 4. 自动化验证与 Git 交付契约
- **证据优先**：完成代码或配置改动后，必须执行目标模块的最小自动化验证（如语法检查、局部编译或单测），以真实执行证据证明改动的正确性，严禁无证据交付。
- **提交规范**：
  - 严格遵循 **Conventional Commits** 规范；
  - 任务交付末尾必须按以下格式输出标准的 Git 提交信息：
    ```text
    ### 5. Git Commit Message
    <type>(<scope>): <简明中文摘要>

    - 详细改动要点1
    - 详细改动要点2
    ```

## 5. Bypass 模式与隔离沙盒契约
- **审计日志追踪**：所有 Bash 执行流均静默记录至 `/tmp/claude_bypass_audit.log`，可通过 `tail -f /tmp/claude_bypass_audit.log` 实时监控后台执行轨迹。
- **高危探索与破坏性重构必须使用 Worktree**：对涉及架构迁移、大范围模块重构或高风险依赖升级的任务，严禁直接在主工作树尝试，必须在 `--worktree` 隔离沙盒中启动；利用 `symlinkDirectories` 复用编译缓存，失败可直接无损销毁。
- **核心私密资产仓库安全降级**：对涉及生产私钥、发布密钥或底层金融核心的仓库，可在项目根目录 `.claude/settings.json` 中配置 `"defaultMode": "ask"` 覆盖全局 bypass，实现分级管控。

