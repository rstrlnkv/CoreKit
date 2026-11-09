#!/usr/bin/env bash
# lib.sh codex-profile: the TOML fragment for ~/.codex/config.toml. Text checks always; the sandbox checks run the
# fragment through `codex sandbox` (no model, nothing sent) with CODEX_HOME in the test sandbox, and are skipped
# without `codex`.
source "$(dirname "$0")/lib.sh"
new_sandbox
trap 'rm -rf "$SANDBOX"' EXIT
FRAG="$SANDBOX/frag.toml"
bash "$SCRIPTS/lib.sh" codex-profile > "$FRAG"; assert_eq "$?" "0" "codex-profile exits 0"
# every non-comment line is blank, key = value or a [table]
bad="$(grep -vE '^[[:space:]]*(#.*)?$|^\[[^]]+\]$|^"[^"]+" = "[a-z]+"$|^default_permissions = "corecrew"$' "$FRAG")"
assert_eq "$bad" "" "fragment lines are comments, tables or key = value"
assert_eq "$(grep -c '^default_permissions = "corecrew"$' "$FRAG")" "1" "one default_permissions line"
assert_eq "$(grep -n '^default_permissions' "$FRAG" | cut -d: -f1)" "$(grep -n -m1 -v '^#' "$FRAG" | cut -d: -f1)" "default_permissions comes before any table"
grep -qi 'every Codex session' "$FRAG" && pass || fail "comment says it applies to every session"
# honest scope: the comment names what the profile does not do, and does not promise a hard boundary
for w in '--sandbox' '--dangerously-bypass-approvals-and-sandbox' 'sandbox_mode' '.codex/config.toml' 'git history' 'hard link' '/tmp' 'nvironment variables' 'CODEX_HOME' 'very top'; do
  grep -qF -- "$w" "$FRAG" && pass || fail "comment names: $w"
done
grep -qiE 'real boundary|drop that line' "$FRAG" && fail "comment still promises a boundary or advises dropping the line" || pass
# the broad name patterns are gone: they blocked tokenizer.py, secret_santa.py
for g in '*[tT]oken*' '*TOKEN*' '*[sS]ecret*' '*SECRET*'; do grep -qF "\"**/$g\"" "$FRAG" && fail "broad pattern still denied: $g" || pass; done
for g in '.env' '.env.*' '*.env' '*.pem' 'id_rsa*' 'id_ecdsa*' 'id_dsa*' '.npmrc' '.aws/**' '.kube/**' '.docker/config.json' '.htpasswd' '.pgpass' '*.token' '[tT]oken' '[sS]ecrets*' '*.secret' '*_[tT]oken' '*-[tT]oken' '*_[tT]oken.*' '.*[tT]oken' '.secrets*' '*client_secret*.json' '.dockercfg' '*-secret.*' '*_secret.*'; do assert_contains "$FRAG" "\"**/$g\" = \"deny\""; done
assert_contains "$FRAG" '"." = "write"'
assert_contains "$FRAG" '":minimal" = "read"'
assert_eq "$(grep -v '^#' "$FRAG" | grep 'ssh' | grep -vxF '"**/.ssh/**" = "deny"')" "" "~/.ssh stays closed by not being listed"
# Codex 0.166 documents ":workspace_roots" and "deny"; ":project_roots" and "none" are legacy aliases kept for now
assert_contains "$FRAG" '[permissions.corecrew.filesystem.":workspace_roots"]'
assert_eq "$(grep -v '^#' "$FRAG" | grep -cE ':project_roots|= "none"$')" "0" "no legacy alias (:project_roots, \"none\") outside comments"
# the deny patterns are the ones coreopinion's review profile blocks (it builds them from secret-patterns.txt)
pat="$ROOT/plugins/coreopinion/skills/second-opinion/scripts/secret-patterns.txt"
assert_file "$pat"
miss=""; set -f   # the patterns are globs: do not expand them
for g in $(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]].*$//' -e '/^#/d' -e '/^$/d' "$pat"); do
  case "$g" in .env\*) continue ;; esac   # the review profile's .env* is spelled .env, .env.* here
  grep -qF "\"**/$g\" = \"deny\"" "$FRAG" || miss="$miss $g"
done
# the review profile still has the broad token and secret globs; this one narrows them on purpose (tokenizer.py, secret_santa.py)
miss="$(printf '%s\n' $miss | grep -vxE '\*\[tT\]oken\*|\*TOKEN\*|\*\[sS\]ecret\*|\*SECRET\*' | tr '\n' ' ' | sed 's/ $//')"
set +f
assert_eq "$miss" "" "every secret pattern of the review profile is denied, but the four broad token and secret globs"

if ! command -v codex >/dev/null 2>&1; then skip codex-profile "codex not on PATH (sandbox checks)"; finish; fi
# the profile writes the temp folder (and git needs its config in a place it can read), so the fake home must not sit in the one the sandbox sees
H="$SANDBOX/home"; mkdir -p "$SANDBOX/tmp"; export TMPDIR="$SANDBOX/tmp"; cp "$GIT_CONFIG_GLOBAL" "$TMPDIR/gitconfig"; export GIT_CONFIG_GLOBAL="$TMPDIR/gitconfig"; mkdir -p "$CODEX_HOME" "$H/.ssh" "$SANDBOX/w/src"
cp "$FRAG" "$CODEX_HOME/config.toml"
echo SSHKEY > "$H/.ssh/x"; echo SECRET > "$SANDBOX/w/.env"; echo SECRET > "$SANDBOX/w/.env.local"; echo SECRET > "$SANDBOX/w/prod.env"
echo old > "$SANDBOX/w/src/a.txt"
git -C "$SANDBOX/w" init -q
cd "$SANDBOX/w" || exit 1
sbx() { codex sandbox -- "$@" 2>&1; }
for f in .env .env.local prod.env "$H/.ssh/x"; do
  out="$(sbx cat "$f")"; case "$out" in *SECRET*|*SSHKEY*) fail "readable in the sandbox: $f" ;; *"not permitted"*) pass ;; *) fail "unexpected for $f: $out" ;; esac
done
assert_eq "$(sbx sh -c 'echo new > src/a.txt && cat src/a.txt')" "new" "editing src/a.txt works"
assert_eq "$(sbx sh -c 'echo x > src/b.txt && cat src/b.txt')" "x" "creating a file in the project works"
out="$(codex sandbox -- git status -s 2>/dev/null)"; case "$out" in *"?? src/"*|*"?? .env"*) pass ;; *) fail "git status: $out" ;; esac
assert_eq "$(cat src/a.txt)" "new" "the edit landed on disk"
out="$(sbx sh -c "echo y > '$H/outside.txt'")"; case "$out" in *"not permitted"*) pass ;; *) fail "write outside the project: $out" ;; esac
assert_no_file "$H/outside.txt"
# --- inputs the first version did not feed: case, nesting, a path with spaces, cp, links, git objects
W2="$SANDBOX/w sp"; mkdir -p "$W2/config" "$W2/src"; cd "$W2" || exit 1; git init -q
for f in .ENV config/.env.local .envrc; do echo SECRET > "$f"; done
echo OK > src/a.txt; echo LINKTGT > "$H/other.txt"; ln -s "$H/.ssh/x" link_ssh; ln -s "$H/other.txt" link_other; 
ln .ENV hard_env; ln -s .ENV soft_env   # (a case-insensitive disk makes .ENV and .env one file; the patterns must match either way)
for f in .ENV config/.env.local soft_env link_ssh link_other; do
  out="$(sbx cat "$f")"; case "$out" in *SECRET*|*SSHKEY*|*LINKTGT*) fail "readable in the sandbox (spaces in the path): $f" ;; *"not permitted"*) pass ;; *) fail "unexpected for $f: $out" ;; esac
done
assert_eq "$(sbx cat .envrc)" "SECRET" ".envrc is not a secret file: readable"
assert_eq "$(sbx cat src/a.txt)" "OK" "a path with spaces: reading works"
assert_eq "$(sbx sh -c 'echo n > src/b.txt && cat src/b.txt')" "n" "a path with spaces: writing works"
out="$(sbx cp .ENV copy.txt)"; case "$out" in *"not permitted"*) pass ;; *) fail "cp of .env: $out" ;; esac
assert_no_file "$W2/copy.txt"
out="$(sbx sh -c 'echo x > made.env; echo x > .env.new; echo x > deep.ENV.bak')"; assert_eq "$(printf '%s\n' "$out" | grep -c 'not permitted')" "3" "creating secret-named files is refused"
out="$(sbx ln .ENV h_new)"; case "$out" in *"not permitted"*) pass ;; *) fail "hardlinking .env inside the sandbox: $out" ;; esac
assert_no_file "$W2/h_new"
# KNOWN LIMITS of a path-based profile (pinned so a change shows; the fragment's comment should say so): a hard link made
# outside the sandbox is another path to the same bytes, and secrets already committed are readable through git objects.
assert_eq "$(sbx cat hard_env)" "SECRET" "KNOWN LIMIT: a pre-existing hard link to .env is readable"
GITBIN="$(xcrun --find git 2>/dev/null || command -v git)"
git add -f .ENV .envrc; git -c user.email=a@b -c user.name=n commit -qm c
assert_eq "$(sbx "$GITBIN" show HEAD:.ENV)" "SECRET" "KNOWN LIMIT: a committed .ENV is readable through git show"
out="$(sbx "$GITBIN" add -f .ENV)"; case "$out" in *"not permitted"*|*"cannot"*|*"fatal"*) pass ;; *) fail "git add of .env: $out" ;; esac
# --- names added and narrowed (fixtures outside /tmp; own TMPDIR)
W3="$SANDBOX/w3"; mkdir -p "$W3/.kube" "$W3/.docker" "$W3/src" "$W3/.ssh" "$W3/sub"; cd "$W3" || exit 1; git init -q
for f in .kube/config .docker/config.json .htpasswd .pgpass id_ecdsa id_dsa id_ed25519 token token.txt Token token.json deploy_token.json deploy-token.json api.token secrets.yaml SECRETS.env x.secret secret.yaml .ssh/k sub/id_ecdsa api_token github_token auth_token.txt .vault-token .secrets.toml client_secret.json my-secret.txt; do echo BODY7 > "$f"; done
for f in src/tokenizer.py src/id_utils.py src/secret_santa.py src/credentials_hint.md src/tokens.py src/token.py src/secrets_helper.py; do echo OKFILE > "$f"; done
for f in .kube/config .docker/config.json .htpasswd .pgpass id_ecdsa id_dsa id_ed25519 token token.txt Token token.json deploy_token.json deploy-token.json api.token secrets.yaml SECRETS.env x.secret secret.yaml .ssh/k sub/id_ecdsa api_token github_token auth_token.txt .vault-token .secrets.toml client_secret.json my-secret.txt; do
  out="$(sbx cat "$f")"; case "$out" in *BODY7*) fail "readable in the sandbox: $f" ;; *"not permitted"*) pass ;; *) fail "unexpected for $f: $out" ;; esac
done
for f in src/tokenizer.py src/id_utils.py src/secret_santa.py src/tokens.py src/token.py; do
  assert_eq "$(sbx cat "$f")" "OKFILE" "common code stays readable: $f"
  assert_eq "$(sbx sh -c "echo edited >> '$f' && tail -1 '$f'")" "edited" "common code stays writable: $f"
done
# KNOWN OVER-BLOCKS (the fragment's comment lists them): a source file named for a secret is refused
out="$(sbx cat src/secrets_helper.py)"; case "$out" in *"not permitted"*) pass ;; *OKFILE*) fail "secrets_helper.py became readable: update the fragment comment" ;; *) fail "unexpected: $out" ;; esac
# KNOWN LIMITS: /tmp stays readable and writable (the git helper needs it); the environment is not filtered
out="$(sbx sh -c 'echo t > /tmp/corecrew_probe_$$ && cat /tmp/corecrew_probe_$$ && rm -f /tmp/corecrew_probe_$$')"; assert_eq "$out" "t" "KNOWN LIMIT: /tmp is writable"
assert_eq "$(CORECREW_PROBE=envval sbx sh -c 'echo $CORECREW_PROBE')" "envval" "KNOWN LIMIT: environment variables are not filtered"
finish
