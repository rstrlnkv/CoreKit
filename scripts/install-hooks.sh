#!/usr/bin/env bash
# Installs new-project git hooks into <project_dir>/code and the Core repo.
# Usage: bash install-hooks.sh <project_dir>    Env: CORE_DIR (default: parent of project_dir)
set -u
# Hook sources: git-hooks/ next to this script (plugin); the Core copy in <Core>/bin uses
# <Core>/hooks/ instead.
SRC="$(cd "$(dirname "$0")" && pwd)/git-hooks"
[ -d "$SRC" ] || SRC="$(cd "$(dirname "$0")/.." && pwd)/hooks"
P="${1:?usage: install-hooks.sh <project_dir>}"
CORE_DIR="${CORE_DIR:-$(dirname "$P")}"
MARK="new-project hook"

install_one() {  # install_one <src> <dest>
  local src="$1" dest="$2"
  if [ -e "$dest" ] && ! grep -q "$MARK" "$dest"; then
    echo "WARN: $dest exists and is not a new-project hook; left unchanged" >&2; return
  fi
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; chmod +x "$dest"
}

[ -d "$P/code/.git" ] || { echo "No git repo at $P/code" >&2; exit 1; }
[ -d "$CORE_DIR/.git" ] || { echo "No git repo at $CORE_DIR" >&2; exit 1; }
H="$P/code/.git/hooks"
cp "$SRC/blocked-patterns" "$H/blocked-patterns"
install_one "$SRC/pre-commit-code" "$H/pre-commit"
install_one "$SRC/pre-push-code"   "$H/pre-push"
install_one "$SRC/pre-push-core"   "$CORE_DIR/.git/hooks/pre-push"
echo "hooks installed"
