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
dummy=""
trap '[ -z "$dummy" ] || kill "$dummy" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

# payload <json-escaped command> [cwd] [description]
payload() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"%s"}}' "${2-$C}" "$1" "${3:-run}"; }
# run_hook <json-escaped command> [cwd] [description] — stdout in OUT, stderr in ERR, exit code in RC
run_hook() { payload "$@" | bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?; OUT="$(cat "$SANDBOX/out")"; ERR="$(cat "$SANDBOX/err")"; }
# expect <rc> <label> <json-escaped command> [cwd] [description]
expect() { local want="$1" label="$2"; shift 2; run_hook "$@"; assert_eq "$RC" "$want" "$label"; assert_eq "$OUT" "" "$label: stdout"; }

# --- nothing running: every command passes
expect 0 "no run in progress" 'swift test --filter Foo'

# --- a run is on
bash -c "exec -a $FAKE sleep 120" & dummy=$!; disown "$dummy" 2>/dev/null
sleep 1
for c in 'swift test --filter Foo' 'cd /x && swift test' '(cd /x; swift test)' 'FOO=1 swift test' 'time swift test' \
         'xcodebuild -scheme App test' 'xcodebuild test -scheme App' 'xcodebuild -scheme App -destination x test | xcpretty' \
         'npm test' 'npm run test' 'npm run test:unit' 'npx test' 'npx vitest' 'npx --yes vitest run' 'vitest run' './node_modules/.bin/vitest run' \
         './gradlew test' './gradlew :app:testDebugUnitTest' '/x/gradlew --info test' \
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
         './gradlew assembleDebug' 'vitest' 'python app.py'; do
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
OUT="$(printf '{"tool_input":{"command":"swift test"}}' | bash "$H" 2>&1)"; assert_eq "$?" "0" "no cwd: exit"; assert_eq "$OUT" "" "no cwd: silent"
OUT="$(printf '{"cwd":"","tool_input":{"command":"swift test"}}' | bash "$H" 2>&1)"; assert_eq "$?" "0" "empty cwd: exit"
# the hook leaves before looking for processes: no pgrep needed outside Core
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

# --- the wait: a run that ends inside the limit lets the waiter through, and not before it ends
( sleep 3; kill "$dummy" 2>/dev/null ) &
t0=$(date +%s); ONE_SUITE_WAIT=20 run_hook 'swift test'; t=$(( $(date +%s) - t0 ))
assert_eq "$RC" "0" "a waiter is let through when the run ends"
[ "$t" -ge 2 ] && [ "$t" -lt 15 ] && pass || fail "waiter waited ${t} s (want 2..14)"
sleep 1; dummy=""

# --- the turn: of two waiters that find nothing running, one goes and the other waits out the grace
rm -rf "$ONE_SUITE_TURN"
ONE_SUITE_GRACE=30 expect 0 "the first of two takes the turn" 'swift test'
ONE_SUITE_GRACE=30 expect 2 "the second is held while the turn is fresh" 'swift test'
t0=$(date +%s); ONE_SUITE_GRACE=3 ONE_SUITE_WAIT=20 run_hook 'swift test'; t=$(( $(date +%s) - t0 ))
assert_eq "$RC" "0" "a turn past its grace is taken by the next waiter"
[ "$t" -ge 1 ] && [ "$t" -lt 15 ] && pass || fail "stale turn: waited ${t} s"
expect 0 "after the run ends: allowed" 'swift test'
# knobs that are not numbers fall back to the defaults instead of hanging or failing
rm -rf "$ONE_SUITE_TURN"
ONE_SUITE_WAIT=abc ONE_SUITE_GRACE=x expect 0 "bad knob values: still decides" 'swift test'

# --- the default process pattern (checked as text: it never touches real processes)
DEF="$(sed -n "s/^default_procs='\(.*\)'\$/\1/p" "$H")"
[ -n "$DEF" ] && pass || fail "default_procs line not found in the hook"
matches() { printf '%s\n' "$1" | LC_ALL=C grep -qE -- "$DEF"; }
for p in '/usr/bin/swift-test --parallel' 'swift test --filter A' '/Applications/Xcode.app/Contents/Developer/usr/bin/xctest /x/AppTests.xctest' \
         'xcodebuild -scheme App test' 'xcodebuild test -scheme App' 'node /p/node_modules/vitest/dist/workers/forks.js' 'node /p/node_modules/.bin/vitest run' \
         '/p/gradlew test' '/p/gradlew :app:testDebugUnitTest' 'java GradleWorkerMain Gradle Test Executor 1' \
         '/x/python -m pytest -x' '/x/.venv/bin/pytest tests' 'pytest' 'cargo test' '/u/.cargo/bin/cargo +nightly test --all' \
         '/bin/bash /f/bin/flutter test' 'dart flutter_tools.snapshot test --no-color' 'go test ./...' '/tmp/go-build123/b001/foo.test -test.v' \
         'bash /x/Scripts/test.sh --filter A' '/bin/bash ./run-tests.sh' '/bin/zsh -e tests.sh'; do
  matches "$p" && pass || fail "default pattern misses: $p"
done
for p in "bash $H" "bash $HOOKS/../tests/test_hook_one_suite.sh" 'bash tests/run.sh' 'vim pytest.ini' 'grep -rn pytest .' 'pip install pytest' 'less tests.sh' 'cat test.sh' \
         'vim /x/Scripts/test.sh' 'swift build' 'swift-build' 'xcodebuild -scheme App build' 'xcodebuild -list' '/p/gradlew assembleDebug' 'gradle --daemon' \
         'cargo build' 'cargo check --tests-not' 'go build ./...' 'go run main.go' 'gopls' 'flutter run' 'flutter_tools.snapshot run' \
         'node server.js' 'python app.py' 'npm run dev' '/usr/bin/sleep 60' 'claude' 'vitest-helper'; do
  matches "$p" && fail "default pattern matches a non-test process: $p" || pass
done

finish
