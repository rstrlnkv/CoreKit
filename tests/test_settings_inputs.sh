#!/usr/bin/env bash
# Inputs nobody fed to the settings resolver (lib.sh settings, setting-path, load_settings):
#  - a settings file with one huge line is read in quadratic time, so every guard hook runs past its 15 s timeout
#    (a timeout does not block: the guards fail open);
#  - a relative CORECREW_CONFIG is resolved against the cwd of whoever runs the script (a relative XDG_CONFIG_HOME
#    is already ignored for that reason);
#  - an empty HOME turns the default core_dir ~/Projects/Core into /Projects/Core at the filesystem root.
source "$(dirname "$0")/lib.sh"
new_sandbox
trap 'rm -rf "$SANDBOX"' EXIT
LIB="$SCRIPTS/lib.sh"
unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_ATTRIBUTION CLAUDE_PLUGIN_OPTION_MODEL_PROFILE CLAUDE_PLUGIN_OPTION_UI_LANGUAGE CORECREW_CONFIG
export HOME="$SANDBOX/home"; mkdir -p "$HOME"
command -v timeout >/dev/null 2>&1 || timeout() { shift; "$@"; }

# 1. one huge line (250 KB of 'a', then a real key): the file is over 64 KB, so it is not read; the answer comes fast
F="$SANDBOX/huge"
head -c 250000 /dev/zero | tr '\0' 'a' > "$F"; printf '\nattribution: forbid\n' >> "$F"
t0="$(date +%s)"
got="$(CORECREW_CONFIG="$F" timeout 60 bash "$LIB" settings attribution 2>/dev/null)"
t1="$(date +%s)"
assert_eq "$got" "attribution: allow" "a 250 KB settings file is over the 64 KB limit: not read, the default is used"
[ $((t1 - t0)) -lt 3 ] && pass || fail "lib.sh settings with a 250 KB line took $((t1 - t0)) s (quadratic read of the settings file)"
# the same through a guard hook: the whole hook must stay far below its 15 s timeout
CD="$SANDBOX/Projects/Core"; mkdir -p "$CD/p/code"; : > "$CD/p/CLAUDE.md"
t0="$(date +%s)"
printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/docs/a.md","content":"x"}}' "$CD/p/code" "$CD/p/code" \
  | CORE_DIR="$CD" CORECREW_CONFIG="$F" timeout 60 bash "$HOOKS/guard-code.sh" >/dev/null 2>"$SANDBOX/hook.err"; rc=$?
t1="$(date +%s)"
[ $((t1 - t0)) -lt 3 ] && pass || fail "guard-code with a 250 KB settings line took $((t1 - t0)) s (hook timeout 15 s, a timeout does not block)"
assert_eq "$rc" "2" "guard-code still refuses docs/ with a huge settings file"

# a 40 KB line (under the limit) is read in one linear pass and the key after it is found
M="$SANDBOX/mid"; { head -c 40000 /dev/zero | tr '\0' 'a'; printf '\nattribution: forbid\n'; } > "$M"
t0="$(date +%s)"; got="$(CORECREW_CONFIG="$M" bash "$LIB" settings attribution 2>/dev/null)"; t1="$(date +%s)"
assert_eq "$got" "attribution: forbid" "a key after a 40 KB line is still read"
[ $((t1 - t0)) -lt 2 ] && pass || fail "a 40 KB line took $((t1 - t0)) s"

# 2. a relative CORECREW_CONFIG is not read against the cwd
mkdir -p "$SANDBOX/cwd"; printf 'attribution: forbid\n' > "$SANDBOX/cwd/rel-settings"
assert_eq "$(cd "$SANDBOX/cwd" && CORECREW_CONFIG=rel-settings bash "$LIB" settings attribution 2>/dev/null)" "attribution: allow" \
  "a relative CORECREW_CONFIG must be ignored like a relative XDG_CONFIG_HOME"
case "$(cd "$SANDBOX/cwd" && CORECREW_CONFIG=rel-settings bash "$LIB" setting-path)" in
  /*) pass ;; *) fail "setting-path prints a relative path for a relative CORECREW_CONFIG" ;;
esac

# 3. an empty HOME: the default Core must not land at /Projects/Core
out="$(HOME= XDG_CONFIG_HOME= bash "$LIB" core-dir 2>/dev/null)"
[ "$out" != "/Projects/Core" ] && pass || fail "HOME empty: the default core_dir became /Projects/Core at the filesystem root"
# an empty or relative HOME: no default Core at all; core-dir warns and fails, a hook stays inert
for H in "" "rel"; do
  HOME="$H" XDG_CONFIG_HOME= bash "$LIB" core-dir >"$SANDBOX/o" 2>"$SANDBOX/e"; rc=$?
  [ "$rc" -ne 0 ] && pass || fail "HOME='$H': core-dir exits 0"
  assert_eq "$(<"$SANDBOX/o")" "" "HOME='$H': core-dir prints no path"
  grep -q "HOME" "$SANDBOX/e" && pass || fail "HOME='$H': core-dir warns about HOME"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/docs/a.md","content":"x"}}' "$SANDBOX" "$SANDBOX" \
    | env -u CORE_DIR HOME="$H" XDG_CONFIG_HOME= bash "$HOOKS/guard-code.sh" >"$SANDBOX/o" 2>"$SANDBOX/e"; rc=$?
  assert_eq "$rc" "0" "HOME='$H': guard-code is inert"
done

# 4. a settings file over 64 KB is not read: one warning, the defaults
B="$SANDBOX/big"; { printf 'attribution: forbid\n'; head -c 70000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$B"
assert_eq "$(CORECREW_CONFIG="$B" bash "$LIB" settings attribution 2>"$SANDBOX/e")" "attribution: allow" "a settings file over 64 KB is not read"
assert_eq "$(grep -c "cannot be read" "$SANDBOX/e")" "1" "a settings file over 64 KB: one warning"
S="$SANDBOX/small"; printf 'attribution: forbid\nui_language: ru\n' > "$S"
assert_eq "$(CORECREW_CONFIG="$S" bash "$LIB" settings attribution ui_language 2>&1)" "$(printf 'attribution: forbid\nui_language: ru')" "a small file gives all its keys"
finish
