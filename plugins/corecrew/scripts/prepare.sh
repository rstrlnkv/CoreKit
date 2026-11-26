#!/usr/bin/env bash
# Brings a machine and a project into the state the corecrew hooks would: for hosts where the session-start
# hook may not have run (Codex runs hooks only after the person trusts them), and for session-start itself.
# Usage: bash prepare.sh [--cwd <dir>] [--part tools|project|host | --migrate-instructions]
# Env:   CORE_DIR (the Core, as everywhere), COREKIT_HOST=claude|codex (tests)
#  tools    sync the tools copy the git hook shims run (tools_dir); on error print the sync_not_ours (exit 2) or sync_failed line.
#           Nothing happens when no data folder is known (no usable HOME).
#  project  when --cwd is in a project: the layout note, the old-layout note (code in <Core>/<name>/code, which this
#           version does not support; nothing else is done for such a project), the ignored AGENTS.md entry file
#           in the main code folder and worktrees, and CLAUDE.local.md only for legacy projects.
#           Also prints the core.hooksPath note.
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

# link_notes <code folder> <Core project folder> — prepare the entry and the legacy Claude-only link.
link_notes() {
  local dir="$1" P="$2" lout
  # Only legacy projects use the Claude-specific entry point.
  if [ ! -f "$P/CLAUDE.md" ]; then prepare_agents_entry "$dir" "$P"; return; fi
  if lout="$(link_local_claude "$dir" "$P" 2>/dev/null)"; then
    case "$lout" in created*) printf '%s\n' "$(msg local_link_created "$P/CLAUDE.md")" ;; esac
  elif [ -e "$dir/CLAUDE.local.md" ] || [ -L "$dir/CLAUDE.local.md" ]; then
    printf '%s\n' "$(msg local_link_wrong "$dir/CLAUDE.local.md" "$P/CLAUDE.md")"
  else   # nothing there, yet ln failed (for example a read-only folder)
    printf '%s\n' "$(msg local_link_failed "$dir/CLAUDE.local.md" "$P/CLAUDE.md")"
  fi
  prepare_agents_entry "$dir" "$P"
}

# An existing user file stays silent. Report a symlink conflict or an error writing the entry.
prepare_agents_entry() {
  local dir="$1" P="$2" aout target rc
  target="$(project_instructions "$P")"
  if aout="$(write_agents_entry "$dir" "$P" 2>/dev/null)"; then
    case "$aout" in created*) printf '%s\n' "$(msg agents_entry_created "$dir/AGENTS.md" "$target")" ;; esac
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      printf '%s\n' "$(msg agents_entry_unignored "$dir/AGENTS.md")"
    elif [ -f "$P/CLAUDE.md" ] && { [ -e "$P/AGENTS.md" ] || [ -L "$P/AGENTS.md" ]; }; then
      printf '%s\n' "$(msg agents_in_core "$P/AGENTS.md")"
    elif [ -L "$dir/AGENTS.md" ] && ! agents_entry_state "$dir/AGENTS.md" "$target" >/dev/null; then
      printf '%s\n' "$(msg agents_entry_wrong "$dir/AGENTS.md" "$target")"
    elif [ -L "$dir/AGENTS.md" ] || [ ! -e "$dir/AGENTS.md" ]; then
      printf '%s\n' "$(msg agents_entry_failed "$dir/AGENTS.md")"
    fi
    return 1
  fi
  # Remove only a managed, ignored link to the old name, after the replacement is ready.
  if [ "$target" = "$P/AGENTS.md" ] && [ -L "$dir/CLAUDE.local.md" ] \
    && [ "$(agents_link_target "$dir/CLAUDE.local.md")" = "$P/CLAUDE.md" ] \
    && [ ! -e "$P/CLAUDE.md" ] && [ ! -L "$P/CLAUDE.md" ] \
    && git -C "$dir" check-ignore -q -- CLAUDE.local.md 2>/dev/null; then
    rm -f "$dir/CLAUDE.local.md"
  fi
  return 0
}

# An explicit migration renames the source and connects the main checkout before retiring the old link.
# Other worktrees reconnect on their next preparation.
migrate_project_instructions() {
  local cwd="$1" proj P code
  if ! proj="$(project_of "$cwd")" || ! code="$(code_dir_of "$proj")"; then
    echo "prepare: no supported Core project for $cwd" >&2; return 1
  fi
  P="$CORE_DIR/$proj"
  if [ ! -e "$P/CLAUDE.md" ] && [ ! -L "$P/CLAUDE.md" ]; then
    prepare_project "$cwd"; return 0
  fi
  if [ ! -f "$P/CLAUDE.md" ] || [ -L "$P/CLAUDE.md" ] || [ -e "$P/AGENTS.md" ] || [ -L "$P/AGENTS.md" ]; then
    echo "prepare: resolve the instruction files in $P before migrating" >&2; return 1
  fi
  if ! git -C "$code" check-ignore -q -- AGENTS.md || ! agents_entry_state "$code/AGENTS.md" "$P/CLAUDE.md" >/dev/null; then
    echo "prepare: $code/AGENTS.md must be ignored by Git and available for the Core entry" >&2; return 1
  fi
  if [ -f "$code/CLAUDE.md" ] || [ -f "$code/.claude/CLAUDE.md" ] || {
    [ -f "$code/CLAUDE.local.md" ] &&
      { [ ! -L "$code/CLAUDE.local.md" ] || [ "$(agents_link_target "$code/CLAUDE.local.md")" != "$P/CLAUDE.md" ]; }
  }; then
    echo "prepare: existing Claude Code instructions in $code can shadow AGENTS.md; resolve them before migrating" >&2
    return 1
  fi
  if ! mv -n "$P/CLAUDE.md" "$P/AGENTS.md" || [ -e "$P/CLAUDE.md" ]; then
    echo "prepare: could not rename $P/CLAUDE.md to AGENTS.md" >&2; return 1
  fi
  if ! prepare_agents_entry "$code" "$P"; then
    if mv -n "$P/AGENTS.md" "$P/CLAUDE.md" && [ -f "$P/CLAUDE.md" ]; then
      echo "prepare: could not update $code/AGENTS.md; restored $P/CLAUDE.md" >&2
    else
      echo "prepare: could not update $code/AGENTS.md; the instructions are at $P/AGENTS.md" >&2
    fi
    return 1
  fi
  printf 'migrated %s -> %s\n' "$P/CLAUDE.md" "$P/AGENTS.md"
  prepare_project "$cwd"
}

# 2. The project.
prepare_project() {
  local cwd="$1" proj P sv old shown code hp oc
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
    # Code folder: the links (in the main folder, also from a worktree or the Core project folder). The old layout
    # (<Core>/<name>/code) is named and gets nothing (code_dir_of refuses it). No code folder, or a case clash:
    # nothing to do.
    code=""
    if oc="$(old_code_of "$proj")"; then
      printf '%s\n' "$(msg old_layout "$oc")"
    else
      code="$(code_dir_of "$proj" 2>/dev/null)" || code=""
    fi
    if [ -n "$code" ]; then
      link_notes "$code" "$P"
      if worktree_of "$cwd" && wt_is_main_of "$proj"; then
        case "$WT_ROOT" in
          "$WT_MAIN"/*) prepare_agents_entry "$WT_ROOT" "$P" ;;
          *) link_notes "$WT_ROOT" "$P" ;;
        esac
      fi
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
    # Inside the Codex sandbox a config.toml that cannot be read is the profile being active (a plain workspace-write
    # sandbox reads everything; the profile keeps config.toml closed, as it can hold MCP tokens). Only a refused read
    # counts: a missing file still gets the note.
    if [ -n "$cfg" ] && [ -n "${CODEX_SANDBOX:-}" ]; then
      case "$(LC_ALL=C cat "$cfg" 2>&1 >/dev/null)" in *"not permitted"*) cfg="" ;; esac
    fi
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
      --migrate-instructions) part=migrate; shift ;;
      *) shift ;;
    esac
  done
  [ -n "$cwd" ] || cwd="$PWD"
  . "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
  . "$SELF/hooks/messages.sh" 2>/dev/null || exit 0
  load_settings
  if [ "$part" = migrate ]; then migrate_project_instructions "$cwd"; exit $?; fi
  case "$part" in all|tools) prepare_tools ;; esac
  case "$part" in all|project) prepare_project "$cwd" ;; esac
  case "$part" in all|host) prepare_host ;; esac
  exit 0
fi
