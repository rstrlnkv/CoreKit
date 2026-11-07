#!/usr/bin/env bash
# Brings a machine and a project into the state the corecrew hooks would: for hosts where the session-start
# hook may not have run (Codex runs hooks only after the person trusts them), and for session-start itself.
# Usage: bash prepare.sh [--cwd <dir>] [--part tools|project|host]     (default: --cwd $PWD, all parts)
# Env:   CORE_DIR (the Core, as everywhere), COREKIT_HOST=claude|codex (tests)
#  tools    sync the tools copy the git hook shims run (tools_dir); on error print the sync_not_ours (exit 2) or sync_failed line.
#           Nothing happens when no data folder is known (no usable HOME).
#  project  when --cwd is in a project: the layout note, the CLAUDE.local.md and AGENTS.md links in the main code
#           folder and in the worktree root when that is a worktree outside the main folder, the old git hooks note.
#  host     on Codex, until the hooks are known to have run (the marker session-start writes): the trust note.
# Idempotent, silent when everything is current. Output lines are for the person (the model relays them). Exit 0 always.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
ROOT="${CLAUDE_PLUGIN_ROOT:-$SELF}"
cwd=""; part=all
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd) [ $# -ge 2 ] || exit 0; cwd="$2"; shift 2 ;;
    --part) [ $# -ge 2 ] || exit 0; part="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$cwd" ] || cwd="$PWD"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0
load_settings

# 1. Tools.
if [ "$part" = all ] || [ "$part" = tools ]; then
  T="$(tools_dir)"
  if [ -n "$T" ]; then
    bash "$ROOT/scripts/sync-tools.sh" "$ROOT" "$T" >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) ;;
      2) printf '%s\n' "$(msg sync_not_ours "$T")" ;;
      *) printf '%s\n' "$(msg sync_failed "$T")" ;;
    esac
  fi
fi

# link_notes <code folder> <Core project folder> — make the two links; say what was made or what is in the way.
# A real AGENTS.md stays silent (its owner may want it).
link_notes() {
  local dir="$1" P="$2" lout aout
  if lout="$(link_local_claude "$dir" "$P" 2>/dev/null)"; then
    case "$lout" in created*) printf '%s\n' "$(msg local_link_created "$P/CLAUDE.md")" ;; esac
  elif [ -e "$dir/CLAUDE.local.md" ] || [ -L "$dir/CLAUDE.local.md" ]; then
    printf '%s\n' "$(msg local_link_wrong "$dir/CLAUDE.local.md" "$P/CLAUDE.md")"
  else   # nothing there, yet ln failed (for example a read-only folder)
    printf '%s\n' "$(msg local_link_failed "$dir/CLAUDE.local.md" "$P/CLAUDE.md")"
  fi
  if aout="$(link_agents "$dir" "$P" 2>/dev/null)"; then
    case "$aout" in created*) printf '%s\n' "$(msg agents_link_created "$P/CLAUDE.md")" ;; esac
  elif [ -L "$dir/AGENTS.md" ]; then   # a link elsewhere (or dangling)
    printf '%s\n' "$(msg agents_link_wrong "$dir/AGENTS.md" "$P/CLAUDE.md")"
  elif [ -e "$P/AGENTS.md" ]; then   # the Core's own AGENTS.md would be hidden by the link
    printf '%s\n' "$(msg agents_in_core "$P/AGENTS.md")"
  fi
}

# 2. The project.
if [ "$part" = all ] || [ "$part" = project ]; then
  proj="$(project_of "$cwd")" || proj=""
  if [ -n "$proj" ]; then
    P="$CORE_DIR/$proj"
    # Layout note: .coredev has no schema line, or an older schema than this plugin writes.
    sv="$(coredev_get schema | tr -d '[:space:]')"
    case "$sv" in
      ""|*[!0-9]*) old=1; shown="$(msg schema_none)" ;;
      *) shown="$sv"; if [ $((10#$sv)) -lt "$COREDEV_SCHEMA" ]; then old=1; else old=0; fi ;;
    esac
    if [ "$old" -eq 1 ]; then
      printf '%s\n' "$(msg layout_note "$shown" "$COREDEV_SCHEMA" "$ROOT/scripts/setup-core.sh" "$CORE_DIR")"
    fi
    # Code folder: new layout gets the links (the main folder, also from a worktree or the Core project folder);
    # old layout is named. No code folder, or a case clash: nothing to do.
    code=""; code="$(code_dir_of "$proj" 2>/dev/null)" || code=""
    if [ -n "$code" ]; then
      if [ "$(layout_of "$proj" 2>/dev/null)" = old ]; then
        printf '%s\n' "$(msg old_layout "$code" "$code" "$PROJECTS_DIR/$proj")"
      else
        link_notes "$code" "$P"
        # A worktree outside the main folder does not find the main folder's links above it.
        if worktree_of "$cwd" && wt_is_main_of "$proj"; then
          case "$WT_ROOT" in "$(canon_dir "$code")"|"$(canon_dir "$code")"/*) ;; *) link_notes "$WT_ROOT" "$P" ;; esac
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
  fi
fi

# 3. The host: Codex does not run the hooks until they are trusted.
if [ "$part" = all ] || [ "$part" = host ]; then
  if [ "$(host)" = codex ]; then
    mk="$(hooks_marker_path)"; v="$(plugin_version "$ROOT")"
    if [ -z "$mk" ] || [ -z "$v" ] || [ "$(cat "$mk" 2>/dev/null)" != "$v" ]; then
      printf '%s\n' "$(msg codex_trust)"
    fi
  fi
fi
exit 0
