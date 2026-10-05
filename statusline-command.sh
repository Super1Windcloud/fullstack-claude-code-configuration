#!/bin/zsh
# 高性能全栈异步非阻塞状态栏 (StatusLine Command) - 生产级稳定版
#
# 特性：
# 1. 极速轻量：单次 jq 原生解析，Token 格式化与 I/O 零子进程（printf -v 与 Zsh 内置模块），耗时约 20ms
# 2. 稳健 Git 感知：--no-optional-locks 无锁查询、Detached HEAD (hash) 识别、原子随机临时文件与目录排他锁
# 3. 遥测感知：Prompt Cache 紧迫黄色预警（≤10m）、cold 重建提醒、hit_ratio 命中率告警与 miss 时效短码
# 4. 统一心智：所有百分比（ctx/5h/7d）均表示已消耗比例；7d 仅在 ≥50% 浮现，消除低价值噪音
# 5. 严格响应式降级：基于 ${(m)#} 精确列宽与多字节安全截断，核心指标（dir/branch/ctx/5h/fast）绝对常驻

input=$(cat)
[ -z "$input" ] && exit 0

zmodload zsh/datetime 2>/dev/null
zmodload zsh/stat 2>/dev/null
setopt extendedglob 2>/dev/null
setopt multibyte 2>/dev/null
[[ -z "$LANG" && -z "$LC_ALL" ]] && export LANG="en_US.UTF-8"

# 修复子进程 COLUMNS=0 导致的宽度判断失效，并支持 STATUSLINE_WIDTH 测试重载
term_cols="${STATUSLINE_WIDTH:-$COLUMNS}"
(( term_cols > 0 )) || term_cols=120

# ---------------------------------------------------------
# 1. Single-pass JQ (提取 2.1.285 官方纯净真实字段)
# ---------------------------------------------------------
IFS=$'\x1f' read -r cwd model effort remaining used_pct used_tok max_tok cost rl5h rl5h_reset rl7d rl7d_reset lines_add lines_del ws_worktree fast_mode cache_warm cache_expires_at cache_observed cache_hit_ratio cache_misses cache_last_miss cache_miss_causes agent_name session_name < <(jq -r '
  [
    .cwd // "",
    (.model.display_name // .model.id // ""),
    (.effort.level // ""),
    (.context_window.remaining_percentage // ""),
    (.context_window.used_percentage // ""),
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
    (.prompt_cache.hit_ratio // ""),
    (.prompt_cache.misses // 0),
    (.prompt_cache.last_miss_at // ""),
    ((.prompt_cache.last_miss_cause.causes // []) | map({"tools_changed":"tools","system_prompt_changed":"sys","ttl_expired_5m":"ttl","likely_server_side":"srv"}[.] // .) | join(",")),
    (.agent.name // ""),
    (.session_name // "")
  ] | map(tostring) | join("\u001f")
' <<<"$input")

[ -z "$cwd" ] && cwd="$PWD"

# ---------------------------------------------------------
# 2. Fast Git inspection (纯 Zsh 0ms / 0 子进程扫描)
# ---------------------------------------------------------
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
      read -r gitdir_line < "$cur/.git" 2>/dev/null
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
is_detached=0

if [ -n "$git_dir" ] && [ -d "$git_dir" ]; then
  # Direct HEAD read (0ms)
  if [ -f "$git_dir/HEAD" ]; then
    head_content=$(<"$git_dir/HEAD")
    if [[ "$head_content" == ref:\ refs/heads/* ]]; then
      branch="${head_content#ref: refs/heads/}"
    elif [ -n "$head_content" ]; then
      branch="${head_content:0:7}"
      is_detached=1
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

    # Async cached dirty & upstream check (3s TTL, 用户独立临时目录与进程锁)
    tmp_base="${TMPDIR:-/tmp}"
    tmp_base="${tmp_base%/}"
    h="${git_root//[\/.]/_}"
    cache_file="${tmp_base}/claude_git_${h}.cache"
    lock_file="${tmp_base}/claude_git_${h}.lock"
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
          up=""
          ah=0
          bh=0
          target_dir="${git_root:-$cwd}"
          st=$(git -C "$target_dir" --no-optional-locks status --porcelain=v2 --branch --ignore-submodules 2>/dev/null)
          for l in "${(@f)st}"; do
            case "$l" in
              "# branch.ab "*)
                ab=(${=l#\# branch.ab })
                ah=${ab[1]#+}
                bh=${ab[2]#-}
                ;;
              "#"*|"") ;;
              *) dirty="*" ;;
            esac
          done
          (( ah > 0 )) && up+="↑$ah"
          (( bh > 0 )) && up+="↓$bh"
          tmp_file="${cache_file}.tmp.$$.$RANDOM"
          printf '%s|%s' "$dirty" "$up" > "$tmp_file" && mv -f "$tmp_file" "$cache_file"
        ) </dev/null >/dev/null 2>&1 &!
      fi
    fi
  fi
fi

# ---------------------------------------------------------
# 3. Smart CWD (锚定 Git 根目录)
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# 4. Tech stack badge (按需呈现)
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# 5. Branch rendering (git:main*↑2 [wt:x] [rebase])
# ---------------------------------------------------------
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
  if (( is_detached )); then
    branch_display="(${branch})"
  else
    branch_display="$branch"
  fi
  printf -v branch_part ' \033[1;35mgit:%s%s%s%s\033[0m' "$branch_display" "$git_dirty" "$upstream_status" "$state_str"
fi

# ---------------------------------------------------------
# 6. Agent name (@agent)
# ---------------------------------------------------------
agent_part=""
if [ -n "$agent_name" ]; then
  printf -v agent_part ' \033[36m@%s\033[0m' "$agent_name"
fi

# ---------------------------------------------------------
# 7. Model name & reasoning effort
# ---------------------------------------------------------
model_part=""
if [ -n "$model" ]; then
  if [ -n "$effort" ]; then
    model_str="${model}·${effort}"
  else
    model_str="$model"
  fi
  printf -v model_part ' \033[2m%s\033[0m' "$model_str"
fi

# ---------------------------------------------------------
# 8. Context Window (ctx:38% 75k/200k，百分比为已用量，核心常驻)
# ---------------------------------------------------------
ctx_pct_part=""
ctx_tok_part=""
tok_str=""
used_num=0
max_num=0
[[ "$used_tok" =~ ^[0-9]+$ ]] && used_num=$used_tok
[[ "$max_tok" =~ ^[0-9]+$ ]] && max_num=$max_tok

if (( used_num > 0 )); then
  if (( used_num >= 1000000 )); then
    printf -v u_fmt '%.1fM' $(( used_num / 1000000.0 ))
  elif (( used_num >= 1000 )); then
    printf -v u_fmt '%.0fk' $(( used_num / 1000.0 ))
  else
    u_fmt="${used_num}"
  fi

  if (( max_num > 0 )); then
    if (( max_num >= 1000000 )); then
      printf -v m_fmt '%.0fM' $(( max_num / 1000000.0 ))
    elif (( max_num >= 1000 )); then
      printf -v m_fmt '%.0fk' $(( max_num / 1000.0 ))
    else
      m_fmt="${max_num}"
    fi
    tok_str="${u_fmt}/${m_fmt}"
  else
    tok_str="${u_fmt}"
  fi
fi

# 统一已用百分比 used_int
used_int=""
if [[ "$used_pct" =~ ^[0-9.]+$ ]]; then
  used_int=${used_pct%.*}
elif [[ "$remaining" =~ ^[0-9.]+$ ]]; then
  rem_val=${remaining%.*}
  used_int=$(( 100 - rem_val ))
elif (( max_num > 0 && used_num > 0 )); then
  used_int=$(( used_num * 100 / max_num ))
fi

if [ -n "$used_int" ]; then
  if (( used_int >= 80 )); then
    ctx_color='1;31'
  elif (( used_int >= 60 )); then
    ctx_color='1;33'
  else
    ctx_color='2'
  fi
  printf -v ctx_pct_part ' \033[%smctx:%d%%\033[0m' "$ctx_color" "$used_int"
fi

if [ -n "$tok_str" ]; then
  printf -v ctx_tok_part ' \033[%sm%s\033[0m' "${ctx_color:-2}" "$tok_str"
fi

# ---------------------------------------------------------
# 9. 订阅用量（5h 窗口与高阈值 7d 倒计时）
# ---------------------------------------------------------
rl_part=""
rl7d_part=""
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

  # 7 天用量仅在 ≥50% 时显示，≥80% 红色并附带重置时间；低用量（<50%）不显示以消除噪音
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
      printf -v rl7d_part ' \033[1;31m7d:%d%%%s\033[0m' "$rl7d_int" "$reset_7d_str"
    else
      printf -v rl7d_part ' \033[1;33m7d:%d%%\033[0m' "$rl7d_int"
    fi
  fi
fi

# ---------------------------------------------------------
# 10. Prompt Cache 感知：<10m 紧迫预警、cache:cold 与 hit_ratio / miss
# ---------------------------------------------------------
cache_part=""
if [ "$cache_warm" = "true" ]; then
  cache_expires_at=${cache_expires_at%.*}
  if [[ "$cache_expires_at" =~ ^[0-9]+$ ]]; then
    c_left=$(( cache_expires_at - EPOCHSECONDS ))
    if (( c_left > 0 && c_left <= 600 )); then
      # 剩余不足 10 分钟黄色高亮预警
      printf -v cache_part ' \033[1;33mcache:%dm\033[0m' $(( (c_left + 59) / 60 ))
    elif (( c_left <= 0 )); then
      printf -v cache_part ' \033[33mcache:cold\033[0m'
    fi
  fi
elif [ "$cache_observed" = "true" ]; then
  # 曾观察到缓存但当前未热，统一显示黄色 cold
  printf -v cache_part ' \033[33mcache:cold\033[0m'
fi

# Hit ratio 命中率告警（官方推荐指标，低于 70% 时黄色告警）
hit_part=""
if [[ "$cache_hit_ratio" =~ ^[0-9.]+$ ]]; then
  hr_float=$cache_hit_ratio
  hr_pct=""
  if [[ "$hr_float" =~ ^0\.[0-9]+$ ]]; then
    printf -v hr_pct '%.0f' $(( hr_float * 100.0 )) 2>/dev/null
  elif [[ "$hr_float" =~ ^[0-9]+$ ]] && (( hr_float <= 100 )); then
    hr_pct=$hr_float
  fi
  if [[ "$hr_pct" =~ ^[0-9]+$ ]] && (( hr_pct < 70 )); then
    printf -v hit_part ' \033[33mhit:%d%%\033[0m' "$hr_pct"
  fi
fi

# Cache Miss 击穿告警（最近 15 分钟内有时效展示）
miss_part=""
cache_last_miss=${cache_last_miss%.*}
if [[ "$cache_misses" =~ ^[0-9]+$ ]] && (( cache_misses > 0 )) && \
   [[ "$cache_last_miss" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - cache_last_miss <= 900 )); then
  if [ -n "$cache_miss_causes" ]; then
    printf -v miss_part ' \033[33mmiss:%d(%s)\033[0m' "$cache_misses" "$cache_miss_causes"
  else
    printf -v miss_part ' \033[33mmiss:%d\033[0m' "$cache_misses"
  fi
fi

# ---------------------------------------------------------
# 11. 本会话改动行数
# ---------------------------------------------------------
lines_part=""
if [[ "$lines_add" =~ ^[0-9]+$ && "$lines_del" =~ ^[0-9]+$ ]] && (( lines_add + lines_del > 0 )); then
  printf -v lines_part ' \033[32m+%d\033[0m\033[2m/\033[0m\033[31m-%d\033[0m' "$lines_add" "$lines_del"
fi

# ---------------------------------------------------------
# 12. 运行模式 (fast_mode)
# ---------------------------------------------------------
mode_part=""
if [ "$fast_mode" = "true" ]; then
  printf -v mode_part ' \033[33m⚡fast\033[0m'
fi

# ---------------------------------------------------------
# 13. 费用估算（仅非订阅账号显示，纯 printf -v 零 subshell）
# ---------------------------------------------------------
cost_part=""
if [ -z "$rl_part" ] && [ -n "$cost" ] && [[ "$cost" =~ ^[0-9.]+$ ]]; then
  printf -v cost_float '%.2f' "$cost" 2>/dev/null
  if [[ -n "$cost_float" && "$cost_float" != "0.00" ]]; then
    printf -v cost_part ' \033[2m~$%s\033[0m' "$cost_float"
  fi
fi

# ---------------------------------------------------------
# 14. 会话名称标识 (暗色显示)
# ---------------------------------------------------------
session_part=""
if [ -n "$session_name" ]; then
  printf -v session_part ' \033[2m[%s]\033[0m' "${session_name:0:15}"
fi

# ---------------------------------------------------------
# 15. 响应式宽度自适应 (COLUMNS Responsive Engine)
# ---------------------------------------------------------
# 预留 2 列给终端边距
avail=$(( term_cols - 2 ))

assemble_line() {
  local esc=$'\e'
  cur_line="${dir_part}${stack_part}${branch_part}${agent_part}${model_part}${ctx_pct_part}${ctx_tok_part}${rl_part}${rl7d_part}${cache_part}${hit_part}${miss_part}${lines_part}${mode_part}${cost_part}${session_part}"
  local plain="${cur_line//${esc}\[[0-9;]#m/}"
  cur_len=${(m)#plain}
}

# 优先级组合（由低到高逐级丢弃次要项）
# 核心保留指标：dir + branch + ctx_pct(ctx:xx%) + rl(5h) + mode
# 丢弃链：session -> stack -> lines -> cache -> hit -> model -> rl7d -> miss -> agent -> ctx_tok
assemble_line
for p in session_part stack_part lines_part cache_part hit_part model_part rl7d_part miss_part agent_part ctx_tok_part; do
  (( cur_len > avail )) || break
  : ${(P)p::=}
  assemble_line
done

# 次核心降级：丢弃 5h 重置倒计时箭头字符串（仅保留 5h:55%）
if (( cur_len > avail )); then
  rl_part="${rl_part//→[0-9dhm]##/}"
  assemble_line
fi

# 终极兜底：超窄屏下按终端真实列宽（多字节安全）截断目录名，确保右侧状态绝不折行
if (( cur_len > avail )); then
  ell="…"
  ell_w=${(m)#ell}
  dir_w=${(m)#dir_str}
  target_w=$(( dir_w - (cur_len - avail) - ell_w ))
  (( target_w < 3 )) && target_w=3
  res_dir=""
  cur_dir_w=0
  for (( i=1; i<=${#dir_str}; i++ )); do
    ch="${dir_str[i]}"
    ch_w=${(m)#ch}
    if (( cur_dir_w + ch_w > target_w )); then
      break
    fi
    res_dir+="$ch"
    (( cur_dir_w += ch_w ))
  done
  printf -v dir_part '\033[1;36m%s%s\033[0m' "$res_dir" "$ell"
  assemble_line
fi

printf '%s\n' "$cur_line"
