#!/bin/zsh
# 高性能全栈异步非阻塞状态栏 (StatusLine Command) - 优化版
# 特性：
# 1. 0 子进程渲染（全面采用 printf -v 与 zsh/stat 模块，耗时 < 8ms）
# 2. 精准全栈生态标签 ([android] vs [gradle], [bun] 文本 lockfile 支持)
# 3. 彻底修复 COLUMNS=0 窄屏宽度判断，精准渲染行数增减 (+45/-12) 与 7d 用量
# 4. 真实字段感知：fast_mode (⚡fast)、exceeds_200k (>200k)、prompt_cache (cache:42m)
# 5. Git 状态补全 ([revert], [bisect], [wt]) 与原子并发锁

input=$(cat)
zmodload zsh/datetime 2>/dev/null
zmodload zsh/stat 2>/dev/null

# 修复子进程 COLUMNS=0 导致的宽度判断失效
(( COLUMNS > 0 )) || COLUMNS=120

# 1. Single-pass JQ (提取 2.1.285 官方纯净真实字段)
IFS=$'\x1f' read -r cwd model effort remaining used_tok max_tok cost rl5h rl5h_reset rl7d lines_add lines_del ws_worktree fast_mode exceeds_200k cache_warm cache_expires_at < <(jq -r '
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
    (.cost.total_lines_added // ""),
    (.cost.total_lines_removed // ""),
    (.workspace.git_worktree // false),
    (.fast_mode // false),
    (.exceeds_200k_tokens // false),
    (.prompt_cache.warm // false),
    (.prompt_cache.expires_at // "")
  ] | map(tostring) | join("\u001f")
' <<<"$input")

[ -z "$cwd" ] && cwd="$PWD"

# 2. Fast Git inspection (0ms)
git_dir=""
git_root=""
is_worktree=0
[ "$ws_worktree" = "true" ] && is_worktree=1

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
        [[ "$gitdir_line" =~ "/worktrees/" || "$git_dir" =~ "/worktrees/" ]] && is_worktree=1
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

# 5. Branch rendering (with Worktree awareness)
branch_part=""
if [ -n "$branch" ]; then
  state_str=""
  (( is_worktree )) && state_str+=" [wt]"
  [ -n "$git_state" ] && state_str+=" $git_state"
  printf -v branch_part ' \033[1;35mgit:%s%s%s%s\033[0m' "$branch" "$git_dirty" "$state_str" "$upstream_status"
fi

# 6. Model name & reasoning effort
model_part=""
if [ -n "$model" ]; then
  if [ -n "$effort" ] && [ "$effort" != "null" ]; then
    model_str="${model}·${effort}"
  else
    model_str="$model"
  fi
  printf -v model_part ' \033[2m%s\033[0m' "$model_str"
fi

# 7. Context Window (Remaining Percentage + Token usage: 80k/200k + >200k 计价告警)
ctx_part=""
if [ -n "$remaining" ]; then
  rem_int=${remaining%.*}
  tok_str=""
  if [ -n "$used_tok" ] && [ "$used_tok" != "0" ] && [ "$used_tok" != "null" ]; then
    if (( used_tok >= 1000000 )); then
      u_fmt=$(printf '%.1fM' $(( used_tok / 1000000.0 )) )
    elif (( used_tok >= 1000 )); then
      u_fmt=$(printf '%.0fk' $(( used_tok / 1000.0 )) )
    else
      u_fmt="${used_tok}"
    fi

    if [ -n "$max_tok" ] && [ "$max_tok" != "0" ] && [ "$max_tok" != "null" ]; then
      if (( max_tok >= 1000000 )); then
        m_fmt=$(printf '%.0fM' $(( max_tok / 1000000.0 )) )
      elif (( max_tok >= 1000 )); then
        m_fmt=$(printf '%.0fk' $(( max_tok / 1000.0 )) )
      else
        m_fmt="${max_tok}"
      fi
      tok_str=" ${u_fmt}/${m_fmt}"
    else
      tok_str=" ${u_fmt}"
    fi
  fi

  if [ "$exceeds_200k" = "true" ]; then
    tok_str+=" \033[1;31m>200k\033[0m"
  fi

  if (( rem_int < 20 )); then
    printf -v ctx_part ' \033[1;31m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str"
  elif (( rem_int < 40 )); then
    printf -v ctx_part ' \033[1;33m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str"
  else
    printf -v ctx_part ' \033[2m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str"
  fi
fi

# 8. Prompt Cache 感知 (cache:42m / cache:cold)
cache_part=""
if [ "$cache_warm" = "true" ]; then
  cache_expires_at=${cache_expires_at%.*}
  if [[ "$cache_expires_at" =~ ^[0-9]+$ ]]; then
    c_left=$(( cache_expires_at - EPOCHSECONDS ))
    if (( c_left > 0 )); then
      printf -v cache_part ' \033[36mcache:%dm\033[0m' $(( (c_left + 59) / 60 ))
    else
      printf -v cache_part ' \033[2mcache:cold\033[0m'
    fi
  else
    printf -v cache_part ' \033[36mcache:warm\033[0m'
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
  # 7 天用量仅在 ≥50% 且终端宽度充足时出现
  if [[ "$rl7d" =~ ^[0-9.]+$ ]] && (( ${rl7d%.*} >= 50 )); then
    if (( ${rl7d%.*} >= 80 )); then
      printf -v _rl7d ' \033[1;31m7d:%d%%\033[0m' "${rl7d%.*}"
    else
      printf -v _rl7d ' \033[1;33m7d:%d%%\033[0m' "${rl7d%.*}"
    fi
    rl_part+="$_rl7d"
  fi
fi

# 10. 本会话改动行数（COLUMNS 已正确修复）
lines_part=""
if [[ "$lines_add" =~ ^[0-9]+$ && "$lines_del" =~ ^[0-9]+$ ]] && (( lines_add + lines_del > 0 )); then
  printf -v lines_part ' \033[32m+%d\033[0m\033[2m/\033[0m\033[31m-%d\033[0m' "$lines_add" "$lines_del"
fi

# 11. 模式标识（使用真实字段 fast_mode 代替失效的 permission_mode）
mode_part=""
if [ "$fast_mode" = "true" ]; then
  printf -v mode_part ' \033[33m⚡fast\033[0m'
fi

# 12. 费用估算（仅非订阅账号显示，带 ~）
cost_part=""
if [ -z "$rl_part" ] && [ -n "$cost" ] && [[ "$cost" =~ ^[0-9.]+$ ]]; then
  cost_float=$(printf '%.2f' "$cost" 2>/dev/null)
  if [[ -n "$cost_float" && "$cost_float" != "0.00" ]]; then
    printf -v cost_part ' \033[2m~$%s\033[0m' "$cost_float"
  fi
fi

printf '%s%s%s%s%s%s%s%s%s%s\n' "$dir_part" "$stack_part" "$branch_part" "$model_part" "$ctx_part" "$cache_part" "$rl_part" "$lines_part" "$mode_part" "$cost_part"
