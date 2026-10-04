#!/bin/bash
# PreToolUse(Bash) 防线：bypass 模式下仍对不可逆操作强制确认，对毁灭性操作直接拒绝。
# 融合 Claude Opus 攻防实测 + 全栈工程契约 + 极速短路 + 审计日志流 + macOS 唤醒通知

raw_cmd=$(jq -r '.tool_input.command // ""')
[ -z "$raw_cmd" ] && exit 0

decide() {
  local decision="$1"
  local reason="$2"

  # 1. 异步写入全链路审计流 (/tmp/claude_bypass_audit.log)
  printf '%s [PID:%s] [%s] %s (Reason: %s)\n' \
    "$(date +'%Y-%m-%d %H:%M:%S')" "$$" "$decision" "$raw_cmd" "$reason" >> /tmp/claude_bypass_audit.log 2>/dev/null &

  # 2. 遇到 ask 或 deny，异步唤醒 macOS 系统级气泡横幅通知
  if [ "$decision" = "ask" ]; then
    ( osascript -e 'display notification "'"$reason"'" with title "Claude Code 安全防线" subtitle "需要人工确认"' 2>/dev/null ) &
  elif [ "$decision" = "deny" ]; then
    ( osascript -e 'display notification "'"$reason"'" with title "Claude Code 物理硬拦截" subtitle "高危破坏操作已被硬性拒绝"' 2>/dev/null ) &
  fi

  jq -n --arg d "$decision" --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# ---------------------------------------------------------
# 0. 极速前置白名单短路 (0ms Fast-Path for Pure Read-Only)
# ---------------------------------------------------------
# 仅当命令完全不含管道、重定向、子 shell、链式连接符且为安全只读前缀时瞬间放行
if ! grep -Eq '[;&|><`$\n]' <<<"$raw_cmd"; then
  if grep -Eq '^[[:space:]]*(git[[:space:]]+(status|diff|log|branch|show|remote|rev-parse|rev-list)|cargo[[:space:]]+(check|test|clippy|tree|metadata|--version)|(pnpm|npm|yarn|bun)[[:space:]]+(test|--version|list)|python3?[[:space:]]+(-V|--version|-m[[:space:]]+unittest)|pytest|ls|pwd|whoami|uname|which|echo|stat|file)([[:space:]]|$)' <<<"$raw_cmd"; then
    printf '%s [PID:%s] [allow] %s (fast-path)\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$$" "$raw_cmd" >> /tmp/claude_bypass_audit.log 2>/dev/null &
    exit 0
  fi
fi

# 边界正则：支持行首、管道、链式、子 shell 以及引号内部边界
B='(^|[;&|(`"'\''[:space:]]|\$\()[[:space:]]*'

# rm 产物安全判定：仅当所有删除目标均位于可再生构建产物/临时目录时放行
SAFE_DIRS=" target node_modules dist build .gradle __pycache__ .next .turbo .pytest_cache .cache "
rm_target_safe() {
  local t="${1//[\"\']/}" c comps
  t="${t%/\*}"; t="${t%/}"
  [[ -z "$t" || "$t" =~ (^|/)\.\.(/|$) ]] && return 1
  [[ "$t" =~ ^(/private)?/tmp/.+ || "$t" =~ ^/var/folders/.+ ]] && return 0
  IFS=/ read -ra comps <<<"$t"
  for c in "${comps[@]}"; do [[ "$SAFE_DIRS" == *" $c "* ]] && return 0; done
  return 1
}

rm_needs_confirm() {
  local seg toks i rec opts_done targets t
  while IFS= read -r seg; do
    read -ra toks <<<"$seg"
    i=0
    # 剥离前导包装器：command, builtin, sudo, exec, nohup, 子shell
    while [[ "${toks[i]}" =~ ^(\(|\{|\$\(|\`|sudo|command|builtin|exec|nohup)$ ]]; do ((i++)); done
    case "${toks[i]##*/}" in
      srm) return 0 ;;
      rm) ;;
      *) continue ;;
    esac
    rec=0; opts_done=0; targets=()
    for t in "${toks[@]:i+1}"; do
      if ((opts_done == 0)) && [[ "$t" == -* ]]; then
        [[ "$t" == "--" ]] && opts_done=1
        [[ "$t" == "--recursive" || "$t" =~ ^-[a-zA-Z]*[rR] ]] && rec=1
      else
        targets+=("$t")
      fi
    done
    ((rec)) || continue
    ((${#targets[@]})) || return 0
    for t in "${targets[@]}"; do rm_target_safe "$t" || return 0; done
  done < <(tr ';&|\n' '\n\n\n\n' <<<"$1")
  return 1
}

# 核心单命令/段落深度审计函数（可递归调用）
audit_command() {
  local cmd="$1"
  [ -z "$cmd" ] && return 0

  # ---------------------------------------------------------
  # 1. 递归解包：遇到 eval 或 sh/bash/zsh -c 时提取内层命令递归审查
  # ---------------------------------------------------------
  if [[ "$cmd" =~ (bash|sh|zsh)[[:space:]]+-c[[:space:]]+[\"'\'](.*)[\"'\'] ]]; then
    local inner="${BASH_REMATCH[2]}"
    audit_command "$inner"
  fi
  if [[ "$cmd" =~ eval[[:space:]]+[\"'\'](.*)[\"'\'] ]]; then
    local inner="${BASH_REMATCH[1]}"
    audit_command "$inner"
  fi

  # ---------------------------------------------------------
  # 2. 绝对拒绝 (DENY)：磁盘格式化与系统级毁灭操作
  # ---------------------------------------------------------
  grep -Eq "${B}(sudo[[:space:]]+)?(mkfs(\.[a-z0-9]+)?|diskutil[[:space:]]+(erase|zero|partition))[[:space:]]" <<<"$cmd" && \
    decide deny "磁盘格式化/擦除操作已被全局硬性禁止"

  grep -Eq "${B}dd[[:space:]].*of=/dev/" <<<"$cmd" && \
    decide deny "向块设备直接写入的 dd 操作已被全局硬性禁止"

  grep -Eq "${B}(sudo[[:space:]]+)?(/bin/)?rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\\\$HOME|/Users/[^/[:space:]]+)/?([[:space:]\"'\']|$)" <<<"$cmd" && \
    decide deny "删除根目录或用户主目录已被全局硬性禁止"

  # ---------------------------------------------------------
  # 3. P0：工程契约执行 —— 物理级禁止裸 cd 指令
  # ---------------------------------------------------------
  if grep -Eq "${B}cd([[:space:]]+|$)" <<<"$cmd"; then
    if ! grep -Eq "${B}cd[[:space:]]+(/private)?/tmp([[:space:]/;|&]|$)|${B}cd[[:space:]]+/var/folders/" <<<"$cmd"; then
      decide deny "严禁使用裸 cd 命令！请遵守工程契约，改用工具自带路径参数（如 git -C <path>、pnpm --filter <pkg>、cargo --manifest-path <path>）"
    fi
  fi

  # ---------------------------------------------------------
  # 4. P0：防线自我保护 (Self-Defense)
  # ---------------------------------------------------------
  if grep -Eq '\.claude/(settings\.json|hooks)' <<<"$cmd"; then
    if grep -Eq "${B}(sed[[:space:]]+-i|>|>>|tee|mv|cp|rm|chmod)[[:space:]]" <<<"$cmd"; then
      decide ask "危险操作需确认：正在尝试修改或删除 Claude 核心配置文件/安全防线钩子"
    fi
  fi

  # ---------------------------------------------------------
  # 5. P0：Bash 读取敏感凭证与系统私钥
  # ---------------------------------------------------------
  grep -Eq "${B}security[[:space:]]+find-(generic|internet)-password" <<<"$cmd" && \
    decide ask "危险操作需确认：正在尝试通过 security 读取 macOS 系统钥匙串密码"

  if grep -Eq "${B}(cat|head|tail|grep|awk|less|more|bat|strings)[[:space:]].*(\.env(\.[a-zA-Z0-9_-]+)?|\.npmrc|\.netrc|\.config/gh/.*|\.docker/config\.json|\.cargo/credentials.*|gradle\.properties|\.(pem|p12|jks|keystore|key))([[:space:]\"'\']|$)" <<<"$cmd"; then
    decide ask "危险操作需确认：正在尝试读取敏感环境配置、Token 或密钥文件"
  fi

  # ---------------------------------------------------------
  # 6. P1：网络出站本地敏感文件上传/外泄防御 (Exfiltration)
  # ---------------------------------------------------------
  if grep -Eq "${B}(curl[[:space:]].*(-[a-zA-Z]*d|--data[a-z-]*|-F|--form)[[:space:]].*@|wget[[:space:]].*--post-file)" <<<"$cmd"; then
    decide ask "危险操作需确认：正在尝试通过网络命令外发本地文件（curl/wget @file）"
  fi

  # ---------------------------------------------------------
  # 7. rm 递归删除精细判定
  # ---------------------------------------------------------
  rm_needs_confirm "$cmd" && decide ask "危险操作需确认：递归删除非构建产物目录（rm -r）"

  # ---------------------------------------------------------
  # 8. Git 工作区与数据抹除防御
  # ---------------------------------------------------------
  if grep -Eq "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?restore[[:space:]]" <<<"$cmd"; then
    grep -Eq -- "--staged|(^|[[:space:]])-S([[:space:]]|$)" <<<"$cmd" && ! grep -Eq -- "--worktree|(^|[[:space:]])-W([[:space:]]|$)" <<<"$cmd" \
      || decide ask "危险操作需确认：git restore 会丢弃工作区改动"
  fi

  if grep -Eq "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?checkout[[:space:]]+(.*[[:space:]])?(\.|--|-[a-zA-Z]*f)([[:space:]]|$)" <<<"$cmd"; then
    decide ask "危险操作需确认：git checkout 会丢弃当前工作区未提交改动"
  fi

  # ---------------------------------------------------------
  # 9. P1：不可逆、对外发布与 Git 核心破坏操作
  # ---------------------------------------------------------
  rules=(
    "${B}find[[:space:]].*(-delete|-exec[[:space:]]+(/bin/)?rm)|find 批量删除"
    "${B}xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(/bin/)?rm([[:space:]]|$)|xargs 批量删除"
    "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?reset[[:space:]].*--hard|git reset --hard 破坏性重置"
    "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?clean[[:space:]].*-[a-zA-Z]*f|git clean -f 强制清除未跟踪文件"
    "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push([[:space:]].*)?[[:space:]](--force|--force-with-lease|-[a-zA-Z]*f([[:space:]]|$)|:[a-zA-Z0-9_.-]+|--tags)|git 强制推送或批量推送/删除 Tag"
    "${B}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(branch[[:space:]]+.*-[a-zA-Z]*[Df]|tag[[:space:]]+-d|stash[[:space:]]+(drop|clear))|强制删除分支/Tag 或丢弃 Stash"
    "${B}(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)|管道直接执行远程未知脚本"
    "${B}(sh|bash|zsh)[[:space:]]+<\([[:space:]]*(curl|wget)|进程替换直接执行远程脚本"
    "${B}(npm|pnpm|yarn|bun)[[:space:]]+publish|发布 npm 包"
    "${B}cargo[[:space:]]+(publish|yank)|发布或撤回 Rust crate"
    "${B}sudo[[:space:]]|sudo 系统提权操作"
    "${B}killall[[:space:]]|${B}kill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-1([[:space:]]|$)|批量终止系统进程"
    "${B}chmod[[:space:]]+-R[[:space:]]+[0-7]*777|递归 777 全局权限修改"
    "${B}(adb[[:space:]].*(uninstall|shell[[:space:]]+rm)|xcrun[[:space:]]+simctl[[:space:]]+erase|pod[[:space:]]+deintegrate)|清除物理/模拟器设备应用或卸载 Pod 依赖"
    "${B}gh[[:space:]]+(pr[[:space:]]+merge|release[[:space:]]+create|api[[:space:]]+-X[[:space:]]+(DELETE|PUT|PATCH))|GitHub PR 合并、发版或高危 API 调用"
    "${B}just[[:space:]]+(release|release_local|release_with_upx|update_hash|upload|push_all)|执行项目级全量发版并推送至所有远端"
  )

  for r in "${rules[@]}"; do
    grep -Eq "${r%|*}" <<<"$cmd" && decide ask "危险操作需确认：${r##*|}"
  done
}

# 启动深度审计
audit_command "$raw_cmd"

# 放行记录并退出
printf '%s [PID:%s] [allow] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$$" "$raw_cmd" >> /tmp/claude_bypass_audit.log 2>/dev/null &
exit 0
