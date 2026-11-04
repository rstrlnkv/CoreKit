#!/usr/bin/env bash
# The coreopinion plugin: manifest, marketplace entry, the second-opinion skill and its docs.
# No network and no codex run: these are file checks only.
source "$(dirname "$0")/lib.sh"
P="$ROOT/plugins/coreopinion"
PJ="$P/.claude-plugin/plugin.json"
M="$ROOT/.claude-plugin/marketplace.json"
S="$P/skills/second-opinion/SKILL.md"

# manifest
assert_file "$PJ"
assert_contains "$PJ" '"name": "coreopinion"'
assert_contains "$PJ" '"displayName": "CoreOpinion"'
assert_contains "$PJ" '"version": "0.1.0"'
assert_contains "$PJ" '"license": "MIT"'
# author, homepage and repository: the same lines as coremodel's (the handle stays out of tests)
CE="$ROOT/plugins/coremodel/.claude-plugin/plugin.json"
for key in author homepage repository; do
  assert_eq "$(grep "\"$key\":" "$PJ")" "$(grep "\"$key\":" "$CE")" "$key like coremodel"
done
assert_contains "$PJ" '"description": '
# well-formed JSON (test-only use of python3; plugin code never uses it)
if command -v python3 >/dev/null 2>&1; then
  assert_exit 0 python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PJ"
  assert_exit 0 python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$M"
else
  echo "  note: python3 not found, JSON well-formedness not checked"
fi

# marketplace: a separate entry with its own source; the description names every plugin
assert_contains "$M" '"name": "coreopinion"'
assert_contains "$M" '"displayName": "CoreOpinion"'
assert_contains "$M" '"source": "./plugins/coreopinion"'
desc="$(grep -m1 '"description"' "$M")"
for p in corecrew coremodel coreopinion; do
  case "$desc" in *"$p"*) pass ;; *) fail "marketplace description does not name $p" ;; esac
done

# the skill
assert_file "$S"
assert_eq "$(head -1 "$S")" "---" "SKILL.md starts with frontmatter"
assert_contains "$S" 'name: second-opinion'
assert_contains "$S" 'description: '
for phrase in 'second opinion' 'GPT' 'Codex' 'review'; do assert_contains "$S" "$phrase"; done
assert_contains "$S" '--sandbox read-only'
assert_contains "$S" 'model_reasoning_effort=medium'
assert_contains "$S" 'model_reasoning_effort=high'
assert_contains "$S" '--output-last-message'
assert_contains "$S" 'git diff HEAD'
assert_contains "$S" 'command -v codex'
assert_contains "$S" 'Operation not permitted'
assert_contains "$S" 'excludedCommands'
assert_contains "$S" '.env'
assert_contains "$S" '~/.ssh'
assert_contains "$S" "user's language"
assert_not_contains "$S" 'danger-full-access'
assert_not_contains "$S" 'workspace-write'
assert_not_contains "$S" 'dangerously-bypass'

# docs
assert_file "$P/README.md"
assert_contains "$P/README.md" '/plugin install coreopinion@corekit'
assert_contains "$P/README.md" '/coreopinion:second-opinion'
assert_contains "$P/README.md" 'read-only'
assert_contains "$P/README.md" 'excludedCommands'
assert_file "$P/CHANGELOG.md"
assert_eq "$(grep -m1 '^## ' "$P/CHANGELOG.md" | cut -c1-9)" '## 0.1.0 ' "coreopinion CHANGELOG first entry"
assert_contains "$ROOT/README.md" '/plugin install coreopinion@corekit'
assert_contains "$ROOT/README.md" 'plugins/coreopinion/README.md'
assert_contains "$ROOT/CLAUDE.md" 'plugins/coreopinion/'

# validates on its own, where the claude CLI is present
if command -v claude >/dev/null 2>&1; then
  assert_exit 0 claude plugin validate "$P"
else
  echo "  note: claude not on PATH, plugin validate skipped"
fi
finish
