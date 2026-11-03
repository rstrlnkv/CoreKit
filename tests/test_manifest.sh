#!/usr/bin/env bash
# Plugin and marketplace manifests: name, version, settings, dependency, rename; docs follow.
source "$(dirname "$0")/lib.sh"
P="$ROOT/.claude-plugin/plugin.json"
M="$ROOT/.claude-plugin/marketplace.json"

# plugin.json
assert_contains "$P" '"name": "coredev"'
assert_contains "$P" '"version": "0.2.1"'
assert_contains "$P" '"userConfig"'
for key in core_dir attribution model_profile ui_language; do assert_contains "$P" "\"$key\""; done
assert_contains "$P" '"type": "directory"'
assert_contains "$P" '"default": "~/Projects/Core"'
assert_contains "$P" '"options": ["allow", "forbid"]'
assert_contains "$P" '"default": "allow"'
assert_contains "$P" '"options": ["economy", "balanced", "strong"]'
assert_contains "$P" '"default": "balanced"'
assert_contains "$P" '"title": "Hook messages language"'
assert_contains "$P" '"description": "Language of the messages coredev hooks show: en (English) or ru (Russian)."'
assert_contains "$P" '"options": ["en", "ru"]'
assert_contains "$P" '"default": "en"'
assert_contains "$ROOT/README.md" '`ui_language`'
assert_contains "$ROOT/README.md" 'claude plugin install coredev@corekit --config ui_language=ru'
assert_not_contains "$P" '"dependencies"'   # a hard dependency stops coredev loading when feature-dev is synced from claude.ai
assert_not_contains "$P" '"marketplace": "claude-plugins-official"'

# marketplace.json
assert_contains "$M" '"name": "corekit"'
assert_contains "$M" '"name": "coredev"'
assert_contains "$M" '"renames"'
assert_contains "$M" '"corekit": "coredev"'
assert_not_contains "$M" 'allowCrossMarketplaceDependenciesOn'

# README and CHANGELOG
assert_contains "$ROOT/README.md" '/plugin install coredev@corekit'
assert_not_contains "$ROOT/README.md" '/corekit:'
assert_not_contains "$ROOT/README.md" 'corekit@corekit'
assert_eq "$(grep -m1 '^## ' "$ROOT/CHANGELOG.md" | cut -c1-9)" '## 0.2.1 ' "CHANGELOG first entry"
assert_contains "$ROOT/CHANGELOG.md" '## 0.2.1 — 2026-11-04'
assert_contains "$ROOT/CHANGELOG.md" '## 0.2.0 — '

# hooks.json: plugin Stop hook; no install.sh any more
assert_file "$ROOT/hooks/hooks.json"
H="$ROOT/hooks/hooks.json"
assert_contains "$H" '"Stop"'
assert_contains "$H" '"timeout"'
# hooks.json wires all five hooks (spec section 14). One key per line, so awk can pair each event and
# matcher with its command and timeout: "Event|matcher|script|timeout".
WIRED="$(awk '
  /^    "[A-Za-z]+": \[/ { ev = $1; gsub(/[":]/, "", ev); m = "" }
  /"matcher":/ { m = $0; sub(/.*"matcher": "/, "", m); sub(/".*/, "", m) }
  /"command":/ { c = $0; sub(/.*\/hooks\//, "", c); sub(/\\".*/, "", c) }
  /"timeout":/ { t = $0; gsub(/[^0-9]/, "", t); print ev "|" m "|" c "|" t }
' "$H")"
want_wired="SessionStart|startup|resume|clear|compact|session-start.sh|30
PreToolUse|Bash|one-suite.sh|540
PreToolUse|Write|Edit|MultiEdit|NotebookEdit|Bash|guard-code.sh|15
PreToolUse|Read|Grep|Glob|Edit|MultiEdit|Write|NotebookEdit|Bash|guard-secrets.sh|15
Stop||stop-remind.sh|10"
assert_eq "$WIRED" "$want_wired" "hooks.json events, matchers, scripts, timeouts"
for s in session-start one-suite guard-code guard-secrets stop-remind; do
  assert_contains "$H" "/hooks/$s.sh"
  assert_file "$ROOT/hooks/$s.sh"
done
# every command runs through bash (the scripts are not executable) and via the plugin root
n_cmd="$(grep -c '"command":' "$H")"; n_to="$(grep -c '"timeout":' "$H")"
assert_eq "$n_cmd" "5" "hook commands in hooks.json"
assert_eq "$n_to" "$n_cmd" "every hook command has a timeout"
n_ok="$(grep -c '"command": "bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/[a-z-]*\.sh\\""' "$H")"
assert_eq "$n_ok" "$n_cmd" "every command is bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/<script>\""
# one-suite waits up to ONE_SUITE_WAIT (default) seconds; its timeout must be larger
wait_default="$(sed -n 's/.*limit="${ONE_SUITE_WAIT:-\([0-9]*\)}".*/\1/p' "$HOOKS/one-suite.sh" | head -1)"
suite_to="$(printf '%s\n' "$WIRED" | awk -F'|' '$(NF-1) == "one-suite.sh" { print $NF }')"
case "$wait_default" in ''|*[!0-9]*) fail "cannot read the ONE_SUITE_WAIT default from one-suite.sh" ;; *) pass ;; esac
case "$suite_to" in ''|*[!0-9]*) fail "one-suite has no timeout in hooks.json" ;; *)
  [ "$suite_to" -gt "${wait_default:-0}" ] && pass || fail "one-suite timeout $suite_to <= default wait $wait_default" ;; esac
# well-formed JSON (test-only use of python3; plugin code never uses it)
if command -v python3 >/dev/null 2>&1; then
  assert_exit 0 python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$H"
else
  echo "  note: python3 not found, JSON well-formedness of hooks.json not checked"
fi
assert_no_file "$ROOT/install.sh"; assert_no_file "$ROOT/tests/test_install.sh"
assert_not_contains "$ROOT/README.md" 'install.sh'
assert_contains "$ROOT/README.md" '2.1.271'
assert_contains "$ROOT/README.md" '/plugin install feature-dev@claude-plugins-official'
T="$ROOT/skills/new-project/templates"
assert_not_contains "$T/code/settings.local.json.tmpl" '"hooks"'
assert_contains "$T/code/settings.local.json.tmpl" '"additionalDirectories"'
assert_not_contains "$T/CLAUDE.md.tmpl" '/bin/'
assert_contains "$T/CLAUDE.md.tmpl" 'undo-step'
assert_contains "$T/CLAUDE.md.tmpl" 'printed at session start'

# migration note: the seven steps of spec section 6
MG="$ROOT/docs/migration-0.2.md"
assert_file "$MG"
assert_contains "$MG" '/plugin install coredev@corekit'
assert_contains "$MG" 'claude plugin disable corekit@synced'
assert_not_contains "$MG" 'see below'
assert_not_contains "$MG" 'TODO'
assert_contains "$MG" 'install-hooks.sh'
assert_contains "$MG" 'session-rules.md'
for n in 1 2 3 4 5 6 7; do assert_contains "$MG" "### Step $n"; done

finish
