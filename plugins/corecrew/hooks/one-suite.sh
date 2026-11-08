#!/usr/bin/env bash
# Claude Code PreToolUse hook on Bash: holds a test run while another one is running in the same
# place, and lets it through when that one ends. Two suites at once in one checkout fail each other —
# they share build folders, settings and scratch paths — and a note in a project's knowledge saying so
# does not stop anyone from doing it. The same place: the project's main code folder and its folder in
# the Core count as one; each linked git worktree is a place of its own. A test run anywhere else on
# the machine (another repo, another project, another worktree) never holds the call, and neither
# does one whose working folder cannot be read. The hook waits here rather than refusing: a refused agent has
# nothing to wait with, so it asks again or looks at `ps` once per step, and every step re-reads its
# whole context. Only a wait longer than ONE_SUITE_WAIT seconds is refused (exit 2; stderr goes back
# to the caller: "run the same command again").
# Inert outside a project (<Core>/<project>/ or
# its code folder beside the Core): with no cwd, or a cwd that is not inside a project, it exits 0 at
# once, before it looks at the command or at any process.
# Only the command is read, never the description: "see whether swift test runs" is not a test run.
# Anything this hook cannot judge passes (exit 0): a stuck guard would stop every Bash call, which is
# worse than one clash. It never prints to stdout. No jq, no python. Without pgrep or ps it lets
# everything through. Processes are found with `pgrep -f` (pids only) and their command lines read
# with `ps -ww -p <pid> -o args=`, which print the same on macOS (BSD) and Linux (procps-ng); `pgrep -l`
# does not (procps prints only the process name with it). -ww: with no terminal procps cuts the line
# to 80 columns without it, so a long test command line would not be recognised.
#
# Env knobs, for tests: ONE_SUITE_PROCS (the process pattern, replaces the default), ONE_SUITE_WAIT
# (seconds to wait; default 120), ONE_SUITE_GRACE (seconds a turn stays fresh; default 3),
# ONE_SUITE_TURN (the turn directory; by default one per place, in a folder of this user's own, see below).
# Known limits: the grace of 3 s is short against a permission prompt the person answers slowly, after
# which a second run may start; and a mkdir lock left by a hook that was killed while holding it is
# broken by the next waiter only after 2 s. The takeover of a stale turn runs under a short lock
# (flock, else mkdir; see stale_take), so waiters that find the same stale turn together no longer go
# together (tried before: one atomic rename; it only narrowed the window, since a fresh turn taken by
# mistake had to be put back).
# The default wait of 120 s must stay under this hook's `timeout` in hooks/hooks.json (150: room for
# the last check and a takeover lock) and well under the stream watchdog, which stops an agent that is
# silent for 600 s.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting

# Inert outside a project.
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0
load_settings
name="$(project_of "$cwd" 2>/dev/null)" || exit 0
[ -n "$name" ] || exit 0

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
command -v pgrep >/dev/null 2>&1 && command -v ps >/dev/null 2>&1 || exit 0

# ONE_SUITE_PROCS replaces the process pattern (ERE, matched against whole command lines by
# `pgrep -f`), so this hook's own tests do not depend on what happens to be running on the machine.
# Every alternative is anchored on a command word, so an editor or `grep` with the name of a runner
# as an argument does not count; the hook's own command line matches nothing here.
default_procs='(^|/)swift[- ]test( |$)|(^|/)xctest( |$)|(^|/)xcodebuild( .*)? test(-without-building)?( |$)|node_modules/(\.bin/vitest|vitest/dist/)|(^|/)vitest run( |$)|(^|/)gradlew( .*)? ([^ ]*:)?(test[A-Za-z0-9]*|[a-z][A-Za-z0-9]*Test)( |$)|Gradle Test Executor|(^|/)pytest( |$)|(^|/)py\.test( |$)|-m pytest( |$)|(^|/)cargo( \+[^ ]+)? test( |$)|(^|/)flutter test( |$)|flutter_tools\.snapshot test( |$)|(^|/)go test( |$)|/go-build[0-9]+/.*\.test( |$)|(^|/)(ba|z)?sh( -[a-z]+)* [^ ]*tests?\.sh( |$)'
procs="${ONE_SUITE_PROCS:-$default_procs}"

# The place of this call: its linked worktree (here_wt), else the project's main code folder (code) and its
# folder in the Core (pdir), which count as one place.
here_wt=""; worktree_of "$cwd" && here_wt="$WT_ROOT"
code="$(code_dir_of "$name" 2>/dev/null)" && code="$(canon_dir "$code")" || code=""
pdir="$CORE_DIR/$name"

# The turn: a directory only one waiter can make. A run that was let through takes a moment to
# appear among the processes, and without the turn every waiter would see "nothing running" in that
# moment and start together. A turn older than its grace belongs to a run that has started or never
# will, and the next waiter takes it. The grace is short (3 s): a run shows among the processes
# within a second of being let through, and a quick suite re-run at once should not wait long.
# If the turn can be neither made nor cleared (its folder is missing, read-only or not this user's
# own, a stale turn cannot be removed) waiting cannot help: the call is let
# through. Every other path through the loop below reaches the limit check and the sleep.
# The turn lives in a folder of this user's own: the plugin's data folder (CLAUDE_PLUGIN_DATA) when the
# host gives one, else <TMPDIR>/corecrew-one-suite-<uid>, made with mode 700. A shared name in /tmp could
# be made first by another user, who could then keep a fresh turn in it and stall every call. A folder
# that is not this user's own (a symlink, someone else's, not writable) is not used: the call goes.
# There is one turn per place, turn-<key> (key: the cksum of the worktree root, else of the code folder, else
# of the project's Core folder), so a run let through in another project or worktree a moment ago never holds
# this call. ONE_SUITE_TURN, when set, is the turn itself, whatever the place.
if [ -n "${ONE_SUITE_TURN:-}" ]; then
  turn="$ONE_SUITE_TURN"
else
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    sdir="${CLAUDE_PLUGIN_DATA%/}/one-suite"
    [ -d "$CLAUDE_PLUGIN_DATA" ] || mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null
  else
    sdir="${TMPDIR:-/tmp}"; sdir="${sdir%/}/corecrew-one-suite-$(id -u 2>/dev/null || echo unknown)"
  fi
  [ -e "$sdir" ] || [ -L "$sdir" ] || mkdir -m 700 "$sdir" 2>/dev/null
  key="$(printf '%s' "${here_wt:-${code:-$pdir}}" | cksum 2>/dev/null)"; key="${key%%[!0-9]*}"
  turn="$sdir/turn-${key:-0}"
fi
grace="${ONE_SUITE_GRACE:-3}"; limit="${ONE_SUITE_WAIT:-120}"
case "$grace" in ''|*[!0-9]*) grace=3 ;; esac
case "$limit" in ''|*[!0-9]*) limit=120 ;; esac

# turn_usable — exit 0 when the turn's folder is this user's own (a real folder, not a symlink, owned by
# this user, writable) and the turn in it, if there is one, is this user's own too.
turn_usable() {
  [ -d "$tdir" ] && [ ! -L "$tdir" ] && [ -O "$tdir" ] && [ -w "$tdir" ] || return 1
  if [ -e "$turn" ] || [ -L "$turn" ]; then [ ! -L "$turn" ] && [ -O "$turn" ] || return 1; fi
  return 0
}

# same_place <dir> — exit 0 when <dir> (a process's working folder) is in the place of this call.
same_place() {
  local d; d="$(canon_dir "$1")"
  if worktree_of "$d"; then [ -n "$here_wt" ] && [ "$WT_ROOT" = "$here_wt" ]; return; fi
  [ -z "$here_wt" ] || return 1
  case "$d/" in "$pdir"/*) return 0 ;; esac
  [ -n "$code" ] || return 1
  case "$d/" in "$code"/*) return 0 ;; esac
  return 1
}

# proc_cwd <pid> — the working folder of a process: /proc/<pid>/cwd on Linux, lsof elsewhere (macOS). Prints
# nothing when it cannot be read (another user's process, no lsof, the process is gone). Such a process
# does not hold the call: this hook is a convenience, not a security boundary, so it fails open.
proc_cwd() {
  local d=""
  [ -d /proc/self ] && d="$(readlink "/proc/$1/cwd" 2>/dev/null)"
  if [ -z "$d" ] && command -v lsof >/dev/null 2>&1; then
    d="$(lsof -a -p "$1" -d cwd -Fn -w 2>/dev/null | sed -n 's/^n//p' | head -1)"
    # lsof writes a non-ASCII byte as \xNN and a backslash as \\; printf %b turns them back into bytes
    case "$d" in *\\*) d="$(printf '%b' "$d")" ;; esac
  fi
  printf '%s' "$d"
}

# running_line — the first other process (pid and command line) that matches $procs and works in the
# place of this call. A gradlew run whose test task follows -x / --exclude-task is dropped: a regular
# expression cannot say "not after -x". The pids come from `pgrep -f`, each command line from `ps -ww -o args=`
# (not `pgrep -l`: on Linux it prints only the process name). A process gone before ps reads it is skipped.
running_line() {
  local args rest pid d
  pgrep -f "$procs" 2>/dev/null | while IFS= read -r pid; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$pid" = "$$" ] && continue
    args="$(ps -ww -p "$pid" -o args= 2>/dev/null | head -1)"
    args="${args#"${args%%[![:space:]]*}"}"
    [ -n "$args" ] || continue
    rest="$args"
    case "$rest" in
      *gradlew*)
        rest="$(printf '%s' "$rest" | LC_ALL=C sed -E 's/[[:space:]](-x|--exclude-task)([[:space:]]+|=)[^[:space:]]+//g')"
        printf '%s' "$rest" | LC_ALL=C grep -qE -- "$procs" || continue ;;
    esac
    d="$(proc_cwd "$pid")"
    [ -n "$d" ] && same_place "$d" || continue
    printf '%s %s\n' "$pid" "$args"
    break
  done
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
    turn_usable || exit 0
    if mkdir "$turn" 2>/dev/null; then echo "$now" > "$turn/at"; exit 0; fi
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
