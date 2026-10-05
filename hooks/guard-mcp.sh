#!/bin/bash
# PreToolUse(MCP) 防线：拦截高危或写操作 MCP 调用，触发用户授权确认

# 纯原生 0-Fork 极速读取输入
IFS= read -r -d '' input || true
[ -z "$input" ] && exit 0

pat_tool='"tool_name":[[:space:]]*"([^"]+)"'
if [[ "$input" =~ $pat_tool ]]; then
  tool_name="${BASH_REMATCH[1]}"
else
  # 保底回退
  command -v jq >/dev/null 2>&1 || exit 0
  tool_name=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)
fi
[ -z "$tool_name" ] && exit 0

# 1. Figma MCP 细粒度权限控制
# 区分只读操作（读取图层、获取节点数据、下载资产等）与破坏性/写操作
if [[ "$tool_name" == *"figma"* ]]; then
  pat_action='"(action|command|type)":[[:space:]]*"([^"]+)"'
  action=""
  [[ "$input" =~ $pat_action ]] && action="${BASH_REMATCH[2]}"
  # 若未指定 action 或 action 属于只读动作
  if [[ "$action" =~ ^(get|read|inspect|search|view|list|download|find) || -z "$action" ]]; then
    # 只要参数中不包含明确的写操作指令，直接放行 (allow)
    pat_write='"(action|command|type)":[[:space:]]*"(create|update|delete|modify|write|post|edit|generate)'
    if [[ ! "$input" =~ $pat_write ]]; then
      exit 0
    fi
  fi
fi

# 2. 其它写操作与高危资源变更拦截 (0-Fork printf 极速响应)
safe_tool="${tool_name//\"/\\\"}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"危险操作需确认：MCP 工具准备执行外部写入或资源变更 (%s)"}}\n' "$safe_tool"
exit 0
