#!/usr/bin/env bash
# hooks/task-gate.sh: the orchestrator (the main session) starts /corecrew:task on its own; any other agent (the hook
# input has an agent_id) gets the user's question first (permissionDecision "ask"). Every other skill, every other
# tool and the main session pass with no output.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/task-gate.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_UI_LANGUAGE
assert_file "$H"

# gate <agent_type or ""> <skill> [tool] — exit code in RC, stdout in OUT, stderr in ERR
gate() {
  local at=""; [ -n "$1" ] && at="$(printf ',"agent_id":"a1","agent_type":"%s"' "$1")"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"skill":"%s","args":"fix the login"}%s}' \
    "$SANDBOX" "${3:-Skill}" "$2" "$at" | bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
  OUT="$(cat "$SANDBOX/out")"; ERR="$(cat "$SANDBOX/err")"
}
asked() {
  gate "$1" "$2"
  assert_eq "$RC" "0" "${1:-main} $2: exit 0"
  case "$OUT" in *'"hookEventName":"PreToolUse"'*'"permissionDecision":"ask"'*) pass ;; *) fail "${1:-main} $2: no ask ($OUT)" ;; esac
  case "$OUT" in *"/corecrew:task"*) pass ;; *) fail "${1:-main} $2: the question does not name /corecrew:task ($OUT)" ;; esac
}
passed() {
  gate "$1" "$2" "$3"
  assert_eq "$RC" "0" "${1:-main} ${3:-Skill} $2: exit 0"
  assert_eq "$OUT$ERR" "" "${1:-main} ${3:-Skill} $2: no output"
}

# the orchestrator starts it without a question (the legitimate action passes)
passed "" corecrew:task
passed "" task
# any agent asks first: a crew role, a built-in agent, another plugin's agent
asked corecrew:engineer corecrew:task
asked general-purpose corecrew:task
asked general-purpose task
asked 'feature-dev:code-architect' corecrew:task
# the question names the agent; a quote in its name stays valid JSON
gate general-purpose corecrew:task
case "$OUT" in *general-purpose*) pass ;; *) fail "the question does not name the agent ($OUT)" ;; esac
gate 'odd"name' corecrew:task
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' && pass || fail "not valid JSON: $OUT"
else
  skip task-gate-json "python3 not on PATH; JSON well-formedness of the question not checked"
fi
# other skills and other tools pass, in an agent too
passed general-purpose corecrew:bloat-audit
passed general-purpose corecrew:ship
passed general-purpose other:task
passed general-purpose task-runner
passed general-purpose corecrew:task Bash
# the question follows ui_language
export CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru
gate general-purpose corecrew:task
case "$OUT" in *агент*) pass ;; *) fail "ru: the question is not in Russian ($OUT)" ;; esac
unset CLAUDE_PLUGIN_OPTION_UI_LANGUAGE
# input it cannot read passes (a guard is a second line; the host's permissions are the boundary)
printf 'not json' | bash "$H" >"$SANDBOX/out" 2>&1; assert_eq "$?" "0" "unreadable input: exit 0"
assert_eq "$(cat "$SANDBOX/out")" "" "unreadable input: no output"

finish
