#!/usr/bin/env bash
# The sandbox must not see the developer's HOME, XDG config or global/system git config.
source "$(dirname "$0")/lib.sh"
REAL_HOME="$HOME"
# a planted outer value (never the real one): new_sandbox must replace it, not keep it
export CORE_DIR="$TEST_TMP/outer-core" CLAUDE_PLUGIN_DATA="$TEST_TMP/outer-data"
new_sandbox
case "$HOME" in "$SANDBOX"/*) pass ;; *) fail "HOME not in the sandbox: $HOME" ;; esac
case "${XDG_CONFIG_HOME:-}" in "$SANDBOX"/*) pass ;; *) fail "XDG_CONFIG_HOME not in the sandbox: ${XDG_CONFIG_HOME:-}" ;; esac
case "${CODEX_HOME:-}" in "$SANDBOX"/*) pass ;; *) fail "CODEX_HOME not in the sandbox: ${CODEX_HOME:-}" ;; esac
case "${CORE_DIR:-}" in "$SANDBOX"/*) pass ;; *) fail "CORE_DIR not in the sandbox: ${CORE_DIR:-}" ;; esac
case "${CLAUDE_PLUGIN_DATA:-}" in "$SANDBOX"/*) pass ;; *) fail "CLAUDE_PLUGIN_DATA not in the sandbox: ${CLAUDE_PLUGIN_DATA:-}" ;; esac
assert_eq "$GIT_CONFIG_GLOBAL" "$SANDBOX/gitconfig" "GIT_CONFIG_GLOBAL"
assert_eq "$GIT_CONFIG_NOSYSTEM" "1" "GIT_CONFIG_NOSYSTEM"
[ "$HOME" != "$REAL_HOME" ] && pass || fail "HOME is the real one"
assert_eq "$(git config --global --get core.excludesFile)" "" "global excludesFile"
assert_eq "$(git config --global --list | grep -c '^user\.')" "0" "global git identity leaked in"
# the default excludes file (from XDG/HOME) is not the developer's: settings.local.json is not ignored
mkdir -p "$SANDBOX/r/.claude"; git init -q "$SANDBOX/r"; : > "$SANDBOX/r/.claude/settings.local.json"
git -C "$SANDBOX/r" check-ignore -q .claude/settings.local.json && fail "settings.local.json ignored by a global excludes file" || pass
# a global setting lands in the sandbox file, not in the real one (never write unless isolated)
[ "$GIT_CONFIG_GLOBAL" = "$SANDBOX/gitconfig" ] && [ "$HOME" != "$REAL_HOME" ] \
  || { fail "sandbox not isolated; skipping the global write"; finish; exit 1; }
git config --global test.isolation yes
assert_contains "$SANDBOX/gitconfig" "isolation = yes"

# Every test file calls new_sandbox. A file run on its own has no throwaway HOME from run.sh, so without new_sandbox
# it would write the developer's files. Only the presence of the call is checked, not its position: code that a file
# runs before its new_sandbox is not seen.
has_sandbox() { grep -qE '(^|[;&(]|then |do )[[:space:]]*new_sandbox' "$1"; }
# self-check on fixtures: the call counts; the word in a comment or in an assert's text does not
F="$SANDBOX/fx"; mkdir -p "$F"
printf 'source "$(dirname "$0")/lib.sh"\nnew_sandbox\nbash "$HOOKS/guard-code.sh" < x\n' > "$F/sandboxed"
printf 'source "$(dirname "$0")/lib.sh"\n# new_sandbox\nassert_contains "$f" new_sandbox\ngit config --global x.y z\n' > "$F/bare"
has_sandbox "$F/sandboxed" && pass || fail "has_sandbox misses new_sandbox"
has_sandbox "$F/bare" && fail "has_sandbox sees a sandbox in a file without one" || pass
for t in "$ROOT"/tests/test_*.sh; do
  has_sandbox "$t" && pass || fail "$(basename "$t") runs without new_sandbox"
done

[ -z "${CORECREW_CONFIG:-}" ] && pass || fail "CORECREW_CONFIG leaks into the sandbox"
finish
