#!/usr/bin/env bash
# Offline Codex check: add this repo as a marketplace, install corecrew, and look at what Codex shows
# the model. CODEX_HOME is inside the sandbox; remote plugin features are switched off. Skipped when
# `codex` is not installed.
source "$(dirname "$0")/lib.sh"
if ! command -v codex >/dev/null 2>&1; then echo "SKIP codex-install: codex not on PATH"; exit 0; fi
new_sandbox
export CODEX_HOME="$SANDBOX/codex-home"; mkdir -p "$CODEX_HOME" "$SANDBOX/work"
cx() { codex --disable remote_plugin --disable plugin_discovery_prefetch "$@"; }
echo "  note: $(codex --version)"

assert_exit 0 cx plugin marketplace add "$ROOT"
assert_exit 0 cx plugin add corecrew@corekit
# coreopinion is Claude Code only, but the marketplace offers it to Codex too: once installed, its skill must not be
# offered to the model (skills/second-opinion/agents/openai.yaml)
assert_exit 0 cx plugin add coreopinion@corekit
ver="$(sed -n 's/^ *"version": *"\(.*\)",\{0,1\}$/\1/p' "$PLUGIN/.codex-plugin/plugin.json" | head -1)"
inst="$CODEX_HOME/plugins/cache/corekit/corecrew/$ver"
assert_file "$inst/.codex-plugin/plugin.json"
assert_file "$inst/skills/task/agents/openai.yaml"
assert_file "$inst/hooks/hooks.json"

cd "$SANDBOX/work" || exit 1
cx debug prompt-input "hi" > "$SANDBOX/prompt.json" 2> "$SANDBOX/prompt.err"; assert_eq "$?" "0" "debug prompt-input exits 0"
if grep -qiE 'openai\.yaml|plugin\.json|invalid|failed to' "$SANDBOX/prompt.err"; then fail "Codex warned: $(head -3 "$SANDBOX/prompt.err")"; else pass; fi
# the prompt lists skills with a root alias: (file: r1/corecrew/<version>/skills/new-project/SKILL.md),
# r1 = <CODEX_HOME>/plugins/cache/corekit
text="$(sed 's/\\n/\n/g' "$SANDBOX/prompt.json")"
listed() { printf '%s\n' "$text" | grep -c "^- corecrew:$1: "; }
assert_eq "$(listed new-project)" "1" "new-project is listed"
# allow_implicit_invocation: false keeps these out of the model's skills list (observed, codex 0.166.0)
for s in task ship new-standard; do assert_eq "$(listed $s)" "0" "$s is not listed (implicit invocation off)"; done
assert_eq "$(printf '%s\n' "$text" | grep -c '^- coreopinion:second-opinion: ')" "0" "coreopinion's skill is not listed in Codex"
# (file: rN/<rest>/SKILL.md): rN is a root alias, defined under "Skill roots" (its value varies with
# what else is listed, so look it up)
f="$(printf '%s\n' "$text" | sed -n 's/^- corecrew:new-project: .*(file: \([^)]*\))$/\1/p' | head -1)"
alias="${f%%/*}"
base="$(printf '%s\n' "$text" | sed -n "s/^- \`$alias\` = \`\(.*\)\`\$/\1/p" | head -1)"
assert_eq "$base/${f#*/}" "$inst/skills/new-project/SKILL.md" "alias $alias + path = the installed SKILL.md"
# the Paths section of every skill works from that folder
skill_dir="$(dirname "$base/${f#*/}")"
assert_eq "$(bash "$skill_dir/../../scripts/lib.sh" plugin-root 2>&1)" "$inst" "plugin-root from the installed copy"
# the Paths section sends Codex to the shared host reference, two folders above the skill folder
assert_file "$skill_dir/../../reference/codex-host.md"
finish
