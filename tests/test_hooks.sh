#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core
bash "$SKILL/scripts/scaffold.sh" --name hook-app >/dev/null
P="$CORE_DIR/hook-app"; C="$P/code"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_file "$C/.git/hooks/pre-commit"; assert_file "$C/.git/hooks/pre-push"
assert_file "$CORE_DIR/.git/hooks/pre-push"
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
finish
