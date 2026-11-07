#!/usr/bin/env bash
# Installs corecrew git hook shims into the project's code folder (beside the Core, or
# <project_dir>/code in the old layout) and the Core repo. A shim is a tiny script that runs the hook
# body kept in the tools folder (see sync-tools.sh), so hooks stay current after plugin updates.
# Usage: bash install-hooks.sh <project_dir> [--tools <dir>]   (project_dir = <Core>/<name>)
# Env:   CORE_DIR (default: parent of project_dir)
#        COREDEV_TOOLS (default: ${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/corecrew-corekit}/tools; the
#        $HOME default only when HOME is an absolute path, else the data folder is unknown and nothing is written)
set -u
P=""; TOOLS="${COREDEV_TOOLS:-}"
if [ -z "$TOOLS" ]; then
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then TOOLS="$CLAUDE_PLUGIN_DATA/tools"
  else case "${HOME:-}" in /*) TOOLS="$HOME/.claude/plugins/data/corecrew-corekit/tools" ;; esac; fi
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --tools) [ $# -ge 2 ] || { echo "usage: install-hooks.sh <project_dir> [--tools <dir>]" >&2; exit 2; }
             TOOLS="$2"; shift 2 ;;
    *) P="$1"; shift ;;
  esac
done
[ -n "$P" ] || { echo "usage: install-hooks.sh <project_dir> [--tools <dir>]" >&2; exit 2; }
[ -n "$TOOLS" ] || { echo "corecrew: the data folder is unknown (HOME is empty or not an absolute path, and CLAUDE_PLUGIN_DATA and --tools are not set); hooks not installed." >&2; exit 1; }
case "$TOOLS" in /*) ;; *) TOOLS="$PWD/$TOOLS" ;; esac
TOOLS="${TOOLS%/}"
CORE_DIR="${CORE_DIR:-$(dirname "$P")}"
MARK="# corecrew hook shim"
OLD_MARK="new-project hook"     # 0.1.x hooks
OLD_SHIM="# coredev hook shim" # 0.2.x shims (plugin was called coredev)

# Run from the plugin (plugin.json is one level up): bring the tools copy up to date first, so
# the shims have something to run. From the tools copy itself (save's reinstall) there is no
# plugin.json and this is skipped.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/../.claude-plugin/plugin.json" ] && [ -f "$HERE/sync-tools.sh" ]; then
  bash "$HERE/sync-tools.sh" "$(cd "$HERE/.." && pwd)" "$TOOLS" >/dev/null || \
    { echo "corecrew: could not update the tools in $TOOLS; hooks not installed." >&2; exit 1; }
fi

# This script's own git-hooks/ folder must be complete: an incomplete copy cannot be trusted.
SRC="$(cd "$(dirname "$0")" && pwd)/git-hooks"
for f in pre-commit-code pre-push-code pre-push-core blocked-patterns; do
  [ -f "$SRC/$f" ] || { echo "corecrew: hook source $SRC/$f is missing; hooks not installed." >&2; exit 1; }
done

install_shim() {  # install_shim <name in tools/git-hooks> <dest hook path>
  local name="$1" dest="$2" target="$TOOLS/git-hooks/$1"
  if [ -e "$dest" ] && ! grep -qF -e "$MARK" -e "$OLD_MARK" -e "$OLD_SHIM" "$dest"; then
    echo "WARN: $dest exists and is not a corecrew hook; left unchanged" >&2; return 0
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  # Single-quote the paths inside the shim (a ' in a path is written as '\'').
  local qt qd
  qt=$(printf '%s' "$target" | sed "s/'/'\\\\''/g"); qd=$(printf '%s' "$dest" | sed "s/'/'\\\\''/g")
  {
    echo '#!/bin/sh'
    echo "$MARK"
    echo "T='$qt'"
    echo "H='$qd'"
    echo '[ -f "$T" ] || { echo "corecrew: $T is missing. Start Claude Code once with corecrew enabled, or remove this hook: rm \"$H\"" >&2; exit 1; }'
    echo 'exec bash "$T" "$@"'
  } > "$dest.tmp.$$" && chmod +x "$dest.tmp.$$" && mv "$dest.tmp.$$" "$dest"
}

# The code folder comes from lib.sh (a folder beside the Core, else <Core>/<name>/code).
. "$HERE/lib.sh"
export CORE_DIR; load_settings
NAME="$(basename "$P")"
# A case clash (exit 3): code_dir_of's line on stderr names the two folders; nothing is installed.
rc=0; CODE="$(code_dir_of "$NAME")" || rc=$?
case "$rc" in 0) ;; 3) exit 1 ;; *) CODE="$P/code" ;; esac
[ -d "$CODE/.git" ] || { echo "No git repo at $CODE" >&2; exit 1; }
[ -d "$CORE_DIR/.git" ] || { echo "No git repo at $CORE_DIR" >&2; exit 1; }
H="$CODE/.git/hooks"
install_shim pre-commit-code "$H/pre-commit" || exit 1
install_shim pre-push-code   "$H/pre-push" || exit 1
install_shim pre-push-core   "$CORE_DIR/.git/hooks/pre-push" || exit 1
echo "hooks installed"
