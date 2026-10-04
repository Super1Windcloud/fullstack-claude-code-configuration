#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude"

echo "=== Fullstack Claude Code Configuration Installer ==="
echo "Target: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}"

# 1. Install statusline
echo "[1/4] Installing statusline-command.sh..."
cp "${SCRIPT_DIR}/statusline-command.sh" "${TARGET_DIR}/statusline-command.sh"
chmod +x "${TARGET_DIR}/statusline-command.sh"

# 2. Install settings.json (backup existing and expand ~/ to actual $HOME)
echo "[2/4] Installing settings.json..."
if [ -f "${TARGET_DIR}/settings.json" ]; then
  bak="${TARGET_DIR}/settings.json.bak.$(date +'%Y%m%d%H%M%S')"
  cp "${TARGET_DIR}/settings.json" "$bak"
  echo "      (Backed up existing settings to $(basename "$bak"))"
fi
sed "s|~/|${HOME}/|g" "${SCRIPT_DIR}/settings.json" > "${TARGET_DIR}/settings.json"

# 3. Install hooks (PreToolUse safety guard & MCP guard)
echo "[3/4] Installing hooks..."
mkdir -p "${TARGET_DIR}/hooks"
mkdir -p -m 0700 "${TARGET_DIR}/logs"
cp -r "${SCRIPT_DIR}/hooks/"* "${TARGET_DIR}/hooks/"
chmod +x "${TARGET_DIR}/hooks/"*.sh

# 4. Install CLAUDE.md (Global engineering defense & delivery contract)
echo "[4/4] Installing CLAUDE.md..."
cp "${SCRIPT_DIR}/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"

echo "=== Installation Completed Successfully! ==="
echo "Claude Code is now equipped with:"
echo "  - Zero-fork responsive statusline (StatusLine v2.5 with Cache Miss & Git lock-free)"
echo "  - Zero-fork native bash safety guard (guard-bash.sh <20ms & guard-mcp.sh)"
echo "  - Fullstack permissions, autoConnectIde & worktree symlink cache"
echo "  - Global engineering defense and Conventional Commits delivery contract"
