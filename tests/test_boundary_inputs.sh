#!/usr/bin/env bash
# Boundary inputs after the settings/patch repair:
#  - a settings file of exactly 64 KB is read, 64 KB + 1 is not (one warning);
#  - HOME="/" (absolute, but the root): no crash, the hooks stay quiet;
#  - a patch path with a TAB or CR at its start or end, and a CR-only line ending, judged like the real Codex parser
#    (the parity part is skipped when `codex` is not installed).
source "$(dirname "$0")/lib.sh"
new_sandbox
LIB="$SCRIPTS/lib.sh"
SBX_CORE="$CORE_DIR"; unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_ATTRIBUTION CLAUDE_PLUGIN_OPTION_MODEL_PROFILE CLAUDE_PLUGIN_OPTION_UI_LANGUAGE CORECREW_CONFIG
export HOME="$SANDBOX/home"; mkdir -p "$HOME"

# 1. exactly 64 KB (65536 bytes) is read; 65537 is not
mkfile() { { printf 'attribution: forbid\n'; head -c "$(( $1 - 20 ))" /dev/zero | tr '\0' '#'; } > "$2"; }
E="$SANDBOX/exact"; mkfile 65536 "$E"; assert_eq "$(wc -c < "$E" | tr -d ' ')" "65536" "fixture is 65536 bytes"
assert_eq "$(CORECREW_CONFIG="$E" bash "$LIB" settings attribution 2>"$SANDBOX/e")" "attribution: forbid" "a 65536-byte settings file is read"
assert_eq "$(grep -c "cannot be read" "$SANDBOX/e")" "0" "a 65536-byte settings file: no warning"
P="$SANDBOX/plus"; mkfile 65537 "$P"
assert_eq "$(CORECREW_CONFIG="$P" bash "$LIB" settings attribution 2>"$SANDBOX/e")" "attribution: allow" "a 65537-byte settings file is not read"
assert_eq "$(grep -c "cannot be read" "$SANDBOX/e")" "1" "a 65537-byte settings file: one warning"

# 2. HOME="/": no crash, no path under //; guard-code and guard-secrets stay inert (exit 0) on a plain edit
out="$(HOME=/ XDG_CONFIG_HOME= bash "$LIB" core-dir 2>"$SANDBOX/e")"; rc=$?
case "$out" in "//"*) fail "HOME=/: core-dir printed $out" ;; *) pass ;; esac
[ "$rc" -le 1 ] && pass || fail "HOME=/: core-dir rc $rc"
for g in guard-code guard-secrets; do
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/a.txt","content":"x"}}' "$SANDBOX" "$SANDBOX" \
    | env -u CORE_DIR HOME=/ XDG_CONFIG_HOME= bash "$HOOKS/$g.sh" >/dev/null 2>"$SANDBOX/e"; assert_eq "$?" "0" "HOME=/: $g passes a plain write"
done

# 3. patch paths with TAB/CR at an edge, and CR-only line endings, against the real parser
if ! command -v codex >/dev/null 2>&1; then skip "part 3 (patch paths against the real parser)" "codex not on PATH"; finish; fi
CORE_DIR="$SBX_CORE"; export CORE_DIR; mkdir -p "$CODEX_HOME" "$CORE_DIR/p/docs"; : > "$CORE_DIR/p/CLAUDE.md"
C="$CORE_DIR/p/code"; nl=$'\n'; B='*** Begin Patch'; En='*** End Patch'; TAB=$'\t'; CR=$'\r'
reset() { rm -rf "$C"; mkdir -p "$C/src" "$C/docs" "$C/.claude"; printf 'one\n' > "$C/src/m.txt"; printf 'one\n' > "$C/docs/e.md"; printf 'K=1\n' > "$C/.env"; printf 'one\n' > "$C/CLAUDE.md"; }
real() { ( cd "$C" && codex --codex-run-as-apply-patch "$1" </dev/null >"$SANDBOX/real.out" 2>&1 ); RC_REAL=$?; }
hook() {
  local j; j="$(printf '%s' "$2" | LC_ALL=C awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); if (NR > 1) printf "\\n"; printf "%s", $0 }')"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$C" "$j" | bash "$HOOKS/$1.sh" >/dev/null 2>"$SANDBOX/hook.err"
}
# edge <guard> <label> <file the real parser writes> <patch>: the real parser writes it, the guard refuses
edge() {
  reset; real "$4"
  if [ "$RC_REAL" = 0 ] && [ -f "$C/$3" ]; then pass; else fail "$2: the real Codex did not write $3 (rc $RC_REAL: $(head -c 200 "$SANDBOX/real.out"))"; fi
  reset; hook "$1" "$4"; assert_eq "$?" "2" "$2: $1 must refuse"
}
edge guard-code "TAB at the start"  docs/a.md "$B${nl}*** Add File: ${TAB}docs/a.md${nl}+x${nl}$En"
edge guard-code "TAB at the end"    docs/a.md "$B${nl}*** Add File: docs/a.md${TAB}${nl}+x${nl}$En"
edge guard-code "CR at the end"     docs/a.md "$B${nl}*** Add File: docs/a.md${CR}${nl}+x${nl}$En"
edge guard-code "CR at the start"   docs/a.md "$B${nl}*** Add File: ${CR}docs/a.md${nl}+x${nl}$En"
edge guard-code "Move to TAB end"   docs/m.md "$B${nl}*** Update File: src/m.txt${nl}*** Move to: docs/m.md${TAB}${nl}@@${nl}-one${nl}+two${nl}$En"
edge guard-secrets "TAB at the start .env.new" .env.new "$B${nl}*** Add File: ${TAB}.env.new${nl}+K=1${nl}$En"
edge guard-secrets "TAB at the end .env.new"   .env.new "$B${nl}*** Add File: .env.new${TAB}${nl}+K=1${nl}$En"
# CR-only line endings: what the real parser does, the guards must do too (refuse when it writes an internal file)
cr_only="${B}${CR}*** Add File: docs/a.md${CR}+x${CR}${En}"
reset; real "$cr_only"; rr="$RC_REAL"; wrote=0; [ -f "$C/docs/a.md" ] && wrote=1
reset; hook guard-code "$cr_only"; rc=$?
if [ "$wrote" = 1 ]; then assert_eq "$rc" "2" "CR-only patch: the real parser wrote docs/a.md, guard-code must refuse"
else assert_eq "$rc" "2" "CR-only patch the real parser rejects (rc $rr): guard-code fails closed"; fi
finish
