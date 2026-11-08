#!/usr/bin/env bash
# lib.sh at its input limits:
#  - a settings file of exactly 64 KB is read, 64 KB + 1 is not (one warning);
#  - HOME="/" (absolute, but the root): core-dir does not crash and prints no path under //.
# HOME="/" for the guards is in test_hook_guard_code.sh and test_hook_guard_secrets.sh; the TAB/CR patch paths
# against the real Codex parser are in test_patch_paths.sh.
source "$(dirname "$0")/lib.sh"
new_sandbox
LIB="$SCRIPTS/lib.sh"
unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_ATTRIBUTION CLAUDE_PLUGIN_OPTION_MODEL_PROFILE CLAUDE_PLUGIN_OPTION_UI_LANGUAGE CORECREW_CONFIG
export HOME="$SANDBOX/home"; mkdir -p "$HOME"

# 1. exactly 64 KB (65536 bytes) is read; 65537 is not
mkfile() { { printf 'attribution: forbid\n'; head -c "$(( $1 - 20 ))" /dev/zero | tr '\0' '#'; } > "$2"; }
E="$SANDBOX/exact"; mkfile 65536 "$E"; assert_eq "$(wc -c < "$E" | tr -d ' ')" "65536" "fixture is 65536 bytes"
assert_eq "$(CORECREW_CONFIG="$E" bash "$LIB" settings attribution 2>"$SANDBOX/e")" "attribution: forbid" "a 65536-byte settings file is read"
assert_eq "$(grep -c "cannot be read" "$SANDBOX/e")" "0" "a 65536-byte settings file: no warning"
P="$SANDBOX/plus"; mkfile 65537 "$P"
assert_eq "$(CORECREW_CONFIG="$P" bash "$LIB" settings attribution 2>"$SANDBOX/e")" "attribution: allow" "a 65537-byte settings file is not read"
assert_eq "$(grep -c "cannot be read" "$SANDBOX/e")" "1" "a 65537-byte settings file: one warning"

# 2. HOME="/": no crash, no path under //
out="$(HOME=/ XDG_CONFIG_HOME= bash "$LIB" core-dir 2>"$SANDBOX/e")"; rc=$?
case "$out" in "//"*) fail "HOME=/: core-dir printed $out" ;; *) pass ;; esac
[ "$rc" -le 1 ] && pass || fail "HOME=/: core-dir rc $rc"
finish
