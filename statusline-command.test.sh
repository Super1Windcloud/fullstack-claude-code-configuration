#!/bin/zsh
# statusline-command.sh 回归测试：zsh ~/.claude/statusline-command.test.sh
# 覆盖：显示宽度不超限（含中文会话名）、降级优先级、兜底截断、hit_ratio 告警、miss 时效与原因短码、冷启动、git dirty 状态

S="${0:A:h}/statusline-command.sh"
now=$(date +%s)
pass=0
fail=0

# 独立于被测脚本的显示宽度计算（CJK / ⚡ 计 2 列）
vis_width() {
  perl -CS -Mutf8 -ne 'chomp; s/\e\[[0-9;]*m//g; $w=0; for(split//){ $w += /[\x{1100}-\x{115F}\x{2E80}-\x{A4CF}\x{AC00}-\x{D7A3}\x{F900}-\x{FAFF}\x{FE30}-\x{FE4F}\x{FF00}-\x{FF60}\x{FFE0}-\x{FFE6}\x{26A1}]/ ? 2 : 1 } print $w'
}
render() { print -r -- "$2" | STATUSLINE_WIDTH=$1 zsh "$S" }
plain() { perl -pe 's/\e\[[0-9;]*m//g' }

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then
    (( pass++ ))
  else
    (( fail++ ))
    print -r -- "FAIL: $name"
    print -r -- "      条件: $cond"
    print -r -- "      输出: $out"
  fi
}

base='"cwd":"/Users/super/demo/hyperscoop","model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"context_window":{"remaining_percentage":62,"total_input_tokens":75000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":55,"resets_at":'$((now+4000))'},"seven_day":{"used_percentage":85,"resets_at":'$((now+200000))'}},"cost":{"total_lines_added":45,"total_lines_removed":12}'
full='{'$base',"session_name":"重构状态栏宽度自适应逻辑","agent":{"name":"reviewer"},"fast_mode":true,"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$((now+300))',"misses":2,"last_miss_at":'$((now-60))',"last_miss_cause":{"causes":["tools_changed","system_prompt_changed"]}}}'
stale='{'$base',"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$((now+3000))',"misses":3,"last_miss_at":'$((now-3600))',"last_miss_cause":{"causes":["tools_changed"]}}}'
cold='{"cwd":"/Users/super/demo/hyperscoop","model":{"display_name":"Opus 5.5"},"context_window":{"total_input_tokens":0,"context_window_size":200000}}'

# 1. 各宽度下显示宽度 ≤ 限制 - 2，且 5h 与上下文百分比始终可见（50 列为最低保障宽度）
for W in 200 160 110 80 60 50; do
  out=$(render $W "$full" | plain)
  w=$(print -r -- "$out" | vis_width)
  check "width=$W 显示宽度 $w 不超限" "(( w <= W - 2 ))"
  check "width=$W 保留 5h 告警" '[[ "$out" == *"5h:55%"* ]]'
  check "width=$W 保留上下文百分比" '[[ "$out" == *"ctx:38%"* ]]'
done

for W in 200 160 110; do
  out=$(render $W "$full" | plain)
  check "width=$W 宽屏保留 7d 告警" '[[ "$out" == *"7d:85%"* ]]'
done

out=$(render 200 "$full" | plain)
check "宽屏上下文含 token 数" '[[ "$out" == *"ctx:38% 75k/200k"* ]]'

# 1b. 7d 低于 50% 消除噪音不显示；无 token 数时仍显示上下文百分比 (已用 9%)
low='{"cwd":"/Users/super/demo/hyperscoop","model":{"display_name":"M"},"context_window":{"remaining_percentage":91,"total_input_tokens":0,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":23}}}'
out=$(render 160 "$low" | plain)
check "7d<50% 消除噪音不显示" '[[ "$out" != *"7d:"* ]]'
check "无 token 数仍显示百分比" '[[ "$out" == *"ctx:9%"* ]]'

# 1c. hit_ratio < 70% 显示命中率告警
low_hit='{'$base',"prompt_cache":{"warm":true,"hit_ratio":0.62}}'
out=$(render 160 "$low_hit" | plain)
check "hit_ratio<70% 显示命中率告警" '[[ "$out" == *"hit:62%"* ]]'

# 2. 降级优先级：miss 比 model 更晚丢弃
out=$(render 110 "$full" | plain)
check "width=110 保留 miss" '[[ "$out" == *"miss:2(tools,sys)"* ]]'
out=$(render 200 "$full" | plain)
check "width=200 全量含中文会话名" '[[ "$out" == *"[重构状态栏"* && "$out" == *"[rust]"* ]]'

# 3. miss 时效：1 小时前的 miss 不再显示
out=$(render 160 "$stale" | plain)
check "过期 miss 不显示" '[[ "$out" != *"miss:"* ]]'

# 4. 冷启动（无 API 响应）正常渲染且无上下文段
out=$(render 120 "$cold" | plain)
check "冷启动渲染目录与模型" '[[ "$out" == "hyperscoop"* && "$out" == *"Opus 5.5" ]]'

# 5. git：touch 但内容未变不应误报 dirty；真实修改应显示 dirty
t_base="${TMPDIR:-/tmp}"
t_base="${t_base%/}"
R=$(mktemp -d "${t_base}/sl-git-test.XXXXXX")
git init -q "$R" && print a > "$R/f" && git -C "$R" add f && git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
gj='{"cwd":"'$R'","model":{"display_name":"M"}}'
h="${R//[\/.]/_}"
wait_cache() { sleep 1.5 }
sleep 1; touch "$R/f"
render 200 "$gj" >/dev/null; wait_cache
out=$(render 200 "$gj" | plain)
check "touch 后不误报 dirty" '[[ "$out" == *"git:main "* || "$out" == *"git:main" ]]'
print b >> "$R/f"; rm -f "${t_base}/claude_git_${h}.cache"
render 200 "$gj" >/dev/null; wait_cache
out=$(render 200 "$gj" | plain)
check "真实修改显示 dirty" '[[ "$out" == *"git:main*"* ]]'
rm -rf "$R" "${t_base}/claude_git_${h}.cache" "${t_base}/claude_git_${h}.lock"

print "passed=$pass failed=$fail"
(( fail == 0 ))
