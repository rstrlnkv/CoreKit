#!/usr/bin/env bash
# Parity with the REAL Codex apply-patch parser: for each patch, the real `codex --codex-run-as-apply-patch` is run in
# the project's code folder and the file it really writes is named; the guards must judge that same file.
# Found by comparing patch-paths.awk with the real parser: Codex deletes TAB and CR inside a path (ADR 004 says
# "paths are verbatim"), so `do<TAB>cs/a.md` really writes docs/a.md while the guards saw `do<TAB>cs/a.md`.
# Skipped when `codex` is not installed. CODEX_HOME and HOME are the sandbox (new_sandbox).
source "$(dirname "$0")/lib.sh"
if ! command -v codex >/dev/null 2>&1; then echo "SKIP codex-patch-parity: codex not on PATH"; exit 0; fi
new_sandbox
trap 'rm -rf "$SANDBOX"' EXIT
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
mkdir -p "$CODEX_HOME" "$CORE_DIR/p/docs" "$HOME/.ssh"
: > "$CORE_DIR/p/CLAUDE.md"
C="$CORE_DIR/p/code"
nl=$'\n'; B='*** Begin Patch'; E='*** End Patch'; TAB=$'\t'; CR=$'\r'

reset() { rm -rf "$C"; mkdir -p "$C/src" "$C/docs" "$C/.claude"; printf 'one\n' > "$C/src/m.txt"; printf 'one\n' > "$C/docs/e.md"; printf 'K=1\n' > "$C/.env"; printf 'one\n' > "$C/CLAUDE.md"; rm -rf "$HOME/.ssh"; mkdir -p "$HOME/.ssh"; }
# real <patch> — run the real Codex parser in the code folder; its rc in RC_REAL
real() { ( cd "$C" && codex --codex-run-as-apply-patch "$1" </dev/null >"$SANDBOX/real.out" 2>&1 ); RC_REAL=$?; }
# hook <guard> <patch> — the apply_patch tool event for that patch; rc of the guard
hook() {
  local j; j="$(printf '%s' "$2" | LC_ALL=C awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); if (NR > 1) printf "\\n"; printf "%s", $0 }')"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"%s"}}' "$C" "$j" | bash "$HOOKS/$1.sh" >/dev/null 2>"$SANDBOX/hook.err"
}
# parity <guard> <label> <file really written, relative to $C or absolute> <patch>
#   the real parser writes that file, and the guard refuses the patch (exit 2 and a message)
parity() {
  reset; real "$4"
  if [ "$RC_REAL" = 0 ] && [ -f "$C/$3" -o -f "$3" ]; then pass; else fail "$2: the real Codex did not write $3 (rc $RC_REAL: $(head -c 200 "$SANDBOX/real.out"))"; fi
  reset; hook "$1" "$4"; local rc=$?
  assert_eq "$rc" "2" "$2: $1 must refuse a patch whose real target is $3"
  [ -s "$SANDBOX/hook.err" ] && pass || fail "$2: exit 2 without a message"
}
# twin <guard> <label> <file really written> <patch> — a harmless patch: really written, and the guard passes
twin() {
  reset; real "$4"
  if [ "$RC_REAL" = 0 ] && [ -f "$C/$3" ]; then pass; else fail "$2: the real Codex did not write $3 (rc $RC_REAL)"; fi
  reset; hook "$1" "$4"; assert_eq "$?" "0" "$2: $1 must pass"
}

# guard-code: the internal names split by a TAB or a CR inside the path
parity guard-code "TAB inside docs"        docs/a.md  "$B${nl}*** Add File: do${TAB}cs/a.md${nl}+x${nl}$E"
parity guard-code "CR inside docs"         docs/a.md  "$B${nl}*** Add File: do${CR}cs/a.md${nl}+x${nl}$E"
parity guard-code "TAB inside CLAUDE.md"   CLAUDE.md  "$B${nl}*** Update File: CLAUDE${TAB}.md${nl}@@${nl}-one${nl}+two${nl}$E"
parity guard-code "TAB inside .claude"     .claude/rules/x.md "$B${nl}*** Add File: .clau${TAB}de/rules/x.md${nl}+x${nl}$E"
parity guard-code "CR inside .claude"      .claude/rules/x.md "$B${nl}*** Add File: .claude/ru${CR}les/x.md${nl}+x${nl}$E"
parity guard-code "TAB between dir and /"  docs/a.md  "$B${nl}*** Add File: docs${TAB}/a.md${nl}+x${nl}$E"
parity guard-code "Update with a TAB"      docs/e.md  "$B${nl}*** Update File: do${TAB}cs/e.md${nl}@@${nl}-one${nl}+two${nl}$E"
parity guard-code "Move to with a TAB"     docs/m.md  "$B${nl}*** Update File: src/m.txt${nl}*** Move to: do${TAB}cs/m.md${nl}@@${nl}-one${nl}+two${nl}$E"
parity guard-code "Move to with a CR"      docs/m.md  "$B${nl}*** Update File: src/m.txt${nl}*** Move to: d${CR}ocs/m.md${nl}@@${nl}-one${nl}+two${nl}$E"
twin   guard-code "TAB in a harmless name" src/ab.c   "$B${nl}*** Add File: src/a${TAB}b.c${nl}+x${nl}$E"

# guard-secrets: .env and ~/.ssh split by a TAB or a CR
parity guard-secrets "TAB inside .env.new"  .env.new  "$B${nl}*** Add File: .e${TAB}nv.new${nl}+K=1${nl}$E"
parity guard-secrets "TAB inside .env.local" .env.local "$B${nl}*** Add File: .env.lo${TAB}cal${nl}+K=1${nl}$E"
parity guard-secrets "CR inside .env.local"  .env.local "$B${nl}*** Add File: .env${CR}.local${nl}+K=1${nl}$E"
parity guard-secrets "Update .env with a TAB" .env     "$B${nl}*** Update File: .e${TAB}nv${nl}@@${nl}-K=1${nl}+K=2${nl}$E"
parity guard-secrets "Move source .env with a CR" src/x "$B${nl}*** Update File: .e${CR}nv${nl}*** Move to: src/x${nl}@@${nl}-K=1${nl}+K=2${nl}$E"
parity guard-secrets "absolute ~/.ssh with a TAB" "$HOME/.ssh/k" "$B${nl}*** Add File: $HOME/.ss${TAB}h/k${nl}+k${nl}$E"
twin   guard-secrets "TAB in a harmless name" src/ab.c "$B${nl}*** Add File: src/a${TAB}b.c${nl}+x${nl}$E"
twin   guard-secrets ".env.example with a TAB" .env.example "$B${nl}*** Add File: .env.exam${TAB}ple${nl}+K=${nl}$E"
finish
