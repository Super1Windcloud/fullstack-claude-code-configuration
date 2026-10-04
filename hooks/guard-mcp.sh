#!/bin/bash
# PreToolUse(MCP) 防线：拦截高危或写操作 MCP 调用，触发用户授权确认

command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(jq -r '.tool_name // ""')
[ -z "$tool_name" ] && exit 0

jq -n --arg t "$tool_name" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("危险操作需确认：MCP 工具准备执行外部写入或资源变更 (" + $t + ")")
  }
}'
exit 0
