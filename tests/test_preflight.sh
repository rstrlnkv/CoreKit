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

# gh is needed only at the GitHub stage: not logged in or missing is a warning, with an OS-neutral hint
GH_AUTH=1 assert_exit 0 bash "$PF"
echo "$OUT" | grep -q '^WARN gh-auth .*gh auth login' && pass || fail "no gh-auth WARN with the login hint: $OUT"
# gh is hidden by a PATH without it, not by "/usr/bin:/bin": a Linux runner keeps gh in /usr/bin beside git
# (simulated here by a system folder that holds both)
SYS="$SANDBOX/sys bin"; mkdir -p "$SYS"; ln -s "$(command -v git)" "$SYS/git"; cp "$STUB/gh" "$SYS/gh"
NOGH="$(PATH="$SYS:$PATH" path_without gh)"
assert_eq "$(PATH="$NOGH" command -v gh)" "" "path_without gh hides every gh"
PATH="$NOGH" assert_exit 0 bash "$PF"
echo "$OUT" | grep -q '^OK git' && pass || fail "git hidden with gh: $OUT"
echo "$OUT" | grep -q '^WARN gh .*https://cli.github.com' && pass || fail "no gh WARN with the install page: $OUT"
echo "$OUT" | grep -q '^FAIL' && fail "a missing gh must not FAIL: $OUT" || pass
# the hints name no single system's package manager
assert_not_contains "$PF" 'brew '

# non-ASCII home -> WARN only
HOME="$SANDBOX/Роман" assert_exit 0 bash "$PF"
echo "$OUT" | grep -q '^WARN' && pass || fail "no ASCII warning"

# existing local folder -> FAIL
mkdir -p "$CORE_DIR/taken-app"
assert_exit 1 bash "$PF" --name taken-app

# a folder beside the Core with that name, in any letter case -> FAIL (the code repo goes there)
mkdir -p "$SANDBOX/Projects/Beside-App"
assert_exit 1 bash "$PF" --name beside-app
echo "$OUT" | grep -qF "FAIL name-local — folder $SANDBOX/Projects/Beside-App already exists" && pass || fail "no beside-the-Core FAIL: $OUT"
mkdir -p "$SANDBOX/Projects/plain-app"
assert_exit 1 bash "$PF" --name plain-app
echo "$OUT" | grep -qF "$SANDBOX/Projects/plain-app already exists" && pass || fail "no FAIL for plain-app: $OUT"

# existing GitHub repo -> FAIL
GH_REPO_EXISTS=1 assert_exit 1 bash "$PF" --name gh-taken
echo "$OUT" | grep -q 'GitHub' && pass || fail "no GitHub reason"
# not logged in -> GitHub name check is not trusted
GH_AUTH=1 assert_exit 0 bash "$PF" --name some-app   # a warning, not a stop: the name is checked again at the GitHub stage
echo "$OUT" | grep -q '^OK name-github' && fail "name-github OK without login" || pass
echo "$OUT" | grep -q '^WARN name-github' && pass || fail "no name-github WARN"
finish
