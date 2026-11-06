#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
scaffold_old hook-app
P="$CORE_DIR/hook-app"; C="$P/code"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_file "$C/.git/hooks/pre-commit"; assert_file "$C/.git/hooks/pre-push"
assert_file "$CORE_DIR/.git/hooks/pre-push"
# the three hooks are shims that run the tools copy; blocked-patterns stays out of .git/hooks
for h in "$C/.git/hooks/pre-commit" "$C/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  assert_contains "$h" "# corecrew hook shim"; [ -x "$h" ] && pass || fail "not executable: $h"
done
assert_contains "$C/.git/hooks/pre-commit" "$COREDEV_TOOLS/git-hooks/pre-commit-code"
assert_contains "$C/.git/hooks/pre-push" "$COREDEV_TOOLS/git-hooks/pre-push-code"
assert_contains "$CORE_DIR/.git/hooks/pre-push" "$COREDEV_TOOLS/git-hooks/pre-push-core"
assert_no_file "$C/.git/hooks/blocked-patterns"
# idempotent
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"

try_commit() {  # try_commit <path> ; force-add past .gitignore to test the hook itself
  mkdir -p "$C/$(dirname "$1")"; echo x > "$C/$1"
  git -C "$C" add -f "$1"
  git -C "$C" commit -q -m "add $1" >/dev/null 2>&1; local rc=$?
  git -C "$C" reset -q 2>/dev/null; return $rc
}
for bad in CLAUDE.md sub/CLAUDE.local.md AGENTS.md sub/AGENTS.md agents.md .claude/x.json .env .env.local docs/superpowers/plan.md a.pem k.key; do
  try_commit "$bad" && fail "commit allowed: $bad" || pass
  rm -rf "$C/$bad"
done
for ok in .env.example .env.sample .env.template sub/.env.sample src/main.dart docs/README.md MYAGENTS.md AGENTS.md.bak; do
  try_commit "$ok" && pass || fail "commit blocked: $ok"
done
# blocked commit message names the file
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md
OUT=$(git -C "$C" commit -m t 2>&1); echo "$OUT" | grep -q 'CLAUDE.md' && pass || fail "message lacks file name"
git -C "$C" reset -q; rm -f "$C/CLAUDE.md"

# pre-push catches a --no-verify commit
git init -q --bare "$SANDBOX/remote.git"; git -C "$C" remote add origin "$SANDBOX/remote.git"
git -C "$C" push -q origin main 2>/dev/null && pass || fail "clean push failed"
# pre-push allows the same .env templates (committed with --no-verify, so only pre-push judges them)
for ok in cfg/.env.example cfg/.env.sample cfg/.env.template; do
  mkdir -p "$C/cfg"; echo x > "$C/$ok"; git -C "$C" add -f "$ok"; git -C "$C" commit -q --no-verify -m "add $ok"
done
git -C "$C" push -q origin main 2>/dev/null && pass || fail "push of .env.example/.sample/.template blocked"
echo x > "$C/cfg/.env.prod"; git -C "$C" add -f cfg/.env.prod; git -C "$C" commit -q --no-verify -m "add env"
git -C "$C" push -q origin main 2>/dev/null && fail "push of cfg/.env.prod allowed" || pass
git -C "$C" reset -q --hard HEAD~1
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md; git -C "$C" commit -q --no-verify -m sneaky
git -C "$C" push -q origin main 2>/dev/null && fail "push of CLAUDE.md allowed" || pass

# Core pre-push: privacy check via gh
STUB="$SANDBOX/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "$GH_STUB"\n' > "$STUB/gh"; chmod +x "$STUB/gh"
H="$CORE_DIR/.git/hooks/pre-push"; URL=https://github.com/someone/Core.git
GH_STUB=true  PATH="$STUB:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && pass || fail "private Core push blocked"
GH_STUB=false PATH="$STUB:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "public Core push allowed" || pass
PATH="/usr/bin:/bin" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "push allowed without gh" || pass
GH_STUB=true PATH="$STUB:$PATH" bash "$H" origin "git@github.com:someone/Core.git" </dev/null >/dev/null 2>&1 && pass || fail "ssh url not parsed"
# a failed gh call (network) is retried: 2 failures then "true" pass, 3 failures block, "false" is final
FL="$SANDBOX/flaky"; mkdir -p "$FL"
cat > "$FL/gh" <<'STUBEOF'
#!/bin/sh
n=$(cat "$GH_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$GH_COUNT"
if [ "$n" -le "$GH_FAILS" ]; then echo "TLS handshake timeout" >&2; exit 1; fi
echo "$GH_ANSWER"
STUBEOF
chmod +x "$FL/gh"
CNT="$SANDBOX/gh.count"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=2 GH_ANSWER=true CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && pass || fail "push blocked after 2 failed gh calls"
assert_eq "$(cat "$CNT")" "3" "gh called three times"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=3 GH_ANSWER=true CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "push allowed after 3 failed gh calls" || pass
assert_eq "$(cat "$CNT")" "3" "gh tried at most three times"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=0 GH_ANSWER=false CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "public Core push allowed (flaky stub)" || pass
assert_eq "$(cat "$CNT")" "1" "a public answer is not retried"

# --- shim edge cases
# tools file missing: the commit fails and the message names the fix and the shim
mv "$COREDEV_TOOLS/git-hooks/pre-commit-code" "$SANDBOX/pcc"
echo x > "$C/ok.txt"; git -C "$C" add ok.txt
OUT=$(git -C "$C" commit -m t 2>&1); rc=$?
[ $rc -ne 0 ] && pass || fail "commit allowed with tools file missing"
echo "$OUT" | grep -q 'is missing' && pass || fail "no 'is missing' message: $OUT"
echo "$OUT" | grep -q 'Start Claude Code once with corecrew enabled' && pass || fail "no fix hint: $OUT"
echo "$OUT" | grep -qF "rm \"$C/.git/hooks/pre-commit\"" && pass || fail "no rm hint: $OUT"
mv "$SANDBOX/pcc" "$COREDEV_TOOLS/git-hooks/pre-commit-code"; git -C "$C" reset -q; rm -f "$C/ok.txt"

# an old 0.1.x hook (marker "new-project hook") is replaced by a shim
printf '#!/bin/sh\n# new-project hook: OLDBODY\nexit 0\n' > "$C/.git/hooks/pre-commit"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_not_contains "$C/.git/hooks/pre-commit" "OLDBODY"

# a 0.2.x shim (marker "coredev hook shim") is replaced by a current shim
printf '#!/bin/sh\n# coredev hook shim\nT=OLDSHIM\n' > "$C/.git/hooks/pre-commit"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_not_contains "$C/.git/hooks/pre-commit" "OLDSHIM"

# a foreign hook is left alone and warned about
printf '#!/bin/sh\n# mine\nexit 0\n' > "$C/.git/hooks/pre-push"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
echo "$OUT" | grep -q 'WARN' && echo "$OUT" | grep -q 'left unchanged' && pass || fail "no WARN for foreign hook: $OUT"
assert_contains "$C/.git/hooks/pre-push" "# mine"; assert_not_contains "$C/.git/hooks/pre-push" "corecrew hook shim"

# --tools overrides the default; a tools dir with a space works
T2="$SANDBOX/my tools"; bash "$SCRIPTS/sync-tools.sh" "$PLUGIN" "$T2" >/dev/null
rm -f "$C/.git/hooks/pre-push"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P" --tools "$T2"
assert_contains "$C/.git/hooks/pre-push" "$T2/git-hooks/pre-push-code"
# (CLAUDE.md is already tracked by the --no-verify test above, so use a fresh blocked file)
echo secret > "$C/.env.local"; git -C "$C" add -f .env.local
OUT=$(git -C "$C" commit -m t 2>&1) && fail "commit allowed with tools in a path with a space" || pass
echo "$OUT" | grep -q 'Commit blocked' && pass || fail "shim with a spaced tools path did not run the hook body: $OUT"
git -C "$C" reset -q; rm -f "$C/.env.local"
echo ok > "$C/clean.txt"; git -C "$C" add clean.txt
git -C "$C" commit -q -m clean >/dev/null 2>&1 && pass || fail "clean commit blocked with tools in a path with a space"

# install-hooks run from the plugin syncs the tools first: empty tools dir, then a clean commit works
new_sandbox; setup_core
scaffold_old fresh-app
C="$CORE_DIR/fresh-app/code"
assert_no_file "$COREDEV_TOOLS"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/fresh-app"
assert_file "$COREDEV_TOOLS/VERSION"; assert_file "$COREDEV_TOOLS/git-hooks/blocked-patterns"
echo ok > "$C/clean.txt"; git -C "$C" add clean.txt
git -C "$C" commit -q -m clean >/dev/null 2>&1 && pass || fail "first commit blocked on a fresh machine"
# run from the tools copy, install-hooks does not sync (no plugin.json next to it)
echo 0.0.0 > "$COREDEV_TOOLS/VERSION"
assert_exit 0 bash "$COREDEV_TOOLS/install-hooks.sh" "$CORE_DIR/fresh-app"
assert_eq "$(cat "$COREDEV_TOOLS/VERSION")" "0.0.0" "install-hooks from the tools copy must not sync"

# missing hook sources: plain message, exit 1
BROKEN="$SANDBOX/broken"; mkdir -p "$BROKEN"; cp "$SCRIPTS/install-hooks.sh" "$BROKEN/"
assert_exit 1 bash "$BROKEN/install-hooks.sh" "$P"
echo "$OUT" | grep -q 'hooks installed' && fail "claimed success without sources" || pass
echo "$OUT" | grep -qi 'missing\|not found' && pass || fail "no plain message: $OUT"
# new layout: code repo beside the Core (<Projects>/Foo), project dir argument is <Core>/foo
new_sandbox; setup_core; sync_tools
F="$SANDBOX/Projects/Foo"; mkdir -p "$F" "$CORE_DIR/foo"; git -C "$F" init -q
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/foo"
for h in "$F/.git/hooks/pre-commit" "$F/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  assert_contains "$h" "# corecrew hook shim"
done
assert_no_file "$CORE_DIR/foo/code"
# no code folder at all: exit 1, names the missing folder
mkdir -p "$CORE_DIR/bar"
assert_exit 1 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/bar"
echo "$OUT" | grep -q 'No git repo at' && pass || fail "no 'No git repo at' message: $OUT"

finish
