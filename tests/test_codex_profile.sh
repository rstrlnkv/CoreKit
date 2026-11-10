#!/usr/bin/env bash
# lib.sh codex-profile: the TOML fragment for ~/.codex/config.toml. Text checks always; the sandbox checks run the
# fragment through `codex sandbox` (no model, nothing sent) with CODEX_HOME in the test sandbox, and are skipped
# without `codex`.
source "$(dirname "$0")/lib.sh"
new_sandbox
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
# --- corecrew's own files: one read line for the folder Codex keeps this marketplace's plugins in, one for the tools
# copy, one for the settings file, one for the hooks marker, and the two global git config files (each file alone, not
# its folder: ~/.config/git may hold a credentials file). All sit in the filesystem table (before the workspace table),
# nothing else of the home is listed, nothing is writable.
fs="$(awk '/^\[permissions\.corecrew\.filesystem\]$/{f=1; next} /^\[/{f=0} f' "$FRAG")"
own="$(printf '%s\n' "$fs" | grep '^"/')"
assert_eq "$own" "\"$CODEX_HOME/plugins/cache/corekit\" = \"read\"
\"$CODEX_HOME/plugins/data/corecrew-corekit/tools\" = \"read\"
\"$XDG_CONFIG_HOME/corecrew/settings\" = \"read\"
\"$XDG_CONFIG_HOME/corecrew/state/hooks-seen-codex\" = \"read\"
\"$HOME/.gitconfig\" = \"read\"
\"$XDG_CONFIG_HOME/git/config\" = \"read\"
\"$XDG_CONFIG_HOME/git/ignore\" = \"read\"" "the seven read lines: plugin folder, tools copy, settings file, hooks marker, two git config files, git ignore file"
assert_eq "$(grep -c '^"/' "$FRAG")" "7" "no other absolute path in the fragment"
assert_eq "$(XDG_CONFIG_HOME= bash "$SCRIPTS/lib.sh" codex-profile | grep -F '/git/config')" "\"$HOME/.config/git/config\" = \"read\"" "no XDG_CONFIG_HOME: the git config line is ~/.config/git/config"
assert_eq "$(XDG_CONFIG_HOME= bash "$SCRIPTS/lib.sh" codex-profile | grep -F '/git/ignore')" "\"$HOME/.config/git/ignore\" = \"read\"" "no XDG_CONFIG_HOME: the git ignore line is ~/.config/git/ignore"
assert_eq "$(grep -v '^#' "$FRAG" | grep -cE '/git"|\.config"|/plugins/data/corecrew-corekit"|/state"')" "0" "no folder of those files is opened"
prof() { bash "$SCRIPTS/lib.sh" codex-profile; }
assert_eq "$(CORECREW_CONFIG="$SANDBOX/my conf" prof | grep -F 'my conf')" "\"$SANDBOX/my conf\" = \"read\"" "the settings line follows CORECREW_CONFIG (the file, not its folder)"
assert_eq "$(CODEX_HOME= prof | grep -F '/plugins/cache/')" "\"$HOME/.codex/plugins/cache/corekit\" = \"read\"" "the plugin line follows the Codex home (~/.codex without CODEX_HOME)"
# a quote or a backslash in the home path stays inside the TOML string
assert_eq "$(CODEX_HOME='/x/a "q" \b' prof | grep -F '/plugins/cache/')" '"/x/a \"q\" \\b/plugins/cache/corekit" = "read"' "a quote and a backslash are escaped"
# no usable home: each line is left out with a comment, the rest is printed, exit 0
out="$(CODEX_HOME=rel HOME=rel XDG_CONFIG_HOME= prof)"; assert_eq "$?" "0" "no usable home: exit 0"
assert_eq "$(printf '%s\n' "$out" | grep -v '^#' | grep -cE 'rel|plugins/cache|plugins/data|settings|hooks-seen|gitconfig|git/config|git/ignore')" "0" "no usable home: no path line"
assert_eq "$(printf '%s\n' "$out" | grep -c '^# (left out: ')" "7" "no usable home: a comment for each line left out"
assert_eq "$(printf '%s\n' "$out" | grep -v '^#' | grep -c .)" "$(($(grep -v '^#' "$FRAG" | grep -c .) - 7))" "no usable home: the rest of the fragment is there"
out="$(CODEX_HOME="$SANDBOX/a
b" prof)"; assert_eq "$(printf '%s\n' "$out" | grep -cE 'plugins/(cache|data)')" "0" "a home path with a newline is left out"
assert_eq "$(printf '%s\n' "$out" | grep -vE '^[[:space:]]*(#.*)?$|^\[[^]]+\]$|^"[^"]+" = "[a-z]+"$|^default_permissions = "corecrew"$')" "" "...and the fragment stays well formed"
# an installed copy names the marketplace it was installed from
VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json" | head -1)"; [ -n "$VER" ] && pass || fail "no plugin version"
mkdir -p "$SANDBOX/inst/plugins/cache/mymkt/corecrew"; cp -R "$PLUGIN" "$SANDBOX/inst/plugins/cache/mymkt/corecrew/$VER"
assert_eq "$(bash "$SANDBOX/inst/plugins/cache/mymkt/corecrew/$VER/scripts/lib.sh" codex-profile | grep -F '/plugins/cache/')" "\"$CODEX_HOME/plugins/cache/mymkt\" = \"read\"" "the marketplace name comes from the install path"
assert_eq "$(bash "$SANDBOX/inst/plugins/cache/mymkt/corecrew/$VER/scripts/lib.sh" codex-profile | grep -F '/plugins/data/')" "\"$CODEX_HOME/plugins/data/corecrew-mymkt/tools\" = \"read\"" "the tools copy line names the same marketplace"

if ! command -v codex >/dev/null 2>&1; then skip codex-profile "codex not on PATH (sandbox checks)"; finish; fi
# --- a read-only sandbox (what `codex sandbox` gives with no config; a plain `codex exec` in a project Codex does not
# trust): nothing is writable, the temp folder included, and bash 3.2 writes a here-string to a temp file. lib.sh must
# still read the settings file, name an ignored value, and print no raw bash error.
RO="$SANDBOX/ro"; mkdir -p "$RO/codex-home" "$RO/Core" "$RO/w" "$SANDBOX/xdg/corecrew"
printf 'core_dir: %s\nmodel_profile: strong\nattribution: maybe\n' "$RO/Core" > "$SANDBOX/xdg/corecrew/settings"
ro() { (cd "$RO/w" && unset CORE_DIR && CODEX_HOME="$RO/codex-home" codex sandbox -- "$@"); }
out="$(ro sh -c ': > probe' 2>&1)"; case "$out" in *"not permitted"*) pass ;; *) fail "the sandbox with no config is not read-only: $out" ;; esac
assert_eq "$(ro bash "$SCRIPTS/lib.sh" settings model_profile 2>/dev/null)" "model_profile: strong" "read-only sandbox: the settings file is read"
assert_eq "$(ro bash "$SCRIPTS/lib.sh" core-dir 2>/dev/null)" "$RO/Core" "read-only sandbox: core-dir is the file's core_dir"
err="$(ro bash "$SCRIPTS/lib.sh" core-dir 2>&1 >/dev/null)"
case "$err" in *'attribution "maybe"'*'is not valid'*) pass ;; *) fail "read-only sandbox: no settings warning on stderr: $err" ;; esac
case "$err" in *"here document"*|*"temp file"*) fail "read-only sandbox: a raw bash error: $err" ;; *) pass ;; esac
rm -f "$SANDBOX/xdg/corecrew/settings"

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
# --- corecrew installed in the Codex home, the fragment printed by that copy as config.toml: sandboxed commands read
# corecrew's scripts, role files and settings file (and the marketplace's other plugins); the rest of both homes stays closed
INST="$CODEX_HOME/plugins/cache/corekit/corecrew/$VER"; mkdir -p "${INST%/*}" "$CODEX_HOME/plugins/cache/corekit/coremodel/1" "$CODEX_HOME/plugins/cache/othermkt/p" "$SANDBOX/xdg/corecrew" "$SANDBOX/xdg/other"
cp -R "$PLUGIN" "$INST"; echo SIBLING > "$CODEX_HOME/plugins/cache/corekit/coremodel/1/x.txt"; echo OTHERMKT > "$CODEX_HOME/plugins/cache/othermkt/p/x.txt"
echo AUTH > "$CODEX_HOME/auth.json"; echo NEIGHBOUR > "$SANDBOX/xdg/corecrew/notes"; echo OTHERCFG > "$SANDBOX/xdg/other/config"
printf 'model_profile: strong\n' > "$SANDBOX/xdg/corecrew/settings"
bash "$INST/scripts/lib.sh" codex-profile > "$CODEX_HOME/config.toml"
cd "$SANDBOX/w" || exit 1
assert_eq "$(sbx bash "$INST/scripts/lib.sh" settings model_profile)" "model_profile: strong" "installed: lib.sh runs and reads the settings file"
assert_eq "$(sbx bash "$INST/scripts/lib.sh" host)" "codex" "installed: lib.sh host"
assert_eq "$(sbx bash "$INST/skills/task/../../scripts/lib.sh" plugin-root)" "$INST" "installed: plugin-root through a skill's path"
out="$(sbx cat "$INST/agents/engineer.md")"; case "$out" in *"not permitted"*) fail "installed: a role file is closed: $out" ;; *"name: engineer"*) pass ;; *) fail "installed: role file: $out" ;; esac
assert_eq "$(sbx cat "$CODEX_HOME/plugins/cache/corekit/coremodel/1/x.txt")" "SIBLING" "installed: another plugin of the marketplace is readable"
for f in .env "$H/.ssh/x" "$CODEX_HOME/auth.json" "$CODEX_HOME/config.toml" "$CODEX_HOME/plugins/cache/othermkt/p/x.txt" "$SANDBOX/xdg/corecrew/notes" "$SANDBOX/xdg/other/config"; do
  out="$(sbx cat "$f")"; case "$out" in *"not permitted"*) pass ;; *) fail "installed: readable in the sandbox: $f: $out" ;; esac
done
out="$(sbx sh -c "echo y > '$INST/scripts/new.sh'; echo y >> '$SANDBOX/xdg/corecrew/settings'")"
assert_eq "$(printf '%s\n' "$out" | grep -c 'not permitted')" "2" "installed: the plugin folder and the settings file are not writable"
assert_no_file "$INST/scripts/new.sh"; assert_eq "$(cat "$SANDBOX/xdg/corecrew/settings")" "model_profile: strong" "installed: the settings file is unchanged"
# closed <label> — in the cwd (a project with a .env): the project's .env, ~/.ssh/x and <Codex home>/auth.json (a fake
# one, removed again) stay refused under the profile, whatever read line was added.
closed() {
  local f out
  echo AUTH > "$CODEX_HOME/auth.json"; echo SECRET > .env
  for f in .env "$H/.ssh/x" "$CODEX_HOME/auth.json"; do
    out="$(sbx cat "$f")"; case "$out" in *"not permitted"*) pass ;; *) fail "$1: readable in the sandbox: $f: $out" ;; esac
  done
  rm -f "$CODEX_HOME/auth.json"
}
# --- the tools copy (plugins/data/corecrew-<marketplace>/tools): session start names its save and undo-step, so a
# sandboxed command must read it; nothing in it is writable, and the rest of the data folder stays closed.
T="$CODEX_HOME/plugins/data/corecrew-corekit/tools"; mkdir -p "${T%/*}"; echo DATA > "${T%/*}/other.txt"
bash "$INST/scripts/sync-tools.sh" "$INST" "$T" >/dev/null; assert_file "$T/save"
cd "$SANDBOX/w" || exit 1
assert_eq "$(sbx bash "$T/lib.sh" host)" "codex" "tools copy: lib.sh runs in the sandbox"
out="$(sbx cat "$T/save")"; case "$out" in *"not permitted"*) fail "tools copy: save is closed: $out" ;; *) pass ;; esac
out="$(codex sandbox -- bash "$T/save" "Second step" 2>&1)"; rc=$?
# (the /usr/bin/git shim may print its own "not permitted" for a cache file: only the line about save counts)
case "$out" in *"$T/save"*"not permitted"*) fail "tools copy: save cannot be read: $out" ;; *) pass ;; esac
case "$out" in *"not a corecrew project"*) pass ;; *) fail "tools copy: save does not reach its own checks: $out" ;; esac
[ "$rc" -ne 126 ] && pass || fail "tools copy: save exits 126"
out="$(sbx sh -c "echo y > '$T/x'")"; case "$out" in *"not permitted"*) pass ;; *) fail "tools copy: writable: $out" ;; esac
assert_no_file "$T/x"
out="$(sbx cat "${T%/*}/other.txt")"; case "$out" in *"not permitted"*) pass ;; *) fail "tools copy: the rest of the data folder is readable: $out" ;; esac
closed "tools copy"
# --- the hooks marker: with the marker of this version and the profile as the default, prepare.sh in the sandbox
# prints neither the trust note nor the profile note (a hidden config.toml is the profile being active).
MK="$SANDBOX/xdg/corecrew/state/hooks-seen-codex"; mkdir -p "${MK%/*}"; echo "$VER" > "$MK"
assert_eq "$(sbx bash "$INST/scripts/prepare.sh" --part host; echo "rc=$?")" "rc=0" "marker and profile: prepare.sh --part host prints nothing in the sandbox"
assert_eq "$(sbx cat "$MK")" "$VER" "marker: readable in the sandbox"
out="$(sbx sh -c "echo y > '$MK'")"; case "$out" in *"not permitted"*) pass ;; *) fail "marker: writable: $out" ;; esac
echo 0.0.1 > "$MK"
out="$(sbx bash "$INST/scripts/prepare.sh" --part host)"
case "$out" in *"until you trust"*) pass ;; *) fail "marker of another version: no trust note in the sandbox: $out" ;; esac
case "$out" in *codex-profile*) fail "profile active: the profile note in the sandbox: $out" ;; *) pass ;; esac
echo "$VER" > "$MK"; cp "$CODEX_HOME/config.toml" "$SANDBOX/profile.toml"
printf '# no corecrew profile\n' > "$CODEX_HOME/config.toml"
out="$(sbx bash "$INST/scripts/prepare.sh" --part host)"
assert_eq "$(printf '%s\n' "$out" | grep -c codex-profile)" "1" "no profile: the profile note still shows in the sandbox"
cp "$SANDBOX/profile.toml" "$CODEX_HOME/config.toml"
closed "hooks marker"
# --- the global git config: git reads ~/.gitconfig or $XDG_CONFIG_HOME/git/config; both files are readable, their
# folders are not (~/.config/git may hold a credentials file). H is outside TMPDIR and /tmp.
GP="$H/proj"; mkdir -p "$GP"; cd "$GP" || exit 1; git init -q; echo a > app.txt; git add app.txt; git commit -qm a; echo b > app.txt
printf '[user]\n\tname = T\n\temail = t@e\n' > "$H/.gitconfig"
assert_eq "$(unset GIT_CONFIG_GLOBAL; codex sandbox -- "$GITBIN" status --short 2>&1; echo "rc=$?")" " M app.txt
rc=0" "~/.gitconfig: git status works in the sandbox"
mkdir -p "$XDG_CONFIG_HOME/git"; mv "$H/.gitconfig" "$XDG_CONFIG_HOME/git/config"; echo CRED > "$XDG_CONFIG_HOME/git/credentials"
assert_eq "$(unset GIT_CONFIG_GLOBAL; codex sandbox -- "$GITBIN" status --short 2>&1; echo "rc=$?")" " M app.txt
rc=0" "XDG git config: git status works in the sandbox"
out="$(sbx cat "$XDG_CONFIG_HOME/git/credentials")"; case "$out" in *"not permitted"*) pass ;; *) fail "git credentials beside the XDG git config: $out" ;; esac
out="$(sbx sh -c "echo y >> '$XDG_CONFIG_HOME/git/config'")"; case "$out" in *"not permitted"*) pass ;; *) fail "git config: writable: $out" ;; esac
closed "git config"
# git's default global ignore file ($XDG_CONFIG_HOME/git/ignore, beside the config): readable, so sandboxed git prints no
# warning and does not count a globally ignored file as a change (save and prepare read status --porcelain)
rm -f .env; echo '*.log' > "$XDG_CONFIG_HOME/git/ignore"; echo l > a.log   # (.env: left by closed above)
assert_eq "$(unset GIT_CONFIG_GLOBAL; codex sandbox -- "$GITBIN" status --short 2>&1; echo "rc=$?")" " M app.txt
rc=0" "global git ignore file: git status in the sandbox has no warning and no ignored file"
out="$(sbx sh -c "echo y >> '$XDG_CONFIG_HOME/git/ignore'")"; case "$out" in *"not permitted"*) pass ;; *) fail "git ignore file: writable: $out" ;; esac
out="$(sbx cat "$XDG_CONFIG_HOME/git/credentials")"; case "$out" in *"not permitted"*) pass ;; *) fail "git credentials beside the git ignore file: $out" ;; esac
closed "git ignore"
rm -f a.log
# --- code_dir_of in the sandbox: <Projects> cannot be listed (not opened, it holds other projects' secrets), so the
# lookup falls back to the cwd when that is the project's code folder. The Core gets write (a stand-in for --add-dir).
P="$SANDBOX/P"; mkdir -p "$P/Core/demo" "$P/Demo/src" "$P/Other"; echo x > "$P/Core/demo/CLAUDE.md"; echo OTHERSECRET > "$P/Other/notes.txt"
awk -v c="$P/Core" '{print} /^":tmpdir" = "write"$/{printf "\"%s\" = \"write\"\n", c}' "$SANDBOX/profile.toml" > "$CODEX_HOME/config.toml"
cd "$P/Demo" || exit 1
assert_eq "$(CORE_DIR="$P/Core" bash "$INST/scripts/lib.sh" layout demo)" "new" "code-dir outside the sandbox: layout new"
assert_eq "$(CORE_DIR="$P/Core" sbx bash "$INST/scripts/lib.sh" layout demo; echo "rc=$?")" "new
rc=0" "code-dir in the sandbox: layout new"
assert_eq "$(CORE_DIR="$P/Core" sbx bash "$INST/scripts/lib.sh" code-dir demo)" "$P/Demo" "code-dir in the sandbox: the cwd's project"
assert_eq "$(cd src && CORE_DIR="$P/Core" sbx bash "$INST/scripts/lib.sh" code-dir demo)" "$P/Demo" "code-dir in the sandbox: from a subfolder"
assert_eq "$(CORE_DIR="$P/Core" sbx bash "$INST/scripts/lib.sh" code-dir other; echo "rc=$?")" "rc=1" "code-dir in the sandbox: another project is not guessed"
out="$(sbx cat "$P/Other/notes.txt")"; case "$out" in *"not permitted"*) pass ;; *) fail "another project is readable: $out" ;; esac
closed "code-dir"
cp "$SANDBOX/profile.toml" "$CODEX_HOME/config.toml"
finish
