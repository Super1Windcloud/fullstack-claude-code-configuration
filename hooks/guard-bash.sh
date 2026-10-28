#!/bin/bash
# PreToolUse(Bash) 精简防线：仅拦截危险度 ≥90% 的不可逆 / 对外 / 凭据外泄操作
#
# 架构与运维说明：
# 1. 递归解包（sh -c / eval / $(...) / `...`）后审查真实指令
# 2. deny：磁盘格式化、块设备写入、删除根/主目录、裸 cd（工程契约）
# 3. ask：非产物目录递归删除、抹除未提交改动的 Git 操作、强推、对外发布、远程脚本执行、文件外发、长期凭据读取
# 4. 其余命令（可恢复、仅影响本地）一律放行
# 5. 审计日志：~/.claude/logs/bypass_audit.log，仅记录 deny/ask，超过 1MB 自动轮转，支持 GUARD_DRY_RUN

IFS= read -r -d '' input || true
[ -z "$input" ] && exit 0

pat_simple='"command":[[:space:]]*"([^"\\]+)"'
if [[ "$input" =~ $pat_simple ]]; then
  raw_cmd="${BASH_REMATCH[1]}"
else
  # 依赖缺失安全降级 (Fail-Closed)
  command -v jq >/dev/null 2>&1 || {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"安全防线依赖(jq)缺失，为防止绕过已默认阻断"}}\n'
    exit 0
  }
  raw_cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)
fi
[ -z "$raw_cmd" ] && exit 0

LOG_DIR="$HOME/.claude/logs"
AUDIT_LOG="$LOG_DIR/bypass_audit.log"

# macOS 自带 bash 3.2 的 ${var//pattern/} 全局替换对长串呈超线性耗时（10KB 约 40s），
# 去引号、换行替换统一交给 tr/awk 线性处理，判定结果保持一致。
strip_quotes() { printf '%s' "$1" | tr -d "\"'"; }

decide() {
  local decision="$1"
  local reason="$2"

  if [ "$decision" != "allow" ] && [ -z "$GUARD_DRY_RUN" ]; then
    [ -d "$LOG_DIR" ] || mkdir -p -m 0700 "$LOG_DIR" 2>/dev/null
    if [ -f "$AUDIT_LOG" ] && [ "$(stat -f%z "$AUDIT_LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
      mv -f "$AUDIT_LOG" "$AUDIT_LOG.1" 2>/dev/null
    fi
    local clean_cmd
    clean_cmd=$(printf '%s' "$raw_cmd" | awk 'NR > 1 { printf "⏎" } { printf "%s", $0 }')
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

# 严格命令起始/连接边界正则（支持真实换行与字面量 \n）
NL=$'\n'
B="(^|[;&|(\`$NL]|\\\\n|\$\()[[:space:]]*"
# 通用前导命令包装器
WRAP="(([\\/[:alnum:]_.-]*/)?(sudo|command|builtin|exec|nohup|env|nice|time|xargs)[[:space:]]+|\\\\)*"

# rm / clean 产物安全判定：仅当目标全为本地项目可再生构建产物或 /tmp 目录时放行
SAFE_DIRS=" target node_modules dist build out coverage .gradle __pycache__ .next .turbo .svelte-kit .nuxt .mypy_cache .ruff_cache .tox htmlcov .pytest_cache .cache .angular .parcel-cache .docusaurus .output .venv venv .vite .astro .rollup.cache storybook-static "
rm_target_safe() {
  local t="${1//[\"\']/}" c comps
  t="${t%/\*}"; t="${t%/}"
  [[ -z "$t" || "$t" =~ (^|/)\.\.(/|$) ]] && return 1
  # 同一命令内仅由 $(mktemp ...) 新建并赋值的临时目录变量（见 collect_mktemp_vars）
  if [[ "$t" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(/.*)?$ && "$MKTEMP_VARS" == *" ${BASH_REMATCH[1]} "* ]]; then
    return 0
  fi
  [[ "$t" =~ ^(/private)?/tmp/.+ || "$t" =~ ^/var/folders/.+ ]] && return 0
  # 主目录、系统绝对目录绝不作为安全产物放行（例如 ~/.gradle）
  [[ "$t" =~ ^(~|\$HOME|\$\{HOME\}|/Users/|/home/|/root/|/etc/|/var/|/usr/|/bin/|/sbin/) ]] && return 1
  IFS=/ read -ra comps <<<"$t"
  for c in "${comps[@]}"; do [[ "$SAFE_DIRS" == *" $c "* ]] && return 0; done
  return 1
}

# 收集同一条命令内只通过 $(mktemp ...) 赋值的变量名；被其他方式二次赋值的变量不视为临时目录
MKTEMP_VARS=" "
collect_mktemp_vars() {
  local name total via
  local assign_pat="(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=\\\$\\(mktemp([[:space:]]|\\))"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    total=$(grep -oE "(^|[^A-Za-z0-9_])${name}=" <<<"$1" | wc -l)
    via=$(grep -oE "(^|[^A-Za-z0-9_])${name}=\\\$\\(mktemp([[:space:]]|\\))" <<<"$1" | wc -l)
    ((total == via)) && MKTEMP_VARS+="$name "
  done < <(grep -oE "$assign_pat" <<<"$1" | sed -E 's/^[^A-Za-z_]//; s/=.*//' | sort -u)
}

# find -delete / -exec rm 判定：搜索根目录全部为构建产物或临时目录时放行，否则需确认
find_delete_needs_confirm() {
  local find_pat="${B}${WRAP}find[[:space:]].*(-delete|-exec(dir)?[[:space:]]+(/bin/)?rm([[:space:]]|$))"
  [[ "$1" =~ $find_pat ]] || return 1
  local seg toks i roots t
  while IFS= read -r seg; do
    [[ "$seg" =~ (^|[[:space:]])find[[:space:]] && "$seg" =~ (-delete|-exec(dir)?[[:space:]]+(/bin/)?rm([[:space:]]|$)) ]] || continue
    read -ra toks <<<"$seg"
    i=0
    while ((i < ${#toks[@]})) && [[ "${toks[i]##*/}" != "find" ]]; do ((i++)); done
    roots=()
    for t in "${toks[@]:i+1}"; do
      # 根目录参数止于第一个表达式（选项、括号或取反）
      [[ "$t" == -* || "$t" == "(" || "$t" == '\(' || "$t" == "!" ]] && break
      roots+=("$t")
    done
    ((${#roots[@]})) || return 0
    for t in "${roots[@]}"; do rm_target_safe "$t" || return 0; done
  done < <(tr ";;&|$NL" "$NL$NL$NL$NL" <<<"$1")
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
        [[ "$tk" == "clean" && $i -gt 0 ]] && in_clean=1
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

    # 未指定具体路径（全仓清理）或指定了根/通配符，必须确认
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
    # 剥离前导包装器
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

# 剥离 heredoc 正文：带引号定界符（<<'EOF'）的正文不做展开，一律跳过；
# 无引号定界符的正文仅在整条命令不含 $ 或 ` 时跳过，否则保留送审。起始行 << 之前的命令始终保留。
strip_heredocs() {
  local input="$1"
  if [[ "$input" != *"<<"* ]]; then
    echo "$input"
    return
  fi
  local has_subst=0
  [[ "$input" =~ [\$\`] ]] && has_subst=1
  awk -v has_subst="$has_subst" '
  !in_here && /<<-?[[:space:]]*['\''"]?[a-zA-Z0-9_]+['\''"]?/ {
    match($0, /<<-?[[:space:]]*['\''"]?[a-zA-Z0-9_]+['\''"]?/)
    raw=substr($0, RSTART, RLENGTH)
    marker=raw
    gsub(/<<-?[[:space:]]*['\''"]?|['\''"]?/, "", marker)
    quoted=(raw ~ /['\''"]/)
    keep_body=(!quoted && has_subst)
    print substr($0, 1, RSTART - 1)
    in_here=1
    next
  }
  in_here && $1 == marker {
    in_here=0
    next
  }
  in_here && !keep_body { next }
  { print }
  ' <<<"$input"
}

# 剥离 git commit 的纯字面量 -m 参数（若含 $ 或 ` 命令替换则保留送审）
strip_commit_messages() {
  local input="$1"
  if [[ "$input" =~ git[[:space:]]+.*commit && ! "$input" =~ [\$\`] ]]; then
    sed -E -e 's/-m[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)//g' \
           -e 's/--message(=|[[:space:]]+)("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)//g' <<<"$input"
  else
    echo "$input"
  fi
}

# 长期凭据/私钥文件读取检测（.env 与环境变量导出已降级放行）
is_sensitive_read() {
  local cmd="$1"
  local kw_pat="(\.npmrc|\.netrc|\.git-credentials|\.config/(gh|gcloud|op)|\.docker/config\.json|\.cargo/credentials|\.ssh|\.aws|\.kube|\.gnupg|gradle\.properties|keystore|\.pypirc|\.m2/settings|\.pem|\.p12|\.jks|\.key)"
  local cmd_nq
  cmd_nq=$(strip_quotes "$cmd")
  [[ "$cmd" =~ $kw_pat || "$cmd_nq" =~ $kw_pat ]] || return 1

  local file_readers="(cat|head|tail|less|more|bat|cp|mv|base64|xxd|hexdump|od|tar|zip|gzip|7z|bzip2)"
  local search_tools="(grep|rg|awk|sed)"
  local all_readers="(cat|head|tail|grep|awk|less|more|bat|strings|rg|sed|jq|cp|mv|source|\.|base64|xxd|hexdump|od|openssl|tar|zip|gzip|7z|bzip2)"

  local global_configs="(\.npmrc|\.netrc|\.git-credentials|\.config/(gh|gcloud|op)(/.*)?|\.docker/config\.json|\.cargo/credentials.*|\.ssh(/.*)?|\.aws(/.*)?|\.kube(/.*)?|\.gnupg(/.*)?|(~|\$HOME|/Users/[^/[:space:]]+)/\.gradle/gradle\.properties|keystore\.properties|\.pypirc|\.m2/settings\.xml|\.(pem|p12|jks|keystore))([[:space:]\"'\''|;&]|$)"
  local specific_key_files="([a-zA-Z0-9_.-]*[._-])?(rsa|dsa|ed25519|ecdsa|private|priv|secret|server|client|ssl|tls|cert|auth|jwt)[a-zA-Z0-9_.-]*\.key"

  # 双重检查：原始命令与去引号命令（免疫 'id_'rsa 等拼接逃逸）
  local check_cmds=("$cmd" "$cmd_nq")
  for c in "${check_cmds[@]}"; do
    local read_global_pat="${B}${WRAP}${all_readers}[[:space:]]+.*${global_configs}"
    [[ "$c" =~ $read_global_pat ]] && return 0
    local key_file_pat="${B}${WRAP}${file_readers}[[:space:]]+.*${specific_key_files}([[:space:]\"'\''|;&]|$)"
    [[ "$c" =~ $key_file_pat ]] && return 0
    local key_search_pat="${B}${WRAP}${search_tools}[[:space:]]+.*${specific_key_files}([[:space:]\"'\''|;&]|$)"
    [[ "$c" =~ $key_search_pat ]] && return 0
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
  # 1. 递归解包：eval、sh/bash/zsh -c、$(...) / `...`
  # ---------------------------------------------------------
  local subshell_pat='(bash|sh|zsh)[[:space:]]+(-[a-zA-Z]*c)[[:space:]]+["'\''"](.*)["'\''"]'
  local eval_pat='eval[[:space:]]+["'\''"](.*)["'\''"]'
  [[ "$cmd" =~ $subshell_pat ]] && audit_command "${BASH_REMATCH[3]}"
  [[ "$cmd" =~ $eval_pat ]] && audit_command "${BASH_REMATCH[1]}"

  local subshell_dollar_pat='\$\(([^)]+)\)'
  local subshell_backtick_pat='`([^`]+)`'
  [[ "$cmd" =~ $subshell_dollar_pat ]] && audit_command "${BASH_REMATCH[1]}"
  [[ "$cmd" =~ $subshell_backtick_pat ]] && audit_command "${BASH_REMATCH[1]}"

  # ---------------------------------------------------------
  # 2. 绝对拒绝 (DENY)：磁盘格式化与系统级毁灭操作
  # ---------------------------------------------------------
  local mkfs_pat="${B}${WRAP}(mkfs(\.[a-z0-9]+)?|diskutil[[:space:]]+(erase|zero|partition))[[:space:]]"
  [[ "$cmd" =~ $mkfs_pat ]] && decide deny "磁盘格式化/擦除操作已被全局硬性禁止"

  local dd_pat="${B}${WRAP}dd[[:space:]].*of=/dev/"
  [[ "$cmd" =~ $dd_pat ]] && decide deny "向块设备直接写入的 dd 操作已被全局硬性禁止"

  local rm_deny_pat="${B}${WRAP}(/bin/)?rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/(\*)?|~(/|\*|/\*)?|\\\$HOME(/|\*|/\*)?|\\\$\{HOME\}(/|\*|/\*)?|/Users/[^/[:space:]]+(/|\*|/\*)?)([[:space:]\"']|$)"
  local cmd_no_quotes
  cmd_no_quotes=$(strip_quotes "$cmd")
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
  # 4. 工程契约：禁止裸 cd（消除成对引号字符串内的误报）
  # ---------------------------------------------------------
  if [[ "$scan_cmd" == *cd* ]]; then
    local no_str_cmd
    no_str_cmd=$(sed -E -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g" <<<"$scan_cmd" 2>/dev/null || echo "$scan_cmd")
    local cd_pat="${B}${WRAP}cd([[:space:]]+|$)"
    local cd_safe_pat="${B}${WRAP}cd[[:space:]]+((/private)?/tmp|/var/folders/)"
    if [[ "$no_str_cmd" =~ $cd_pat && ! "$no_str_cmd" =~ $cd_safe_pat ]]; then
      decide deny "严禁使用裸 cd 命令！请遵守工程契约，改用工具自带路径参数（如 git -C <path>、pnpm --filter <pkg>、cargo --manifest-path <path>）"
    fi
  fi

  # ---------------------------------------------------------
  # 5. 长期凭据与系统私钥读取
  # ---------------------------------------------------------
  local keychain_pat="${B}security[[:space:]]+find-(generic|internet)-password"
  [[ "$cmd" =~ $keychain_pat ]] && decide ask "危险操作需确认：正在尝试通过 security 读取 macOS 系统钥匙串密码"

  is_sensitive_read "$cmd" && decide ask "危险操作需确认：正在尝试读取长期凭据、Token 或私钥文件"

  # ---------------------------------------------------------
  # 6. 网络出站本地文件外发 (Exfiltration)，排除回环与私有局域网
  # ---------------------------------------------------------
  local exfil_pat="${B}(curl[[:space:]].*(-[a-zA-Z]*d|--data[a-z-]*|-F|--form)[[:space:]].*@|curl[[:space:]].*(-[a-zA-Z]*T|--upload-file)[[:space:]]|wget[[:space:]].*--post-file)"
  if [[ "$cmd" =~ $exfil_pat ]]; then
    local local_net_pat="(https?://)?(localhost|127\.0\.0\.1|0\.0\.0\.0|\[?::1\]?|10\.[0-9]+(\.[0-9]+){2}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|[a-zA-Z0-9_.-]+\.(local|internal|test|example)|host\.docker\.internal)(:[0-9]+)?(/|[[:space:]\"']|$)"
    [[ ! "$cmd" =~ $local_net_pat ]] && decide ask "危险操作需确认：正在尝试通过网络命令外发本地文件（curl/wget @file 或 -T）"
  fi

  # ---------------------------------------------------------
  # 7. rm 递归删除非产物目录
  # ---------------------------------------------------------
  rm_needs_confirm "$cmd" && decide ask "危险操作需确认：递归删除非构建产物目录（rm -r）"

  # ---------------------------------------------------------
  # 8. Git 工作区未提交改动抹除
  # ---------------------------------------------------------
  local GIT_OPTS="([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+"
  local git_restore_pat="${B}${WRAP}git${GIT_OPTS}restore[[:space:]]"
  if [[ "$cmd" =~ $git_restore_pat ]]; then
    local staged_pat="--staged|(^|[[:space:]])-S([[:space:]]|$)"
    local worktree_pat="--worktree|(^|[[:space:]])-W([[:space:]]|$)"
    if [[ ! "$cmd" =~ $staged_pat || "$cmd" =~ $worktree_pat ]]; then
      # 仅全局丢弃（. / :/* / *）时确认；单文件恢复放行
      local wipe_all_pat="[[:space:]](\.|:\/\*|\*)([[:space:]]|$)"
      [[ "$cmd" =~ $wipe_all_pat ]] && decide ask "危险操作需确认：git restore 会全局丢弃所有工作区未提交改动"
    fi
  fi

  local git_checkout_wipe_pat="${B}${WRAP}git${GIT_OPTS}checkout[[:space:]]+(.*[[:space:]])?((--[[:space:]]+)?(\.|:\/\*|\*)|-[a-zA-Z]*f|--force)([[:space:]]|$)"
  [[ "$cmd" =~ $git_checkout_wipe_pat ]] && decide ask "危险操作需确认：git checkout 会丢弃当前工作区未提交改动"

  local git_clean_pat="${B}${WRAP}git${GIT_OPTS}clean[[:space:]]"
  if [[ "$cmd" =~ $git_clean_pat ]] && git_clean_needs_confirm "$cmd"; then
    decide ask "危险操作需确认：git clean -f 强制清除未跟踪文件"
  fi

  # ---------------------------------------------------------
  # 9. 危险度 ≥90% 规则矩阵：不可逆删除、历史重写、强推、对外发布、远程执行、提权
  # ---------------------------------------------------------
  local rules=(
    "${B}xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(/bin/)?rm([[:space:]]|$)|xargs 批量删除"
    "${B}git${GIT_OPTS}reset[[:space:]].*--hard|git reset --hard 破坏性重置"
    "${B}git${GIT_OPTS}stash[[:space:]]+(drop|clear)|丢弃 Stash"
    "${B}git${GIT_OPTS}reflog[[:space:]]+expire|git reflog 清理不可逆操作"
    "${B}git${GIT_OPTS}(filter-branch|filter-repo)|重写 Git 历史提交 (filter-branch/repo)"
    "${B}git${GIT_OPTS}update-ref[[:space:]]+.*-d|删除 Git 引用"
    "${B}git${GIT_OPTS}gc[[:space:]]+.*--prune=now|立即剪枝 Git 垃圾回收"
    "${B}git${GIT_OPTS}worktree[[:space:]]+remove[[:space:]]+.*--force|强制删除 Git Worktree"
    "${B}git${GIT_OPTS}config[[:space:]]+.*core\.hooksPath|覆盖 hooksPath 防线"
    "${B}git${GIT_OPTS}push[[:space:]]+.*(-[a-zA-Z]*f|--force|--force-with-lease|--force-if-includes|\+[a-zA-Z0-9_.-]+:|--delete|:[a-zA-Z0-9_.-]+)([[:space:]]|$)|git push 强制推送或删除远程分支"
    "${B}gh[[:space:]]+pr[[:space:]]+(create|close|merge)|GitHub PR 创建、关闭或合并"
    "${B}gh[[:space:]]+gist[[:space:]]+create|创建 GitHub Gist 公开代码片段"
    "${B}gh[[:space:]]+repo[[:space:]]+(create|delete|edit.*--visibility)|GitHub 仓库创建、删除或修改公开性"
    "${B}gh[[:space:]]+release[[:space:]]+(create|delete|upload)|GitHub Release 创建、删除或上传产物"
    "${B}gh[[:space:]]+secret[[:space:]]+(set|delete)|GitHub 密钥配置或删除"
    "${B}gh[[:space:]]+workflow[[:space:]]+run|GitHub Actions 工作流远程触发执行"
    "${B}gh[[:space:]]+api[[:space:]]+.*(-X[[:space:]]+(POST|DELETE|PUT|PATCH)|--input|(-F|-f)[[:space:]]|--field)|GitHub API 数据修改或外发操作"
    "${B}docker[[:space:]]+push|docker push 镜像推送"
    "${B}(\./)?gradlew[[:space:]]+.*(publish|upload)|Gradle 依赖发布或上传"
    "${B}(npm|pnpm|yarn|bun)[[:space:]]+(publish|unpublish|deprecate)|发布、下架或废弃 npm 包"
    "${B}cargo[[:space:]]+(publish|yank|owner)|发布、撤回 Rust crate 或修改 owner"
    "${B}(python3?[[:space:]]+-m[[:space:]]+)?twine[[:space:]]+upload|Python PyPI 包上传"
    "${B}just[[:space:]]+(release|release_local|release_with_upx|update_hash|upload|push_all)|执行项目级全量发版并推送至所有远端"
    "${B}(scp|rsync|sftp)[[:space:]]+.*[a-zA-Z0-9_.-]+:[^[:space:]]+|向远程主机传输数据文件 (scp/rsync/sftp)"
    "${B}(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)|管道直接执行远程未知脚本"
    "${B}(curl|wget)[[:space:]].*(;|&&)[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)[[:space:]]+|远程下载脚本并立即执行"
    "${B}(sh|bash|zsh)[[:space:]]+<\([[:space:]]*(curl|wget)|进程替换直接执行远程脚本"
    "${B}sudo[[:space:]]|sudo 系统提权操作"
  )

  # GitHub API GraphQL 只读查询免检
  if [[ "$scan_cmd" =~ gh[[:space:]]+api[[:space:]]+graphql && ! "$scan_cmd" =~ mutation ]]; then
    scan_cmd="${scan_cmd//gh api graphql/gh_api_graphql_read_safe}"
  fi

  # find 批量删除：仅对非产物、非临时根目录要求确认
  find_delete_needs_confirm "$scan_cmd" && decide ask "危险操作需确认：find 批量删除非构建产物目录"

  # 聚合关键字预筛：未命中直接放行
  local prefilter_keywords="find|xargs|git|gh|docker|gradlew|npm|pnpm|yarn|bun|cargo|twine|just|scp|rsync|sftp|curl|wget|sudo"
  [[ ! "$scan_cmd" =~ $prefilter_keywords ]] && return 0

  for r in "${rules[@]}"; do
    local pat="${r%|*}"
    [[ "$scan_cmd" =~ $pat ]] && decide ask "危险操作需确认：${r##*|}"
  done
}

collect_mktemp_vars "$raw_cmd"
audit_command "$raw_cmd"
exit 0
