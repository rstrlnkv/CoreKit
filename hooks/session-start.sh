#!/usr/bin/env bash
# Claude Code SessionStart hook (startup, resume, clear, compact). Stdout becomes context.
#  1. refreshes ${CLAUDE_PLUGIN_DATA}/tools (runs everywhere; it only touches the plugin's own folder);
#  2. Core not set up and the session is not in a project: one hint per machine (marker in state/);
#  3. inside <Core>/<project>/ (worktrees included): project name, docs index, tools, standards,
#     session rules, layout notes, old git hooks that need re-installing.
# Outside the Core it prints nothing else. Always exits 0: a hook must never block a session.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-$SELF}"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/coredev-corekit}"
in=""; [ -t 0 ] || in="$(cat)"

# 1. Tools: quiet unless it failed.
msg="$(bash "$ROOT/scripts/sync-tools.sh" "$ROOT" "$DATA/tools" 2>&1)" \
  || echo "coredev: tools not refreshed: $(printf '%s' "$msg" | head -1)"

. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
load_settings
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
proj="$(project_of "$cwd")"

# 2. No Core yet, session elsewhere: the hint, once per machine.
if ! core_ready && [ -z "$proj" ]; then
  if [ ! -e "$DATA/state/core-hint-shown" ]; then
    echo "coredev: Core not found at $CORE_DIR — /coredev:new-project or /coredev:task adopt <folder> will set it up"
    { mkdir -p "$DATA/state" && : > "$DATA/state/core-hint-shown"; } 2>/dev/null
  fi
  exit 0
fi
# Core set up, session elsewhere: nothing to say.
[ -n "$proj" ] || exit 0

# 3. Inside a project.
P="$CORE_DIR/$proj"; T="$DATA/tools"
echo "coredev: you are in the Core project \"$proj\" (Core: $CORE_DIR)"
echo "Project docs index: $P/docs/INDEX.md"
echo "Save a finished step: bash \"$T/save\" \"<message>\"; undo the last step: bash \"$T/undo-step\""
names=""
for f in "$CORE_DIR"/standards/*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f" .md)"; [ "$b" = README ] && continue
  names="${names:+$names, }$b"
done
echo "Standards: ${names:-none}"
if [ -f "$CORE_DIR/session-rules.md" ]; then
  echo "Session rules ($CORE_DIR/session-rules.md):"
  cat "$CORE_DIR/session-rules.md"
fi

# Layout notes: .coredev has no schema line, or an older schema than this plugin writes.
sv="$(coredev_get schema | tr -d '[:space:]')"
case "$sv" in
  ""|*[!0-9]*) old=1; shown="none" ;;
  *) shown="$sv"; if [ $((10#$sv)) -lt "$COREDEV_SCHEMA" ]; then old=1; else old=0; fi ;;
esac
if [ "$old" -eq 1 ]; then
  echo "Layout note: this Core has layout schema $shown, the plugin expects $COREDEV_SCHEMA. Bring it up to date (adds only what is missing): bash \"$ROOT/scripts/setup-core.sh\" \"$CORE_DIR\""
fi

# Old git hooks from before the plugin ("new-project hook"). A shim, or a hook of the user's own, is left alone.
stale=""
for h in "$P/code/.git/hooks/pre-commit" "$P/code/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  [ -f "$h" ] || continue
  grep -qF "# coredev hook shim" "$h" && continue
  grep -qF "new-project hook" "$h" && stale="${stale:+$stale, }$h"
done
if [ -n "$stale" ]; then
  echo "Old git hooks (not coredev shims): $stale. Replace them with: bash \"$ROOT/scripts/install-hooks.sh\" \"$P\""
fi
exit 0
