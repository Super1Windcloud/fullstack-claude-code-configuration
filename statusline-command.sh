#!/bin/zsh
# 读取 stdin 传入的完整 JSON
input=$(cat)

# 1. 单次 jq 批量提取所有指标，避免多次进程创建开销
IFS=$'\t' read -r cwd model remaining cost < <(echo "$input" | jq -r '
  [
    .cwd // "",
    (.model.display_name // ""),
    (.context_window.remaining_percentage // ""),
    (.cost.total_cost_usd // "")
  ] | @tsv
')

# 2. 路径处理（先规范替换 ~，再截取后 3 级）
home="$HOME"
rel_path="${cwd/#$home/~}"
if [[ "$rel_path" == "~"* ]]; then
  parts=(${(s:/:)rel_path})
  if (( ${#parts} > 3 )); then
    dir_str="~/.../${parts[-2]}/${parts[-1]}"
  else
    dir_str="$rel_path"
  fi
else
  parts=(${(s:/:)cwd})
  if (( ${#parts} > 3 )); then
    dir_str=".../${parts[-2]}/${parts[-1]}"
  else
    dir_str="$cwd"
  fi
fi
dir_part=$(printf '\033[1;36m%s\033[0m' "$dir_str")

# 3. Git 分支与改动感知
if [ -n "$cwd" ] && [ -d "$cwd/.git" -o -f "$cwd/.git" ] || git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -c gc.auto=0 -C "$cwd" branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -c gc.auto=0 -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_dirty=""
    [[ -n $(git -C "$cwd" status --porcelain 2>/dev/null | head -n 1) ]] && git_dirty="*"
    branch_part=$(printf ' \033[1;35mgit:%s%s\033[0m' "$branch" "$git_dirty")
  else
    branch_part=""
  fi
else
  branch_part=""
fi

# 4. 模型名称
[ -n "$model" ] && model_part=$(printf ' \033[2m%s\033[0m' "$model") || model_part=""

# 5. 上下文余量（智能三色阶警示：绿 > 40%，黄 20-40%，红 < 20% 告警）
if [ -n "$remaining" ]; then
  rem_int=${remaining%.*}
  if (( rem_int < 20 )); then
    ctx_part=$(printf ' \033[1;31mctx:%d%%\033[0m' "$rem_int")
  elif (( rem_int < 40 )); then
    ctx_part=$(printf ' \033[1;33mctx:%d%%\033[0m' "$rem_int")
  else
    ctx_part=$(printf ' \033[2mctx:%d%%\033[0m' "$rem_int")
  fi
else
  ctx_part=""
fi

printf '%s%s%s%s\n' "$dir_part" "$branch_part" "$model_part" "$ctx_part"
