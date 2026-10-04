#!/bin/zsh
input=$(cat)

# 1. Single-pass JQ with robust token fallback & effort level extraction
IFS=$'\x1f' read -r cwd model effort remaining used_tok max_tok cost rl5h mode < <(echo "$input" | jq -r '
  [
    .cwd // "",
    (.model.display_name // .model.id // ""),
    (.effort.level // .effort_level // ""),
    (.context_window.remaining_percentage // ""),
    (
      ((.context_window.current_usage.input_tokens // 0) +
       (.context_window.current_usage.cache_creation_input_tokens // 0) +
       (.context_window.current_usage.cache_read_input_tokens // 0)) |
      if . > 0 then . else "" end
    ),
    (.context_window.context_window_size // .context_window.size // ""),
    (.cost.total_cost_usd // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.permission_mode // .mode // "")
  ] | map(tostring) | join("\u001f")
')

[ -z "$cwd" ] && cwd="$PWD"

# 2. Fast Git inspection
git_dir=""
git_root=""
is_worktree=0
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
  [ -z "$branch" ] && branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

  if [ -n "$branch" ]; then
    # Special states
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
      git_state="[rebase]"
    elif [ -f "$git_dir/MERGE_HEAD" ]; then
      git_state="[merge]"
    elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
      git_state="[cherry-pick]"
    fi

    # Async cached dirty & upstream check (3s TTL)
    h=$(printf '%s' "$git_root" | cksum | cut -d' ' -f1)
    cache_file="/tmp/claude_git_${h}.cache"
    lock_file="/tmp/claude_git_${h}.lock"
    now=$(date +%s)
    cache_mtime=0
    if [ -f "$cache_file" ]; then
      cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
      cached_val=$(<"$cache_file")
      git_dirty="${cached_val%%|*}"
      upstream_status="${cached_val#*|}"
    fi

    # Background async refresh if expired (with lock and unique tmp file to avoid collisions)
    if (( now - cache_mtime > 3 )); then
      if mkdir "$lock_file" 2>/dev/null; then
        (
          trap 'rm -rf "$lock_file"' EXIT
          dirty=""
          # Check modified files, staged changes, and untracked files
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
dir_part=$(printf '\033[1;36m%s\033[0m' "$dir_str")

# 4. Tech stack badge (0ms fast check)
stack_part=""
root_or_cwd="${git_root:-$cwd}"
if [ -f "$root_or_cwd/settings.gradle" ] || [ -f "$root_or_cwd/settings.gradle.kts" ] || [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then
  stack_part=$(printf ' \033[32m[android]\033[0m')
elif [ -f "$cwd/Cargo.toml" ] || [ -f "$root_or_cwd/Cargo.toml" ]; then
  stack_part=$(printf ' \033[33m[rust]\033[0m')
elif [ -f "$cwd/pnpm-lock.yaml" ] || [ -f "$root_or_cwd/pnpm-lock.yaml" ]; then
  stack_part=$(printf ' \033[35m[pnpm]\033[0m')
elif [ -f "$cwd/bun.lockb" ] || [ -f "$root_or_cwd/bun.lockb" ]; then
  stack_part=$(printf ' \033[35m[bun]\033[0m')
elif [ -f "$cwd/yarn.lock" ] || [ -f "$root_or_cwd/yarn.lock" ]; then
  stack_part=$(printf ' \033[34m[yarn]\033[0m')
elif [ -f "$cwd/package.json" ] || [ -f "$root_or_cwd/package.json" ]; then
  stack_part=$(printf ' \033[36m[npm]\033[0m')
elif [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$root_or_cwd/pyproject.toml" ]; then
  py_suffix=""
  [ -n "$VIRTUAL_ENV" ] && py_suffix=":venv"
  stack_part=$(printf ' \033[34m[python%s]\033[0m' "$py_suffix")
fi

# 5. Branch rendering (with Worktree awareness)
if [ -n "$branch" ]; then
  state_str=""
  (( is_worktree )) && state_str+=" [wt]"
  [ -n "$git_state" ] && state_str+=" $git_state"
  branch_part=$(printf ' \033[1;35mgit:%s%s%s%s\033[0m' "$branch" "$git_dirty" "$state_str" "$upstream_status")
else
  branch_part=""
fi

# 5. Model name & reasoning effort
model_str=""
if [ -n "$model" ]; then
  if [ -n "$effort" ] && [ "$effort" != "null" ]; then
    model_str="${model}·${effort}"
  else
    model_str="$model"
  fi
  model_part=$(printf ' \033[2m%s\033[0m' "$model_str")
else
  model_part=""
fi

# 6. Context Window (Remaining Percentage + Token usage: 80k/200k)
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

  if (( rem_int < 20 )); then
    ctx_part=$(printf ' \033[1;31m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str")
  elif (( rem_int < 40 )); then
    ctx_part=$(printf ' \033[1;33m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str")
  else
    ctx_part=$(printf ' \033[2m剩余:%d%%%s\033[0m' "$rem_int" "$tok_str")
  fi
fi

# 7. 订阅用量（5 小时窗口）：存在 rate_limits 即为订阅账号，此时费用仅为 API 等价估算，不再显示
rl_part=""
if [[ "$rl5h" =~ ^[0-9.]+$ ]]; then
  rl_int=${rl5h%.*}
  if (( rl_int >= 80 )); then
    rl_part=$(printf ' \033[1;31m5h:%d%%\033[0m' "$rl_int")
  elif (( rl_int >= 50 )); then
    rl_part=$(printf ' \033[1;33m5h:%d%%\033[0m' "$rl_int")
  else
    rl_part=$(printf ' \033[2m5h:%d%%\033[0m' "$rl_int")
  fi
fi

# 8. 权限模式显式标识 (⚡bypass vs 🛡️ask)
mode_part=""
if [[ "$mode" =~ "bypass" ]]; then
  mode_part=$(printf ' \033[33m⚡bypass\033[0m')
elif [ -n "$mode" ] && [ "$mode" != "null" ]; then
  mode_part=$(printf ' \033[32m🛡️%s\033[0m' "$mode")
fi

# 9. Cost (Estimated with ~)
cost_part=""
if [ -z "$rl_part" ] && [ -n "$cost" ] && [[ "$cost" =~ ^[0-9.]+$ ]]; then
  cost_float=$(printf '%.2f' "$cost" 2>/dev/null)
  if [[ -n "$cost_float" && "$cost_float" != "0.00" ]]; then
    cost_part=$(printf ' \033[2m~$%s\033[0m' "$cost_float")
  fi
fi

printf '%s%s%s%s%s%s%s%s\n' "$dir_part" "$stack_part" "$branch_part" "$model_part" "$ctx_part" "$rl_part" "$mode_part" "$cost_part"
