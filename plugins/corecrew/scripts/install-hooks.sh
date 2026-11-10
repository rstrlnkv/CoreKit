#!/usr/bin/env bash
# Installs corecrew git hook shims into the project's code folder (beside the Core, or
# <project_dir>/code in the old layout) and the Core repo. A shim is a tiny script that runs the hook
# body kept in the tools folder (see sync-tools.sh), so hooks stay current after plugin updates.
# Usage: bash install-hooks.sh <project_dir> [--tools <dir>]   (project_dir = <Core>/<name>)
# Env:   CORE_DIR (default: parent of project_dir)
#        COREDEV_TOOLS (default: lib.sh tools_dir: $CLAUDE_PLUGIN_DATA/tools, else the host's data folder under an
#        absolute HOME or CODEX_HOME, else the data folder is unknown and nothing is written)
# Shims go to the folder git runs hooks from (`git rev-parse --git-path hooks`: the shared one of a
# linked worktree). When core.hooksPath sends git to another folder (husky, lefthook, a global
# setting) or is empty, nothing is written: that folder belongs to the user's tool (or is the work
# tree). A message names it with the lines to chain the corecrew hooks, and the exit status is 4
# (after installing the shims of the other repo, if it has no such setting).
set -u
P=""
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"
TOOLS="$(tools_dir)"   # COREDEV_TOOLS, else the host's data folder; empty when HOME is not absolute
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
# The shim's advice names the host that installed corecrew (lib.sh host): a session of that host refreshes the tools.
case "$(host)" in codex) HOST_NAME=Codex ;; *) HOST_NAME="Claude Code" ;; esac
OLD_MARK="new-project hook"     # 0.1.x hooks
OLD_SHIM="# coredev hook shim" # 0.2.x shims (plugin was called coredev)

# Run from the plugin (plugin.json is one level up): bring the tools copy up to date first, so
# the shims have something to run. From the tools copy itself (save's reinstall) there is no
# plugin.json and this is skipped. A copy that could not be refreshed because its folder cannot be written (no
# folder can be made beside it: a read-only data folder, the Codex sandbox) goes on running as it is.
if [ -f "$HERE/../.claude-plugin/plugin.json" ] && [ -f "$HERE/sync-tools.sh" ]; then
  bash "$HERE/sync-tools.sh" "$(cd "$HERE/.." && pwd)" "$TOOLS" >/dev/null || \
    { [ -f "$TOOLS/VERSION" ] && ! mkdir "$TOOLS.probe.$$" 2>/dev/null; } || \
    { rmdir "$TOOLS.probe.$$" 2>/dev/null; echo "corecrew: could not update the tools in $TOOLS; hooks not installed." >&2; exit 1; }
fi

# This script's own git-hooks/ folder must be complete: an incomplete copy cannot be trusted.
SRC="$(cd "$(dirname "$0")" && pwd)/git-hooks"
for f in pre-commit-code pre-push-code pre-push-core blocked-patterns allowed-patterns; do
  [ -f "$SRC/$f" ] || { echo "corecrew: hook source $SRC/$f is missing; hooks not installed." >&2; exit 1; }
done

# install_shim <name in tools/git-hooks> <dest hook path> — writes the shim through a temp file. When the
# folder cannot be made or written, one corecrew line names the hook (not a raw shell error) and it
# returns 1.
install_shim() {
  local dest="$2" target="$TOOLS/git-hooks/$1"
  # (-L: a link whose target is missing is the user's hook too; grep fails on it, so it is left as it is)
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && ! grep -qF -e "$MARK" -e "$OLD_MARK" -e "$OLD_SHIM" "$dest"; then
    echo "WARN: $dest exists and is not a corecrew hook; left unchanged" >&2; return 0
  fi
  mkdir -p "$(dirname "$dest")" 2>/dev/null || {
    echo "corecrew: could not write $dest; hooks not installed." >&2; return 1; }
  # Single-quote the paths inside the shim (a ' in a path is written as '\'').
  local qt qd
  qt=$(printf '%s' "$target" | sed "s/'/'\\\\''/g"); qd=$(printf '%s' "$dest" | sed "s/'/'\\\\''/g")
  # 2>/dev/null comes before the redirect: else bash prints its own error when it cannot open the file
  {
    echo '#!/bin/sh'
    echo "$MARK"
    echo "T='$qt'"
    echo "H='$qd'"
    echo '[ -f "$T" ] || { echo "corecrew: $T is missing. Start a '"$HOST_NAME"' session with corecrew enabled, or remove this hook: rm \"$H\"" >&2; exit 1; }'
    echo 'exec bash "$T" "$@"'
  } 2>/dev/null > "$dest.tmp.$$" && chmod +x "$dest.tmp.$$" 2>/dev/null && mv "$dest.tmp.$$" "$dest" 2>/dev/null || {
    rm -f "$dest.tmp.$$"; echo "corecrew: could not write $dest; hooks not installed." >&2; return 1; }
}

# The code folder comes from lib.sh (a folder beside the Core, else <Core>/<name>/code).
export CORE_DIR; load_settings
NAME="$(basename "$P")"
# A case clash (exit 3): code_dir_of's line on stderr names the two folders; nothing is installed.
rc=0; CODE="$(code_dir_of "$NAME")" || rc=$?
case "$rc" in 0) ;; 3) exit 1 ;; *) CODE="$P/code" ;; esac
# .git is a file in a linked worktree
[ -e "$CODE/.git" ] || { echo "No git repo at $CODE" >&2; exit 1; }
[ -e "$CORE_DIR/.git" ] || { echo "No git repo at $CORE_DIR" >&2; exit 1; }

# hooks_dir <repo> — sets HD to the absolute folder git runs the repo's hooks from. Returns 4 when
# that is not git's own hooks folder (<common dir>/hooks): core.hooksPath points at a folder another
# tool manages, or is empty (then git runs no hooks and rev-parse names the work tree root).
hooks_dir() {
  local repo="$1" def
  HD="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null)" && [ -n "$HD" ] || {
    echo "corecrew: git cannot tell the hooks folder of $repo; hooks not installed." >&2; return 1; }
  case "$HD" in /*) ;; *) HD="$repo/$HD" ;; esac
  def="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$def" ] || {
    echo "corecrew: git cannot tell the git folder of $repo; hooks not installed." >&2; return 1; }
  case "$def" in /*) ;; *) def="$repo/$def" ;; esac
  [ "$(canon_dir "$HD")" = "$(canon_dir "$def/hooks")" ] && return 0
  HP_SET=1; HP="$(git -C "$repo" config --get core.hooksPath 2>/dev/null)" || HP_SET=0
  return 4
}

# install_repo <repo> <hook>=<tools name>... — installs the shims, or prints why not and the lines
# that chain them from the user's own hooks.
REFUSED=0
install_repo() {
  local repo="$1" rc=0 pair q; shift
  hooks_dir "$repo" || rc=$?
  case "$rc" in
    0) for pair in "$@"; do install_shim "${pair#*=}" "$HD/${pair%%=*}" || return 1; done; return 0 ;;
    4) REFUSED=1 ;;
    *) return 1 ;;
  esac
  if [ "$HP_SET" = 1 ] && [ -z "$HP" ]; then
    {
      echo "corecrew: core.hooksPath of $repo is set to an empty value, so git runs no hooks there. corecrew hooks were NOT installed."
      echo "  To let corecrew install them, remove the setting (git -C '$repo' config --unset core.hooksPath) and run this again."
    } >&2
    return 0
  fi
  q=$(printf '%s' "$TOOLS" | sed "s/'/'\\\\''/g")
  {
    if [ "$HP_SET" = 1 ]; then
      echo "corecrew: git runs the hooks of $repo from $HD (core.hooksPath = $HP, set for example by husky, lefthook or a global git setting), not from its own hooks folder. corecrew hooks were NOT installed, so they do not run there."
    else
      echo "corecrew: git runs the hooks of $repo from $HD, not from its own hooks folder. corecrew hooks were NOT installed, so they do not run there."
    fi
    [ -d "$HD" ] || echo "  ($HD does not exist.)"
    echo "  To chain them, add a line to each hook file in $HD, right after the first line (create a missing hook file with the first line #!/bin/sh and make it executable with chmod +x). With lefthook, add the command to lefthook.yml instead: lefthook rewrites its hook files."
    for pair in "$@"; do
      case "${pair%%=*}" in
        # git sends pre-push the refs on stdin: keep a copy, so the rest of the user's hook gets them too
        pre-push) echo "    ${pair%%=*}: f=\$(mktemp) || exit 1; cat > \"\$f\"; bash '$q/git-hooks/${pair#*=}' \"\$@\" < \"\$f\" || { rm -f \"\$f\"; exit 1; }; exec < \"\$f\"; rm -f \"\$f\"" ;;
        *)        echo "    ${pair%%=*}: bash '$q/git-hooks/${pair#*=}' || exit 1" ;;
      esac
    done
  } >&2
}
install_repo "$CODE" pre-commit=pre-commit-code pre-push=pre-push-code || exit 1
install_repo "$CORE_DIR" pre-push=pre-push-core || exit 1
[ "$REFUSED" = 0 ] || exit 4
echo "hooks installed"
