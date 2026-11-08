#!/usr/bin/env bash
# hooks/one-suite.sh: a test run waits while another one is running, is let through when it
# ends, and is refused only when the wait runs out. Inert outside <Core>/<project>/.
# Env knobs (ONE_SUITE_PROCS/WAIT/GRACE/TURN) keep this fast and independent of what runs on the
# machine: ONE_SUITE_PROCS points at a fake process with a name no real process has.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/one-suite.sh"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR

mkdir -p "$CORE_DIR/app/code" "$SANDBOX/elsewhere"; : > "$CORE_DIR/app/CLAUDE.md"
C="$CORE_DIR/app/code"

FAKE="onesuite-fake-run-$$"
export ONE_SUITE_PROCS="$FAKE"
# no waiting unless a test asks for it; a turn of this run's own that the next call may take at once
export ONE_SUITE_WAIT=0 ONE_SUITE_GRACE=0 ONE_SUITE_TURN="$SANDBOX/turn"
dummy=""; FAKES=""
PTMP="$(cd -P /tmp && pwd)"; NOTOWNED="$PTMP/onesuite-turn-$$"   # see "a state folder not owned by this user"
trap '[ -z "$dummy" ] || kill "$dummy" 2>/dev/null; [ -z "$FAKES" ] || kill $FAKES 2>/dev/null; rm -rf "$NOTOWNED"' EXIT
# fake <cwd> <argv0> — starts a fake test run (a renamed sleep) whose working folder is <cwd>; its pid in FAKE_PID.
# The hook holds a call only for a run whose working folder is in the same place as the call.
fake() {
  bash -c 'cd "$1" && exec -a "$2" sleep 120' _ "$1" "$2" >/dev/null 2>&1 & FAKE_PID=$!
  disown "$FAKE_PID" 2>/dev/null; FAKES="$FAKES $FAKE_PID"
}
# stop <pid>... — kills fake runs and waits (up to 2 s) until they are gone
stop() {
  local p i
  kill "$@" 2>/dev/null
  for p in "$@"; do i=0; while kill -0 "$p" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done; done
}

# payload <json-escaped command> [cwd] [description]
payload() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"%s"}}' "${2-$C}" "$1" "${3:-run}"; }
# run_hook <json-escaped command> [cwd] [description] — stdout in OUT, stderr in ERR, exit code in RC
run_hook() { payload "$@" | bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?; OUT="$(cat "$SANDBOX/out")"; ERR="$(cat "$SANDBOX/err")"; }
# expect <rc> <label> <json-escaped command> [cwd] [description]
expect() { local want="$1" label="$2"; shift 2; run_hook "$@"; assert_eq "$RC" "$want" "$label"; assert_eq "$OUT" "" "$label: stdout"; }

# --- nothing running: every command passes
expect 0 "no run in progress" 'swift test --filter Foo'

# --- a run is on (in this project's code folder)
fake "$C" "$FAKE"; dummy=$FAKE_PID
sleep 1
for c in 'swift test --filter Foo' 'cd /x && swift test' '(cd /x; swift test)' 'FOO=1 swift test' 'time swift test' \
         'xcodebuild -scheme App test' 'xcodebuild test -scheme App' 'xcodebuild -scheme App -destination x test | xcpretty' 'xcodebuild test-without-building -scheme App' \
         'xcodebuild -scheme App -destination x test-without-building' \
         'npm test' 'npm run test' 'npm run test:unit' 'npx test' 'npx vitest' 'npx --yes vitest run' 'vitest run' './node_modules/.bin/vitest run' \
         './gradlew test' './gradlew :app:testDebugUnitTest' '/x/gradlew --info test' './gradlew connectedAndroidTest' \
         './gradlew :app:test --tests Foo' './gradlew build test' './gradlew test -x lint' \
         'pytest' 'pytest -x tests/' 'python -m pytest' 'python3 -m pytest tests/' '.venv/bin/pytest' 'uv run pytest' \
         'cargo test' 'cargo test --release' 'cargo +nightly test' \
         'flutter test' 'go test ./...' 'go test -run Foo ./pkg' \
         'bash Scripts/test.sh --scratch-path /tmp/x --filter A' './run-tests.sh' 'sh tests.sh' 'bash -e ./test.sh' \
         'cd /x\nbash Scripts/test.sh --filter A' 'cd /x\nswift test' 'git status\r\npytest' \
         'echo \"it'"'"'s\" && swift test'; do
  expect 2 "refused while a run is on: $c" "$c"
done
assert_contains "$SANDBOX/err" "still in progress"
assert_contains "$SANDBOX/err" "run the same command again"

# --- not a run: a runner named in data, a read of a script, near misses
for c in 'git status' 'ls' 'cat Scripts/test.sh' 'cat tests.sh' 'vim test.sh' \
         "git commit -m 'run swift test later'" 'git commit -m \"fix pytest and cargo test\"' 'echo \"npm test\"' \
         'echo '"'"'go test ./...'"'"'' 'python -c \"print(1)\" # not pytest' \
         'git commit -m \"first line\nswift test\nthird\"' \
         'cat > notes.txt <<'"'"'EOF'"'"'\nswift test\nnpm test\nEOF' 'cat <<EOF\npytest\nEOF' \
         'pip install pytest' 'which pytest' 'grep -rn pytest .' 'ls cargo test-data' \
         'go build ./...' 'go run test.go' 'cargo build' 'cargo check' 'flutter run' 'flutter pub get' \
         'npm install' 'npm run build' 'npm testimonial' 'swift build' 'swift testing' 'xcodebuild -scheme App build' \
         './gradlew assembleDebug' 'vitest' 'python app.py' \
         'xcodebuild build-for-testing -scheme App' './gradlew build -x test' './gradlew build --exclude-task test' \
         './gradlew build --exclude-task=test' './gradlew assembleDebug -x testDebugUnitTest' './gradlew compileTestKotlin' \
         './gradlew compileDebugUnitTestKotlin' './gradlew --latest'; do
  expect 0 "not a run: $c" "$c"
done
expect 0 "a description that names a test does not count" 'ls' "$C" 'see whether swift test is running'
run_hook 'swift test' "$C" 'ls'; assert_eq "$RC" "2" "the command is read, not the description"

# --- inert outside <Core>/<project>/: exit 0 at once, even while a run is active
expect 0 "cwd outside Core" 'swift test' "$SANDBOX/elsewhere"
expect 0 "cwd outside Core: script" 'bash Scripts/test.sh' "$SANDBOX/elsewhere"
expect 0 "cwd is the Core root" 'swift test' "$CORE_DIR"
expect 0 "cwd is Core standards/" 'swift test' "$CORE_DIR/standards"
expect 0 "cwd does not exist" 'swift test' "$SANDBOX/no/such/dir"
expect 2 "cwd is the project folder" 'swift test' "$CORE_DIR/app"
expect 2 "cwd inside the project" 'swift test' "$C"
mkdir -p "$CORE_DIR/foo" "$(dirname "$CORE_DIR")/Foo/src" "$(dirname "$CORE_DIR")/Brain"; : > "$CORE_DIR/foo/CLAUDE.md"
F="$(dirname "$CORE_DIR")/Foo"
expect 0 "new layout: a run in another project does not hold Projects/Foo" 'swift test' "$F/src"
fake "$F" "$FAKE"; foo=$FAKE_PID; sleep 1
expect 2 "new layout: a run in Projects/Foo holds a call in Projects/Foo/src" 'swift test' "$F/src"
expect 0 "new layout: Projects/Brain is not a project" 'swift test' "$(dirname "$CORE_DIR")/Brain"
expect 2 "a run in Foo does not hide the run in app (every match is looked at)" 'swift test' "$C"
stop "$foo"
# lsof prints a non-ASCII byte of a working folder as \xNN; the name must still match
U="$CORE_DIR/uni проект q %s/code"; mkdir -p "$U/src"; : > "$CORE_DIR/uni проект q %s/CLAUDE.md"
fake "$U" "$FAKE"; uni=$FAKE_PID; sleep 1
expect 2 "a run in a folder with a non-ASCII name holds a call there" 'swift test' "$U/src"
stop "$uni"

# --- only a run in the same place holds a call: the project's main code folder and its folder in the Core are one
# place, each linked worktree is a place of its own; a run elsewhere on the machine (another repo, another project,
# another worktree) never holds it, and neither does a run whose working folder cannot be read
OTHER="onesuite-other-run-$$"
mkdir -p "$C/sub/deep"
ONE_SUITE_PROCS="$OTHER" expect 0 "nothing of this pattern runs" 'swift test'
fake "$SANDBOX/elsewhere" "$OTHER"; o1=$FAKE_PID
fake "$CORE_DIR/foo" "$OTHER"; o2=$FAKE_PID
fake "$F/src" "$OTHER"; o3=$FAKE_PID
sleep 1
ONE_SUITE_PROCS="$OTHER" expect 0 "a run in a folder outside every project does not hold" 'swift test'
ONE_SUITE_PROCS="$OTHER" expect 0 "a run in another project does not hold" 'swift test' "$CORE_DIR/app"
stop "$o1" "$o2" "$o3"
fake "$C/sub/deep" "$OTHER"; o1=$FAKE_PID; sleep 1
ONE_SUITE_PROCS="$OTHER" expect 2 "a run deep in this project's code folder holds" 'swift test'
case "$ERR" in *"$o1 "*) pass ;; *) fail "the refusal names the run in this project ($o1): $ERR" ;; esac
ONE_SUITE_PROCS="$OTHER" expect 2 "a run in the code folder holds a call in the project's Core folder" 'swift test' "$CORE_DIR/app"
# the working folder cannot be read (another user's process, no lsof): no hold
mkdir -p "$SANDBOX/nocwd"
printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/nocwd/lsof"; printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/nocwd/readlink"
chmod +x "$SANDBOX/nocwd/lsof" "$SANDBOX/nocwd/readlink"
PATH="$SANDBOX/nocwd:$PATH" ONE_SUITE_PROCS="$OTHER" expect 0 "a run whose working folder cannot be read does not hold" 'swift test'
stop "$o1"
# linked worktrees: each is its own place
git -C "$C" init -q && git -C "$C" commit -q --allow-empty -m init
W="$C/wt/w1"; mkdir -p "$C/wt"; git -C "$C" worktree add -q "$W" -b w1 2>/dev/null
assert_file "$W/.git"
fake "$W" "$OTHER"; o1=$FAKE_PID; sleep 1
ONE_SUITE_PROCS="$OTHER" expect 0 "a run in a linked worktree does not hold the main checkout" 'swift test'
ONE_SUITE_PROCS="$OTHER" expect 2 "a run in a linked worktree holds a call in the same worktree" 'swift test' "$W"
stop "$o1"
fake "$C/sub" "$OTHER"; o1=$FAKE_PID; sleep 1
ONE_SUITE_PROCS="$OTHER" expect 0 "a run in the main checkout does not hold a linked worktree" 'swift test' "$W"
stop "$o1"
rm -rf "$ONE_SUITE_TURN"
OUT="$(printf '{"tool_input":{"command":"swift test"}}' | bash "$H" 2>&1)"; assert_eq "$?" "0" "no cwd: exit"; assert_eq "$OUT" "" "no cwd: silent"
OUT="$(printf '{"cwd":"","tool_input":{"command":"swift test"}}' | bash "$H" 2>&1)"; assert_eq "$?" "0" "empty cwd: exit"
# inside the Core, but pgrep is not on PATH: let the call through
mkdir -p "$SANDBOX/nopgrep"
for t in cat sed tr grep date sleep mkdir head dirname basename awk rm; do ln -sf "$(command -v $t)" "$SANDBOX/nopgrep/$t"; done
OUT="$(payload 'swift test' | PATH="$SANDBOX/nopgrep" "$(command -v bash)" "$H" 2>&1)"
assert_eq "$?" "0" "no pgrep: let through"; assert_eq "$OUT" "" "no pgrep: silent"

# --- input the hook cannot judge passes
for in in '' 'not json at all' '{}' '{"cwd":"'"$C"'"}' '{"cwd":"'"$C"'","tool_input":{}}' \
          '{"cwd":"'"$C"'","tool_input":{"command":"swift test' '{"cwd":"'"$C"'","tool_input":{"command":42}}' \
          '{"cwd":"'"$C"'","tool_input":{"command":""}}' '{"cwd":"'"$C"'","tool_input":{"command":"swift test\' '{"cwd":"unterminated'; do
  OUT="$(printf '%s' "$in" | bash "$H" 2>&1)"; assert_eq "$?" "0" "unjudgeable input passes: $in"; assert_eq "$OUT" "" "unjudgeable input is silent"
done
OUT="$(bash "$H" </dev/null 2>&1)"; assert_eq "$?" "0" "closed stdin"

# --- the refusal says why and names the way out
msg="$(payload 'swift test' | bash "$H" 2>&1 >/dev/null)"
case "$msg" in *"still in progress"*"run the same command again"*) pass ;; *) fail "refusal message: $msg" ;; esac
case "$msg" in *"after 0 s"*) pass ;; *) fail "refusal names the wait: $msg" ;; esac
case "$msg" in *"$FAKE"*) pass ;; *) fail "refusal names the running command: $msg" ;; esac
case "$msg" in *"$dummy "*) pass ;; *) fail "refusal names the pid $dummy: $msg" ;; esac
case "$msg" in *"watcher you started, stop it"*) pass ;; *) fail "refusal mentions watchers: $msg" ;; esac
assert_eq "$(printf '%s\n' "$msg" | wc -l | tr -d ' ')" "1" "refusal is one line"
case "$msg" in *"do not poll"*) fail "refusal still says do not poll: $msg" ;; *) pass ;; esac

# --- gradle: a task word that follows -x / --exclude-task is not a test run, in the process list either
# (the pattern below names a marker no real process has; the exclusion is the hook's own filter)
GP="onesuite-gradle-$$"
export ONE_SUITE_PROCS="$GP/gradlew( .*)? ([^ ]*:)?(test[A-Za-z0-9]*|[a-z][A-Za-z0-9]*Test)( |$)"
fake "$C" "$GP/gradlew build -x test"; g1=$FAKE_PID
fake "$C" "$GP/gradlew build --exclude-task=test"; g2=$FAKE_PID
sleep 1
kill "$dummy" 2>/dev/null   # the other fake run is not part of this check
sleep 1
rm -rf "$ONE_SUITE_TURN"
expect 0 "a running 'gradlew build -x test' is not a test run" 'swift test'
fake "$C" "$GP/gradlew build test"; g3=$FAKE_PID
sleep 1
rm -rf "$ONE_SUITE_TURN"
expect 2 "a running 'gradlew build test' is a test run" 'swift test'
kill "$g1" "$g2" "$g3" 2>/dev/null
export ONE_SUITE_PROCS="$FAKE"
fake "$C" "$FAKE"; dummy=$FAKE_PID
sleep 1
rm -rf "$ONE_SUITE_TURN"

# --- the turn must never make the hook spin: it either waits (sleeping) or lets the call through
# timed_hook <json-escaped command> — RC, OUT and ERR as run_hook; T = seconds it took; a hook that
# spins is killed after 10 s (RC 143)
timed_hook() {
  payload "$@" > "$SANDBOX/in"
  local t0=$SECONDS
  bash "$H" < "$SANDBOX/in" >"$SANDBOX/out" 2>"$SANDBOX/err" & local hp=$!
  ( sleep 10; kill "$hp" 2>/dev/null ) >/dev/null 2>&1 & local wd=$!; disown "$wd" 2>/dev/null
  wait "$hp"; RC=$?; kill "$wd" 2>/dev/null
  T=$((SECONDS - t0)); OUT="$(cat "$SANDBOX/out")"; ERR="$(cat "$SANDBOX/err")"
}
export ONE_SUITE_WAIT=2 ONE_SUITE_GRACE=0
ONE_SUITE_TURN="$SANDBOX/missing-dir/turn" timed_hook 'swift test'
assert_eq "$RC" "2" "run active, turn dir cannot exist: normal refusal"
[ "$T" -ge 1 ] && [ "$T" -lt 9 ] && pass || fail "run active, turn dir cannot exist: took ${T} s (want 1..8)"


# --- the wait: a run that ends inside the limit lets the waiter through, and not before it ends
( sleep 3; kill "$dummy" 2>/dev/null ) &
t0=$(date +%s); ONE_SUITE_WAIT=20 run_hook 'swift test'; t=$(( $(date +%s) - t0 ))
assert_eq "$RC" "0" "a waiter is let through when the run ends"
[ "$t" -ge 2 ] && [ "$t" -lt 15 ] && pass || fail "waiter waited ${t} s (want 2..14)"
sleep 1; dummy=""

# --- no run, and the turn cannot be claimed or cleared: fail open at once, never spin
ONE_SUITE_TURN="$SANDBOX/missing-dir/turn" timed_hook 'swift test'
assert_eq "$RC" "0" "turn parent does not exist: let through"
[ "$T" -lt 5 ] && pass || fail "turn parent does not exist: took ${T} s"
assert_eq "$OUT" "" "turn parent does not exist: silent"
mkdir -p "$SANDBOX/ro"; chmod 555 "$SANDBOX/ro"
ONE_SUITE_TURN="$SANDBOX/ro/turn" timed_hook 'swift test'
assert_eq "$RC" "0" "turn parent not writable: let through"
[ "$T" -lt 5 ] && pass || fail "turn parent not writable: took ${T} s"
mkdir -p "$SANDBOX/stuck/turn/sub"; echo 0 > "$SANDBOX/stuck/turn/at"; echo x > "$SANDBOX/stuck/turn/sub/f"; chmod 555 "$SANDBOX/stuck/turn/sub"
ONE_SUITE_TURN="$SANDBOX/stuck/turn" timed_hook 'swift test'
assert_eq "$RC" "0" "a stale turn that cannot be removed: let through"
[ "$T" -lt 5 ] && pass || fail "stale turn that cannot be removed: took ${T} s"
chmod -R u+rwx "$SANDBOX/stuck" "$SANDBOX/ro"

# --- where the turn lives: a folder of this user's own, never a shared name in /tmp that another user could make
# first (and fill with a fresh turn that would stall every call). CLAUDE_PLUGIN_DATA/one-suite when that is set,
# else <TMPDIR>/corecrew-one-suite-<uid>, made with mode 700. A folder there that is not this user's own (a symlink,
# someone else's, not writable) cannot be used: the call goes at once.
UID_="$(id -u)"; NONE='onesuite-fake[-]none'
( unset ONE_SUITE_TURN; export CLAUDE_PLUGIN_DATA="$SANDBOX/pd" ONE_SUITE_PROCS="$NONE"; run_hook 'swift test'; exit $RC )
assert_eq "$?" "0" "state in CLAUDE_PLUGIN_DATA: the call goes"
assert_file "$SANDBOX/pd/one-suite/turn/at"
mkdir -p "$SANDBOX/tmpd"
( unset ONE_SUITE_TURN CLAUDE_PLUGIN_DATA; export TMPDIR="$SANDBOX/tmpd/" ONE_SUITE_PROCS="$NONE"; run_hook 'swift test'; exit $RC )
assert_eq "$?" "0" "state in TMPDIR: the call goes"
assert_file "$SANDBOX/tmpd/corecrew-one-suite-$UID_/turn/at"
assert_eq "$(ls -ld "$SANDBOX/tmpd/corecrew-one-suite-$UID_" | cut -c1-10)" "drwx------" "the state folder in TMPDIR is private"
# made in advance as a symlink to a folder that holds a fresh turn: not used, nothing written through it
mkdir -p "$SANDBOX/tmpe" "$SANDBOX/planted/turn"; date +%s > "$SANDBOX/planted/turn/at"
ln -s "$SANDBOX/planted" "$SANDBOX/tmpe/corecrew-one-suite-$UID_"
( unset ONE_SUITE_TURN CLAUDE_PLUGIN_DATA; export TMPDIR="$SANDBOX/tmpe" ONE_SUITE_PROCS="$NONE" ONE_SUITE_GRACE=1000 ONE_SUITE_WAIT=3
  timed_hook 'swift test'; echo "$RC $T" > "$SANDBOX/res" )
read -r rc t < "$SANDBOX/res"
assert_eq "$rc" "0" "a state folder that is a symlink: the call goes"
[ "$t" -lt 2 ] && pass || fail "a state folder that is a symlink: took ${t} s"
assert_no_file "$SANDBOX/planted/turn.lock"
# made in advance and not writable, with a fresh turn in it: the call goes at once
mkdir -p "$SANDBOX/tmpf/corecrew-one-suite-$UID_/turn"; date +%s > "$SANDBOX/tmpf/corecrew-one-suite-$UID_/turn/at"
chmod 555 "$SANDBOX/tmpf/corecrew-one-suite-$UID_"
( unset ONE_SUITE_TURN CLAUDE_PLUGIN_DATA; export TMPDIR="$SANDBOX/tmpf" ONE_SUITE_PROCS="$NONE" ONE_SUITE_GRACE=1000 ONE_SUITE_WAIT=3
  timed_hook 'swift test'; echo "$RC $T" > "$SANDBOX/res" )
read -r rc t < "$SANDBOX/res"
assert_eq "$rc" "0" "a state folder that is not writable: the call goes"
[ "$t" -lt 2 ] && pass || fail "a state folder that is not writable: took ${t} s"
chmod -R u+rwx "$SANDBOX/tmpf"
# a state folder not owned by this user: /tmp itself (root's, writable by all) as the turn's folder. The turn
# is not made there. (Ownership cannot be faked without root; /tmp is a real folder of someone else's.)
if [ "$UID_" != "0" ] && [ ! -O "$PTMP" ] && [ -w "$PTMP" ]; then
  ONE_SUITE_TURN="$NOTOWNED" ONE_SUITE_PROCS="$NONE" timed_hook 'swift test'
  assert_eq "$RC" "0" "a state folder not owned by this user: the call goes"
  assert_no_file "$NOTOWNED"
else
  pass   # running as root, or /tmp is this user's: nothing to check here
fi
export ONE_SUITE_WAIT=0 ONE_SUITE_GRACE=0

# --- the turn: of two waiters that find nothing running, one goes and the other waits out the grace
rm -rf "$ONE_SUITE_TURN"
ONE_SUITE_GRACE=30 expect 0 "the first of two takes the turn" 'swift test'
ONE_SUITE_GRACE=30 expect 2 "the second is held while the turn is fresh" 'swift test'
t0=$(date +%s); ONE_SUITE_GRACE=3 ONE_SUITE_WAIT=20 run_hook 'swift test'; t=$(( $(date +%s) - t0 ))
assert_eq "$RC" "0" "a turn past its grace is taken by the next waiter"
[ "$t" -ge 1 ] && [ "$t" -lt 15 ] && pass || fail "stale turn: waited ${t} s"
expect 0 "after the run ends: allowed" 'swift test'
# the default grace is short: a quick suite re-run at once (fix one line, run again) waits a moment,
# not 10 s. A run that was let through shows among the processes well within it.
rm -rf "$ONE_SUITE_TURN"
( unset ONE_SUITE_GRACE; ONE_SUITE_WAIT=20; export ONE_SUITE_WAIT; run_hook 'swift test'; exit $RC ); assert_eq "$?" "0" "default grace: the first run goes"
t0=$(date +%s); ( unset ONE_SUITE_GRACE; ONE_SUITE_WAIT=20; export ONE_SUITE_WAIT; run_hook 'swift test'; exit $RC ); rc=$?; t=$(( $(date +%s) - t0 ))
assert_eq "$rc" "0" "default grace: a re-run at once goes"
[ "$t" -le 4 ] && pass || fail "default grace: a re-run at once waited ${t} s"
# knobs that are not numbers fall back to the defaults instead of hanging or failing
rm -rf "$ONE_SUITE_TURN"
ONE_SUITE_WAIT=abc ONE_SUITE_GRACE=x expect 0 "bad knob values: still decides" 'swift test'

# --- the takeover of a stale turn: of many waiters that find the same stale turn in the same instant,
# exactly one goes (they used to remove and re-make it one after another, each taking the turn the
# previous one had just made). stress <rounds> <waiters> [path-dir] runs the rounds side by side, each
# with its own turn, every hook held on a fifo until all are started, then released together. An empty
# or missing path-dir keeps the real PATH. RCS = one line per round: the exit codes of its waiters.
# The process pattern never matches anything (the [-] keeps pgrep's own command line out of it), so the
# parallel hooks do not see each other as a running suite and all refuse.
stress() {
  local rounds="$1" n="$2" pathdir="${3-}" r i d pids=""
  rm -rf "$SANDBOX/stress"; mkdir -p "$SANDBOX/stress"; payload 'swift test' > "$SANDBOX/stress/in"
  for r in $(seq 1 "$rounds"); do
    d="$SANDBOX/stress/r$r"; mkdir -p "$d/turn"; echo 1 > "$d/turn/at"   # stale: written in 1970
    for i in $(seq 1 "$n"); do
      mkfifo "$d/f$i"
      ( if [ -n "$pathdir" ]; then PATH="$pathdir"; fi
        ONE_SUITE_PROCS='onesuite-fake[-]none' ONE_SUITE_GRACE=5 ONE_SUITE_WAIT=1 ONE_SUITE_TURN="$d/turn" \
          "$(command -v bash)" "$H" < "$d/f$i" >/dev/null 2>&1; echo $? > "$d/rc$i" ) &
      pids="$pids $!"
    done
  done
  for r in $(seq 1 "$rounds"); do for i in $(seq 1 "$n"); do cat "$SANDBOX/stress/in" > "$SANDBOX/stress/r$r/f$i" & done; done
  wait $pids
  RCS=""
  for r in $(seq 1 "$rounds"); do RCS="$RCS$(cat "$SANDBOX/stress/r$r"/rc* | tr '\n' ' ')
"; done
}
# check_stress <label> — every round let exactly one waiter through (exit 0) and refused the rest (exit 2)
check_stress() {
  local line bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$(printf '%s\n' $line | sort | uniq -c | tr -s ' ' | tr '\n' ',')" in
      " 1 0, 7 2,") ;;
      *) bad=$((bad + 1)); echo "    round: $line" ;;
    esac
  done <<EOF
$RCS
EOF
  [ "$bad" -eq 0 ] && pass || fail "$1: $bad of 8 rounds did not let exactly one of 8 waiters through"
}
stress 8 8
check_stress "stale turn, 8 waiters (real PATH)"
# the same without flock on PATH: the fallback lock. Only the tools the hook uses are linked in.
mkdir -p "$SANDBOX/noflock"
for t in bash cat sed tr grep date sleep mkdir head dirname basename awk rm cut pgrep; do
  p="$(command -v $t 2>/dev/null)"; [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$SANDBOX/noflock/$t"
done
[ ! -e "$SANDBOX/noflock/flock" ] && pass || fail "the no-flock PATH has flock"
stress 8 8 "$SANDBOX/noflock"
check_stress "stale turn, 8 waiters (no flock on PATH)"

# the lock itself: flock is used when it is installed, mkdir otherwise, and a lock that cannot be had
# neither hangs the hook nor lets everything through. stale_run <path-dir> — one waiter, stale turn,
# with PATH=<path-dir>: RC, T (seconds), ERR.
stale_run() {
  rm -rf "$SANDBOX/lk"; mkdir -p "$SANDBOX/lk/turn"; echo 1 > "$SANDBOX/lk/turn/at"
  payload 'swift test' > "$SANDBOX/in"
  local t0=$SECONDS
  PATH="$1" ONE_SUITE_PROCS='onesuite-fake[-]none' ONE_SUITE_GRACE=5 ONE_SUITE_WAIT="${2:-1}" ONE_SUITE_TURN="$SANDBOX/lk/turn" \
    "$(command -v bash)" "$H" < "$SANDBOX/in" >/dev/null 2>"$SANDBOX/err" & local hp=$!
  ( sleep 12; kill "$hp" 2>/dev/null ) >/dev/null 2>&1 & local wd=$!; disown "$wd" 2>/dev/null
  wait "$hp"; RC=$?; kill "$wd" 2>/dev/null; T=$((SECONDS - t0)); ERR="$(cat "$SANDBOX/err")"
}
REAL_FLOCK="$(command -v flock 2>/dev/null)"
if [ -n "$REAL_FLOCK" ]; then
  mkdir -p "$SANDBOX/withflock"; cp -P "$SANDBOX/noflock"/* "$SANDBOX/withflock/"
  printf '#!/bin/sh\necho "$@" >> "%s/flock.log"\nexec "%s" "$@"\n' "$SANDBOX" "$REAL_FLOCK" > "$SANDBOX/withflock/flock"; chmod +x "$SANDBOX/withflock/flock"
  rm -f "$SANDBOX/flock.log"; stale_run "$SANDBOX/withflock"
  assert_eq "$RC" "0" "flock installed: the stale turn is taken"
  assert_contains "$SANDBOX/flock.log" "-x"
  assert_no_file "$SANDBOX/lk/turn.lockd"
  # a flock that fails: the mkdir lock takes over
  printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/withflock/flock"
  stale_run "$SANDBOX/withflock"
  assert_eq "$RC" "0" "flock fails: falls back to the mkdir lock and takes the turn"
  assert_no_file "$SANDBOX/lk/turn.lockd"
else
  pass   # no flock on this machine: only the mkdir path can be run here
fi
stale_run "$SANDBOX/noflock"
assert_eq "$RC" "0" "no flock: the stale turn is taken"
assert_no_file "$SANDBOX/lk/turn.lockd"
[ "$(cat "$SANDBOX/lk/turn/at")" -gt 1000000000 ] && pass || fail "no flock: the new turn has no time in it"
# a mkdir lock left by a hook that died is broken after about 2 s
rm -rf "$SANDBOX/lk"; mkdir -p "$SANDBOX/lk/turn" "$SANDBOX/lk/turn.lockd"; echo 1 > "$SANDBOX/lk/turn/at"
payload 'swift test' > "$SANDBOX/in"; t0=$SECONDS
PATH="$SANDBOX/noflock" ONE_SUITE_PROCS='onesuite-fake[-]none' ONE_SUITE_GRACE=5 ONE_SUITE_WAIT=1 ONE_SUITE_TURN="$SANDBOX/lk/turn" \
  "$(command -v bash)" "$H" < "$SANDBOX/in" >/dev/null 2>&1; rc=$?; t=$((SECONDS - t0))
assert_eq "$rc" "0" "a dead hook's mkdir lock is broken and the turn taken"
[ "$t" -ge 1 ] && [ "$t" -le 8 ] && pass || fail "dead lock: took ${t} s (want 1..8)"
assert_no_file "$SANDBOX/lk/turn.lockd"

# --- the default wait is short (a stalled call costs the person minutes), and the hook's entry in hooks.json gives
# it a timeout above that wait and a status line, so the person sees what the call waits for
assert_contains "$H" 'limit="${ONE_SUITE_WAIT:-120}"'
HJ="$HOOKS/hooks.json"
suite_to="$(awk '/one-suite.sh/ { on = 1 } on && /"timeout":/ { print; exit }' "$HJ" | sed -n 's/.*"timeout": *\([0-9]*\).*/\1/p')"
[ -n "$suite_to" ] && [ "$suite_to" -gt 120 ] && [ "$suite_to" -le 180 ] && pass || fail "one-suite timeout in hooks.json: '$suite_to' (want 121..180)"
assert_contains "$HJ" '"statusMessage": "corecrew: checking for a running test suite"'

# --- the default process pattern (checked as text: it never touches real processes)
DEF="$(sed -n "s/^default_procs='\(.*\)'\$/\1/p" "$H")"
[ -n "$DEF" ] && pass || fail "default_procs line not found in the hook"
matches() { printf '%s\n' "$1" | LC_ALL=C grep -qE -- "$DEF"; }
for p in '/usr/bin/swift-test --parallel' 'swift test --filter A' '/Applications/Xcode.app/Contents/Developer/usr/bin/xctest /x/AppTests.xctest' \
         'xcodebuild -scheme App test' 'xcodebuild test -scheme App' 'node /p/node_modules/vitest/dist/workers/forks.js' 'node /p/node_modules/.bin/vitest run' \
         '/p/gradlew test' '/p/gradlew :app:testDebugUnitTest' '/p/gradlew connectedAndroidTest' '/p/gradlew build test' 'java GradleWorkerMain Gradle Test Executor 1' \
         'xcodebuild test-without-building -scheme App' \
         '/x/python -m pytest -x' '/x/.venv/bin/pytest tests' 'pytest' 'cargo test' '/u/.cargo/bin/cargo +nightly test --all' \
         '/bin/bash /f/bin/flutter test' 'dart flutter_tools.snapshot test --no-color' 'go test ./...' '/tmp/go-build123/b001/foo.test -test.v' \
         'bash /x/Scripts/test.sh --filter A' '/bin/bash ./run-tests.sh' '/bin/zsh -e tests.sh'; do
  matches "$p" && pass || fail "default pattern misses: $p"
done
for p in "bash $H" "bash $HOOKS/../tests/test_hook_one_suite.sh" 'bash tests/run.sh' 'vim pytest.ini' 'grep -rn pytest .' 'pip install pytest' 'less tests.sh' 'cat test.sh' \
         'vim /x/Scripts/test.sh' 'swift build' 'swift-build' 'xcodebuild -scheme App build' 'xcodebuild -list' '/p/gradlew assembleDebug' '/p/gradlew compileTestKotlin' '/p/gradlew --latest' 'gradle --daemon' 'xcodebuild build-for-testing -scheme App' \
         'cargo build' 'cargo check --tests-not' 'go build ./...' 'go run main.go' 'gopls' 'flutter run' 'flutter_tools.snapshot run' \
         'node server.js' 'python app.py' 'npm run dev' '/usr/bin/sleep 60' 'claude' 'vitest-helper'; do
  matches "$p" && fail "default pattern matches a non-test process: $p" || pass
done

# --- Codex payloads (fixtures built from the rust-v0.166.0 structs): tool_input.command is a string, cwd the
# command's workdir, and an exit 2 carries a non-empty stderr (Codex ignores exit 2 with an empty one)
FX="$ROOT/tests/fixtures/codex"
cfx() { sed "s|@CWD@|$C|g" "$FX/$1.json" | bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?; OUT="$(cat "$SANDBOX/out")"; ERR="$(cat "$SANDBOX/err")"; }
kill "$dummy" 2>/dev/null; dummy=""; sleep 1
cfx pre-bash; assert_eq "$RC" "0" "codex: no run in progress passes"
cfx pre-bash-subagent; assert_eq "$RC" "0" "codex: a subagent's call passes"
fake "$C" "$FAKE"; dummy=$FAKE_PID
sleep 1
cfx pre-bash; assert_eq "$RC" "2" "codex: a test run while another one is on is refused"
assert_eq "$OUT" "" "codex: stdout"
[ -n "$ERR" ] && pass || fail "codex: exit 2 with an empty stderr"
cfx pre-bash-applypatch-heredoc; assert_eq "$RC" "0" "codex: a patch through Bash is not a test run"

finish
