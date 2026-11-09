#!/usr/bin/env bash
# What each hook costs: for each hook and a common payload, the outcome (exit code; silent or refused) and an upper
# bound on the programs the run starts. A hook runs on every tool call, so a program more on its common path is paid
# on every call; this file is where such a change shows. The bounds are counts, not times: wall time varies 3 to 5
# times between machines (Decision 39 of the round-3 plan).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox

# --- The budgets: the programs a run starts, measured on the round-3 branch after wave 5, with zero slack. A count
# is what count_execs (tests/lib.sh) logs: every program started through PATH, nested ones included, and so also the
# counting wrapper's own `bash` (run_hook starts the hook with `bash <hook>`). The `sh` that runs each logging shim
# is started by its full path (the shim's #! line) and is not counted; the `sh` in the Stop count is the hook's own
# (xargs sh -c). Raise a budget only with the reason in the commit; lower it when a hook gets cheaper.
COST_GIT_STATUS_ONE_SUITE=2        # bash cat: the prefilter finds no "test" in the payload
COST_GIT_STATUS_GUARD_CODE=5       # bash cat dirname*2 awk
COST_GIT_STATUS_GUARD_SECRETS=5    # bash cat dirname*2 awk
COST_REDIRECT_ONE_SUITE=2          # bash cat
COST_REDIRECT_GUARD_CODE=8         # bash cat dirname*2 awk*2 tr*2
COST_REDIRECT_GUARD_SECRETS=8      # bash cat dirname*2 awk*2 tr*2
COST_WRITE_GUARD_CODE=6            # bash cat dirname*2 awk tr
COST_WRITE_GUARD_SECRETS=10        # bash cat dirname*2 awk grep tr*4
COST_READ_GUARD_SECRETS=10         # bash cat dirname*2 awk grep tr*4
COST_PATCH_GUARD_CODE=7            # bash cat dirname*2 awk*2 tr
COST_PATCH_GUARD_SECRETS=10        # bash cat dirname*2 awk*2 tr*4
COST_OUTSIDE_ONE_SUITE=2           # bash cat
COST_OUTSIDE_GUARD_CODE=5          # bash cat dirname*2 awk
COST_OUTSIDE_GUARD_SECRETS=5       # bash cat dirname*2 awk
COST_SESSION_START=28              # bash*2 (the wrapper's, sync-tools.sh) git cat*2 awk*4 cksum*4 grep*3 tr*5 ...
COST_STOP_REMINDED=44              # git*13 dirname*6 tr*4 cat*3 basename*3 xargs*2 sh find ls mktemp rm ...
# load_settings (every hook runs it) opens 2 command substitutions with CORE_DIR unset and no settings file:
# canon_dir's one `cd -P` for each of its two paths. Counted under xtrace, as tests/test_settings.sh counts them.
COST_LOAD_SETTINGS_COMSUBS=2

# The project lives under a temp path of its own: one-suite's prefilter looks for "test" anywhere in the payload, and
# the sandbox path holds np-test, so a cwd there would always take the long path.
NT="$(mktemp -d "${TMPDIR:-/tmp}/hc.XXXXXX")" && NT="$(cd -P "$NT" && pwd)"
at_exit 'rm -rf "$NT"'
case "$NT" in *[tT]est*) skip "hook-cost" "the temp path $NT holds \"test\""; finish ;; esac
export CORE_DIR="$NT/Projects/Core"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
setup_core; sync_tools   # sync_tools: SessionStart finds the tools current
bash "$SKILL/scripts/scaffold.sh" --name app >/dev/null || fail "scaffold"
C="$NT/Projects/app"; E="$NT/elsewhere"; mkdir -p "$C/src" "$E"
(cd "$C" && bash "$SCRIPTS/save" "init") >/dev/null 2>&1 || fail "save init"
# shellcheck disable=SC2034  # run_hook and count_execs (tests/lib.sh) write under OD
OD="$SANDBOX"
exec_shims

# cost <label> <hook> <budget> <rc> <silent|refused> <json> — runs the hook once under count_execs and asserts the
# outcome and the bound; the log of programs goes into the message when the bound is passed.
cost() {
  count_execs run_hook "$HOOKS/$2.sh" "$6"
  assert_eq "$RC" "$4" "$1: exit code"
  assert_eq "$OUT" "" "$1: stdout"
  case "$5" in
    silent) assert_eq "$ERR" "" "$1: stderr" ;;
    refused) [ -n "$ERR" ] && pass || fail "$1: no message" ;;
  esac
  note "$1: $EXECS programs (budget $3)"
  [ "$EXECS" -le "$3" ] && pass \
    || fail "$1: $EXECS programs, budget $3: $(LC_ALL=C sort "$EXEC_LOG" | uniq -c | tr -s ' \n' ' ')"
}
pre() { hook_event claude PreToolUse "${3-$C}" tool=Bash command="$1"; }
file() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$C" "$1" "$2"; }
PATCH='*** Begin Patch
*** Add File: src/x.py
+x
*** End Patch'

cost "Bash git status: one-suite"       one-suite     "$COST_GIT_STATUS_ONE_SUITE"     0 silent "$(pre 'git status')"
cost "Bash git status: guard-code"      guard-code    "$COST_GIT_STATUS_GUARD_CODE"    0 silent "$(pre 'git status')"
cost "Bash git status: guard-secrets"   guard-secrets "$COST_GIT_STATUS_GUARD_SECRETS" 0 silent "$(pre 'git status')"
cost "Bash redirect: one-suite"         one-suite     "$COST_REDIRECT_ONE_SUITE"       0 silent "$(pre 'echo hi > src/out.txt')"
cost "Bash redirect: guard-code"        guard-code    "$COST_REDIRECT_GUARD_CODE"      0 silent "$(pre 'echo hi > src/out.txt')"
cost "Bash redirect: guard-secrets"     guard-secrets "$COST_REDIRECT_GUARD_SECRETS"   0 silent "$(pre 'echo hi > src/out.txt')"
cost "Write src/x.py: guard-code"       guard-code    "$COST_WRITE_GUARD_CODE"         0 silent "$(file Write "$C/src/x.py")"
cost "Write src/x.py: guard-secrets"    guard-secrets "$COST_WRITE_GUARD_SECRETS"      0 silent "$(file Write "$C/src/x.py")"
cost "Read src/x.py: guard-secrets"     guard-secrets "$COST_READ_GUARD_SECRETS"       0 silent "$(file Read "$C/src/x.py")"
cost "Codex apply_patch: guard-code"    guard-code    "$COST_PATCH_GUARD_CODE"         0 silent "$(hook_event codex PreToolUse "$C" tool=apply_patch command="$PATCH")"
cost "Codex apply_patch: guard-secrets" guard-secrets "$COST_PATCH_GUARD_SECRETS"      0 silent "$(hook_event codex PreToolUse "$C" tool=apply_patch command="$PATCH")"
cost "Bash outside a project: one-suite"     one-suite     "$COST_OUTSIDE_ONE_SUITE"     0 silent "$(pre 'git status' "$E")"
cost "Bash outside a project: guard-code"    guard-code    "$COST_OUTSIDE_GUARD_CODE"    0 silent "$(pre 'git status' "$E")"
cost "Bash outside a project: guard-secrets" guard-secrets "$COST_OUTSIDE_GUARD_SECRETS" 0 silent "$(pre 'git status' "$E")"

# SessionStart prints the project context on stdout, so its outcome is checked here and not by cost
count_execs run_hook "$HOOKS/session-start.sh" "$(hook_event claude SessionStart "$C" source=startup)"
assert_eq "$RC" "0" "SessionStart: exit code"; assert_eq "$ERR" "" "SessionStart: stderr"
[ -n "$OUT" ] && pass || fail "SessionStart: no context on stdout"
note "SessionStart: $EXECS programs (budget $COST_SESSION_START)"
[ "$EXECS" -le "$COST_SESSION_START" ] && pass \
  || fail "SessionStart: $EXECS programs, budget $COST_SESSION_START: $(LC_ALL=C sort "$EXEC_LOG" | uniq -c | tr -s ' \n' ' ')"

# Stop in a dirty project that was already reminded of this change set: silent, exit 0
stop_in() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$C"; }
echo x > "$C/new.txt"
run_hook "$HOOKS/stop-remind.sh" "$(stop_in)"; assert_eq "$RC" "2" "Stop, dirty: the first stop reminds"
cost "Stop, dirty and reminded: stop-remind" stop-remind "$COST_STOP_REMINDED" 0 silent "$(stop_in)"

# load_settings' command substitutions
subs() { ( unset CORE_DIR; bash -c '. "$1"; PS4=+; set -x; load_settings' _ "$SCRIPTS/lib.sh" 2>&1 ) \
  | awk '/^\+\+/ && prev !~ /^\+\+/ {s++} {prev=$0} END{print s+0}'; }
[ ! -e "$XDG_CONFIG_HOME/corecrew/settings" ] && pass || fail "a settings file in the sandbox"
n="$(subs)"; note "load_settings: $n command substitutions (budget $COST_LOAD_SETTINGS_COMSUBS)"
[ "$n" -le "$COST_LOAD_SETTINGS_COMSUBS" ] && pass || fail "load_settings: $n command substitutions, budget $COST_LOAD_SETTINGS_COMSUBS"

finish
