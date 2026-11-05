#!/usr/bin/env bash
# Claude Code PreToolUse hook on Bash: holds a test run while another one is running on this
# machine, and lets it through when that one ends. Two suites at once fail each other — they share
# settings, the Trash, $TMPDIR and a scratch path — and a note in a project's knowledge saying so
# does not stop anyone from doing it. The hook waits here rather than refusing: a refused agent has
# nothing to wait with, so it asks again or looks at `ps` once per step, and every step re-reads its
# whole context. Only a wait longer than ONE_SUITE_WAIT seconds is refused (exit 2; stderr goes back
# to the caller: "run the same command again").
# Inert outside a project (docs/specs/2026-11-04-project-layout-design.md section 4: <Core>/<project>/ or
# its code folder beside the Core): with no cwd, or a cwd that is not inside a project, it exits 0 at
# once, before it looks at the command or at any process.
# Only the command is read, never the description: "see whether swift test runs" is not a test run.
# Anything this hook cannot judge passes (exit 0): a stuck guard would stop every Bash call, which is
# worse than one clash. It never prints to stdout. No jq, no python. Without pgrep it lets everything
# through.
#
# Env knobs, for tests: ONE_SUITE_PROCS (the process pattern, replaces the default), ONE_SUITE_WAIT
# (seconds to wait; default 480), ONE_SUITE_GRACE (seconds a turn stays fresh; default 3),
# ONE_SUITE_TURN (the turn directory).
# Known limits: the grace of 3 s is short against a permission prompt the person answers slowly, after
# which a second run may start; and the takeover of a stale turn is safe only among hooks that use the
# lock (a hook killed while it holds a mkdir lock leaves it for 2 s). The takeover is done under a short
# lock (flock, else mkdir; see stale_take), so waiters that find the same stale turn together no longer
# go together (tried before: one atomic rename; it only narrowed the window, since a fresh turn taken
# by mistake had to be put back).
# The default wait of 480 s must stay under this hook's `timeout` in hooks/hooks.json (Task 19 sets
# it to 540) and under the stream watchdog, which stops an agent that is silent for 600 s.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting

# Inert outside a project.
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0
load_settings
project_of "$cwd" >/dev/null 2>&1 || exit 0

cmd="$(json_str "$in" command)"
[ -n "$cmd" ] || exit 0

# Only command words count. A heredoc's body is cut at its `<<`; a new line (or CR) separates
# commands like `;` does; then quoted text (a commit message, a `python -c` body: 'x' or "x", with \"
# inside double quotes) is cut. A command that merely mentions a runner is no run.
# A << that is a shift ($((1<<3)), (( x << 2 )), <<3) is no heredoc: it is taken out before the cut.
noshift="$(printf '%s' "$cmd" | LC_ALL=C sed -E 's/\(\([^()]*\)\)//g; s/<<[[:space:]]*[0-9]/ 0/g')"
bare="$(printf '%s' "${noshift%%<<*}" | LC_ALL=C tr '\n\r\t' ';; ' \
  | LC_ALL=C sed -E "s/('[^']*'|\"([^\"\\\\]|\\\\.)*\")//g")"

# A runner is a command word: after a separator, optionally behind env assignments and wrappers
# (time, sudo, uv run, ...) and a path (./gradlew, .venv/bin/pytest); `cat tests.sh`, `pip install
# pytest` and `grep -rn pytest .` are not runs. A project's test script is run as a command
# (`bash Scripts/test.sh`, `./run-tests.sh`); `cat Scripts/test.sh` reads it and is not a run.
sp='[[:space:]]'; stop='[^[:space:];&|]'
pre="(^|[;&|(])$sp*(([A-Za-z_][A-Za-z0-9_]*=$stop*|then|do|else|time|exec|command|nohup|sudo|env|nice|xcrun|caffeinate|(uv|poetry|pipenv)$sp+run|bundle$sp+exec)$sp+)*($stop*/)?"
end="($sp|[;&|)]|\$)"
runners="swift$sp+test$end"
runners="$runners|xcodebuild[^;&|]*$sp+test(-without-building)?$end"
runners="$runners|npm$sp+(run$sp+)?test([:_-]$stop*)?$end"
runners="$runners|npx($sp+-$stop+)*$sp+(test|vitest)$end"
runners="$runners|vitest$sp+run$end"
# gradlew: a task word counts: test, testX or fooTest (connectedAndroidTest), with an optional :project: path.
# compileTestKotlin does not, and neither does a task that follows -x / --exclude-task (cut out below).
runners="$runners|gradlew[^;&|]*$sp(:?[A-Za-z0-9_-]+:)*(test[A-Za-z0-9]*|[a-z][A-Za-z0-9]*Test)$end"
runners="$runners|(python[0-9.]*$sp+-m$sp+)?pytest$end"
runners="$runners|cargo($sp+[+-]$stop*)*$sp+test$end"
runners="$runners|flutter$sp+test$end"
runners="$runners|go$sp+test$end"
script="(^|[;&|(])$sp*(([A-Za-z_][A-Za-z0-9_]*=$stop*|time|exec|nohup|sudo)$sp+)*((ba|z)?sh($sp+-[a-z]+)*$sp+)?$stop*tests?\\.sh$end"
bare="$(printf '%s' "$bare" | LC_ALL=C sed -E "s/$sp(-x|--exclude-task)($sp+|=)$stop+//g")"
printf '%s' "$bare" | LC_ALL=C grep -qE "${pre}(${runners})|${script}" || exit 0
command -v pgrep >/dev/null 2>&1 || exit 0

# ONE_SUITE_PROCS replaces the process pattern (ERE, matched against whole command lines by
# `pgrep -f`), so this hook's own tests do not depend on what happens to be running on the machine.
# Every alternative is anchored on a command word, so an editor or `grep` with the name of a runner
# as an argument does not count; the hook's own command line matches nothing here.
default_procs='(^|/)swift[- ]test( |$)|(^|/)xctest( |$)|(^|/)xcodebuild( .*)? test(-without-building)?( |$)|node_modules/(\.bin/vitest|vitest/dist/)|(^|/)vitest run( |$)|(^|/)gradlew( .*)? ([^ ]*:)?(test[A-Za-z0-9]*|[a-z][A-Za-z0-9]*Test)( |$)|Gradle Test Executor|(^|/)pytest( |$)|(^|/)py\.test( |$)|-m pytest( |$)|(^|/)cargo( \+[^ ]+)? test( |$)|(^|/)flutter test( |$)|flutter_tools\.snapshot test( |$)|(^|/)go test( |$)|/go-build[0-9]+/.*\.test( |$)|(^|/)(ba|z)?sh( -[a-z]+)* [^ ]*tests?\.sh( |$)'
procs="${ONE_SUITE_PROCS:-$default_procs}"

# The turn: a directory only one waiter can make. A run that was let through takes a moment to
# appear among the processes, and without the turn every waiter would see "nothing running" in that
# moment and start together. A turn older than its grace belongs to a run that has started or never
# will, and the next waiter takes it. The grace is short (3 s): a run shows among the processes
# within a second of being let through, and a quick suite re-run at once should not wait long.
# If the turn can be neither made nor cleared (its folder is
# missing or read-only, a stale turn belongs to someone else) waiting cannot help: the call is let
# through. Every other path through the loop below reaches the limit check and the sleep.
turn="${ONE_SUITE_TURN:-${TMPDIR:-/tmp}/corecrew-one-suite.turn}"
grace="${ONE_SUITE_GRACE:-3}"; limit="${ONE_SUITE_WAIT:-480}"
case "$grace" in ''|*[!0-9]*) grace=3 ;; esac
case "$limit" in ''|*[!0-9]*) limit=480 ;; esac

# running_line — the first other process (pid and command line) that matches $procs. A gradlew run
# whose test task follows -x / --exclude-task is dropped: a regular expression cannot say "not after -x".
running_line() {
  local line rest
  pgrep -fl "$procs" 2>/dev/null | while IFS= read -r line; do
    [ "${line%% *}" = "$$" ] && continue
    rest="${line#* }"
    case "$rest" in
      *gradlew*)
        rest="$(printf '%s' "$rest" | LC_ALL=C sed -E 's/[[:space:]](-x|--exclude-task)([[:space:]]+|=)[^[:space:]]+//g')"
        printf '%s' "$rest" | LC_ALL=C grep -qE -- "$procs" || continue ;;
    esac
    printf '%s\n' "$line"
  done | head -1
}

# stale_take — take a stale turn over, under a short lock. Two waiters that find the same stale turn
# at the same instant must not both remove and re-make it: the second removal would take away the turn
# the first one has just made, and both go. So the turn is judged again once the lock is held, and only
# then removed and made anew. Returns 0: the turn is ours, the call goes; 1: it is not ours (it is
# fresh again, or the lock stayed busy): keep waiting; 2: it cannot be cleared: let the call through.
stale_take_locked() {
  local at now; now="$(date +%s)"
  at="$(cat "$turn/at" 2>/dev/null)"
  case "$at" in ''|*[!0-9]*)   # a turn made an instant ago has no `at` yet (mkdir, then the write): look again
    sleep 0.1 2>/dev/null; at="$(cat "$turn/at" 2>/dev/null)"; now="$(date +%s)"
    case "$at" in ''|*[!0-9]*) at=0 ;; esac ;;
  esac
  [ $((now - at)) -ge "$grace" ] || return 1
  rm -rf "$turn" 2>/dev/null
  if mkdir "$turn" 2>/dev/null; then echo "$now" > "$turn/at"; return 0; fi
  # Not made: either a waiter that does not take the lock made it in the instant after the removal (a
  # fresh turn, not ours: keep waiting), or the stale turn is still there (-L: a dangling symlink) and
  # cannot be cleared.
  sleep 0.1 2>/dev/null; at="$(cat "$turn/at" 2>/dev/null)"; now="$(date +%s)"
  case "$at" in ''|*[!0-9]*) ;; *) [ $((now - at)) -ge "$grace" ] || return 1 ;; esac
  return 2
}
# The lock is flock on a file beside the turn when flock is installed, else a directory made with
# mkdir. Either is held for a few milliseconds; the wait for it is bounded (5 s; 20 tries of 0.1 s),
# so the hook never spins. A directory lock still there after 2 s was left by a hook that died: it is
# broken. A flock that cannot be used (no lock file, flock failed or timed out) falls back to mkdir.
stale_take() {
  local rc i=0 ld="$turn.lockd"
  if command -v flock >/dev/null 2>&1 && ( : >> "$turn.lock" ) 2>/dev/null; then
    ( flock -x -w 5 9 || exit 3; stale_take_locked; exit $? ) 9>> "$turn.lock" 2>/dev/null
    rc=$?; [ "$rc" -eq 3 ] || return "$rc"
  fi
  while ! mkdir "$ld" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 20 ]; then
      rm -rf "$ld" 2>/dev/null; mkdir "$ld" 2>/dev/null && break
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  stale_take_locked; rc=$?
  rm -rf "$ld" 2>/dev/null
  return "$rc"
}

start="$(date +%s)"; running=""; tdir="$(dirname "$turn")"
while :; do
  running="$(running_line)"
  now="$(date +%s)"
  if [ -z "$running" ]; then
    if mkdir "$turn" 2>/dev/null; then echo "$now" > "$turn/at"; exit 0; fi
    [ -d "$tdir" ] && [ -w "$tdir" ] || exit 0
    at="$(cat "$turn/at" 2>/dev/null)"; case "$at" in ''|*[!0-9]*) at=0 ;; esac
    if [ $((now - at)) -ge "$grace" ]; then
      stale_take; case $? in 0|2) exit 0 ;; esac
    fi
  fi
  [ $((now - start)) -ge "$limit" ] && break
  sleep 1
done
what="$(printf '%s' "${running:-$(msg run_starting)}" | tr -d '\n\r' | cut -c1-120)"
printf '%s\n' "$(msg one_suite_wait "$limit" "$what")" >&2
exit 2
