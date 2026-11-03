#!/usr/bin/env bash
# The sandbox must not see the developer's HOME, XDG config or global/system git config.
source "$(dirname "$0")/lib.sh"
REAL_HOME="$HOME"
new_sandbox
case "$HOME" in "$SANDBOX"/*) pass ;; *) fail "HOME not in the sandbox: $HOME" ;; esac
case "${XDG_CONFIG_HOME:-}" in "$SANDBOX"/*) pass ;; *) fail "XDG_CONFIG_HOME not in the sandbox: ${XDG_CONFIG_HOME:-}" ;; esac
assert_eq "$GIT_CONFIG_GLOBAL" "$SANDBOX/gitconfig" "GIT_CONFIG_GLOBAL"
assert_eq "$GIT_CONFIG_NOSYSTEM" "1" "GIT_CONFIG_NOSYSTEM"
[ "$HOME" != "$REAL_HOME" ] && pass || fail "HOME is the real one"
assert_eq "$(git config --global --get core.excludesFile)" "" "global excludesFile"
assert_eq "$(git config --global --list | grep -c '^user\.')" "0" "global git identity leaked in"
# the default excludes file (from XDG/HOME) is not the developer's: settings.local.json is not ignored
mkdir -p "$SANDBOX/r/.claude"; git init -q "$SANDBOX/r"; : > "$SANDBOX/r/.claude/settings.local.json"
git -C "$SANDBOX/r" check-ignore -q .claude/settings.local.json && fail "settings.local.json ignored by a global excludes file" || pass
# a global setting lands in the sandbox file, not in the real one
git config --global test.isolation yes
assert_contains "$SANDBOX/gitconfig" "isolation = yes"
finish
