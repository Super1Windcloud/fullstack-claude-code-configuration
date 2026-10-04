#!/bin/bash
# PostToolUse(Edit|Write) 单文件安全格式化：
# 1. 严格使用项目已有工具（Prettier / Biome / rustfmt / gofmt 等），杜绝主观强加全局格式化器；
# 2. 仅当文件在 HEAD 中本身符合规范或为新文件时才执行整文件格式化，避免污染历史存量代码；
# 3. 格式化失败或工具退出非 0 时绝不篡改文件，并将简短诊断记录至 /tmp/claude_format.log。

f=$(jq -r '.tool_input.file_path // ""')
[ -f "$f" ] || exit 0
dir=$(dirname "$f")

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/format.log"
log_diag() {
  [ -d "$LOG_DIR" ] || mkdir -p -m 0700 "$LOG_DIR" 2>/dev/null
  if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
  fi
  printf '[%s] %s: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$f" "$1" >> "$LOG_FILE" 2>/dev/null
}

find_up() {
  local d="$dir"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    [ -e "$d/$1" ] && { echo "$d"; return 0; };
    d=$(dirname "$d")
  done
  return 1
}

# 检查该文件在 HEAD 中是否本就符合规范（避免对存量未格式化文件引入全量无关 diff）
head_is_clean() {
  local rel orig formatted
  rel=$(git -C "$dir" ls-files --full-name -- "$f" 2>/dev/null)
  [ -z "$rel" ] && return 0 # 新文件默认允许格式化
  orig=$(git -C "$dir" show "HEAD:$rel" 2>/dev/null) || return 0
  formatted=$(printf '%s\n' "$orig" | "$@" 2>/dev/null)
  [ "$orig" = "$formatted" ]
}

# 安全应用格式化：仅当退出码为 0 且输出非空时更新
apply_format() {
  local out err exit_code
  local err_file
  err_file=$(mktemp "/tmp/fmt_err.XXXXXX")
  
  out=$("$@" < "$f" 2>"$err_file")
  exit_code=$?
  err=$(<"$err_file")
  rm -f "$err_file"

  if [ $exit_code -ne 0 ]; then
    log_diag "Format failed (exit code $exit_code): $err"
    return 1
  fi

  if [ -n "$out" ] && [ "$out" != "$(cat "$f")" ]; then
    printf '%s\n' "$out" > "$f"
    log_diag "Successfully formatted"
  fi
  return 0
}

case "$f" in
  *.rs)
    command -v rustfmt >/dev/null || exit 0
    cargo_root=$(find_up Cargo.toml)
    ed=""
    if [ -n "$cargo_root" ]; then
      ed=$(grep -hEo '^edition[[:space:]]*=[[:space:]]*"[0-9]+"' "$cargo_root/Cargo.toml" 2>/dev/null | grep -Eo '[0-9]+')
    fi
    [ -z "$ed" ] && ed=$(grep -hEo '^edition[[:space:]]*=[[:space:]]*"[0-9]+"' "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)/Cargo.toml" 2>/dev/null | grep -Eo '[0-9]+')
    ed=${ed:-2021}
    FMT=(rustfmt --edition "$ed" --emit stdout -q)
    (cd "$dir" && head_is_clean "${FMT[@]}" && apply_format "${FMT[@]}")
    ;;

  *.go)
    command -v gofmt >/dev/null || exit 0
    (cd "$dir" && head_is_clean gofmt && apply_format gofmt)
    ;;

  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue|*.svelte|*.css|*.scss|*.less|*.html|*.json|*.md|*.yaml|*.yml)
    # 优先检测项目本地 Biome
    biome_root=$(find_up node_modules/.bin/biome)
    if [ -n "$biome_root" ] && [ -x "$biome_root/node_modules/.bin/biome" ]; then
      b="$biome_root/node_modules/.bin/biome"
      (cd "$biome_root" && head_is_clean "$b" format --stdin-file-path="$f" && apply_format "$b" format --stdin-file-path="$f")
      exit 0
    fi

    # 其次检测项目本地 Prettier
    prettier_root=$(find_up node_modules/.bin/prettier)
    if [ -n "$prettier_root" ] && [ -x "$prettier_root/node_modules/.bin/prettier" ]; then
      p="$prettier_root/node_modules/.bin/prettier"
      (cd "$prettier_root" && head_is_clean "$p" --stdin-filepath "$f" && apply_format "$p" --stdin-filepath "$f")
      exit 0
    fi
    ;;

  *.kt|*.kts)
    if command -v ktlint >/dev/null; then
      (cd "$dir" && head_is_clean ktlint --stdin -F -q && apply_format ktlint --stdin -F -q)
    elif command -v ktfmt >/dev/null; then
      (cd "$dir" && head_is_clean ktfmt --stdin-format && apply_format ktfmt --stdin-format)
    fi
    ;;

  *.py)
    if command -v ruff >/dev/null; then
      (cd "$dir" && head_is_clean ruff format --stdin-filename "$f" && apply_format ruff format --stdin-filename "$f")
    elif command -v black >/dev/null; then
      (cd "$dir" && head_is_clean black -q - && apply_format black -q -)
    fi
    ;;
esac

exit 0
