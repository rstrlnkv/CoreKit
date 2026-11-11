#!/usr/bin/env bash
# Offline Codex check: add this repo as a marketplace, install corecrew, and look at what Codex shows
# the model. CODEX_HOME is inside the sandbox; remote plugin features are switched off. Skipped when
# `codex` is not installed.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
if ! command -v codex >/dev/null 2>&1; then skip codex-install "codex not on PATH"; finish; fi
new_sandbox
export CODEX_HOME="$SANDBOX/codex-home"; mkdir -p "$CODEX_HOME" "$SANDBOX/work"
cx() { codex --disable remote_plugin --disable plugin_discovery_prefetch "$@"; }
note "$(codex --version)"

assert_exit 0 cx plugin marketplace add "$ROOT"
assert_exit 0 cx plugin add corecrew@corekit
# coreopinion is Claude Code only (P1): Codex reads .agents/plugins/marketplace.json, which lists corecrew and
# coremodel only, so Codex neither offers nor installs coreopinion.
lst="$(cx plugin list 2>&1)"
case "$lst" in *'.agents/plugins/marketplace.json'*) pass ;; *) fail "Codex reads the Codex marketplace file: $lst" ;; esac
case "$lst" in *'coremodel@corekit'*) pass ;; *) fail "Codex lists coremodel: $lst" ;; esac
case "$lst" in *coreopinion*) fail "Codex lists coreopinion: $lst" ;; *) pass ;; esac
assert_exit 1 cx plugin add coreopinion@corekit
ver="$(sed -n 's/^ *"version": *"\(.*\)",\{0,1\}$/\1/p' "$PLUGIN/.codex-plugin/plugin.json" | head -1)"
inst="$CODEX_HOME/plugins/cache/corekit/corecrew/$ver"
assert_file "$inst/.codex-plugin/plugin.json"
assert_file "$inst/skills/task/agents/openai.yaml"
assert_file "$inst/hooks/hooks.json"

# Ask Codex (app-server hooks/list) which corecrew hooks it loads: exactly the five entries of hooks/hooks.json, each with
# the matcher of hooks.json and its "timeout" as timeoutSec (Codex reports 600 for a key it does not read), the command
# on the installed path with no CLAUDE_PLUGIN_ROOT left, and no warning or error.
HL="$SANDBOX/hooks-list.txt"
codex_hooks_list "$SANDBOX/work" "$HL" && pass || fail "hooks/list: no answer in 10 s: $(head -3 "$HL.err")"
grep '^{"key":"corecrew@' "$HL" > "$SANDBOX/cc-hooks"
assert_eq "$(sed 's/^{"key":"\([^"]*\)".*/\1/' "$SANDBOX/cc-hooks" | LC_ALL=C sort | tr '\n' ' ')" \
  "corecrew@corekit:hooks/hooks.json:pre_tool_use:0:0 corecrew@corekit:hooks/hooks.json:pre_tool_use:1:0 corecrew@corekit:hooks/hooks.json:pre_tool_use:2:0 corecrew@corekit:hooks/hooks.json:session_start:0:0 corecrew@corekit:hooks/hooks.json:stop:0:0 " \
  "Codex loads exactly the five corecrew hooks"
# hooks.json is pretty-printed one key per line: "<Event>": [ opens an event, each inner "hooks": [ an entry
# "<key>|<matcher>|<command>|<timeout>": the command JSON-escaped, as Codex prints it, with the plugin root filled in
awk -v root="$inst" '
  /^ *"[A-Z][A-Za-z]*": \[/ { ev = $1; gsub(/[":]/, "", ev); gsub(/[A-Z]/, "_&", ev); ev = tolower(substr(ev, 2)); n = 0; next }
  /"matcher":/ { m = $0; sub(/^ *"matcher": *"/, "", m); sub(/",? *$/, "", m); next }
  /"hooks": \[/ { idx = n++; cm = m; m = ""; next }
  /"command":/ { c = $0; sub(/^ *"command": *"/, "", c); sub(/",? *$/, "", c); i = index(c, "${CLAUDE_PLUGIN_ROOT}")
                 if (i) c = substr(c, 1, i - 1) root substr(c, i + 21); next }
  /"timeout":/ { t = $0; gsub(/[^0-9]/, "", t); next }
  /^ *},?$/ && c != "" { printf "corecrew@corekit:hooks/hooks.json:%s:%d:0|%s|%s|%s\n", ev, idx, cm, c, t; c = ""; t = "" }
' "$PLUGIN/hooks/hooks.json" | LC_ALL=C sort > "$SANDBOX/want"
sed -E 's/^[{]"key":"([^"]*)".*"command":"(.*)","async":.*"matcher":(null|"[^"]*"),"timeoutSec":([0-9]+|null),.*$/\1|\3|\2|\4/' \
  "$SANDBOX/cc-hooks" | sed -E 's/^([^|]*)[|](null|"([^"]*)")[|]/\1|\3|/' | LC_ALL=C sort > "$SANDBOX/got"
if cmp -s "$SANDBOX/want" "$SANDBOX/got"; then pass; else fail "matcher, command or timeout differ from hooks.json: $(diff "$SANDBOX/want" "$SANDBOX/got" | head -12)"; fi
assert_not_contains "$SANDBOX/cc-hooks" 'CLAUDE_PLUGIN_ROOT'
# the featured-plugin prefetch is off: Codex does not even try that request (the helper's closed proxy makes a try
# fail and log a WARN, so the try shows even when the machine is online)
assert_not_contains "$HL.err" 'featured plugin'
assert_eq "$(grep -c '"warnings":\[\],"errors":\[\]' "$HL")" "1" "hooks/list reports no warning or error"
# trustStatus "untrusted" is Codex's default for a hook nobody reviewed: asserted only as the fact the README's Codex
# section relies on (the person reviews and trusts the hooks in /hooks before they run), not as a corecrew choice
assert_eq "$(grep -c '"trustStatus":"untrusted"' "$SANDBOX/cc-hooks")" "5" "every corecrew hook is untrusted until reviewed"

cd "$SANDBOX/work" || exit 1
cx debug prompt-input "hi" > "$SANDBOX/prompt.json" 2> "$SANDBOX/prompt.err"; assert_eq "$?" "0" "debug prompt-input exits 0"
if grep -qiE 'openai\.yaml|plugin\.json|invalid|failed to' "$SANDBOX/prompt.err"; then fail "Codex warned: $(head -3 "$SANDBOX/prompt.err")"; else pass; fi
# the prompt lists skills with a root alias: (file: r1/corecrew/<version>/skills/new-project/SKILL.md),
# r1 = <CODEX_HOME>/plugins/cache/corekit
text="$(sed 's/\\n/\n/g' "$SANDBOX/prompt.json")"
listed() { printf '%s\n' "$text" | grep -c "^- corecrew:$1: "; }
assert_eq "$(listed new-project)" "1" "new-project is listed"
assert_eq "$(listed bloat-audit)" "1" "bloat-audit is listed (it triggers by meaning)"
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
