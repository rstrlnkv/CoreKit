#!/usr/bin/env bash
# Claude Code and Codex SessionStart hook (startup, resume, clear, compact, fork). Stdout becomes context.
#  1. refreshes the tools copy (scripts/prepare.sh prepare_tools; runs everywhere; it only touches the plugin's own folder);
#  2. Core not set up and the session is not in a project: one hint per machine (marker in state/), shown to the person as a systemMessage;
#  3. inside a project (<Core>/<project>/ or its code folder beside the Core, worktrees included): project name, docs index, tools, standards,
#     session rules, then scripts/prepare.sh prepare_project's layout note, links and old git hooks note. On Codex it also records that the
#     hooks ran (the marker prepare.sh looks for).
# Outside a project it prints nothing else.
# Always exits 0: a hook must never block a session.
# prepare.sh is sourced, not run: its parts are functions that return and never exit, so a failing part
# (a tools sync that fails, a code folder that cannot be read) cannot end this hook early.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-$SELF}"
in=""; [ -t 0 ] || in="$(cat)"

. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting
. "$SELF/scripts/prepare.sh" 2>/dev/null || exit 0   # prepare_tools, prepare_project
# The data folder (state markers): CLAUDE_PLUGIN_DATA, else lib-host.sh default_data_dir (the marketplace read from the plugin
# root's path, under an absolute HOME or CODEX_HOME); else unknown (empty): no state marker, no save hint. An empty or
# relative HOME would write to /.claude or <cwd>/<HOME>/.claude. The tools copy (lib.sh tools_dir) follows the same rule.
DATA="${CLAUDE_PLUGIN_DATA:-}"
[ -n "$DATA" ] || DATA="$(default_data_dir "$ROOT")"
load_settings
# 1. Tools: quiet unless it failed (prepare_tools).
# A failure is reported below: on stdout inside a project, on stderr elsewhere (no context noise).
syncerr="$(prepare_tools 2>&1)"
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
proj="$(project_of "$cwd")"
if [ -n "$syncerr" ]; then
  if [ -n "$proj" ]; then printf '%s\n' "$syncerr"; else printf '%s\n' "$syncerr" >&2; fi
fi
# Codex runs hooks only after they are trusted: this run proves it. The marker holds the plugin version (prepare.sh reads it).
if [ "$(host)" = codex ]; then
  mk="$(hooks_marker_path)"; v="$(plugin_version "$ROOT")"
  if [ -n "$mk" ] && [ -n "$v" ] && [ "$(cat "$mk" 2>/dev/null)" != "$v" ]; then
    { mkdir -p "$(dirname "$mk")" && printf '%s\n' "$v" > "$mk"; } 2>/dev/null
  fi
fi

# An invalid setting is named once per session start (not on resume, clear or compact).
warn=""; WNL=$'\n'
case "$(json_str "$in" source)" in
  ""|startup)
    while IFS=$'\t' read -r wk wv ws we; do
      [ -n "$wk" ] || continue
      warn="${warn:+$warn$WNL}$(msg_settings_warning "$wk" "$wv" "$ws" "$we" "$(settings_file_path)")"
    done <<< "$SETTINGS_WARN" ;;
esac
# json_text <text> — escaped for a JSON string, on one line.
# Newlines (between several warnings) become the JSON escape \n.
json_text() { printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | LC_ALL=C tr '\r\t' '  ' | LC_ALL=C awk 'NR>1{printf "\\n"} {printf "%s",$0}'; }

# 2. No Core yet, session elsewhere: the hint, once per machine.
if ! core_ready && [ -z "$proj" ]; then
  # No Core path at all (the settings_no_home warning says why): no hint with an empty path.
  if [ -z "$CORE_DIR" ]; then
    [ -z "$warn" ] || printf '{"systemMessage":"%s"}\n' "$(json_text "$warn")"
    exit 0
  fi
  if [ -z "$DATA" ] || [ ! -e "$DATA/state/core-hint-shown" ]; then
    # For the person, once: a systemMessage. Plain stdout would go to the model only, and the marker
    # below would then mark a hint nobody read.
    if [ -d "$CORE_DIR" ]; then hint="$(msg hint_not_set_up "$CORE_DIR")"
    else hint="$(msg hint_not_found "$CORE_DIR")"; fi
    printf '{"systemMessage":"%s"}\n' "$(json_text "${warn:+$warn$WNL}$hint")"
    [ -z "$DATA" ] || { mkdir -p "$DATA/state" && : > "$DATA/state/core-hint-shown"; } 2>/dev/null
    exit 0
  fi
  [ -z "$warn" ] || printf '{"systemMessage":"%s"}\n' "$(json_text "$warn")"
  exit 0
fi
# Core set up, session elsewhere: nothing to say but a setting problem.
if [ -z "$proj" ]; then
  [ -z "$warn" ] || printf '{"systemMessage":"%s"}\n' "$(json_text "$warn")"
  exit 0
fi

# 3. Inside a project.
P="$CORE_DIR/$proj"; T="$(tools_dir)"
[ -z "$warn" ] || printf '%s\n' "$warn"
printf '%s\n' "$(msg project_header "$proj" "$CORE_DIR")"
printf '%s\n' "$(msg docs_index "$P/docs/INDEX.md")"
noattr=""; [ "$ATTRIBUTION" = forbid ] && noattr=" --no-attribution"
[ -z "$T" ] || printf '%s\n' "$(msg save_hint "$T/save" "$noattr" "$T/undo-step")"
names=""
for f in "$CORE_DIR"/standards/*.md; do
  [ -f "$f" ] || continue
  b="${f##*/}"; b="${b%.md}"; [ "$b" = README ] && continue   # (the glob gives no bare ".md", where basename would differ)
  names="${names:+$names, }$b"
done
printf '%s\n' "$(msg standards "${names:-$(msg standards_none)}")"
if [ -f "$CORE_DIR/session-rules.md" ]; then
  printf '%s\n' "$(msg session_rules "$CORE_DIR/session-rules.md")"
  cat "$CORE_DIR/session-rules.md"
  [ -z "$(tail -c 1 "$CORE_DIR/session-rules.md")" ] || echo   # no final newline: end the line
fi

# Layout note, the CLAUDE.local.md and AGENTS.md links, the old git hooks note: scripts/prepare.sh prepare_project.
prepare_project "$cwd"
exit 0
