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
assert_contains "$PJ" '"version": "0.2.3"'
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
assert_contains "$P/skills/second-opinion/scripts/ask-gpt.sh" 'model_reasoning_effort="$effort"'
assert_contains "$S" 'pass `high` only when the user asks'
assert_contains "$P/skills/second-opinion/scripts/ask-gpt.sh" '--output-last-message'
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
# named files go through scripts/allowed-files.sh. `git ls-files -- <files in one folder> <excludes>`
# is wrong both ways (git 2.54): plain excludes list nothing, glob excludes let secrets through.
AF="$P/skills/second-opinion/scripts/allowed-files.sh"
assert_file "$AF"
assert_contains "$S" 'scripts/allowed-files.sh'
assert_not_contains "$S" '-- <named paths>'
R6="$SANDBOX/named"; mkdir -p "$R6/plugins/x/hooks" "$R6/sub/.aws" "$R6/sp ace" "$R6/new"; git -C "$R6" init -q; git -C "$R6" config core.ignorecase true
for f in plugins/x/hooks/g.sh plugins/x/hooks/h.sh plugins/x/hooks/.env sub/prod.env sub/Credentials.json sub/.aws/config sub/app.sh README.md "sp ace/f.md"; do printf 'x\n' > "$R6/$f"; done
git -C "$R6" add -A; git -C "$R6" commit -qm init
printf 'x\n' > "$R6/new/untracked.sh"; printf 'x\n' > "$R6/new/.env.local"
af() { (cd "$R6${2:+/$2}" && eval "bash \"\$AF\" $1") | LC_ALL=C sort | tr '\n' ';'; }
assert_eq "$(af 'plugins/x/hooks/g.sh')" "plugins/x/hooks/g.sh;" "one nested file"
assert_eq "$(af 'plugins/x/hooks/g.sh plugins/x/hooks/h.sh plugins/x/hooks/.env')" "plugins/x/hooks/g.sh;plugins/x/hooks/h.sh;" "files in one folder: the secret dropped"
assert_eq "$(af 'plugins/x/hooks/.env')" "" "a named secret alone: nothing"
assert_eq "$(af 'sub sub/prod.env')" "sub/app.sh;" "a folder: its allowed files only"
assert_eq "$(af './new/ README.md')" "README.md;new/untracked.sh;" "untracked and ./ prefixed"
assert_eq "$(af '"sp ace/f.md"')" "sp ace/f.md;" "a path with a space"
assert_eq "$(af 'x/hooks/g.sh' plugins)" "x/hooks/g.sh;" "from a subfolder, relative to it"
assert_eq "$(af 'missing.txt')" "" "a missing path: nothing"
(cd "$SANDBOX" && bash "$AF" a >/dev/null 2>&1); assert_eq "$?" "3" "outside a git repository: exit 3"
# a repo with no commits: the diff base is the empty tree, an error is not 'nothing to review'
assert_contains "$S" 'git hash-object -t tree /dev/null'
assert_contains "$S" 'is not "nothing to review"'
R4="$SANDBOX/nocommit"; mkdir -p "$R4"; git -C "$R4" init -q; printf 'x\n' > "$R4/a.sh"; git -C "$R4" add a.sh
got="$(cd "$R4" && git diff "$(git hash-object -t tree /dev/null)" --name-only | tr '\n' ';')"
assert_eq "$got" "a.sh;" "empty-tree base lists staged files in a repo without commits"
# the user confirms the file list before anything is sent
assert_contains "$S" 'wait for the'
assert_contains "$S" 'Nothing is sent before'
# what read-only really confines: honest wording, narrowed profile, user config off (in the run script)
A="$P/skills/second-opinion/scripts/ask-gpt.sh"
assert_contains "$A" 'default_permissions='
assert_contains "$A" '--ignore-user-config'
assert_contains "$A" 'web_search="disabled"'
assert_contains "$A" '":project_roots"'
# the run needs one yes (the skill's own): the script is pre-approved for the skill's turn only
assert_contains "$S" 'allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/ask-gpt.sh *)'
assert_contains "$S" 'bash "${CLAUDE_SKILL_DIR}/scripts/ask-gpt.sh" "'
# the profile blocks, inside the project, every secret the send filter drops (README promises it).
# Checked for real with `codex sandbox` (local, nothing goes to OpenAI) where codex is installed.
A="$P/skills/second-opinion/scripts/ask-gpt.sh"
assert_file "$A"
profile="$(grep -o "permissions.review.filesystem={.*}}'" "$A" | head -1 | sed "s/'\$//")"
assert_eq "${profile:+found}" "found" "ask-gpt.sh has the review permission profile"
if command -v codex >/dev/null 2>&1 && codex sandbox --help >/dev/null 2>&1; then
  R5="$SANDBOX/profile"; mkdir -p "$R5/.aws" "$R5/sub" "$R5/k"; git -C "$R5" init -q
  secrets='.env prod.env app.env.local sub/.env.prod key.pem server.key cert.p12 cert.pfx id_rsa id_ed25519.pub Credentials.txt
           .npmrc sub/.netrc .pypirc .git-credentials prod.tfvars terraform.tfstate terraform.tfstate.backup app.jks release.keystore
           AuthKey_X.p8 my-secret.txt SECRETS.md api_token.txt kubeconfig k/kubeconfig-prod db.kdbx .aws/config
           gcp-service-account.json service_account_key.json sa-serviceaccount.json
           Credentials.json KubeConfig ServiceAccount.json API_TOKEN.txt MY_SECRET.md'
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
# the -C path never goes through shell parsing: it is read from a file by the script
assert_not_contains "$S" '-C "<project dir>"'
assert_not_contains "$S" 'codex exec --ignore-user-config'   # one copy of the command: the script's
mkdir -p "$SANDBOX/stub"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$STUB_ARGS"\necho "GPT says hi" > "$(dirname "$STUB_ARGS")/last"\nfor a; do case "$p" in --output-last-message) echo "GPT says hi" > "$a" ;; esac; p="$a"; done\n' > "$SANDBOX/stub/codex"; chmod +x "$SANDBOX/stub/codex"
BAD="$SANDBOX/we ird\"\$(touch PWNED)\`touch PWNED2\`dir"; mkdir -p "$BAD"; git -C "$BAD" init -q
T2="$(mktemp -d)"; printf '%s' "$BAD" > "$T2/dir"; printf 'p\n' > "$T2/prompt.md"
OUT="$(cd "$SANDBOX" && STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" bash "$A" "$T2" 2>&1)"
assert_eq "$([ -e "$SANDBOX/PWNED" ] || [ -e "$SANDBOX/PWNED2" ] && echo ran || echo safe)" "safe" "a hostile project path runs nothing"
assert_contains "$SANDBOX/args.txt" 'PWNED'
assert_not_contains "$SANDBOX/args.txt" '--skip-git-repo-check'
case "$OUT" in *"exit=0"*"--- answer"*"GPT says hi"*"--- log tail"*) pass ;; *) fail "ask-gpt.sh output: $OUT" ;; esac
assert_no_file "$T2"   # the temp folder (it holds the diff) is gone after the run
grep -qx 'model_reasoning_effort=medium' "$SANDBOX/args.txt" && pass || fail "default effort is medium"
# high on request; anything else falls back to medium
T3="$(mktemp -d)"; printf '%s' "$BAD" > "$T3/dir"; printf 'p\n' > "$T3/prompt.md"
( STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" bash "$A" "$T3" xhigh >/dev/null 2>&1 )
grep -qx 'model_reasoning_effort=medium' "$SANDBOX/args.txt" && pass || fail "an unknown effort falls back to medium"
# outside a git repository: the flag, and an empty folder instead of the project
NR="$SANDBOX/norepo"; mkdir -p "$NR"; printf 'x\n' > "$NR/f.txt"
T4="$(mktemp -d)"; printf '%s' "$NR" > "$T4/dir"; printf 'p\n' > "$T4/prompt.md"
( STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" bash "$A" "$T4" >/dev/null 2>&1 )
assert_contains "$SANDBOX/args.txt" '--skip-git-repo-check'
assert_eq "$(grep -A1 -x -- '-C' "$SANDBOX/args.txt" | tail -1)" "$T4/empty" "no repo: Codex gets an empty folder"
# a missing prompt is refused, and the folder is not removed then
T5="$(mktemp -d)"
( PATH="$SANDBOX/stub:$PATH" bash "$A" "$T5" >/dev/null 2>&1 ); assert_eq "$?" "2" "missing prompt: refused"
assert_dir "$T5"; rm -rf "$T5"
# the folder the script removes must be a mktemp folder right in the temp folder: a wrong path (the
# project, say) that happens to hold prompt.md and dir is refused and left alone
PRJ="$SANDBOX/proj"; mkdir -p "$PRJ"; printf '%s' "$BAD" > "$PRJ/dir"; printf 'p\n' > "$PRJ/prompt.md"; printf 'keep\n' > "$PRJ/code.sh"
( PATH="$SANDBOX/stub:$PATH" bash "$A" "$PRJ" >/dev/null 2>&1 ); assert_eq "$?" "2" "not a temp folder: refused"
assert_file "$PRJ/code.sh"
TD="$(mktemp -d)"; mkdir -p "$TD/inner"; printf '%s' "$BAD" > "$TD/inner/dir"; printf 'p\n' > "$TD/inner/prompt.md"
( PATH="$SANDBOX/stub:$PATH" bash "$A" "$TD/inner" >/dev/null 2>&1 ); assert_eq "$?" "2" "a folder inside a temp folder: refused"
assert_dir "$TD/inner"; rm -rf "$TD"
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
assert_eq "$(grep -m1 '^## ' "$P/CHANGELOG.md" | cut -c1-9)" '## 0.2.3 ' "coreopinion CHANGELOG first entry"
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
