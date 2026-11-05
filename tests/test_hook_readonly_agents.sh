#!/usr/bin/env bash
# hooks/guard-code.sh, read-only checkers: inside the corecrew agents designer, localizer, security and
# verifier (hook input agent_type), a Bash command that changes files outside the temp folders is
# refused: redirects, tee, touch, cp, mv, mkdir, rm, ln, in-place sed or perl edits, and git commands that change
# the repo. Reading, running tests and writing logs under the temp folders pass. Other agents and the
# main chat are not affected.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/guard-code.sh"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
setup_core >/dev/null 2>&1
mkdir -p "$CORE_DIR/ro-app"; : > "$CORE_DIR/ro-app/CLAUDE.md"   # the project: its private folder in the Core
C="$SANDBOX/Projects/ro-app"; mkdir -p "$C/src"; : > "$C/src/a.txt"
TMPD="$(cd "${TMPDIR:-/tmp}" && pwd -P)"

# run_as <agent_type> <command> [cwd] — exit code in RC, stderr in ERR
run_as() {
  local at=""; [ -n "$1" ] && at="$(printf ',"agent_id":"a1","agent_type":"%s"' "$1")"
  local cmd; cmd="$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  ERR="$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}%s}' "${3:-$C}" "$cmd" "$at" | bash "$H" 2>&1 >/dev/null)"; RC=$?
}
refused() { run_as "$1" "$2" "$3"; assert_eq "$RC" "2" "$1 refused: $2"; case "$ERR" in *read-only*) pass ;; *) fail "no read-only reason for: $2 ($ERR)" ;; esac; }
allowed() { run_as "$1" "$2" "$3"; assert_eq "$RC" "0" "${1:-main} allowed: $2 ($ERR)"; }

V=corecrew:verifier
# writes into the project
refused $V 'echo x > src/a.txt'
refused $V 'printf x >> src/new.txt'
refused $V 'tee src/out.txt < /dev/null'
refused $V 'touch src/b.txt'
refused $V 'cp src/a.txt src/c.txt'
refused $V 'mv src/a.txt src/d.txt'
refused $V 'mkdir src/x'
refused $V 'rm -f src/a.txt'
refused $V 'ln -s src/a.txt src/l'
SEDI="sed -""i"   # spelled in two parts: the portability check reads this file too
refused $V "$SEDI '' s/a/b/ src/a.txt"
refused $V "perl -pi -e s/a/b/ src/a.txt"
refused $V 'git commit -qm x'
refused $V 'git -C . add -A'
refused $V 'git checkout -- src/a.txt'
refused $V 'git reset --hard'
refused $V 'git stash'
refused $V 'git branch -D old'
refused $V 'bash -c "rm src/a.txt"'
refused $V "echo x > /opt/ro-elsewhere.txt"   # outside the temp folders
# reading, tests, logs under the temp folders
allowed $V 'cat src/a.txt'
allowed $V 'git status --short && git diff && git log --oneline -3 && git branch'
allowed $V "sed -n 1,5p src/a.txt"
allowed $V "npm test > $TMPD/ro-log.txt 2>&1"
allowed $V "swift test 2>&1 | tee /tmp/ro-log.txt"
allowed $V "cp src/a.txt $TMPD/copy.txt"
allowed $V "rm -f /tmp/ro-log.txt"
allowed $V 'ls > /dev/null 2>&1'
allowed $V 'echo x > "$TMPDIR/log.txt"'   # a target with a variable is not judged (fails open)
# every read-only checker, also by its bare name; outside a project too
for a in corecrew:designer corecrew:localizer corecrew:security verifier designer; do refused "$a" 'echo x > src/a.txt'; done
refused $V "echo x > /opt/ro-elsewhere.txt" "$SANDBOX"
# the sandbox (and so this project) sits inside the temp folder: a project there is still the project
refused $V "echo x > $C/src/abs.txt"
# the authors and other agents are not affected
allowed corecrew:engineer 'echo x > src/a.txt'
allowed corecrew:tester 'rm -f src/a.txt'
allowed other:verifier 'rm -f src/a.txt'
allowed Explore 'echo x > src/a.txt'
allowed "" 'rm -f src/a.txt'
# messages in Russian
CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run_as $V 'rm -f src/a.txt'
case "$ERR" in *"только читает"*) pass ;; *) fail "ru message: $ERR" ;; esac
finish
