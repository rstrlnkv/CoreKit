#!/usr/bin/env bash
# Empty or relative HOME, empty Core:
#  - install-hooks.sh and session-start.sh do not derive the data folder from such a HOME: nothing is written under
#    the cwd (HOME=rel) or at the filesystem root (HOME=""); with a normal HOME, or CLAUDE_PLUGIN_DATA, they work as before;
#  - an empty Core path gives one clear message, not "Core not found at  —", a Core in the cwd or "already inside Core";
#  - guard-code refuses an apply_patch call whose path reader printed nothing, whatever the paths look like.
source "$(dirname "$0")/lib.sh"
new_sandbox
SBX_CORE="$CORE_DIR"
unset CLAUDE_PLUGIN_DATA COREDEV_TOOLS CORECREW_CONFIG CLAUDE_PLUGIN_OPTION_CORE_DIR
SCR="$SANDBOX/scratch"; mkdir -p "$SCR"
# a mkdir that logs its arguments, then runs the real one: the root path /.claude must never be asked for
mkdir -p "$SANDBOX/stub"; REAL_MKDIR="$(command -v mkdir)"
printf '#!/bin/sh\necho "$@" >> "%s/mkdir.log"\nexec "%s" "$@"\n' "$SANDBOX" "$REAL_MKDIR" > "$SANDBOX/stub/mkdir"; chmod +x "$SANDBOX/stub/mkdir"
untouched() {  # untouched <label>: the scratch cwd is still empty and no mkdir asked for a /.claude path
  assert_eq "$(ls -A "$SCR" | wc -l | tr -d ' ')" "0" "$1: nothing created in the cwd"
  if [ -f "$SANDBOX/mkdir.log" ] && grep -qE '(^| )(/\.claude|rel/)' "$SANDBOX/mkdir.log"; then fail "$1: mkdir asked for /.claude or rel/"; else pass; fi
  rm -f "$SANDBOX/mkdir.log"
}
mkdir -p "$CORE_DIR/p"

# --- 1. install-hooks.sh
for h in "" rel; do
  OUT="$(cd "$SCR" && env -u COREDEV_TOOLS HOME="$h" PATH="$SANDBOX/stub:$PATH" bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/p" 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && pass || fail "install-hooks HOME='$h': exit $RC, wanted non-zero"
  case "$OUT" in *"data folder is unknown"*) pass ;; *) fail "install-hooks HOME='$h': message: $OUT" ;; esac
  untouched "install-hooks HOME='$h'"
done
# legitimate: a normal HOME uses $HOME/.claude/plugins/data/corecrew-corekit/tools; CLAUDE_PLUGIN_DATA wins, also with HOME empty
mkdir -p "$SANDBOX/code1" && git -C "$SANDBOX/code1" init -q
env -u COREDEV_TOOLS HOME="$SANDBOX/home" bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/p" >/dev/null 2>&1
assert_file "$SANDBOX/home/.claude/plugins/data/corecrew-corekit/tools/VERSION"
env -u COREDEV_TOOLS HOME="" CLAUDE_PLUGIN_DATA="$SANDBOX/pd" bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/p" >/dev/null 2>&1
assert_file "$SANDBOX/pd/tools/VERSION"

# --- 2. session-start.sh
SS() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$SCR" | (cd "$SCR" && env -u CORE_DIR HOME="$1" PATH="$SANDBOX/stub:$PATH" bash "$HOOKS/session-start.sh") 2>&1; }
for h in "" rel; do
  OUT="$(SS "$h")"
  case "$OUT" in *"Core not found"*) fail "session-start HOME='$h': prints the hint with an empty Core path: $OUT" ;; *) pass ;; esac
  case "$OUT" in *"HOME is empty or not an absolute"*) pass ;; *) fail "session-start HOME='$h': no settings_no_home warning: $OUT" ;; esac
  untouched "session-start HOME='$h'"
done
# a Core path set by CORE_DIR but a bad HOME: the hint is shown, nothing is written, no tools sync
OUT="$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$SCR" | (cd "$SCR" && CORE_DIR="$SANDBOX/nocore" HOME=rel PATH="$SANDBOX/stub:$PATH" bash "$HOOKS/session-start.sh") 2>&1)"
case "$OUT" in *"Core not found at $SANDBOX/nocore"*) pass ;; *) fail "session-start HOME=rel CORE_DIR set: no hint: $OUT" ;; esac
untouched "session-start HOME=rel, CORE_DIR set"
# legitimate: a normal HOME writes the marker and the tools under it
OUT="$(SS "$SANDBOX/home2")"
assert_file "$SANDBOX/home2/.claude/plugins/data/corecrew-corekit/state/core-hint-shown"
assert_file "$SANDBOX/home2/.claude/plugins/data/corecrew-corekit/tools/VERSION"

# --- 3. an empty Core path in setup-core.sh, lib.sh core-paths, adopt.sh
for args in "" "--dry-run"; do
  OUT="$(cd "$SCR" && env -u CORE_DIR HOME="" bash "$SCRIPTS/setup-core.sh" $args 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && pass || fail "setup-core $args with no Core: exit $RC"
  case "$OUT" in *"no Core path"*) pass ;; *) fail "setup-core $args with no Core: message: $OUT" ;; esac
  if printf '%s\n' "$OUT" | grep -qE '^(would create|created) '; then fail "setup-core $args with no Core: lists work: $OUT"; else pass; fi
  untouched "setup-core $args with no Core"
done
OUT="$(cd "$SCR" && env -u CORE_DIR HOME="" bash "$SCRIPTS/setup-core.sh" "" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && pass || fail "setup-core with an empty argument: exit $RC"
untouched "setup-core with an empty argument"
OUT="$(env -u CORE_DIR HOME="" bash "$SCRIPTS/lib.sh" core-paths foo 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && pass || fail "core-paths with no Core: exit $RC"
case "$OUT" in "foo "*) fail "core-paths with no Core printed paths: $OUT" ;; *) pass ;; esac
# legitimate: with a Core it still prints the paths
assert_eq "$(CORE_DIR="$SBX_CORE" bash "$SCRIPTS/lib.sh" core-paths foo | cut -d' ' -f1)" "foo" "core-paths with a Core"
mkdir -p "$SANDBOX/repo" && git -C "$SANDBOX/repo" init -q && git -C "$SANDBOX/repo" commit -q --allow-empty -m i
OUT="$(env -u CORE_DIR HOME="" bash "$SCRIPTS/adopt.sh" --from "$SANDBOX/repo" --dry-run 2>&1)"; RC=$?
assert_eq "$RC" "2" "adopt with no Core: exit"
assert_eq "$OUT" "adopt: no Core: set core_dir, CORE_DIR or HOME first" "adopt with no Core: message"
# legitimate: a Core that is set up and a clean repo beside it is still planned as before (one exact outcome)
CORE_DIR="$SBX_CORE" bash "$SCRIPTS/setup-core.sh" >/dev/null 2>&1
PD="$(dirname "$SBX_CORE")"; LEGIT="$PD/legitrepo"; mkdir -p "$LEGIT" && git -C "$LEGIT" init -q && git -C "$LEGIT" commit -q --allow-empty -m i
OUT="$(CORE_DIR="$SBX_CORE" bash "$SCRIPTS/adopt.sh" --from "$LEGIT" --dry-run 2>&1)"; RC=$?
assert_eq "$RC" "0" "adopt with a Core, repo beside it: exit"
assert_eq "$(printf '%s\n' "$OUT" | tail -1)" "dry run: nothing was changed" "adopt with a Core, repo beside it: last line"
[ ! -e "$SBX_CORE/legitrepo" ] && pass || fail "adopt dry run created $SBX_CORE/legitrepo"
# a folder inside the Core that is not <name>/code of a project is refused with exactly this reason
mkdir -p "$SBX_CORE/inner" && git -C "$SBX_CORE/inner" init -q && git -C "$SBX_CORE/inner" commit -q --allow-empty -m i
OUT="$(CORE_DIR="$SBX_CORE" bash "$SCRIPTS/adopt.sh" --from "$SBX_CORE/inner" --dry-run 2>&1)"; RC=$?
assert_eq "$RC" "2" "adopt of a folder inside Core: exit"
assert_eq "$OUT" "already inside Core" "adopt of a folder inside Core: message"

# --- 4. guard-code: the reader printed nothing -> refused outright
CP="$SANDBOX/plugin-copy"; mkdir -p "$CP"; cp -R "$PLUGIN/." "$CP/"; rm -f "$CP/scripts/patch-paths.awk"
mkdir -p "$SBX_CORE/p/docs"; : > "$SBX_CORE/p/CLAUDE.md"
nl=$'\n'
gp() {  # gp <cwd> <patch text with \n escapes already as real newlines>
  local j; j="$(printf '%s' "$2" | LC_ALL=C awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); if (NR > 1) printf "\\n"; printf "%s", $0 }')"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$1" "$j" \
    | CORE_DIR="$SBX_CORE" bash "$CP/hooks/guard-code.sh" >/dev/null 2>"$SANDBOX/g.err"; GRC=$?
}
TAB=$'\t'
gp "$SBX_CORE/p/docs" "*** Begin Patch${nl}*** Add File: x.md${nl}+x${nl}*** End Patch"; assert_eq "$GRC" "2" "no reader: cwd-relative x.md in docs refused"
gp "$SBX_CORE/p/code" "*** Begin Patch${nl}*** Add File: do${TAB}cs/a.md${nl}+x${nl}*** End Patch"; assert_eq "$GRC" "2" "no reader: do<TAB>cs/a.md refused"
assert_contains "$SANDBOX/g.err" "patch-paths.awk is missing or failed"
# guard-secrets, same copy: a missing reader refuses, even .e<TAB>nv (the raw *** check cannot see it)
gs() {
  local j; j="$(printf '%s' "$2" | LC_ALL=C awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); if (NR > 1) printf "\\n"; printf "%s", $0 }')"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$1" "$j" \
    | CORE_DIR="$SBX_CORE" bash "$3/hooks/guard-secrets.sh" >/dev/null 2>"$SANDBOX/s.err"; GRC=$?
}
gs "$SBX_CORE/p/code" "*** Begin Patch${nl}*** Add File: .e${TAB}nv${nl}+x${nl}*** End Patch" "$CP"; assert_eq "$GRC" "2" "guard-secrets, no reader: .e<TAB>nv refused"
assert_contains "$SANDBOX/s.err" "patch-paths.awk is missing or failed"
gs "$SBX_CORE/p/code" "*** Begin Patch${nl}*** Add File: src/a.txt${nl}+x${nl}*** End Patch" "$CP"; assert_eq "$GRC" "2" "guard-secrets, no reader: plain patch refused"
# a patch that names no file: the reader ran, nothing to judge, both guards pass
gs "$SBX_CORE/p/code" "*** Begin Patch${nl}*** End Patch" "$PLUGIN"; assert_eq "$GRC" "0" "guard-secrets, empty patch passes"
gp "$SBX_CORE/p/code" "*** Begin Patch${nl}*** End Patch"; GP0="$GRC"
CP_SAVE="$CP"; CP="$PLUGIN"; gp "$SBX_CORE/p/code" "*** Begin Patch${nl}*** End Patch"; assert_eq "$GRC" "0" "guard-code, empty patch passes"; CP="$CP_SAVE"
assert_eq "$GP0" "2" "guard-code, empty patch with no reader refused"
# legitimate: the reader present, the same plain patch in a code folder passes
mkdir -p "$SBX_CORE/../code-p"
printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Add File: src/a.txt\\n+x\\n*** End Patch"}}' "$SBX_CORE/../code-p" \
  | CORE_DIR="$SBX_CORE" bash "$HOOKS/guard-code.sh" >/dev/null 2>&1; assert_eq "$?" "0" "reader present: plain patch passes"
finish
