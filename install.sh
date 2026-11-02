#!/usr/bin/env bash
# Installs CoreKit skills for Claude Code: copies skills/<name>/ to ~/.claude/skills/<name>/,
# replacing only the skill folders that CoreKit owns.
# Env: CLAUDE_SKILLS_DIR (default: $HOME/.claude/skills)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$DEST"
for s in "$HERE"/skills/*/; do
  name=$(basename "$s")
  rm -rf "${DEST:?}/$name"
  cp -R "$s" "$DEST/$name"
  echo "installed $name → $DEST/$name"
done
echo "Restart Claude Code (or start a new session) to pick up the skills."
