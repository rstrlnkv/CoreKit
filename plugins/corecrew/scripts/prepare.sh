#!/usr/bin/env bash
# Brings a machine and a project into the state the corecrew hooks would: for hosts where the session-start
# hook may not have run (Codex runs hooks only after the person trusts them), and for session-start itself.
# Usage: bash prepare.sh [--cwd <dir>] [--part tools|project|host]     (default: --cwd $PWD, all parts)
# Env:   CORE_DIR (the Core, as everywhere), COREKIT_HOST=claude|codex (tests)
#  tools    sync the tools copy the git hook shims run (tools_dir); on error print the sync_not_ours (exit 2) or sync_failed line.
#           Nothing happens when no data folder is known (no usable HOME).
#  project  when --cwd is in a project: the layout note, the CLAUDE.local.md and AGENTS.md links in the main code
#           folder and in the worktree root when that is a worktree outside the main folder, the old git hooks note.
#  host     on Codex: the trust note until the hooks are known to have run (the marker session-start writes), and the
#           sandbox profile note while config.toml names no default_permissions (read as data, never written).
# Idempotent, silent when everything is current. Output lines are for the person (the model relays them). Exit 0 always.
# Sourced (hooks/session-start.sh), it only defines prepare_tools, prepare_project <cwd> and prepare_host, which
# return and never exit (an exit would end the hook); the caller has sourced lib.sh and messages.sh, run
# load_settings and set ROOT (the plugin root). Run as a command, it does that itself and runs the parts asked for.

# 1. Tools.
prepare_tools() {
  local T rc
  T="$(tools_dir)"
  [ -n "$T" ] || return 0
  bash "$ROOT/scripts/sync-tools.sh" "$ROOT" "$T" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) ;;
    2) printf '%s\n' "$(msg sync_not_ours "$T")" ;;
    *) printf '%s\n' "$(msg sync_failed "$T")" ;;
  esac
  return 0
}

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
  elif [ ! -e "$dir/AGENTS.md" ]; then   # nothing there, yet ln failed (for example a read-only folder)
    printf '%s\n' "$(msg agents_link_failed "$dir/AGENTS.md" "$P/CLAUDE.md")"
  fi
}

# 2. The project.
prepare_project() {
  local cwd="$1" proj P sv old shown code stale h hp
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
    # core.hooksPath: git runs the hooks of another folder (husky, lefthook, a global setting), so the corecrew
    # shims never run there: install-hooks prints the lines to chain them. An empty value makes git run no hooks
    # at all: the setting must go before install-hooks can install them. Said each time, until the setting changes.
    if [ -n "$code" ]; then
      hp=""
      if hp="$(git -C "$code" config --get core.hooksPath 2>/dev/null)"; then
        if [ -z "$hp" ]; then printf '%s\n' "$(msg hooks_path_empty "$code" "$ROOT/scripts/install-hooks.sh" "$P")"
        else printf '%s\n' "$(msg hooks_path "$code" "$hp" "$ROOT/scripts/install-hooks.sh" "$P")"; fi
      fi
    fi
  fi
  return 0
}

# 3. The host: Codex does not run the hooks until they are trusted.
prepare_host() {
  local mk v cfg base
  if [ "$(host)" = codex ]; then
    mk="$(hooks_marker_path)"; v="$(plugin_version "$ROOT")"
    if [ -z "$mk" ] || [ -z "$v" ] || [ "$(cat "$mk" 2>/dev/null)" != "$v" ]; then
      printf '%s\n' "$(msg codex_trust)"
    fi
    # The corecrew sandbox profile is not the default in config.toml (read as data, never written; the path comes from
    # lib-host.sh codex_home): secrets are guarded best-effort only. Only a top-level key counts (before the first
    # [table] line; a line with a triple quote or an escaped quote before it makes the answer unsure, so the note shows); either quote style, a quoted key and a BOM are read; the value must be corecrew.
    cfg=""; base="$(codex_home)" && cfg="$base/config.toml"
    # LC_ALL=C: the BOM is compared byte for byte (in a UTF-8 locale awk's regex does not match the octal escapes).
    if [ -n "$cfg" ] && ! { LC_ALL=C tr -d '\r' < "$cfg" | LC_ALL=C tr "'" '"' | LC_ALL=C awk 'NR == 1 && substr($0, 1, 3) == "\357\273\277" { $0 = substr($0, 4) }
        { if ($0 ~ /"""/ || $0 ~ /\\"/) exit 1
          if ($0 ~ /^[ \t]*\[/) exit 1
          if ($0 ~ /^[ \t]*"?default_permissions"?[ \t]*=[ \t]*"corecrew"[ \t]*(#.*)?$/) { ok = 1; exit 0 }
        }
        END { exit !ok }'; } 2>/dev/null; then
      printf '%s\n' "$(msg codex_profile "$ROOT/scripts/lib.sh" "$cfg")"
    fi
  fi
  return 0
}

# The command: bash prepare.sh [--cwd <dir>] [--part tools|project|host].
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
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
  case "$part" in all|tools) prepare_tools ;; esac
  case "$part" in all|project) prepare_project "$cwd" ;; esac
  case "$part" in all|host) prepare_host ;; esac
  exit 0
fi
