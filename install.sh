#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude"

echo "=== Fullstack Claude Code Configuration Installer ==="
echo "Target: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}"

# 1. Install statusline
echo "[1/3] Installing statusline-command.sh..."
cp "${SCRIPT_DIR}/statusline-command.sh" "${TARGET_DIR}/statusline-command.sh"
chmod +x "${TARGET_DIR}/statusline-command.sh"

# 2. Install settings.json (expand ~/ to actual $HOME for absolute directory paths)
echo "[2/3] Installing settings.json..."
sed "s|~/|${HOME}/|g" "${SCRIPT_DIR}/settings.json" > "${TARGET_DIR}/settings.json"

# 3. Install CLAUDE.md (Global engineering defense & delivery contract)
echo "[3/3] Installing CLAUDE.md..."
cp "${SCRIPT_DIR}/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"

echo "=== Installation Completed Successfully! ==="
echo "Claude Code is now equipped with:"
echo "  - High-performance asynchronous non-blocking statusline"
echo "  - Fullstack permissions, autoConnectIde & worktree symlink cache"
echo "  - Global engineering defense and Conventional Commits contract"
