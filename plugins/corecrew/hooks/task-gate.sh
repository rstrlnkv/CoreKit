#!/usr/bin/env bash
# Claude Code and Codex PreToolUse hook on Skill: the orchestrator (the main session) starts /corecrew:task on its
# own; any other agent asks the user first. Inside a subagent the hook input carries agent_id; then a Skill call for
# corecrew:task (or the bare name task) gets permissionDecision "ask" with a question that names the agent, in the
# ui_language setting. Every other skill, every other tool and the main session pass with no output.
# Codex has no Skill tool, so the hook never fires there; the task skill's Overview says the same rule in words.
# Best effort, not a boundary (docs: the threat model): input it cannot read passes. No jq.
S="$(dirname "$0")/../scripts"
. "$S/lib.sh" 2>/dev/null || exit 0                    # json_fields, json_text, load_settings
. "$(dirname "$0")/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting
in="$(cat)"
{
  IFS= read -r -d '' tool; IFS= read -r -d '' skill; IFS= read -r -d '' agent_id; IFS= read -r -d '' agent_type
} < <(json_fields "$in" tool_name skill agent_id agent_type)
[ "$tool" = Skill ] && [ -n "$agent_id" ] || exit 0
case "$skill" in corecrew:task|task) ;; *) exit 0 ;; esac
load_settings
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' \
  "$(json_text "$(msg task_agent_ask "${agent_type:-$agent_id}")")"
exit 0
