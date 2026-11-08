#!/usr/bin/env bash
# The test harness itself. lib.sh: skip, finish, note, assert_not_contains, sandbox removal.
# run.sh: filter, per-file time, quiet passing files, the skip list, -j N, one throwaway root.
# Each case runs fake test files in a copy of lib.sh and run.sh inside the sandbox.
source "$(dirname "$0")/lib.sh"
new_sandbox
T="$SANDBOX/t"; RT="$SANDBOX/rt"; mkdir -p "$T" "$RT"
cp "$ROOT/tests/lib.sh" "$ROOT/tests/run.sh" "$T/"
# fake <name> <body> — a test file in $T that sources lib.sh
fake() { printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/lib.sh"\n%s\n' "$2" > "$T/$1"; }
# one <name> — runs one fake file with TMPDIR=$RT: output in OUT, exit code in RC
one() { OUT="$(cd "$T" && TMPDIR="$RT" bash "$1" 2>&1)"; RC=$?; }
# left — the temp folders a run left in $RT
left() { find "$RT" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '; }
has() { case "$OUT" in *"$1"*) pass ;; *) fail "${2:-output} lacks: $1 :: $OUT" ;; esac; }
lacks() { case "$OUT" in *"$1"*) fail "${2:-output} has: $1 :: $OUT" ;; *) pass ;; esac; }

# --- skip prints one fixed line; skip then finish ends the file (TEST-1: nothing after it runs)
fake x_skip.sh 'pass; skip part-3 "codex not on PATH"; finish; echo AFTER; fail "ran after finish"'
one x_skip.sh; assert_eq "$RC" "0" "skip then finish: exit 0"
has "SKIP x_skip.sh: part-3: codex not on PATH"; lacks AFTER "skip then finish"
# finish exits with the result: 1 on a failure, 0 otherwise
fake x_fail.sh 'fail boom; finish; echo AFTER'
one x_fail.sh; assert_eq "$RC" "1" "finish after a failure exits 1"; lacks AFTER "finish after a failure"
# note prints only with VERBOSE=1 (TEST-14)
fake x_note.sh 'note "hello there"; pass; finish'
one x_note.sh; lacks "hello there" "note without VERBOSE"
OUT="$(cd "$T" && VERBOSE=1 TMPDIR="$RT" bash x_note.sh 2>&1)"; has "note: hello there" "note with VERBOSE=1"

# --- assert_not_contains fails on a missing file (TEST-11), passes on a file without the text
fake x_nc.sh 'printf "abc\n" > "$TEST_TMP/f"; assert_not_contains "$TEST_TMP/f" zzz; finish'
one x_nc.sh; assert_eq "$RC" "0" "assert_not_contains on a file without the text"
fake x_nc3.sh 'assert_not_contains <(printf "abc\n") zzz; finish'
one x_nc3.sh; assert_eq "$RC" "0" "assert_not_contains on a process substitution"
fake x_nc2.sh 'assert_not_contains "$TEST_TMP/missing" zzz; finish'
one x_nc2.sh; assert_eq "$RC" "1" "assert_not_contains on a missing file must fail"

# --- every sandbox is removed on exit (TEST-2): after finish, after a plain exit, when the file sets its own
# EXIT trap, and for a sandbox made in a subshell; KEEP_SANDBOX=1 keeps them
rm -rf "$RT"; mkdir -p "$RT"
fake x_sb1.sh 'new_sandbox; new_sandbox; ( new_sandbox ); pass; finish'
one x_sb1.sh; assert_eq "$RC" "0" "sandboxes: exit 0"; assert_eq "$(left)" "0" "sandboxes left after finish"
fake x_sb2.sh 'new_sandbox; mkdir -p "$SANDBOX/ro/x"; chmod 500 "$SANDBOX/ro"; exit 0'
one x_sb2.sh; assert_eq "$(left)" "0" "sandbox (with a read-only folder) left after a plain exit"
fake x_sb3.sh 'new_sandbox; trap "true" EXIT; pass; finish'
one x_sb3.sh; assert_eq "$(left)" "0" "sandbox left when the file set its own EXIT trap"
OUT="$(cd "$T" && KEEP_SANDBOX=1 TMPDIR="$RT" bash x_sb1.sh 2>&1)"
assert_eq "$(left)" "1" "KEEP_SANDBOX=1 keeps the sandboxes"; has "kept:" "KEEP_SANDBOX=1"
chmod -R u+rwx "$RT"; rm -rf "$RT"; mkdir -p "$RT"

# --- run.sh: a filter, one line with the time per file, quiet passing files, the skip list after the result
rm -f "$T"/x_*.sh
fake test_ok.sh 'note "noisy"; pass; finish'
fake test_skip.sh 'pass; skip part-2 "node not on PATH"; finish'
fake test_bad.sh 'fail boom; finish'
printf '#!/usr/bin/env bash\necho "SKIP legacy-part: codex not on PATH"; exit 0\n' > "$T/test_legacy.sh"
fake test_env.sh 'printf "%s\n" "$HOME" "$XDG_CONFIG_HOME" "$CODEX_HOME" "$GIT_CONFIG_GLOBAL" "${GIT_CONFIG_NOSYSTEM:-}" "$TMPDIR" > "$ENVOUT.$(basename "$0")"; pass; finish'
cp "$T/test_env.sh" "$T/test_env2.sh"
export ENVOUT="$SANDBOX/env"
run() { OUT="$(cd "$T" && TMPDIR="$RT" bash run.sh "$@" 2>&1)"; RC=$?; }

run ok skip
assert_eq "$RC" "0" "filter ok skip: exit 0"
has "ALL TESTS PASSED" "filter run"; lacks "test_bad" "filter run"; lacks "test_legacy" "filter run"
printf '%s\n' "$OUT" | grep -qE '^ok +test_ok\.sh \([0-9]+ s\)$' && pass || fail "no per-file line with the time: $OUT"
lacks "1 passed" "a passing file is quiet"; lacks "noisy" "a passing file is quiet"
printf '%s\n' "$OUT" | sed -n '/ALL TESTS PASSED/,$p' | grep -qxF "SKIP test_skip.sh: part-2: node not on PATH" \
  && pass || fail "the skip is not listed after the result: $OUT"

run
assert_eq "$RC" "1" "a failing file: exit 1"; has "SOME TESTS FAILED"; has "FAIL: boom" "a failing file shows its output"
printf '%s\n' "$OUT" | grep -qE '^FAIL +test_bad\.sh' && pass || fail "no FAIL line for test_bad.sh: $OUT"
has "SKIP test_legacy.sh: legacy-part: codex not on PATH" "an old-style SKIP line is listed with its file"
norm() { printf '%s\n' "$OUT" | sed -e 's/([0-9]* s)//' -e '/^wall time/d'; }
SERIAL="$(norm)"
has "wall time:" "the run's wall time"

VERBOSE=1 run ok; has "1 passed" "VERBOSE=1 shows a passing file's output"
run nothing-matches; [ "$RC" != 0 ] && pass || fail "a filter that matches no file must fail"

# -j N: the same lines in the same order
run -j 4
assert_eq "$RC" "1" "-j 4: exit 1"
assert_eq "$(norm)" "$SERIAL" "-j 4 output equals the serial output"

# one throwaway root (TEST-3): HOME, XDG, CODEX_HOME, git config and TMPDIR under it, each file its own, removed at the end
run env
assert_eq "$RC" "0" "env files: exit 0"
for f in test_env.sh test_env2.sh; do
  E="$ENVOUT.$f"; assert_file "$E"
  r="$(sed -n 6p "$E")"; r="${r%/*}"   # the file's own folder: TMPDIR is <root>/<n>/tmp
  case "$r" in "$RT"/*) pass ;; *) fail "$f: TMPDIR not under the run's temp folder: $r" ;; esac
  n=0; while IFS= read -r v; do n=$((n + 1)); [ "$n" = 5 ] && continue
    case "$v" in "$r"/*) pass ;; *) fail "$f: line $n not under the file's root $r: $v" ;; esac
  done < "$E"
  assert_eq "$(sed -n 5p "$E")" "1" "$f: GIT_CONFIG_NOSYSTEM"
done
[ "$(sed -n 1p "$ENVOUT.test_env.sh")" != "$(sed -n 1p "$ENVOUT.test_env2.sh")" ] && pass || fail "two files share one HOME"
assert_eq "$(left)" "0" "run.sh left its root"
OUT="$(cd "$T" && KEEP_SANDBOX=1 TMPDIR="$RT" bash run.sh env 2>&1)"; has "kept:" "run.sh KEEP_SANDBOX=1"
assert_eq "$(left)" "1" "run.sh KEEP_SANDBOX=1 keeps its root"
chmod -R u+rwx "$RT"; rm -rf "$RT"
finish
