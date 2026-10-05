#!/bin/bash
# PreToolUse(MCP) 防线：拦截高危或写操作 MCP 调用，触发用户授权确认

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -z "$input" ] && exit 0

tool_name=$(jq -r '.tool_name // ""' <<<"$input")
[ -z "$tool_name" ] && exit 0

# 1. Figma MCP 细粒度权限控制
# 区分只读操作（读取图层、获取节点数据、下载资产等）与破坏性/写操作
if [[ "$tool_name" == *"figma"* ]]; then
  action=$(jq -r '.tool_input.action // .tool_input.command // .tool_input.type // ""' <<<"$input" 2>/dev/null)
  # 若未指定 action 或 action 属于只读动作
  if [[ "$action" =~ ^(get|read|inspect|search|view|list|download|find) || -z "$action" ]]; then
    tool_input_str=$(jq -r '.tool_input // {} | tostring' <<<"$input" 2>/dev/null)
    # 只要参数中不包含明确的写操作指令，直接放行 (allow)
    if [[ ! "$tool_input_str" =~ \"(action|command|type)\":\"(create|update|delete|modify|write|post|edit|generate) ]]; then
      exit 0
    fi
  fi
fi

# 2. 其它写操作与高危资源变更拦截
jq -n --arg t "$tool_name" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("危险操作需确认：MCP 工具准备执行外部写入或资源变更 (" + $t + ")")
  }
}'
exit 0
