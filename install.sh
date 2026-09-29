#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude"

echo "=== Fullstack Claude Code Configuration Installer ==="
echo "Target: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}/agents"
mkdir -p "${TARGET_DIR}/skills"

# 1. Install statusline
echo "[1/4] Installing statusline..."
cp "${SCRIPT_DIR}/statusline-command.sh" "${TARGET_DIR}/statusline-command.sh"
chmod +x "${TARGET_DIR}/statusline-command.sh"

# 2. Install agents
echo "[2/4] Installing agents..."
cp -R "${SCRIPT_DIR}/agents/"* "${TARGET_DIR}/agents/" 2>/dev/null || true

# 3. Install skills
echo "[3/4] Installing skills..."
cp -R "${SCRIPT_DIR}/skills/"* "${TARGET_DIR}/skills/" 2>/dev/null || true

# 4. Handle settings.json (preserve existing token if present)
echo "[4/4] Installing settings.json..."
if [ -f "${TARGET_DIR}/settings.json" ]; then
  CURRENT_TOKEN=$(grep -o '"ANTHROPIC_AUTH_TOKEN": *"[^"]*"' "${TARGET_DIR}/settings.json" | cut -d'"' -f4 || true)
  if [ -n "$CURRENT_TOKEN" ] && [ "$CURRENT_TOKEN" != "YOUR_ANTHROPIC_AUTH_TOKEN_HERE" ]; then
    echo "Found existing ANTHROPIC_AUTH_TOKEN in ${TARGET_DIR}/settings.json, preserving it."
    sed "s|\"YOUR_ANTHROPIC_AUTH_TOKEN_HERE\"|\"${CURRENT_TOKEN}\"|g" "${SCRIPT_DIR}/settings.json" > "${TARGET_DIR}/settings.json.tmp"
    # Also expand ~/ to actual $HOME for absolute directory paths
    sed -i '' "s|~/|${HOME}/|g" "${TARGET_DIR}/settings.json.tmp" 2>/dev/null || sed -i "s|~/|${HOME}/|g" "${TARGET_DIR}/settings.json.tmp"
    mv "${TARGET_DIR}/settings.json.tmp" "${TARGET_DIR}/settings.json"
  else
    sed "s|~/|${HOME}/|g" "${SCRIPT_DIR}/settings.json" > "${TARGET_DIR}/settings.json"
  fi
else
  sed "s|~/|${HOME}/|g" "${SCRIPT_DIR}/settings.json" > "${TARGET_DIR}/settings.json"
fi

# 5. Install CLAUDE.md
if [ -f "${SCRIPT_DIR}/CLAUDE.md" ]; then
  echo "[5/5] Installing CLAUDE.md..."
  cp "${SCRIPT_DIR}/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"
fi

echo "=== Installation Completed Successfully! ==="
echo "Please verify your ANTHROPIC_AUTH_TOKEN in ${TARGET_DIR}/settings.json."
