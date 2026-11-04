#!/usr/bin/env bash
# Claude Code SessionStart hook (startup, resume, clear, compact). Stdout becomes context.
#  1. refreshes ${CLAUDE_PLUGIN_DATA}/tools (runs everywhere; it only touches the plugin's own folder);
#  2. Core not set up and the session is not in a project: one hint per machine (marker in state/);
#  3. inside a project (<Core>/<project>/ or its code folder beside the Core, worktrees included): project name, docs index, tools, standards,
#     session rules, layout notes, old git hooks that need re-installing.
# Outside the Core it prints nothing else. Always exits 0: a hook must never block a session.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-$SELF}"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/corecrew-corekit}"
in=""; [ -t 0 ] || in="$(cat)"

# 1. Tools: quiet unless it failed.
# A failure is reported below: on stdout inside a project, on stderr elsewhere (no context noise).
syncerr=""
syncout="$(bash "$ROOT/scripts/sync-tools.sh" "$ROOT" "$DATA/tools" 2>&1)" || syncerr=1

. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting
load_settings
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
proj="$(project_of "$cwd")"
if [ -n "$syncerr" ]; then
  syncerr="$(msg sync_failed "$(printf '%s' "$syncout" | head -1)")"
  if [ -n "$proj" ]; then printf '%s\n' "$syncerr"; else printf '%s\n' "$syncerr" >&2; fi
fi

# 2. No Core yet, session elsewhere: the hint, once per machine.
if ! core_ready && [ -z "$proj" ]; then
  if [ ! -e "$DATA/state/core-hint-shown" ]; then
    if [ -d "$CORE_DIR" ]; then printf '%s\n' "$(msg hint_not_set_up "$CORE_DIR")"
    else printf '%s\n' "$(msg hint_not_found "$CORE_DIR")"; fi
    { mkdir -p "$DATA/state" && : > "$DATA/state/core-hint-shown"; } 2>/dev/null
  fi
  exit 0
fi
# Core set up, session elsewhere: nothing to say.
[ -n "$proj" ] || exit 0

# 3. Inside a project.
P="$CORE_DIR/$proj"; T="$DATA/tools"
printf '%s\n' "$(msg project_header "$proj" "$CORE_DIR")"
printf '%s\n' "$(msg docs_index "$P/docs/INDEX.md")"
noattr=""; [ "$ATTRIBUTION" = forbid ] && noattr=" --no-attribution"
printf '%s\n' "$(msg save_hint "$T/save" "$noattr" "$T/undo-step")"
names=""
for f in "$CORE_DIR"/standards/*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f" .md)"; [ "$b" = README ] && continue
  names="${names:+$names, }$b"
done
printf '%s\n' "$(msg standards "${names:-$(msg standards_none)}")"
if [ -f "$CORE_DIR/session-rules.md" ]; then
  printf '%s\n' "$(msg session_rules "$CORE_DIR/session-rules.md")"
  cat "$CORE_DIR/session-rules.md"
  [ -z "$(tail -c 1 "$CORE_DIR/session-rules.md")" ] || echo   # no final newline: end the line
fi

# Layout notes: .coredev has no schema line, or an older schema than this plugin writes.
sv="$(coredev_get schema | tr -d '[:space:]')"
case "$sv" in
  ""|*[!0-9]*) old=1; shown="$(msg schema_none)" ;;
  *) shown="$sv"; if [ $((10#$sv)) -lt "$COREDEV_SCHEMA" ]; then old=1; else old=0; fi ;;
esac
if [ "$old" -eq 1 ]; then
  printf '%s\n' "$(msg layout_note "$shown" "$COREDEV_SCHEMA" "$ROOT/scripts/setup-core.sh" "$CORE_DIR")"
fi

# Code folder: new layout gets the CLAUDE.local.md link (the main folder, also from a worktree or the
# Core project folder); old layout is named. No code folder, or a case clash: nothing to do.
code=""; code="$(code_dir_of "$proj" 2>/dev/null)" || code=""
if [ -n "$code" ]; then
  if [ "$(layout_of "$proj" 2>/dev/null)" = old ]; then
    printf '%s\n' "$(msg old_layout "$code" "$code" "$PROJECTS_DIR/$proj")"
  else
    if lout="$(link_local_claude "$code" "$P" 2>/dev/null)"; then
      case "$lout" in created*) printf '%s\n' "$(msg local_link_created "$P/CLAUDE.md")" ;; esac
    elif [ -e "$code/CLAUDE.local.md" ] || [ -L "$code/CLAUDE.local.md" ]; then
      printf '%s\n' "$(msg local_link_wrong "$code/CLAUDE.local.md" "$P/CLAUDE.md")"
    else   # nothing there, yet ln failed (for example a read-only folder)
      printf '%s\n' "$(msg local_link_failed "$code/CLAUDE.local.md" "$P/CLAUDE.md")"
    fi
  fi
fi

# Old git hooks: from before the plugin ("new-project hook") or 0.2.x shims of coredev, which run a
# tools copy that is no longer updated. A current shim, or a hook of the user's own, is left alone.
stale=""
for h in "${code:-$P/code}/.git/hooks/pre-commit" "${code:-$P/code}/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  [ -f "$h" ] || continue
  grep -qF "# corecrew hook shim" "$h" && continue
  grep -qF -e "new-project hook" -e "# coredev hook shim" "$h" && stale="${stale:+$stale, }$h"
done
if [ -n "$stale" ]; then
  printf '%s\n' "$(msg old_hooks "$stale" "$ROOT/scripts/install-hooks.sh" "$P")"
fi
exit 0
