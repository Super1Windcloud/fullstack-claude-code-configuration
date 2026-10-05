#!/bin/bash
# PreToolUse(Bash) 全栈工程防线 (工业加固与 0ms 零 Fork 高性能版)
#
# 架构与运维说明：
# 1. 攻防实测与红队逃逸防御（复合包装器解包、命令替换穿透、敏感文件深度匹配、远程下载执行防御）
# 2. 全栈工程生命周期契约（物理禁止裸 cd、多语言增量缓存保护、状态感知）
# 3. 0ms 极速白名单短路与零 Fork 原生正则引擎（全流程杜绝外部子进程 fork，消除命令执行延迟）
# 4. 极简轻量审计日志：
#    - 存储路径：~/.claude/logs/bypass_audit.log（目录权限 0700，日志权限 0600）
#    - 记录策略：仅记录高危拦截（deny）与人工确认（ask），支持 GUARD_DRY_RUN 静默测试
#    - 自动轮转：单文件大小超过 1MB 自动轮转为 .1 归档
#    - 凭据脱敏：针对 Bearer Token、GitHub PAT 及 Base64 密钥做正则自动抹除脱敏

# 0-Fork 极速两级输入提取 (Tier 1: 纯原生无转义命令 0.05ms 解析; Tier 2: 含转义/换行长命令直接调用 jq，杜绝回溯挂起)
IFS= read -r -d '' input || true
[ -z "$input" ] && exit 0

pat_simple='"command":[[:space:]]*"([^"\\]+)"'
if [[ "$input" =~ $pat_simple ]]; then
  raw_cmd="${BASH_REMATCH[1]}"
else
  # 依赖缺失安全降级 (Fail-Closed: 若 jq 缺失则默认阻断，严防逃逸)
  command -v jq >/dev/null 2>&1 || {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"安全防线依赖(jq)缺失，为防止绕过已默认阻断"}}\n'
    exit 0
  }
  raw_cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)
fi
[ -z "$raw_cmd" ] && exit 0

LOG_DIR="$HOME/.claude/logs"
AUDIT_LOG="$LOG_DIR/bypass_audit.log"

decide() {
  local decision="$1"
  local reason="$2"

  if [ "$decision" != "allow" ] && [ -z "$GUARD_DRY_RUN" ]; then
    [ -d "$LOG_DIR" ] || mkdir -p -m 0700 "$LOG_DIR" 2>/dev/null
    # 超过 1MB 自动轮转归档
    if [ -f "$AUDIT_LOG" ] && [ "$(stat -f%z "$AUDIT_LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
      mv -f "$AUDIT_LOG" "$AUDIT_LOG.1" 2>/dev/null
    fi
    local clean_cmd="${raw_cmd//$'\n'/⏎}"
    # 基础脱敏：掩盖常见 Token、密钥字面量
    clean_cmd=$(sed -E -e 's/(bearer[[:space:]]+)[a-zA-Z0-9_\.~-]{10,}/\1[REDACTED]/gi' \
                       -e 's/(ghp_[a-zA-Z0-9]{20,}|gho_[a-zA-Z0-9]{20,})/[REDACTED]/g' \
                       -e 's/([A-Za-z0-9+/]{40,}={0,2})/[REDACTED]/g' <<<"$clean_cmd")
    printf '%s [PID:%s] [%s] %s (Reason: %s)\n' \
      "$(date +'%Y-%m-%d %H:%M:%S')" "$$" "$decision" "$clean_cmd" "$reason" >> "$AUDIT_LOG" 2>&1 </dev/null &
  fi

  local safe_r="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$decision" "$safe_r"
  exit 0
}

# 严格命令起始/连接边界正则（排除引号与空格，支持真实换行与字面量 \n，避免参数内部误伤）
NL=$'\n'
B="(^|[;&|(\`$NL]|\\\\n|\$\()[[:space:]]*"
# 通用前导命令包装器（支持 sudo/command/builtin/exec/nohup/env/nice/time/xargs 及反斜杠转义）
WRAP="(([\\/[:alnum:]_.-]*/)?(sudo|command|builtin|exec|nohup|env|nice|time|xargs)[[:space:]]+|\\\\)*"

# ---------------------------------------------------------
# 0. 极速前置白名单短路 (0ms Fast-Path for Safe Local Development Commands)
# ---------------------------------------------------------
# 仅对单条无管道重定向且参数完全安全的常规只读/开发命令瞬间放行（排除 --output 任意文件写参数）
branch_safe_opts='(--show-current|--list([[:space:]]+[a-zA-Z0-9_][a-zA-Z0-9_./-]*)?|-a|-r|-v{1,2}|-d|--delete|-m|-M|--format=[^;&|><`$]*|[a-zA-Z0-9_][a-zA-Z0-9_./-]*)'
tag_safe_opts='(-l|--list([[:space:]]+[a-zA-Z0-9_][a-zA-Z0-9_./-]*)?|-n[0-9]*|-d|--delete|--sort=[^;&|><`$]*|--format=[^;&|><`$]*|-v|--verify|-a[[:space:]]+[a-zA-Z0-9_][a-zA-Z0-9_./-]*([[:space:]]+-[m|F][[:space:]]+[^;&|><`$]+)?|[a-zA-Z0-9_][a-zA-Z0-9_./-]*)'
remote_safe_opts='(-v|--verbose|show([[:space:]]+[^;&|><`$]+)*|add[[:space:]]+[^;&|><`$]+|set-url[[:space:]]+[^;&|><`$]+)'
fast_path_pat="^[[:space:]]*(git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+(status|diff|log|show|rev-parse|rev-list|add|fetch|pull|blame|ls-files|shortlog|describe|cat-file|check-ignore|show-branch|merge-base|merge[[:space:]]+--(abort|continue)|rebase[[:space:]]+--(abort|continue|skip)|cherry-pick[[:space:]]+--(abort|continue|skip)|stash([[:space:]]+(list|show|pop|apply|push([[:space:]]+-[a-zA-Z0-9_.-]+)*))?|worktree([[:space:]]+(list|prune|add([[:space:]]+-[a-zA-Z0-9_.-]+)*([[:space:]]+[^;&|><\`\$]+)*))?)|git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+branch([[:space:]]+${branch_safe_opts})?[[:space:]]*$|git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+tag([[:space:]]+${tag_safe_opts})?[[:space:]]*$|git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+remote([[:space:]]+${remote_safe_opts})?[[:space:]]*$|git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+(checkout([[:space:]]+(-b|--))?|switch([[:space:]]+(-c|--create))?)([[:space:]]+[a-zA-Z0-9_][a-zA-Z0-9_./-]*)?[[:space:]]*$|git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]+-[a-zA-Z0-9_.-]+)*([[:space:]]+-[m|F][[:space:]]+[^;&|><\`\$]+|([[:space:]]+--amend)?([[:space:]]+--no-edit)?)$|cargo([[:space:]]+--manifest-path[=[:space:]][^[:space:]]+|[[:space:]]+-p[[:space:]]+[^[:space:]]+)*[[:space:]]+(check|test|clippy|tree|metadata|--version|build|fmt|run|doc|bench|expand|audit|add|update|search|info|nextest([[:space:]]+run)?)|just([[:space:]]+-[a-zA-Z0-9_.-]+)*([[:space:]]+(test|check|lint|fmt|build|dev|run|bench|test-.*|check-.*|--list|-l|--summary))?$|(\./)?gradlew([[:space:]]+-D[^[:space:]]+)*[[:space:]]+(:?[a-zA-Z0-9_:-]+)+|(pnpm|bun|yarn|npm)([[:space:]]+--filter[[:space:]]+[^[:space:]]+)*[[:space:]]+(test|--version|list|build|add|install|i|audit|outdated|update|create[[:space:]]+[a-zA-Z0-9_.-]+|dlx[[:space:]]+[a-zA-Z0-9_.-]+|link([[:space:]]+[a-zA-Z0-9_.-]+)?|unlink([[:space:]]+[a-zA-Z0-9_.-]+)?|exec[[:space:]]+[a-zA-Z0-9_.-]+|run[[:space:]]+[a-zA-Z0-9_-]+)|(npx|pnpx|bunx)([[:space:]]+-[a-zA-Z0-9_.-]+)*[[:space:]]+(tsc|eslint|prettier|vitest|jest|biome|tailwind|turbo|next|vite|astro|vue-tsc|prisma|drizzle-kit|playwright|cypress|shadcn|supabase|rimraf)|go([[:space:]]+[a-zA-Z0-9_.-]+)*[[:space:]]+(test|build|run|vet|fmt|version|env|list|doc|generate|mod([[:space:]]+(tidy|verify|download))?)|rustc[[:space:]]+--version|swift([[:space:]]+(test|build|run|--version))?|xcodebuild([[:space:]]+(-showsdks|-version|-list))|pod([[:space:]]+(install|update|repo[[:space:]]+update|--version))?|adb([[:space:]]+(devices|logcat|version|install([[:space:]]+-[a-zA-Z0-9_.-]+)*|push|pull|shell([[:space:]]+(am|pm|dumpsys|getprop|ls|cat))?)([[:space:]]+[^;&|><\`\$]+)*)|docker([[:space:]]+(compose([[:space:]]+(ps|logs|config|version|port|up|down|build|restart|exec|start|stop))?|ps|images|logs|inspect|version|info|build|run|exec|stop|start|restart)([[:space:]]+[^;&|><\`\$]+)*)|chmod[[:space:]]+([+]x|u[+]x|755|644)[[:space:]]+[^;&|><\`\$]+|uv([[:space:]]+(add|remove|pip|run|sync|lock|tool|init)([[:space:]]+[^;&|><\`\$]+)*)?|poetry([[:space:]]+(add|install|run|check|update)([[:space:]]+[^;&|><\`\$]+)*)?|pip3?([[:space:]]+(install|list|show|check|cache)([[:space:]]+-[a-zA-Z0-9_.-]+)*([[:space:]]+[^;&|><\`\$]+)*)|gh([[:space:]]+(pr|issue|run|workflow|repo|release)[[:space:]]+(view|list|status|diff|checks|checkout)|--version)|python3?[[:space:]]+(-V|--version|-m[[:space:]]+(unittest|pytest|py_compile))|(ruff|mypy|black|flake8|isort)([[:space:]]+[^;&|><\`\$]+)*|pytest|ls|pwd|whoami|uname|which|where|type|stat|file|echo|printf|wc|tree|sort|uniq|head|tail|jq|du|df|basename|dirname|realpath|readlink|mkdir|touch|cp|mv)([[:space:]]|$)"

if [[ "$raw_cmd" != *$'\n'* && ! "$raw_cmd" =~ ([\;\&\|\>\<\`\$]|--output) ]]; then
  # 进一步排除 publish / upload / -g 等高危字样及敏感凭据文件（确保敏感文件绝不走 Fast-Path 逃逸）
  if [[ ! "$raw_cmd" =~ (publish|upload|yank|owner|-g[[:space:]]|--global|uninstall|remove|\.env|\.ssh|\.aws|\.npmrc|\.cargo/credentials|\.netrc|\.git-credentials|keystore|\.key|\.pem|\.p12|\.jks|\.m2/settings) ]]; then
    if [[ "$raw_cmd" =~ $fast_path_pat ]]; then
      exit 0
    fi
  fi
fi

# rm / clean 产物安全判定：仅当目标全为本地项目可再生构建产物或 /tmp 目录时放行
SAFE_DIRS=" target node_modules dist build out coverage .gradle __pycache__ .next .turbo .svelte-kit .nuxt .mypy_cache .ruff_cache .tox htmlcov .pytest_cache .cache .angular .parcel-cache .docusaurus .output .venv venv .vite .astro .rollup.cache storybook-static "
rm_target_safe() {
  local t="${1//[\"\']/}" c comps
  t="${t%/\*}"; t="${t%/}"
  [[ -z "$t" || "$t" =~ (^|/)\.\.(/|$) ]] && return 1
  [[ "$t" =~ ^(/private)?/tmp/.+ || "$t" =~ ^/var/folders/.+ ]] && return 0
  # 关键防御：任何主目录、绝对系统目录绝不可作为安全产物自动放行（例如 ~/.gradle 或 ~/.cache）
  [[ "$t" =~ ^(~|\$HOME|\$\{HOME\}|/Users/|/home/|/root/|/etc/|/var/|/usr/|/bin/|/sbin/) ]] && return 1
  IFS=/ read -ra comps <<<"$t"
  for c in "${comps[@]}"; do [[ "$SAFE_DIRS" == *" $c "* ]] && return 0; done
  return 1
}

# git clean 安全判定：仅当带 -f/--force 且清理目标全为 safe 产物目录时放行
git_clean_needs_confirm() {
  [[ "$1" =~ git[[:space:]].*clean && "$1" =~ (-[a-zA-Z]*f|--force) ]] || return 1
  local seg toks i targets opts_done in_clean skip_next tk t
  while IFS= read -r seg; do
    [[ "$seg" =~ git[[:space:]].*clean && "$seg" =~ (-[a-zA-Z]*f|--force) ]] || continue
    read -ra toks <<<"$seg"
    in_clean=0; opts_done=0; targets=(); skip_next=0
    for ((i=0; i<${#toks[@]}; i++)); do
      tk="${toks[i]}"
      if ((in_clean == 0)); then
        if [[ "$tk" == "clean" && $i -gt 0 ]]; then
          in_clean=1
        fi
        continue
      fi
      if ((skip_next)); then
        skip_next=0
        continue
      fi
      if ((opts_done == 0)) && [[ "$tk" == -* ]]; then
        if [[ "$tk" == "--" ]]; then
          opts_done=1
        elif [[ "$tk" == "-e" ]]; then
          skip_next=1
        fi
        continue
      fi
      targets+=("$tk")
    done

    # 未指定任何具体路径（全局清理仓库）或指定了根/通配符，必须确认
    ((${#targets[@]} == 0)) && return 0
    for t in "${targets[@]}"; do
      [[ "$t" == "." || "$t" == "*" || "$t" == ":/*" ]] && return 0
      rm_target_safe "$t" || return 0
    done
  done < <(tr ";;&|$NL" "$NL$NL$NL$NL" <<<"$1")
  return 1
}

rm_needs_confirm() {
  [[ "$1" =~ (^|[;&|[:space:]])(/bin/)?(rm|srm)([[:space:]]|$) ]] || return 1
  local seg toks i rec opts_done targets t
  while IFS= read -r seg; do
    read -ra toks <<<"$seg"
    i=0
    # 剥离前导包装器：command, builtin, sudo, exec, nohup, env, nice, time, xargs, 子shell
    while [[ "${toks[i]}" =~ ^(\(|\{|\$\(|\`|sudo|command|builtin|exec|nohup|env|nice|time|xargs)$ ]]; do
      ((i++))
    done
    local cmd_name="${toks[i]##*/}"
    cmd_name="${cmd_name#\\}"
    case "$cmd_name" in
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
  done < <(tr ";;&|$NL" "$NL$NL$NL$NL" <<<"$1")
  return 1
}

# 剥离纯字面量 heredoc 块（若含 $ 或 ` 命令替换则坚决保留送审）
strip_heredocs() {
  local input="$1"
  if [[ "$input" == *"<<"* && ! "$input" =~ [\$\`] ]]; then
    awk '
    /<<[[:space:]]*['\''"]?[a-zA-Z0-9_]+['\''"]?/ {
      match($0, /<<[[:space:]]*['\''"]?[a-zA-Z0-9_]+['\''"]?/)
      marker=substr($0, RSTART, RLENGTH)
      gsub(/<<[[:space:]]*['\''"]?|['\''"]?/, "", marker)
      in_here=1
      next
    }
    in_here && $1 == marker {
      in_here=0
      next
    }
    !in_here { print }
    ' <<<"$input"
  else
    echo "$input"
  fi
}

# 剥离 git commit 的纯字面量 -m 参数（若含 $ 或 ` 命令替换则坚决保留送审）
strip_commit_messages() {
  local input="$1"
  if [[ "$input" =~ git[[:space:]]+.*commit && ! "$input" =~ [\$\`] ]]; then
    sed -E -e 's/-m[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)//g' \
           -e 's/--message(=|[[:space:]]+)("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)//g' <<<"$input"
  else
    echo "$input"
  fi
}

# 敏感凭据/密钥文件检测（纯原生零 Fork 引擎）
is_sensitive_read() {
  local cmd="$1"
  # 明确放行 .env.example, .env.sample, .env.template, .env.dist, .env.development, .env.dev, .env.test, .env.defaults, .env.schema, .env.ci, .env.docker, .env.mock
  [[ "$cmd" =~ \.env\.(example|sample|template|dist|development|dev|test|defaults|schema|ci|docker|mock) ]] && return 1

  # 快速预筛：若完全不含任何敏感关键词，0ms 瞬间返回
  local kw_pat="(\.env|\.npmrc|\.netrc|\.git-credentials|\.config/(gh|gcloud|op)|\.docker/config\.json|\.cargo/credentials|\.ssh|\.aws|\.kube|\.gnupg|gradle\.properties|keystore|\.pypirc|\.m2/settings|\.pem|\.p12|\.jks|\.key)"
  [[ "$cmd" =~ $kw_pat || "${cmd//[\"\']/}" =~ $kw_pat ]] || return 1

  local file_readers="(cat|head|tail|less|more|bat|cp|mv|base64|xxd|hexdump|od|tar|zip|gzip|7z|bzip2)"
  local search_tools="(grep|rg|awk|sed)"
  local all_readers="(cat|head|tail|grep|awk|less|more|bat|strings|rg|sed|jq|cp|mv|source|\.|base64|xxd|hexdump|od|openssl|tar|zip|gzip|7z|bzip2)"

  local env_cmd_pattern="${B}${WRAP}${all_readers}[[:space:]]+([^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?\.env(\.[a-zA-Z0-9_-]+)?([[:space:]\"'\''|;&]|$)"
  local global_configs="(\.npmrc|\.netrc|\.git-credentials|\.config/(gh|gcloud|op)(/.*)?|\.docker/config\.json|\.cargo/credentials.*|\.ssh(/.*)?|\.aws(/.*)?|\.kube(/.*)?|\.gnupg(/.*)?|(~|\$HOME|/Users/[^/[:space:]]+)/\.gradle/gradle\.properties|keystore\.properties|\.pypirc|\.m2/settings\.xml|\.(pem|p12|jks|keystore))([[:space:]\"'\''|;&]|$)"
  local specific_key_files="([a-zA-Z0-9_.-]*[._-])?(rsa|dsa|ed25519|ecdsa|private|priv|secret|server|client|ssl|tls|cert|auth|jwt)[a-zA-Z0-9_.-]*\.key"

  # 双重检查：原始命令与去引号命令（彻底免疫 .en""v、'id_'rsa 等字符串拼接逃逸）
  local check_cmds=("$cmd" "${cmd//[\"\']/}")
  for c in "${check_cmds[@]}"; do
    [[ "$c" =~ $env_cmd_pattern ]] && return 0
    local read_global_pat="${B}${WRAP}${all_readers}[[:space:]]+.*${global_configs}"
    [[ "$c" =~ $read_global_pat ]] && return 0
    local key_file_pat="${B}${WRAP}${file_readers}[[:space:]]+.*${specific_key_files}([[:space:]\"'\''|;&]|$)"
    [[ "$c" =~ $key_file_pat ]] && return 0
    local key_search_pat="${B}${WRAP}${search_tools}[[:space:]]+.*${specific_key_files}([[:space:]\"'\''|;&]|$)"
    [[ "$c" =~ $key_search_pat ]] && return 0
    local inline_env_pat="${B}${WRAP}(python3?|node|ruby|perl)[[:space:]].*(open|read[a-zA-Z]*)\([\"'\'].*([^/[:space:]]*/)?\.env(\.[a-zA-Z0-9_-]+)?[\"'\']"
    [[ "$c" =~ $inline_env_pat ]] && return 0
    local inline_conf_pat="${B}${WRAP}(python3?|node|ruby|perl)[[:space:]].*(open|read[a-zA-Z]*)\([\"'\'].*(${global_configs}|${specific_key_files})"
    [[ "$c" =~ $inline_conf_pat ]] && return 0
  done

  return 1
}

# 深度审计与决策主函数
audit_command() {
  local cmd="$1"
  [ -z "$cmd" ] && return 0

  # ---------------------------------------------------------
  # 1. 递归解包：遇到 eval、sh/bash/zsh -c 或 $(...) / `...` 命令替换时递归审查内层真实指令
  # ---------------------------------------------------------
  local subshell_pat='(bash|sh|zsh)[[:space:]]+(-[a-zA-Z]*c)[[:space:]]+["'\''"](.*)["'\''"]'
  local eval_pat='eval[[:space:]]+["'\''"](.*)["'\''"]'
  [[ "$cmd" =~ $subshell_pat ]] && audit_command "${BASH_REMATCH[3]}"
  [[ "$cmd" =~ $eval_pat ]] && audit_command "${BASH_REMATCH[1]}"

  # 提取 $(...) 与 `...` 内部命令递归审计（彻底防御双引号/Heredoc 内的命令替换逃逸）
  local subshell_dollar_pat='\$\(([^)]+)\)'
  local subshell_backtick_pat='`([^`]+)`'
  if [[ "$cmd" =~ $subshell_dollar_pat ]]; then
    audit_command "${BASH_REMATCH[1]}"
  fi
  if [[ "$cmd" =~ $subshell_backtick_pat ]]; then
    audit_command "${BASH_REMATCH[1]}"
  fi

  # ---------------------------------------------------------
  # 2. 绝对拒绝 (DENY)：磁盘格式化与系统级毁灭操作（原生匹配，支持包装器穿透与带引号 HOME 判定）
  # ---------------------------------------------------------
  local mkfs_pat="${B}${WRAP}(mkfs(\.[a-z0-9]+)?|diskutil[[:space:]]+(erase|zero|partition))[[:space:]]"
  if [[ "$cmd" =~ $mkfs_pat ]]; then
    decide deny "磁盘格式化/擦除操作已被全局硬性禁止"
  fi

  local dd_pat="${B}${WRAP}dd[[:space:]].*of=/dev/"
  if [[ "$cmd" =~ $dd_pat ]]; then
    decide deny "向块设备直接写入的 dd 操作已被全局硬性禁止"
  fi

  local rm_deny_pat="${B}${WRAP}(/bin/)?rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/(\*)?|~(/|\*|/\*)?|\\\$HOME(/|\*|/\*)?|\\\$\{HOME\}(/|\*|/\*)?|/Users/[^/[:space:]]+(/|\*|/\*)?)([[:space:]\"']|$)"
  local cmd_no_quotes="${cmd//[\"\']/}"
  if [[ "$cmd" =~ $rm_deny_pat || "$cmd_no_quotes" =~ $rm_deny_pat ]]; then
    decide deny "删除根目录或用户主目录已被全局硬性禁止"
  fi

  # ---------------------------------------------------------
  # 3. 预处理：剥离 heredoc 与 git commit -m 文本，防止参数误报
  # ---------------------------------------------------------
  local scan_cmd
  scan_cmd=$(strip_heredocs "$cmd")
  scan_cmd=$(strip_commit_messages "$scan_cmd")

  # ---------------------------------------------------------
  # 4. P0：工程契约执行 —— 物理级禁止裸 cd 指令 (消除成对引号字符串内的误报)
  # ---------------------------------------------------------
  local no_str_cmd
  no_str_cmd=$(sed -E -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g" <<<"$scan_cmd" 2>/dev/null || echo "$scan_cmd")
  local cd_pat="${B}${WRAP}cd([[:space:]]+|$)"
  local cd_safe_pat="${B}${WRAP}cd[[:space:]]+((/private)?/tmp|/var/folders/)"
  if [[ "$no_str_cmd" =~ $cd_pat ]]; then
    if [[ ! "$no_str_cmd" =~ $cd_safe_pat ]]; then
      decide deny "严禁使用裸 cd 命令！请遵守工程契约，改用工具自带路径参数（如 git -C <path>、pnpm --filter <pkg>、cargo --manifest-path <path>）"
    fi
  fi

  # ---------------------------------------------------------
  # 6. P0：Bash 读取敏感凭据与系统私钥
  # ---------------------------------------------------------
  local keychain_pat="${B}security[[:space:]]+find-(generic|internet)-password"
  if [[ "$cmd" =~ $keychain_pat ]]; then
    decide ask "危险操作需确认：正在尝试通过 security 读取 macOS 系统钥匙串密码"
  fi

  # 敏感环境变量全局 Dump (printenv / 无参 env)
  local standalone_env_pat="${B}${WRAP}(printenv|env)([[:space:]]*($|[;&|)]))"
  if [[ "$cmd" =~ $standalone_env_pat ]]; then
    decide ask "危险操作需确认：正在尝试通过 printenv/env 导出全量环境变量（含各类 Token 与密钥）"
  fi

  if is_sensitive_read "$cmd"; then
    decide ask "危险操作需确认：正在尝试读取敏感环境配置、Token 或密钥文件"
  fi

  # ---------------------------------------------------------
  # 7. P1：网络出站本地敏感文件上传/外泄防御 (Exfiltration)
  # ---------------------------------------------------------
  local exfil_pat="${B}(curl[[:space:]].*(-[a-zA-Z]*d|--data[a-z-]*|-F|--form)[[:space:]].*@|curl[[:space:]].*(-[a-zA-Z]*T|--upload-file)[[:space:]]|wget[[:space:]].*--post-file)"
  if [[ "$cmd" =~ $exfil_pat ]]; then
    # 排除本地回环接口、私有局域网/容器网络 (RFC 1918) 及本地内部域名联调
    local local_net_pat="(https?://)?(localhost|127\.0\.0\.1|0\.0\.0\.0|\[?::1\]?|10\.[0-9]+(\.[0-9]+){2}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|[a-zA-Z0-9_.-]+\.(local|internal|test|example)|host\.docker\.internal)(:[0-9]+)?(/|[[:space:]\"']|$)"
    if [[ ! "$cmd" =~ $local_net_pat ]]; then
      decide ask "危险操作需确认：正在尝试通过网络命令外发本地文件（curl/wget @file 或 -T）"
    fi
  fi

  # ---------------------------------------------------------
  # 8. rm 递归删除精细判定
  # ---------------------------------------------------------
  rm_needs_confirm "$cmd" && decide ask "危险操作需确认：递归删除非构建产物目录（rm -r）"

  # ---------------------------------------------------------
  # 9. Git 工作区与数据抹除防御（兼容任意前置选项参数）
  # ---------------------------------------------------------
  local GIT_OPTS="([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+"
  local git_restore_pat="${B}${WRAP}git${GIT_OPTS}restore[[:space:]]"
  if [[ "$cmd" =~ $git_restore_pat ]]; then
    local staged_pat="--staged|(^|[[:space:]])-S([[:space:]]|$)"
    local worktree_pat="--worktree|(^|[[:space:]])-W([[:space:]]|$)"
    if [[ ! "$cmd" =~ $staged_pat || "$cmd" =~ $worktree_pat ]]; then
      # 仅当全局丢弃所有工作区（含 . 或 :/* 或 *）时才确认；单文件路径恢复正常放行
      local wipe_all_pat="[[:space:]](\.|:\/\*|\*)([[:space:]]|$)"
      if [[ "$cmd" =~ $wipe_all_pat ]]; then
        decide ask "危险操作需确认：git restore 会全局丢弃所有工作区未提交改动"
      fi
    fi
  fi

  local git_checkout_wipe_pat="${B}${WRAP}git${GIT_OPTS}checkout[[:space:]]+(.*[[:space:]])?((--[[:space:]]+)?(\.|:\/\*|\*)|-[a-zA-Z]*f|--force)([[:space:]]|$)"
  if [[ "$cmd" =~ $git_checkout_wipe_pat ]]; then
    decide ask "危险操作需确认：git checkout 会丢弃当前工作区未提交改动"
  fi

  local git_clean_pat="${B}${WRAP}git${GIT_OPTS}clean[[:space:]]"
  if [[ "$cmd" =~ $git_clean_pat ]]; then
    if git_clean_needs_confirm "$cmd"; then
      decide ask "危险操作需确认：git clean -f 强制清除未跟踪文件"
    fi
  fi

  # ---------------------------------------------------------
  # 10. P1：不可逆操作、对外发布、外泄、Git/GitHub 与系统破坏规则全矩阵
  # ---------------------------------------------------------
  local rules=(
    # 批量与不可逆删除
    "${B}find[[:space:]].*(-delete|-exec[[:space:]]+(/bin/)?rm)|find 批量删除"
    "${B}xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(/bin/)?rm([[:space:]]|$)|xargs 批量删除"
    "${B}git${GIT_OPTS}reset[[:space:]].*--hard|git reset --hard 破坏性重置"
    # Git 分支、Tag、Stash 强制重置
    "${B}git${GIT_OPTS}(branch([[:space:]]+.*)?[[:space:]](-[a-zA-Z]*[Df]|--force)([[:space:]]|$)|checkout[[:space:]]+.*-B[[:space:]]+|switch[[:space:]]+.*-C[[:space:]]+|tag[[:space:]]+.*(-[a-zA-Z]*f|--force)|stash[[:space:]]+(drop|clear))|强制重置/删除分支、强制覆盖 Tag 或丢弃 Stash"
    "${B}git${GIT_OPTS}remote[[:space:]]+(remove|rm)([[:space:]]|$)|删除 git 远程仓库配置"
    "${B}git${GIT_OPTS}rebase[[:space:]]+.*-[a-zA-Z]*i|交互式 git rebase"
    # Git 深度破坏操作
    "${B}git${GIT_OPTS}reflog[[:space:]]+expire|git reflog 清理不可逆操作"
    "${B}git${GIT_OPTS}(filter-branch|filter-repo)|重写 Git 历史提交 (filter-branch/repo)"
    "${B}git${GIT_OPTS}update-ref[[:space:]]+.*-d|删除 Git 引用引用点"
    "${B}git${GIT_OPTS}gc[[:space:]]+.*--prune=now|立即剪枝 Git 垃圾回收"
    "${B}git${GIT_OPTS}worktree[[:space:]]+remove[[:space:]]+.*--force|强制删除 Git Worktree"
    "${B}git${GIT_OPTS}config[[:space:]]+.*(--global|core\.hooksPath)|修改全局 Git 配置或覆盖 hooksPath 防线"
    "${B}git[[:space:]]+.*--output[[:space:]=]|git 带有 --output 任意文件写参数"
    # 对外推送与发版操作（含任意选项参数的 git push 与 PR）
    "${B}git${GIT_OPTS}push([[:space:]]|$)|git push 代码推送至远程仓库"
    "${B}gh[[:space:]]+pr[[:space:]]+(create|close)|GitHub PR 创建或关闭操作"
    "${B}gh[[:space:]]+pr[[:space:]]+merge|GitHub PR 合并操作"
    "${B}gh[[:space:]]+gist[[:space:]]+create|创建 GitHub Gist 公开代码片段"
    "${B}gh[[:space:]]+repo[[:space:]]+(create|delete|edit.*--visibility)|GitHub 仓库创建、删除或修改公开性"
    "${B}gh[[:space:]]+release[[:space:]]+(create|delete|upload)|GitHub Release 创建、删除或上传产物"
    "${B}gh[[:space:]]+secret[[:space:]]+(set|delete)|GitHub 密钥配置或删除"
    "${B}gh[[:space:]]+workflow[[:space:]]+run|GitHub Actions 工作流远程触发执行"
    "${B}gh[[:space:]]+api[[:space:]]+.*(-X[[:space:]]+(POST|DELETE|PUT|PATCH)|--input|(-F|-f)[[:space:]]|--field)|GitHub API 数据修改或外发操作"
    # 容器与包管理破坏
    "${B}docker[[:space:]]+push|docker push 镜像推送"
    "${B}docker[[:space:]]+(system[[:space:]]+prune|(rm|volume[[:space:]]+rm|network[[:space:]]+rm)[[:space:]]+.*-[a-zA-Z]*f|compose[[:space:]]+down[[:space:]]+.*-[a-zA-Z]*v)|Docker 容器/卷/网络强制销毁或系统清理"
    "${B}brew[[:space:]]+(uninstall|remove)|Homebrew 卸载系统包"
    "${B}(npm|pnpm)[[:space:]]+(install|uninstall|i|un)[[:space:]]+.*(-g|--global)|Node 全局包安装或卸载"
    "${B}yarn[[:space:]]+global[[:space:]]+(add|remove)|Yarn 全局包操作"
    "${B}(\./)?gradlew[[:space:]]+.*(publish|upload)|Gradle 依赖发布或上传"
    "${B}(npm|pnpm|yarn|bun)[[:space:]]+publish|发布 npm 包"
    "${B}(npm|pnpm|yarn|bun)[[:space:]]+(unpublish|deprecate)|NPM 包下架或废弃操作"
    "${B}cargo[[:space:]]+(publish|yank)|发布或撤回 Rust crate"
    "${B}cargo[[:space:]]+owner|Cargo Crate 权限修改"
    "${B}(python3?[[:space:]]+-m[[:space:]]+)?twine[[:space:]]+upload|Python PyPI 包上传"
    "${B}just[[:space:]]+(release|release_local|release_with_upx|update_hash|upload|push_all)|执行项目级全量发版并推送至所有远端"
    # 系统破坏与网络执行
    "${B}(history[[:space:]]+-c|rm[[:space:]]+.*\.zsh_history)|清除 Shell 历史命令记录 (Anti-forensics)"
    "${B}(scp|rsync|sftp)[[:space:]]+.*[a-zA-Z0-9_.-]+:[^[:space:]]+|向远程主机传输数据文件 (scp/rsync/sftp)"
    "${B}(nc|ncat|netcat|socat)[[:space:]]|原始网络 Socket 发送/监听操作 (nc/socat)"
    "${B}(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)|管道直接执行远程未知脚本"
    "${B}(curl|wget)[[:space:]].*(;|&&)[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)[[:space:]]+|远程下载脚本并立即执行"
    "${B}(sh|bash|zsh)[[:space:]]+<\([[:space:]]*(curl|wget)|进程替换直接执行远程脚本"
    "${B}sudo[[:space:]]|sudo 系统提权操作"
    "${B}killall[[:space:]]|${B}kill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-1([[:space:]]|$)|批量终止系统进程"
    "${B}chmod[[:space:]]+-R[[:space:]]+[0-7]*777|递归 777 全局权限修改"
    "${B}(adb[[:space:]].*(uninstall|shell[[:space:]]+rm)|xcrun[[:space:]]+simctl[[:space:]]+erase|pod[[:space:]]+deintegrate)|清除物理/模拟器设备应用或卸载 Pod 依赖"
    # macOS 系统底层操作
    "${B}crontab[[:space:]]+.*-r|清空系统 crontab 定时任务"
    "${B}launchctl[[:space:]]+(unload|remove|bootout)|卸载或移除 launchctl 系统服务"
    "${B}osascript[[:space:]]|通过 AppleScript 执行系统脚本或弹窗"
    "${B}defaults[[:space:]]+delete|删除 macOS 用户 Defaults 系统配置"
    "${B}tmutil[[:space:]]+delete|删除 Time Machine 系统备份"
  )

  # ---------------------------------------------------------
  # 11. 聚合单正则预筛 (Aggregated Regex Pre-filter)
  # ---------------------------------------------------------
  # GitHub API GraphQL 只读查询免检：若为 gh api graphql 且不包含 mutation，则放行只读查询
  if [[ "$scan_cmd" =~ gh[[:space:]]+api[[:space:]]+graphql && ! "$scan_cmd" =~ mutation ]]; then
    scan_cmd="${scan_cmd//gh api graphql/gh_api_graphql_read_safe}"
  fi

  # 放行良性本地开发进程 killall（用于快速清理端口占用或卡死的编译/服务进程）
  local dev_procs="(node|cargo|rust-analyzer|gradle|gradlew|vite|next|webpack|esbuild|watchman|adb|python3?|uvicorn|bun|deno|nginx|caddy|emulator|redis-server|postgres|mongod|ollama|tsc|java|gunicorn|celery|flask|fastapi|ruby|puma|sidekiq|surreal|surrealdb)"
  if [[ "$scan_cmd" =~ ${B}killall([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+${dev_procs}([[:space:]]|$) ]]; then
    scan_cmd="${scan_cmd//killall/killall_dev_safe}"
  fi

  # nc / ncat 本地与私网端口健康探测免检（-z 为 Zero-I/O 模式，无任何数据外发或监听风险）
  local nc_probe_pat="${B}(nc|ncat|netcat)[[:space:]]+.*-[a-zA-Z]*z"
  if [[ "$scan_cmd" =~ $nc_probe_pat ]]; then
    local local_probe_pat="(localhost|127\.0\.0\.1|0\.0\.0\.0|\[?::1\]?|10\.[0-9]+(\.[0-9]+){2}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|[a-zA-Z0-9_.-]+\.(local|internal|test|example)|host\.docker\.internal)"
    if [[ "$scan_cmd" =~ $local_probe_pat ]]; then
      scan_cmd="${scan_cmd//nc/nc_probe_safe}"
      scan_cmd="${scan_cmd//ncat/ncat_probe_safe}"
      scan_cmd="${scan_cmd//netcat/netcat_probe_safe}"
    fi
  fi

  # 快速预筛：若未命中任何危险操作关键字，0ms 瞬间放行
  local prefilter_keywords="find|xargs|git|gh|docker|brew|npm|pnpm|yarn|bun|gradle|gradlew|cargo|twine|just|history|scp|rsync|sftp|nc|ncat|socat|curl|wget|sudo|kill|chmod|adb|xcrun|pod|crontab|launchctl|osascript|defaults|tmutil"
  if [[ ! "$scan_cmd" =~ $prefilter_keywords ]]; then
    return 0
  fi

  # 命中预筛后，在内存中纯原生遍历判定，零 Fork 提取精确拦截原因
  for r in "${rules[@]}"; do
    local pat="${r%|*}"
    if [[ "$scan_cmd" =~ $pat ]]; then
      decide ask "危险操作需确认：${r##*|}"
    fi
  done
}

# 启动深度审计
audit_command "$raw_cmd"

# 放行并退出（不产生外部审计进程）
exit 0
