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
assert_contains "$PJ" '"version": "0.2.0"'
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
# 0.2.0: the exclusion pathspec also covers cloud, package-manager and infra secrets
R2="$SANDBOX/secrets2"; mkdir -p "$R2/.aws" "$R2/sub" "$R2/k"
git -C "$R2" init -q; printf 'x\n' > "$R2/ok.txt"; git -C "$R2" add ok.txt; git -C "$R2" commit -qm init
for f in .npmrc sub/.netrc .pypirc .git-credentials prod.tfvars a.auto.tfvars terraform.tfstate terraform.tfstate.backup \
         app.jks release.keystore AuthKey_X.p8 my-secret.txt SECRETS.md api_token.txt tokens.json kubeconfig k/kubeconfig-prod \
         db.kdbx .aws/config .aws/credentials gcp-service-account.json service_account_key.json sa-serviceaccount.json ok.txt; do
  printf 'changed\n' >> "$R2/$f"
done
git -C "$R2" add -A
got="$(cd "$R2" && eval "set -- $specs" && git diff HEAD --name-only -- . "$@" | LC_ALL=C sort | tr '\n' ';')"
assert_eq "$got" "ok.txt;" "the widened pathspec drops cloud/infra/package secrets"
# untracked files go through the same pathspec: the skill has an ls-files line for them
ut_line="$(grep -m1 '^git ls-files --others --exclude-standard -- \. ' "$S")"
assert_eq "${ut_line:+found}" "found" "SKILL.md filters untracked files with the same pathspec"
R3="$SANDBOX/untracked"; mkdir -p "$R3"; git -C "$R3" init -q
for f in new.sh .npmrc deploy.tfvars my-token.txt note.md; do printf 'x\n' > "$R3/$f"; done
got="$(cd "$R3" && eval "set -- $specs" && git ls-files --others --exclude-standard -- . "$@" | LC_ALL=C sort | tr '\n' ';')"
assert_eq "$got" "new.sh;note.md;" "untracked secrets are filtered"
# named files are checked with the same pathspec
nm_line="$(grep -m1 '^git ls-files --cached --others --exclude-standard -- <named' "$S")"
assert_eq "${nm_line:+found}" "found" "SKILL.md checks user-named files against the pathspec"
# a repo with no commits: the diff base is the empty tree, an error is not 'nothing to review'
assert_contains "$S" 'git hash-object -t tree /dev/null'
assert_contains "$S" 'is not "nothing to review"'
R4="$SANDBOX/nocommit"; mkdir -p "$R4"; git -C "$R4" init -q; printf 'x\n' > "$R4/a.sh"; git -C "$R4" add a.sh
got="$(cd "$R4" && git diff "$(git hash-object -t tree /dev/null)" --name-only | tr '\n' ';')"
assert_eq "$got" "a.sh;" "empty-tree base lists staged files in a repo without commits"
# the user confirms the file list before anything is sent
assert_contains "$S" 'wait for the'
assert_contains "$S" 'Nothing is sent before'
# what read-only really confines: honest wording, narrowed profile, user config off
assert_contains "$S" 'default_permissions='
assert_contains "$S" '--ignore-user-config'
assert_contains "$S" 'web_search="disabled"'
assert_contains "$S" '":project_roots"'
# the profile blocks, inside the project, every secret the send filter drops (README promises it).
# Checked for real with `codex sandbox` (local, nothing goes to OpenAI) where codex is installed.
profile="$(grep -o "permissions.review.filesystem={.*}}'" "$S" | head -1 | sed "s/'\$//")"
assert_eq "${profile:+found}" "found" "SKILL.md has the review permission profile"
if command -v codex >/dev/null 2>&1 && codex sandbox --help >/dev/null 2>&1; then
  R5="$SANDBOX/profile"; mkdir -p "$R5/.aws" "$R5/sub" "$R5/k"; git -C "$R5" init -q
  secrets='.env prod.env app.env.local sub/.env.prod key.pem server.key cert.p12 cert.pfx id_rsa id_ed25519.pub Credentials.txt
           .npmrc sub/.netrc .pypirc .git-credentials prod.tfvars terraform.tfstate terraform.tfstate.backup app.jks release.keystore
           AuthKey_X.p8 my-secret.txt SECRETS.md api_token.txt kubeconfig k/kubeconfig-prod db.kdbx .aws/config
           gcp-service-account.json service_account_key.json sa-serviceaccount.json'
  for f in $secrets ok.txt; do printf 'x\n' > "$R5/$f"; done
  if ( cd "$R5" && codex sandbox -c 'default_permissions="review"' -c "$profile" cat ok.txt >/dev/null 2>&1 ); then
    open=""
    for f in $secrets; do
      ( cd "$R5" && codex sandbox -c 'default_permissions="review"' -c "$profile" cat "$f" >/dev/null 2>&1 ) && open="$open $f"
    done
    assert_eq "${open:-none}" "none" "the codex profile blocks every secret the filter drops"
  else
    echo "  note: codex sandbox cannot read an ordinary file here (nested sandbox?), the profile is not run"
  fi
else
  echo "  note: codex not installed, the profile is not run"
fi
assert_not_contains "$S" 'GPT can read the project but'
assert_not_contains "$P/README.md" 'GPT can read the project but'
assert_contains "$P/README.md" 'whole disk'
assert_contains "$P/README.md" 'codex sandbox'
# the -C path never goes through shell parsing: it is read from a file
assert_not_contains "$S" '-C "<project dir>"'
assert_contains "$S" '-C "$(cat "$T/dir")"'
run_line="$(grep -m1 '^codex exec ' "$S")"
assert_eq "${run_line:+found}" "found" "SKILL.md has a codex exec line"
BAD="$SANDBOX/we ird\"\$(touch PWNED)\`touch PWNED2\`dir"; mkdir -p "$BAD"
T2="$SANDBOX/T2"; mkdir -p "$T2"; printf '%s' "$BAD" > "$T2/dir"; printf 'p\n' > "$T2/prompt.md"
mkdir -p "$SANDBOX/stub"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$STUB_ARGS"\n' > "$SANDBOX/stub/codex"; chmod +x "$SANDBOX/stub/codex"
( cd "$SANDBOX" && export STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" T="$T2" && eval "$run_line" >/dev/null 2>&1 )
assert_eq "$([ -e "$SANDBOX/PWNED" ] || [ -e "$SANDBOX/PWNED2" ] && echo ran || echo safe)" "safe" "a hostile project path runs nothing"
assert_contains "$SANDBOX/args.txt" 'PWNED'
# cleanup happens whatever the run does: one trap line, run block ends by printing the answer
assert_contains "$S" "trap 'rm -rf \"\$T\"' EXIT HUP INT TERM"
assert_contains "$S" 'cat "$T/answer.md"'
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
assert_eq "$(grep -m1 '^## ' "$P/CHANGELOG.md" | cut -c1-9)" '## 0.2.0 ' "coreopinion CHANGELOG first entry"
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
