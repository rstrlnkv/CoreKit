#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
bash "$SKILL/scripts/scaffold.sh" --name hook-app >/dev/null
P="$CORE_DIR/hook-app"; C="$P/code"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_file "$C/.git/hooks/pre-commit"; assert_file "$C/.git/hooks/pre-push"
assert_file "$CORE_DIR/.git/hooks/pre-push"
# the three hooks are shims that run the tools copy; blocked-patterns stays out of .git/hooks
for h in "$C/.git/hooks/pre-commit" "$C/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  assert_contains "$h" "# coredev hook shim"; [ -x "$h" ] && pass || fail "not executable: $h"
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
for bad in CLAUDE.md sub/CLAUDE.local.md .claude/x.json .env .env.local docs/superpowers/plan.md a.pem k.key; do
  try_commit "$bad" && fail "commit allowed: $bad" || pass
  rm -rf "$C/$bad"
done
for ok in .env.example src/main.dart docs/README.md; do
  try_commit "$ok" && pass || fail "commit blocked: $ok"
done
# blocked commit message names the file
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md
OUT=$(git -C "$C" commit -m t 2>&1); echo "$OUT" | grep -q 'CLAUDE.md' && pass || fail "message lacks file name"
git -C "$C" reset -q; rm -f "$C/CLAUDE.md"

# pre-push catches a --no-verify commit
git init -q --bare "$SANDBOX/remote.git"; git -C "$C" remote add origin "$SANDBOX/remote.git"
git -C "$C" push -q origin main 2>/dev/null && pass || fail "clean push failed"
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

# --- shim edge cases
# tools file missing: the commit fails and the message names the fix and the shim
mv "$COREDEV_TOOLS/git-hooks/pre-commit-code" "$SANDBOX/pcc"
echo x > "$C/ok.txt"; git -C "$C" add ok.txt
OUT=$(git -C "$C" commit -m t 2>&1); rc=$?
[ $rc -ne 0 ] && pass || fail "commit allowed with tools file missing"
echo "$OUT" | grep -q 'is missing' && pass || fail "no 'is missing' message: $OUT"
echo "$OUT" | grep -q 'Start Claude Code once with coredev enabled' && pass || fail "no fix hint: $OUT"
echo "$OUT" | grep -qF "rm \"$C/.git/hooks/pre-commit\"" && pass || fail "no rm hint: $OUT"
mv "$SANDBOX/pcc" "$COREDEV_TOOLS/git-hooks/pre-commit-code"; git -C "$C" reset -q; rm -f "$C/ok.txt"

# an old 0.1.x hook (marker "new-project hook") is replaced by a shim
printf '#!/bin/sh\n# new-project hook: OLDBODY\nexit 0\n' > "$C/.git/hooks/pre-commit"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# coredev hook shim"
assert_not_contains "$C/.git/hooks/pre-commit" "OLDBODY"

# a foreign hook is left alone and warned about
printf '#!/bin/sh\n# mine\nexit 0\n' > "$C/.git/hooks/pre-push"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
echo "$OUT" | grep -q 'WARN' && echo "$OUT" | grep -q 'left unchanged' && pass || fail "no WARN for foreign hook: $OUT"
assert_contains "$C/.git/hooks/pre-push" "# mine"; assert_not_contains "$C/.git/hooks/pre-push" "coredev hook shim"

# --tools overrides the default; a tools dir with a space works
T2="$SANDBOX/my tools"; bash "$SCRIPTS/sync-tools.sh" "$ROOT" "$T2" >/dev/null
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
bash "$SKILL/scripts/scaffold.sh" --name fresh-app >/dev/null
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
finish
