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
assert_contains "$PJ" '"version": "0.2.5"'
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
# One list of secret names (scripts/secret-patterns.txt) feeds the send filter and the Codex profile.
# SKILL.md does not paste the pathspec: it takes it from `allowed-files.sh --pathspec` as <EXCLUDE>.
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }   # has <text> <literal part>
SP="$P/skills/second-opinion/scripts/secret-patterns.txt"
AF="$P/skills/second-opinion/scripts/allowed-files.sh"
assert_file "$SP"
assert_file "$AF"
assert_contains "$S" 'secret-patterns.txt'
assert_contains "$S" 'allowed-files.sh" --pathspec'
assert_not_contains "$S" "':(exclude"
assert_contains "$S" 'git diff HEAD --name-only -- . <EXCLUDE>'
assert_contains "$S" 'git ls-files --others --exclude-standard -- . <EXCLUDE>'
# the patterns: comment and blank lines dropped, text after a space is a comment
patterns="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]].*$//' -e '/^#/d' -e '/^$/d' "$SP" 2>/dev/null)"
assert_eq "${patterns:+found}" "found" "secret-patterns.txt lists patterns"
specs="$(bash "$AF" --pathspec)"
assert_eq "$?" "0" "allowed-files.sh --pathspec works (outside a repository too)"
# (a) every pattern is in the pathspec (case-insensitive glob at any depth)
missing="$(printf '%s\n' "$patterns" | while IFS= read -r g; do
  has " $specs " " ':(exclude,glob,icase)**/$g' " || printf ' %s' "$g"
done)"
assert_eq "${missing:-none}" "none" "every secret pattern is in the --pathspec output"
new_sandbox
R="$SANDBOX/secrets-repo"; mkdir -p "$R/sub" "$R/keys"
git -C "$R" init -q
printf 'x\n' > "$R/ok.txt"; git -C "$R" add ok.txt; git -C "$R" commit -qm init
for f in .env .env.local sub/.env sub/.env.production keys/id_rsa keys/id_rsa.pub keys/id_ed25519 \
         a.pem b.key c.p12 d.pfx sub/aws-credentials.json ok.txt sub/app.sh; do
  printf 'changed\n' >> "$R/$f"
done
git -C "$R" add -A
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
# (b) SSH keys of every kind, cluster, database, web and Docker credentials are dropped, at any depth;
# (c) ordinary source files still pass
R7="$SANDBOX/named2"; git init -q "$R7"
NEW='id_ecdsa id_ecdsa.pub id_dsa .ssh/config .ssh/known_hosts .ssh/my_key .kube/config .pgpass .htpasswd .dockercfg .docker/config.json'
for f in $NEW src/app.js sub/lib/util.py; do
  for d in "" deep/er/; do mkdir -p "$(dirname "$R7/$d$f")"; printf 'x\n' > "$R7/$d$f"; done
done
assert_eq "$(af . ../named2)" "deep/er/src/app.js;deep/er/sub/lib/util.py;src/app.js;sub/lib/util.py;" \
  "new secret names are dropped, ordinary files pass"
assert_eq "$(af 'src/app.js .kube/config deep/er/.ssh' ../named2)" "src/app.js;" "named: the ordinary file passes, secrets do not"
# a folder with a secret name: everything under it is dropped too (listed from ".", named, and through
# the --pathspec line SKILL.md uses for untracked files); ordinary files still pass
R9="$SANDBOX/secretdirs"; git init -q "$R9"
for f in secrets/config.yml credentials/gcp.json tokens/list.txt kubeconfig/prod deep/secrets/db.yml App/Secrets/x.yml \
         src/app.js sub/lib/util.py; do
  mkdir -p "$(dirname "$R9/$f")"; printf 'x\n' > "$R9/$f"
done
assert_eq "$(af . ../secretdirs)" "src/app.js;sub/lib/util.py;" "files under a folder with a secret name are dropped"
assert_eq "$(af 'secrets deep credentials/gcp.json src' ../secretdirs)" "src/app.js;" "named: a secret folder gives nothing"
got="$(cd "$R9" && eval "set -- $specs" && git ls-files --others --exclude-standard -- . "$@" | LC_ALL=C sort | tr '\n' ';')"
assert_eq "$got" "src/app.js;sub/lib/util.py;" "the --pathspec line drops files under a secret folder"
# (a) every pattern also covers everything under a folder of that name
missing="$(printf '%s\n' "$patterns" | while IFS= read -r g; do
  [ "${g%/\*\*}" = "$g" ] || continue   # a folder pattern (ending in /**) already covers what is under it
  has " $specs " " ':(exclude,glob,icase)**/$g/**' " || printf ' %s' "$g"
done)"
assert_eq "${missing:-none}" "none" "every secret pattern also excludes the folder of that name in --pathspec"
# --pathspec takes no other argument: a file named with it is not silently left unchecked
out="$(bash "$AF" --pathspec src/app.js 2>/dev/null)"; rc=$?
assert_eq "$rc:$out" "2:" "--pathspec with another argument: usage, exit 2, nothing printed"
# (d) every secret name corecrew blocks is dropped here too (the plugins stay independent: this is a test-only
# comparison). Each glob of corecrew's Codex profile becomes a sample name ([xX] -> x, * -> a, ? -> _);
# each secret regex of its blocked-patterns must match one of the samples, and no sample may pass.
CC="$ROOT/plugins/corecrew/scripts"
cc_globs="$(bash "$CC/lib.sh" codex-profile | sed -nE 's/^"\*\*\/(.*)" = "(none|deny)"$/\1/p')"
assert_eq "${cc_globs:+found}" "found" "corecrew codex-profile globs read"
samples="$(printf '%s\n' "$cc_globs" | sed -e 's/\[\(.\)[^]]*\]/\1/g' -e 's/\*\*/a/g' -e 's/\*/a/g' -e 's/?/_/g')"
R8="$SANDBOX/cross"; git init -q "$R8"
printf '%s\n' "$samples" | while IFS= read -r f; do mkdir -p "$(dirname "$R8/x/$f")"; printf 'x\n' > "$R8/x/$f"; done
printf 'x\n' > "$R8/x/ok.txt"
assert_eq "$(af . ../cross)" "x/ok.txt;" "every corecrew Codex-profile secret is dropped by coreopinion"
unmatched="$(grep -v -e CLAUDE -e AGENTS -e '\\\.claude/' -e '^\^docs/' "$CC/git-hooks/blocked-patterns" | while IFS= read -r re; do
  [ -n "$re" ] || continue
  printf '%s\n' "$samples" | grep -qE -- "$re" || printf ' %s' "$re"
done)"
assert_eq "${unmatched:-none}" "none" "every corecrew blocked-patterns secret has a sample (dropped above)"
# the list is required: without it nothing is printed and the script fails
NL="$SANDBOX/nolist"; mkdir -p "$NL"; cp "$AF" "$NL/"
out="$(cd "$R7" && bash "$NL/allowed-files.sh" src/app.js 2>/dev/null)"; rc=$?
assert_eq "$out" "" "no pattern list: nothing printed"
[ "$rc" -ne 0 ] && pass || fail "no pattern list: allowed-files.sh must fail"
(bash "$NL/allowed-files.sh" --pathspec >/dev/null 2>&1) && fail "no pattern list: --pathspec must fail" || pass
printf '# only a comment\n\n' > "$NL/secret-patterns.txt"
(cd "$R7" && bash "$NL/allowed-files.sh" src/app.js >/dev/null 2>&1) && fail "an empty pattern list must fail" || pass
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
# the profile is built from secret-patterns.txt: take it from a run with a stub codex that records its arguments
mkdir -p "$SANDBOX/stub"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$STUB_ARGS"\necho "GPT says hi" > "$(dirname "$STUB_ARGS")/last"\nfor a; do case "$p" in --output-last-message) echo "GPT says hi" > "$a" ;; esac; p="$a"; done\n' > "$SANDBOX/stub/codex"; chmod +x "$SANDBOX/stub/codex"
GR="$SANDBOX/gitrepo"; git init -q "$GR"
TP="$(mktemp -d)"; printf '%s' "$GR" > "$TP/dir"; printf 'p\n' > "$TP/prompt.md"
( STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" bash "$A" "$TP" >/dev/null 2>&1 )
profile="$(grep '^permissions\.review\.filesystem=' "$SANDBOX/args.txt" 2>/dev/null | head -1)"
assert_eq "${profile:+found}" "found" "ask-gpt.sh passes the review permission profile"
# (a) every pattern is in the profile, denied
missing="$(printf '%s\n' "$patterns" | while IFS= read -r g; do
  has "$profile" "\"**/$g\"=\"deny\"" || printf ' %s' "$g"
done)"
assert_eq "${missing:-none}" "none" "every secret pattern is denied in the Codex profile"
missing="$(printf '%s\n' "$patterns" | while IFS= read -r g; do
  [ "${g%/\*\*}" = "$g" ] || continue   # a folder pattern (ending in /**) already covers what is under it
  has "$profile" "\"**/$g/**\"=\"deny\"" || printf ' %s' "$g"
done)"
assert_eq "${missing:-none}" "none" "every secret pattern also denies the folder of that name in the Codex profile"
# the list is required: without it codex is never run
rm -f "$SANDBOX/args.txt"; cp "$A" "$NL/"; rm -f "$NL/secret-patterns.txt"
TP="$(mktemp -d)"; printf '%s' "$GR" > "$TP/dir"; printf 'p\n' > "$TP/prompt.md"
( STUB_ARGS="$SANDBOX/args.txt" PATH="$SANDBOX/stub:$PATH" bash "$NL/ask-gpt.sh" "$TP" >/dev/null 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && pass || fail "no pattern list: ask-gpt.sh must fail"
assert_no_file "$SANDBOX/args.txt"
assert_no_file "$TP"   # the temp folder (it holds the diff) is still removed
if command -v codex >/dev/null 2>&1 && codex sandbox --help >/dev/null 2>&1; then
  mkdir -p "$CODEX_HOME"   # the sandbox CODEX_HOME: codex refuses to start when it does not exist
  R5="$SANDBOX/profile"; mkdir -p "$R5/.aws" "$R5/sub" "$R5/k" "$R5/.ssh" "$R5/.kube" "$R5/.docker"; git -C "$R5" init -q
  mkdir -p "$R5/secrets" "$R5/credentials" "$R5/tokens" "$R5/sub/kubeconfig" "$R5/deep/secrets"
  secrets='.env prod.env app.env.local sub/.env.prod key.pem server.key cert.p12 cert.pfx id_rsa id_ed25519.pub Credentials.txt
           .npmrc sub/.netrc .pypirc .git-credentials prod.tfvars terraform.tfstate terraform.tfstate.backup app.jks release.keystore
           AuthKey_X.p8 my-secret.txt SECRETS.md api_token.txt kubeconfig k/kubeconfig-prod db.kdbx .aws/config
           gcp-service-account.json service_account_key.json sa-serviceaccount.json
           Credentials.json KubeConfig ServiceAccount.json API_TOKEN.txt MY_SECRET.md
           id_ecdsa id_dsa.pub .ssh/config .ssh/my_key .kube/config .pgpass .htpasswd .dockercfg .docker/config.json
           secrets/config.yml credentials/gcp.json tokens/a.txt sub/kubeconfig/prod deep/secrets/db.yml'
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
assert_eq "$(grep -m1 '^## ' "$P/CHANGELOG.md" | cut -c1-9)" '## 0.2.5 ' "coreopinion CHANGELOG first entry"
assert_contains "$ROOT/README.md" '/plugin install coreopinion@corekit'
assert_contains "$ROOT/README.md" 'plugins/coreopinion/README.md'

# validates on its own, where the claude CLI is present
if command -v claude >/dev/null 2>&1; then
  assert_exit 0 claude plugin validate "$P"
else
  echo "  note: claude not on PATH, plugin validate skipped"
fi
finish
