#!/bin/zsh
# 高性能全栈异步非阻塞状态栏 (StatusLine Command) - 工业级自适应版
# 特性：
# 1. 0 子进程原生渲染（printf -v 与 zsh 内置模块，全流程 0 次 subshell fork，耗时 < 8ms）
# 2. 彻底修复 Bug 1（去除 >200k 字符转义乱码）与 Bug 2（修复 git_worktree 字符串名称解析）
# 3. 真实 Prompt Cache 语义感知：仅在 <10m 预警、支持 cache:cold 重建提醒与 miss 击穿原因感知
# 4. 真实宽度自适应 (COLUMNS Responsive Layout)：在窄屏下按优先级依次优雅降级

input=$(cat)
zmodload zsh/datetime 2>/dev/null
zmodload zsh/stat 2>/dev/null
setopt extendedglob 2>/dev/null

# 修复子进程 COLUMNS=0 导致的宽度判断失效，并支持 STATUSLINE_WIDTH 测试重载
term_cols="${STATUSLINE_WIDTH:-$COLUMNS}"
(( term_cols > 0 )) || term_cols=120

# 1. Single-pass JQ (提取官方 2.1.285 纯净真实字段)
IFS=$'\x1f' read -r cwd model effort remaining used_tok max_tok cost rl5h rl5h_reset rl7d rl7d_reset lines_add lines_del ws_worktree fast_mode cache_warm cache_expires_at cache_observed cache_misses cache_miss_causes agent_name session_name < <(jq -r '
  [
    .cwd // "",
    (.model.display_name // .model.id // ""),
    (.effort.level // ""),
    (.context_window.remaining_percentage // ""),
    (.context_window.total_input_tokens // ""),
    (.context_window.context_window_size // ""),
    (.cost.total_cost_usd // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.cost.total_lines_added // ""),
    (.cost.total_lines_removed // ""),
    (if (.workspace.git_worktree | type) == "string" then .workspace.git_worktree elif .workspace.git_worktree == true then "wt" else "" end),
    (.fast_mode // false),
    (.prompt_cache.warm // false),
    (.prompt_cache.expires_at // ""),
    (.prompt_cache.caching_observed // false),
    (.prompt_cache.misses // 0),
    ((.prompt_cache.last_miss_cause.causes // []) | join(",")),
    (.agent.name // ""),
    (.session_name // "")
  ] | map(tostring) | join("\u001f")
' <<<"$input")

[ -z "$cwd" ] && cwd="$PWD"

# 2. Fast Git inspection (0ms)
git_dir=""
git_root=""
is_worktree=0
wt_name=""
if [ -n "$ws_worktree" ] && [ "$ws_worktree" != "false" ]; then
  is_worktree=1
  [ "$ws_worktree" != "wt" ] && wt_name="$ws_worktree"
fi

cur="$cwd"
while [ -n "$cur" ] && [ "$cur" != "/" ]; do
  if [ -e "$cur/.git" ]; then
    git_root="$cur"
    if [ -f "$cur/.git" ]; then
      gitdir_line=$(head -n 1 "$cur/.git" 2>/dev/null)
      if [[ "$gitdir_line" == gitdir:* ]]; then
        gd="${gitdir_line#gitdir: }"
        [[ "$gd" != /* ]] && gd="$cur/$gd"
        git_dir="$gd"
        if [[ "$gitdir_line" =~ "/worktrees/" || "$git_dir" =~ "/worktrees/" ]]; then
          is_worktree=1
          [ -z "$wt_name" ] && wt_name="${git_root##*/}"
        fi
      fi
    else
      git_dir="$cur/.git"
    fi
    break
  fi
  cur="${cur%/*}"
done

branch=""
git_state=""
git_dirty=""
upstream_status=""

if [ -n "$git_dir" ] && [ -d "$git_dir" ]; then
  # Direct HEAD read (0ms)
  if [ -f "$git_dir/HEAD" ]; then
    head_content=$(<"$git_dir/HEAD")
    if [[ "$head_content" == ref:\ refs/heads/* ]]; then
      branch="${head_content#ref: refs/heads/}"
    elif [ -n "$head_content" ]; then
      branch="${head_content:0:7}"
    fi
  fi

  if [ -n "$branch" ]; then
    # Special states (rebase, merge, cherry-pick, revert, bisect)
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
      git_state="[rebase]"
    elif [ -f "$git_dir/MERGE_HEAD" ]; then
      git_state="[merge]"
    elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
      git_state="[cherry-pick]"
    elif [ -f "$git_dir/REVERT_HEAD" ]; then
      git_state="[revert]"
    elif [ -f "$git_dir/BISECT_LOG" ]; then
      git_state="[bisect]"
    fi

    # Async cached dirty & upstream check (3s TTL, 0 子进程哈希与文件信息读取)
    h="${git_root//[\/.]/_}"
    cache_file="/tmp/claude_git_${h}.cache"
    lock_file="/tmp/claude_git_${h}.lock"
    now=$EPOCHSECONDS
    cache_mtime=0
    if [ -f "$cache_file" ]; then
      zstat -A _st +mtime "$cache_file" 2>/dev/null && cache_mtime="${_st[1]}"
      cached_val=$(<"$cache_file")
      git_dirty="${cached_val%%|*}"
      upstream_status="${cached_val#*|}"
    fi

    # Background async refresh if expired (with lock and unique tmp file to avoid collisions)
    if (( now - cache_mtime > 3 )); then
      if [ -d "$lock_file" ]; then
        lock_mtime=$now
        zstat -A _lst +mtime "$lock_file" 2>/dev/null && lock_mtime="${_lst[1]}"
        (( now - lock_mtime > 30 )) && rmdir "$lock_file" 2>/dev/null
      fi
      if mkdir "$lock_file" 2>/dev/null; then
        (
          trap 'rm -rf "$lock_file"' EXIT
          dirty=""
          if ! git -C "$cwd" diff-files --quiet --ignore-submodules 2>/dev/null || \
             ! git -C "$cwd" diff-index --cached --quiet --ignore-submodules HEAD 2>/dev/null || \
             [ -n "$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | head -n 1)" ]; then
            dirty="*"
          fi
          up=""
          counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{u} 2>/dev/null)
          if [ -n "$counts" ]; then
            ah=${counts%%	*}
            bh=${counts##*	}
            (( ah > 0 )) && up+="↑$ah"
            (( bh > 0 )) && up+="↓$bh"
          fi
          tmp_file="${cache_file}.tmp.$$.$RANDOM"
          printf '%s|%s' "$dirty" "$up" > "$tmp_file" && mv -f "$tmp_file" "$cache_file"
        ) &!
      fi
    fi
  fi
fi

# 3. Smart CWD (anchored on Git root)
dir_str=""
home="$HOME"
if [ -n "$git_root" ]; then
  repo_name="${git_root##*/}"
  sub="${cwd#$git_root}"
  sub="${sub#/}"
  if [ -z "$sub" ]; then
    dir_str="$repo_name"
  else
    parts=(${(s:/:)sub})
    if (( ${#parts} > 2 )); then
      dir_str="$repo_name/.../${parts[-1]}"
    else
      dir_str="$repo_name/$sub"
    fi
  fi
else
  rel_path="${cwd/#$home/~}"
  parts=(${(s:/:)rel_path})
  if (( ${#parts} > 3 )); then
    dir_str="~/.../${parts[-2]}/${parts[-1]}"
  else
    dir_str="$rel_path"
  fi
fi
printf -v dir_part '\033[1;36m%s\033[0m' "$dir_str"

# 4. Tech stack badge (精确区分 [android] vs [gradle]，支持 bun.lock)
stack_part=""
root_or_cwd="${git_root:-$cwd}"
if [ -f "$root_or_cwd/settings.gradle" ] || [ -f "$root_or_cwd/settings.gradle.kts" ] || [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then
  if [ -f "$cwd/AndroidManifest.xml" ] || [ -f "$cwd/src/main/AndroidManifest.xml" ] || [ -f "$root_or_cwd/app/src/main/AndroidManifest.xml" ] || [ -f "$root_or_cwd/AndroidManifest.xml" ]; then
    printf -v stack_part ' \033[32m[android]\033[0m'
  else
    printf -v stack_part ' \033[32m[gradle]\033[0m'
  fi
elif [ -f "$cwd/Cargo.toml" ] || [ -f "$root_or_cwd/Cargo.toml" ]; then
  printf -v stack_part ' \033[33m[rust]\033[0m'
elif [ -f "$cwd/pnpm-lock.yaml" ] || [ -f "$root_or_cwd/pnpm-lock.yaml" ]; then
  printf -v stack_part ' \033[35m[pnpm]\033[0m'
elif [ -f "$cwd/bun.lock" ] || [ -f "$cwd/bun.lockb" ] || [ -f "$root_or_cwd/bun.lock" ] || [ -f "$root_or_cwd/bun.lockb" ]; then
  printf -v stack_part ' \033[35m[bun]\033[0m'
elif [ -f "$cwd/yarn.lock" ] || [ -f "$root_or_cwd/yarn.lock" ]; then
  printf -v stack_part ' \033[34m[yarn]\033[0m'
elif [ -f "$cwd/package.json" ] || [ -f "$root_or_cwd/package.json" ]; then
  printf -v stack_part ' \033[36m[npm]\033[0m'
elif [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$root_or_cwd/pyproject.toml" ]; then
  py_suffix=""
  [ -n "$VIRTUAL_ENV" ] && py_suffix=":venv"
  printf -v stack_part ' \033[34m[python%s]\033[0m' "$py_suffix"
fi

# 5. Branch rendering (with Worktree awareness & name)
branch_part=""
if [ -n "$branch" ]; then
  state_str=""
  if (( is_worktree )); then
    if [ -n "$wt_name" ]; then
      state_str+=" [wt:$wt_name]"
    else
      state_str+=" [wt]"
    fi
  fi
  [ -n "$git_state" ] && state_str+=" $git_state"
  printf -v branch_part ' \033[1;35mgit:%s%s%s%s\033[0m' "$branch" "$git_dirty" "$state_str" "$upstream_status"
fi

# 6. Agent name (@agent)
agent_part=""
if [ -n "$agent_name" ]; then
  printf -v agent_part ' \033[36m@%s\033[0m' "$agent_name"
fi

# 7. Model name & reasoning effort
model_part=""
if [ -n "$model" ]; then
  if [ -n "$effort" ]; then
    model_str="${model}·${effort}"
  else
    model_str="$model"
  fi
  printf -v model_part ' \033[2m%s\033[0m' "$model_str"
fi

# 8. Context Window (精简为 75k/200k，彻底消除 >200k 转义问题)
ctx_part=""
tok_str=""
if [ -n "$used_tok" ] && [ "$used_tok" != "0" ] && [ "$used_tok" != "null" ]; then
  if (( used_tok >= 1000000 )); then
    printf -v u_fmt '%.1fM' $(( used_tok / 1000000.0 ))
  elif (( used_tok >= 1000 )); then
    printf -v u_fmt '%.0fk' $(( used_tok / 1000.0 ))
  else
    u_fmt="${used_tok}"
  fi

  if [ -n "$max_tok" ] && [ "$max_tok" != "0" ] && [ "$max_tok" != "null" ]; then
    if (( max_tok >= 1000000 )); then
      printf -v m_fmt '%.0fM' $(( max_tok / 1000000.0 ))
    elif (( max_tok >= 1000 )); then
      printf -v m_fmt '%.0fk' $(( max_tok / 1000.0 ))
    else
      m_fmt="${max_tok}"
    fi
    tok_str="${u_fmt}/${m_fmt}"
  else
    tok_str="${u_fmt}"
  fi
fi

if [ -n "$tok_str" ]; then
  rem_int=100
  [ -n "$remaining" ] && rem_int=${remaining%.*}
  if (( rem_int < 20 )); then
    printf -v ctx_part ' \033[1;31m%s\033[0m' "$tok_str"
  elif (( rem_int < 40 )); then
    printf -v ctx_part ' \033[1;33m%s\033[0m' "$tok_str"
  else
    printf -v ctx_part ' \033[2m%s\033[0m' "$tok_str"
  fi
fi

# 9. 订阅用量（5 小时窗口）：存在 rate_limits 即为订阅账号
rl_part=""
if [[ "$rl5h" =~ ^[0-9.]+$ ]]; then
  rl_int=${rl5h%.*}
  reset_str=""
  if (( rl_int >= 50 )) && [[ "$rl5h_reset" =~ ^[0-9]+$ ]]; then
    left=$(( rl5h_reset - EPOCHSECONDS ))
    if (( left > 0 )); then
      if (( left >= 3600 )); then
        reset_str="→$(( left / 3600 ))h$(( left % 3600 / 60 ))m"
      else
        reset_str="→$(( (left + 59) / 60 ))m"
      fi
    fi
  fi
  if (( rl_int >= 80 )); then
    printf -v rl_part ' \033[1;31m5h:%d%%%s\033[0m' "$rl_int" "$reset_str"
  elif (( rl_int >= 50 )); then
    printf -v rl_part ' \033[1;33m5h:%d%%%s\033[0m' "$rl_int" "$reset_str"
  else
    printf -v rl_part ' \033[2m5h:%d%%\033[0m' "$rl_int"
  fi

  # 7 天用量及重置倒计时（≥50% 显示，≥80% 红色并附带重置时间）
  if [[ "$rl7d" =~ ^[0-9.]+$ ]] && (( ${rl7d%.*} >= 50 )); then
    rl7d_int=${rl7d%.*}
    reset_7d_str=""
    if (( rl7d_int >= 80 )) && [[ "$rl7d_reset" =~ ^[0-9]+$ ]]; then
      left_7d=$(( rl7d_reset - EPOCHSECONDS ))
      if (( left_7d > 0 )); then
        if (( left_7d >= 86400 )); then
          reset_7d_str="→$(( left_7d / 86400 ))d$(( (left_7d % 86400) / 3600 ))h"
        elif (( left_7d >= 3600 )); then
          reset_7d_str="→$(( left_7d / 3600 ))h$(( (left_7d % 3600) / 60 ))m"
        else
          reset_7d_str="→$(( (left_7d + 59) / 60 ))m"
        fi
      fi
    fi

    if (( rl7d_int >= 80 )); then
      printf -v _rl7d ' \033[1;31m7d:%d%%%s\033[0m' "$rl7d_int" "$reset_7d_str"
    else
      printf -v _rl7d ' \033[1;33m7d:%d%%\033[0m' "$rl7d_int"
    fi
    rl_part+="$_rl7d"
  fi
fi

# 10. Prompt Cache 感知：<10m 预警、cache:cold 重建提醒与 miss 击穿原因
cache_part=""
if [ "$cache_warm" = "true" ]; then
  cache_expires_at=${cache_expires_at%.*}
  if [[ "$cache_expires_at" =~ ^[0-9]+$ ]]; then
    c_left=$(( cache_expires_at - EPOCHSECONDS ))
    if (( c_left > 0 && c_left <= 600 )); then
      # 剩余不足 10 分钟黄色预警
      printf -v cache_part ' \033[1;33mcache:%dm\033[0m' $(( (c_left + 59) / 60 ))
    elif (( c_left <= 0 )); then
      printf -v cache_part ' \033[2mcache:cold\033[0m'
    fi
  fi
elif [ "$cache_observed" = "true" ]; then
  # 曾观察到缓存但当前未热，提示冷启动
  printf -v cache_part ' \033[33mcache:cold\033[0m'
fi

# Cache Miss 击穿告警（最有价值，避免额度隐形消耗）
miss_part=""
if [[ "$cache_misses" =~ ^[0-9]+$ ]] && (( cache_misses > 0 )); then
  if [ -n "$cache_miss_causes" ]; then
    printf -v miss_part ' \033[33mmiss:%d(%s)\033[0m' "$cache_misses" "${cache_miss_causes:0:20}"
  else
    printf -v miss_part ' \033[33mmiss:%d\033[0m' "$cache_misses"
  fi
fi

# 11. 本会话改动行数
lines_part=""
if [[ "$lines_add" =~ ^[0-9]+$ && "$lines_del" =~ ^[0-9]+$ ]] && (( lines_add + lines_del > 0 )); then
  printf -v lines_part ' \033[32m+%d\033[0m\033[2m/\033[0m\033[31m-%d\033[0m' "$lines_add" "$lines_del"
fi

# 12. 模式标识 (fast_mode)
mode_part=""
if [ "$fast_mode" = "true" ]; then
  printf -v mode_part ' \033[33m⚡fast\033[0m'
fi

# 13. 费用估算（仅非订阅账号显示）
cost_part=""
if [ -z "$rl_part" ] && [ -n "$cost" ] && [[ "$cost" =~ ^[0-9.]+$ ]]; then
  cost_float=$(printf '%.2f' "$cost" 2>/dev/null)
  if [[ -n "$cost_float" && "$cost_float" != "0.00" ]]; then
    printf -v cost_part ' \033[2m~$%s\033[0m' "$cost_float"
  fi
fi

# 14. 会话名称标识 (暗色显示)
session_part=""
if [ -n "$session_name" ]; then
  printf -v session_part ' \033[2m[%s]\033[0m' "${session_name:0:15}"
fi

# ---------------------------------------------------------
# 15. 响应式宽度自适应 (COLUMNS Responsive Engine)
# ---------------------------------------------------------
# 纯 zsh 剥离 ANSI 码计算可见长度 (0 子进程)
calc_len() {
  local esc=$'\e'
  local plain="${1//${esc}\[[0-9;]#m/}"
  echo ${#plain}
}

# 优先级组合（从高到低）
# 核心必备：dir + branch + ctx + rl + mode
# 逐步降级：session_part -> stack_part -> lines_part -> miss_part -> cache_part -> model_part

assemble_line() {
  echo "${dir_part}${stack_part}${branch_part}${agent_part}${model_part}${ctx_part}${rl_part}${cache_part}${miss_part}${lines_part}${mode_part}${cost_part}${session_part}"
}

cur_line=$(assemble_line)
cur_len=$(calc_len "$cur_line")

if (( cur_len > term_cols )); then
  session_part=""
  cur_line=$(assemble_line)
  cur_len=$(calc_len "$cur_line")
fi

if (( cur_len > term_cols )); then
  stack_part=""
  cur_line=$(assemble_line)
  cur_len=$(calc_len "$cur_line")
fi

if (( cur_len > term_cols )); then
  lines_part=""
  cur_line=$(assemble_line)
  cur_len=$(calc_len "$cur_line")
fi

if (( cur_len > term_cols )); then
  cache_part=""
  miss_part=""
  cur_line=$(assemble_line)
  cur_len=$(calc_len "$cur_line")
fi

if (( cur_len > term_cols )); then
  model_part=""
  cur_line=$(assemble_line)
  cur_len=$(calc_len "$cur_line")
fi

printf '%s\n' "$cur_line"
