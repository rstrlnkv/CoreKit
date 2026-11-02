#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
PF="$SKILL/scripts/preflight.sh"
new_sandbox
STUB="$SANDBOX/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'G'
#!/bin/sh
case "$1 $2" in
  "auth status") exit "${GH_AUTH:-0}" ;;
  "repo view") [ "${GH_REPO_EXISTS:-0}" = 1 ] && exit 0 || exit 1 ;;
esac
exit 0
G
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

assert_exit 0 bash "$PF"
echo "$OUT" | grep -q '^FAIL' && fail "unexpected FAIL: $OUT" || pass
echo "$OUT" | grep -q '^OK git' && pass || fail "no git line"

assert_exit 0 bash "$PF" --name free-app

# gh not logged in
GH_AUTH=1 assert_exit 1 bash "$PF"
echo "$OUT" | grep -q 'gh auth login' && pass || fail "no login hint"

# gh missing
PATH="/usr/bin:/bin" assert_exit 1 bash "$PF"
echo "$OUT" | grep -q '^FAIL gh' && pass || fail "no gh FAIL line"

# non-ASCII home -> WARN only
HOME="$SANDBOX/Роман" assert_exit 0 bash "$PF"
echo "$OUT" | grep -q '^WARN' && pass || fail "no ASCII warning"

# existing local folder -> FAIL
mkdir -p "$CORE_DIR/taken-app"
assert_exit 1 bash "$PF" --name taken-app

# existing GitHub repo -> FAIL
GH_REPO_EXISTS=1 assert_exit 1 bash "$PF" --name gh-taken
echo "$OUT" | grep -q 'GitHub' && pass || fail "no GitHub reason"
# not logged in -> GitHub name check is not trusted
GH_AUTH=1 assert_exit 1 bash "$PF" --name some-app
echo "$OUT" | grep -q '^OK name-github' && fail "name-github OK without login" || pass
echo "$OUT" | grep -q '^WARN name-github' && pass || fail "no name-github WARN"
finish
