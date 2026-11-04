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
assert_contains "$PJ" '"version": "0.1.1"'
assert_contains "$PJ" '"license": "MIT"'
# author, homepage and repository: the same lines as coreeffort's (the handle stays out of tests)
CE="$ROOT/plugins/coreeffort/.claude-plugin/plugin.json"
for key in author homepage repository; do
  assert_eq "$(grep "\"$key\":" "$PJ")" "$(grep "\"$key\":" "$CE")" "$key like coreeffort"
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
for p in corecrew coreeffort coreopinion; do
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

# secrets: list paths first, read a diff only through the exclusion pathspec, never a bare full diff
assert_contains "$S" 'git diff HEAD --name-only'
assert_contains "$S" 'git show --name-only --format= HEAD'
assert_not_contains "$S" 'then `git diff HEAD` (unstaged'
assert_not_contains "$S" 'then `git show HEAD`'
# the pathspec line in SKILL.md, run for real on a throwaway repo full of secret-looking files
spec_line="$(grep -m1 '^git diff HEAD --name-only -- \. ' "$S")"
assert_eq "${spec_line:+found}" "found" "SKILL.md has a 'git diff HEAD --name-only -- . <pathspec>' line"
new_sandbox
R="$SANDBOX/secrets-repo"; mkdir -p "$R/sub" "$R/keys"
git -C "$R" init -q
printf 'x\n' > "$R/ok.txt"; git -C "$R" add ok.txt; git -C "$R" commit -qm init
for f in .env .env.local sub/.env sub/.env.production keys/id_rsa keys/id_rsa.pub keys/id_ed25519 \
         a.pem b.key c.p12 d.pfx sub/aws-credentials.json ok.txt sub/app.sh; do
  printf 'changed\n' >> "$R/$f"
done
git -C "$R" add -A
specs="${spec_line#git diff HEAD --name-only -- . }"
got="$(cd "$R" && eval "set -- $specs" && git diff HEAD --name-only -- . "$@" | LC_ALL=C sort | tr '\n' ';')"
assert_eq "$got" "ok.txt;sub/app.sh;" "the exclusion pathspec keeps only non-secret files"
# a 429 is not always the plan's limit: the skill quotes the error instead of guessing
assert_contains "$S" 'quote the error line'
assert_not_contains "$S" '`429`, `quota`): the ChatGPT plan'"'"'s Codex limit'

# docs
assert_file "$P/README.md"
assert_contains "$P/README.md" '/plugin install coreopinion@corekit'
assert_contains "$P/README.md" '/coreopinion:second-opinion'
assert_contains "$P/README.md" 'read-only'
assert_contains "$P/README.md" 'excludedCommands'
assert_file "$P/CHANGELOG.md"
assert_eq "$(grep -m1 '^## ' "$P/CHANGELOG.md" | cut -c1-9)" '## 0.1.1 ' "coreopinion CHANGELOG first entry"
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
