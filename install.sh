#!/usr/bin/env bash
# Installs CoreKit skills for Claude Code: copies skills/<name>/ to ~/.claude/skills/<name>/,
# replacing only the skill folders that CoreKit owns (marked with a .corekit file).
# Usage: bash install.sh [--force]    --force also replaces same-named skills CoreKit did not install
# Env: CLAUDE_SKILLS_DIR (default: $HOME/.claude/skills)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
mkdir -p "$DEST"

# owned <src> <dest> — dest has the marker, or is a pre-marker (0.1.0) copy with the same layout
owned() {
  [ -f "$2/.corekit" ] && return 0
  [ -f "$2/SKILL.md" ] || return 1
  for d in "$1"/*/; do [ -d "$2/$(basename "$d")" ] || return 1; done
}

rc=0
for s in "$HERE"/skills/*/; do
  s="${s%/}"; name=$(basename "$s")
  if [ -e "$DEST/$name" ] && [ $FORCE -eq 0 ] && ! owned "$s" "$DEST/$name"; then
    echo "skipped $name: $DEST/$name was not installed by CoreKit; move it away or rerun with --force" >&2
    rc=1; continue
  fi
  rm -rf "${DEST:?}/$name"
  cp -R "$s" "$DEST/$name"
  echo "CoreKit skill; this folder is replaced on reinstall." > "$DEST/$name/.corekit"
  echo "installed $name → $DEST/$name"
done
echo "Restart Claude Code (or start a new session) to pick up the skills."
exit $rc
