#!/bin/bash
# PreToolUse(Bash) 防线：bypass 模式下仍对不可逆操作强制确认，对毁灭性操作直接拒绝。
cmd=$(jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && exit 0

decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

B='(^|[;&|(`]|\$\()[[:space:]]*'

# 一票否决：磁盘/系统级毁灭操作 (deny)
grep -Eq "${B}(sudo[[:space:]]+)?(mkfs(\.[a-z0-9]+)?|diskutil[[:space:]]+(erase|zero|partition))[[:space:]]" <<<"$cmd" && decide deny "磁盘格式化/擦除操作已被全局禁止"
grep -Eq "${B}dd[[:space:]].*of=/dev/" <<<"$cmd" && decide deny "向块设备写入的 dd 已被全局禁止"
grep -Eq "${B}(sudo[[:space:]]+)?(/bin/)?rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\\\$HOME|/Users/[^/[:space:]]+)/?([[:space:]]|$)" <<<"$cmd" && decide deny "删除根目录或用户主目录已被全局禁止"

# 安全目录白名单（仅末尾目录名严格匹配或 /tmp 路径）
SAFE_BASENAMES=" target dist build .gradle __pycache__ .next .turbo .pytest_cache .cache out .output "
rm_target_safe() {
  local raw="$1"
  raw="${raw%\"}"; raw="${raw#\"}"
  raw="${raw%\'}"; raw="${raw#\'}"
  raw="${raw%/\*}"; raw="${raw%/}"

  [[ -z "$raw" || "$raw" =~ (^|/)\.\.(/|$) ]] && return 1
  [[ "$raw" =~ ^(/private)?/tmp/.+ || "$raw" =~ ^/var/folders/.+ ]] && return 0

  local base="${raw##*/}"
  for safe in $SAFE_BASENAMES; do
    [ "$base" = "$safe" ] && return 0
  done
  return 1
}

# 复合命令安全切分器：保留单双引号内部字符，按 ; && || | & \n 切分子命令
split_commands() {
  local str="$1"
  local len=${#str} in_sq=0 in_dq=0 esc=0 cur="" i ch
  for ((i=0; i<len; i++)); do
    ch="${str:i:1}"
    if ((esc)); then cur+="$ch"; esc=0; continue; fi
    if [ "$ch" = "\\" ] && ((!in_sq)); then cur+="$ch"; esc=1; continue; fi
    if [ "$ch" = "'" ] && ((!in_dq)); then in_sq=$((1-in_sq)); cur+="$ch"; continue; fi
    if [ "$ch" = '"' ] && ((!in_sq)); then in_dq=$((1-in_dq)); cur+="$ch"; continue; fi
    if ((!in_sq && !in_dq)); then
      if [[ "$ch" == ";" || "$ch" == "&" || "$ch" == "|" || "$ch" == $'\n' ]]; then
        cur=$(echo "$cur" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$cur" ] && printf '%s\n' "$cur"
        cur=""
        continue
      fi
    fi
    cur+="$ch"
  done
  cur=$(echo "$cur" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$cur" ] && printf '%s\n' "$cur"
}

# 安全分词器（处理带引号的参数）
tokenize() {
  local str="$1"
  local len=${#str} in_sq=0 in_dq=0 esc=0 cur="" i ch
  for ((i=0; i<len; i++)); do
    ch="${str:i:1}"
    if ((esc)); then cur+="$ch"; esc=0; continue; fi
    if [ "$ch" = "\\" ] && ((!in_sq)); then cur+="$ch"; esc=1; continue; fi
    if [ "$ch" = "'" ] && ((!in_dq)); then in_sq=$((1-in_sq)); continue; fi
    if [ "$ch" = '"' ] && ((!in_sq)); then in_dq=$((1-in_dq)); continue; fi
    if ((!in_sq && !in_dq)) && [[ "$ch" =~ [[:space:]] ]]; then
      [ -n "$cur" ] && printf '%s\n' "$cur"
      cur=""
      continue
    fi
    cur+="$ch"
  done
  [ -n "$cur" ] && printf '%s\n' "$cur"
}

# 逐段审查子命令
while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # 1. 静态危险模式检测
  grep -Eq "${B}find[[:space:]].*(-delete|-exec[[:space:]]+(/bin/)?rm)" <<<"$seg" && decide ask "危险操作需确认：find 批量删除"
  grep -Eq "${B}xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(/bin/)?rm([[:space:]]|$)" <<<"$seg" && decide ask "危险操作需确认：xargs 批量删除"
  grep -Eq "${B}(npm|pnpm|yarn|bun)[[:space:]]+publish" <<<"$seg" && decide ask "危险操作需确认：发布 npm 包"
  grep -Eq "${B}cargo[[:space:]]+(publish|yank)" <<<"$seg" && decide ask "危险操作需确认：发布/撤回 crate"
  grep -Eq "${B}sudo[[:space:]]" <<<"$seg" && decide ask "危险操作需确认：sudo 提权"
  grep -Eq "${B}killall[[:space:]]|${B}kill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-1([[:space:]]|$)" <<<"$seg" && decide ask "危险操作需确认：批量结束进程"
  grep -Eq "${B}chmod[[:space:]]+-R[[:space:]]+[0-7]*777" <<<"$seg" && decide ask "危险操作需确认：递归 777 权限"
  grep -Eq "${B}(adb[[:space:]].*(uninstall|shell[[:space:]]+rm)|xcrun[[:space:]]+simctl[[:space:]]+erase|pod[[:space:]]+deintegrate)" <<<"$seg" && decide ask "危险操作需确认：清除设备/工程数据"

  # 2. 分词解析工具与参数
  toks=()
  while IFS= read -r tok; do toks+=("$tok"); done < <(tokenize "$seg")
  ((${#toks[@]} == 0)) && continue

  # 跳过前导包装命令与环境变量
  idx=0
  while ((idx < ${#toks[@]})); do
    w="${toks[idx]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || [[ "$w" =~ ^(sudo|env|nohup|time|exec)$ ]]; then
      ((idx++))
      continue
    fi
    break
  done
  cmd_bin="${toks[idx]##*/}"
  ((idx++))

  # 3. rm 审查
  if [[ "$cmd_bin" == "rm" || "$cmd_bin" == "srm" ]]; then
    rec=0; opts_done=0; targets=()
    for t in "${toks[@]:idx}"; do
      if ((opts_done == 0)) && [[ "$t" == -* ]]; then
        [[ "$t" == "--" ]] && opts_done=1
        [[ "$t" == "--recursive" || "$t" =~ ^-[a-zA-Z]*[rR] ]] && rec=1
      else
        targets+=("$t")
      fi
    done
    if ((rec)); then
      ((${#targets[@]} == 0)) && decide ask "危险操作需确认：递归删除目录（rm -r）"
      for t in "${targets[@]}"; do
        rm_target_safe "$t" || decide ask "危险操作需确认：递归删除非构建产物目录 ($t)"
      done
    fi
  fi

  # 4. git 审查（完整跳过所有全局选项，精准捕获子命令）
  if [[ "$cmd_bin" == "git" ]]; then
    while ((idx < ${#toks[@]})); do
      opt="${toks[idx]}"
      case "$opt" in
        -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--exec-path)
          ((idx += 2)) # 跳过该选项及其后跟着的路径/参数值
          continue
          ;;
        -C*|-c*|--git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|--config-env=*|--exec-path=*)
          ((idx++))
          continue
          ;;
        --no-pager|-p|--paginate|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs)
          ((idx++))
          continue
          ;;
        -*)
          ((idx++))
          continue
          ;;
        *)
          break
          ;;
      esac
    done

    subcmd="${toks[idx]}"
    args=("${toks[@]:idx+1}")

    case "$subcmd" in
      reset)
        for a in "${args[@]}"; do
          [[ "$a" == "--hard" || "$a" == "--merge" ]] && decide ask "危险操作需确认：git reset --hard"
        done
        ;;
      clean)
        for a in "${args[@]}"; do
          [[ "$a" =~ ^-[a-zA-Z]*f ]] && decide ask "危险操作需确认：git clean -f"
        done
        ;;
      restore)
        has_staged=0; has_worktree=0
        for a in "${args[@]}"; do
          [[ "$a" == "--staged" || "$a" == "-S" ]] && has_staged=1
          [[ "$a" == "--worktree" || "$a" == "-W" ]] && has_worktree=1
        done
        # 只要没有 --staged 或者带了 --worktree，都会触碰丢弃工作区改动
        ((has_staged && !has_worktree)) || decide ask "危险操作需确认：git restore 会丢弃工作区改动"
        ;;
      push)
        for a in "${args[@]}"; do
          [[ "$a" == "--force" || "$a" =~ ^-[a-zA-Z]*f || "$a" =~ ^\+refs/ || "$a" =~ ^\+HEAD ]] && decide ask "危险操作需确认：git 强制推送"
        done
        ;;
      checkout)
        for a in "${args[@]}"; do
          [[ "$a" == "--" ]] && decide ask "危险操作需确认：git checkout 丢弃工作区改动"
        done
        ;;
      branch)
        for a in "${args[@]}"; do
          [[ "$a" == "-D" ]] && decide ask "危险操作需确认：git branch -D 强制删除分支"
        done
        ;;
      stash)
        subaction="${args[0]}"
        [[ "$subaction" == "drop" || "$subaction" == "clear" ]] && decide ask "危险操作需确认：git stash drop/clear"
        ;;
    esac
  fi

done < <(split_commands "$cmd")

exit 0
