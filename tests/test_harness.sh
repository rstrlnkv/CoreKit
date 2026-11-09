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

# --- at_exit: a file's own cleanup runs from lib.sh's one EXIT trap, in order, after finish or a plain exit (whose
# code stays); the sandboxes are still removed, or kept under KEEP_SANDBOX=1; the fake runs are stopped
export AT_MARK="$SANDBOX/at-ran"
fake x_at.sh 'new_sandbox; at_exit "echo one >> \"\$AT_MARK\""; at_exit "echo two >> \"\$AT_MARK\""; pass; finish'
rm -f "$AT_MARK"; one x_at.sh
assert_eq "$RC" "0" "at_exit: exit 0"; assert_eq "$(tr '\n' ' ' < "$AT_MARK" 2>/dev/null)" "one two " "at_exit: both commands ran, in order"
assert_eq "$(left)" "0" "at_exit: sandbox left after finish"
fake x_at2.sh 'new_sandbox; at_exit "echo ran >> \"\$AT_MARK\""; exit 3'
rm -f "$AT_MARK"; one x_at2.sh
assert_eq "$RC" "3" "at_exit: a plain exit keeps its code"; assert_eq "$(cat "$AT_MARK" 2>/dev/null)" "ran" "at_exit: ran after a plain exit"
assert_eq "$(left)" "0" "at_exit: sandbox left after a plain exit"
rm -f "$AT_MARK"; OUT="$(cd "$T" && KEEP_SANDBOX=1 TMPDIR="$RT" bash x_at.sh 2>&1)"
assert_eq "$(tr '\n' ' ' < "$AT_MARK" 2>/dev/null)" "one two " "at_exit under KEEP_SANDBOX=1: the cleanup ran"
assert_eq "$(left)" "1" "at_exit under KEEP_SANDBOX=1: the sandbox is kept"; has "kept:" "at_exit under KEEP_SANDBOX=1"
[ -n "$(find "$RT" -mindepth 2 -maxdepth 2 -name 'sb.*')" ] && pass || fail "at_exit under KEEP_SANDBOX=1: the kept folder holds no sb.*"
chmod -R u+rwx "$RT"; rm -rf "$RT"; mkdir -p "$RT"
fake x_fk.sh 'new_sandbox; fake "$SANDBOX" "harness-fake-run-$$"; echo "$FAKE_PID" > "$AT_MARK"; pass; exit 0'
rm -f "$AT_MARK"; one x_fk.sh; fpid="$(cat "$AT_MARK" 2>/dev/null)"
i=0; while [ -n "$fpid" ] && kill -0 "$fpid" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
[ -n "$fpid" ] && ! kill -0 "$fpid" 2>/dev/null && pass || { fail "a fake run outlived its file (pid ${fpid:-none})"; [ -z "$fpid" ] || kill "$fpid" 2>/dev/null; }
assert_eq "$(left)" "0" "fake runs: sandbox left"

# --- cpu_run, assert_linear and count_execs: speed is judged by CPU time, which load on the machine does not raise
# cpu_run runs the command in this shell: what it sets (RC, OUT, ERR) and its exit code survive. CPU_MS counts the
# children and the shell itself, not the time spent waiting.
cat > "$T/x_cpu.sh" <<'EOF'
source "$(dirname "$0")/lib.sh"
setall() { RC=7; OUT=o; ERR=e; rc=5; return 3; }
cpu_run setall; r=$?
[ "$RC/$OUT/$ERR/$rc/$r" = "7/o/e/5/3" ] && pass || fail "cpu_run lost what the command set: $RC/$OUT/$ERR/$rc/$r"
case "$CPU_MS" in ""|*[!0-9]*) fail "CPU_MS is not a number: $CPU_MS" ;; *) pass ;; esac
cpu_run sleep 1; [ "$CPU_MS" -lt 500 ] && pass || fail "a sleep counted as CPU time: $CPU_MS ms"
cpu_run awk 'BEGIN { for (i = 0; i < 3000000; i++) x++ }'; [ "$CPU_MS" -ge 20 ] && pass || fail "a busy child was not counted: $CPU_MS ms"
spin() { local i=0; while [ $i -lt 30000 ]; do i=$((i + 1)); done; }
cpu_run spin; [ "$CPU_MS" -ge 20 ] && pass || fail "a busy function in this shell was not counted: $CPU_MS ms"
finish
EOF
one x_cpu.sh; assert_eq "$RC" "0" "cpu_run: $OUT"
# assert_linear passes a linear command and fails a quadratic one, naming its label
cat > "$T/x_lin.sh" <<'EOF'
source "$(dirname "$0")/lib.sh"
lin() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) x++ }'; }
quad() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) for (j = 0; j < n; j += 100) x++ }'; }
assert_linear "a linear loop" 6 "lin 2000000" "lin 8000000"
[ -n "${QUAD:-}" ] && assert_linear "a quadratic loop" 6 "quad 8000" "quad 32000"
finish
EOF
one x_lin.sh; assert_eq "$RC" "0" "assert_linear: a linear command passes: $OUT"
OUT="$(cd "$T" && QUAD=1 TMPDIR="$RT" bash x_lin.sh 2>&1)"; RC=$?
assert_eq "$RC" "1" "assert_linear: a quadratic command fails"; has "FAIL: a quadratic loop" "assert_linear on a quadratic command"
# count_execs counts every program started through PATH, nested ones too, and keeps the exit code
cat > "$T/x_exec.sh" <<'EOF'
source "$(dirname "$0")/lib.sh"
exec_shims
count_execs bash -c 'ls / >/dev/null; sh -c "cat </dev/null"; exit 4'; r=$?
assert_eq "$r" "4" "count_execs: the exit code"
assert_eq "$EXECS" "4" "count_execs: bash, ls, sh and the nested cat"
assert_eq "$(tr '\n' ' ' < "$EXEC_LOG")" "bash ls sh cat " "count_execs: the log"
count_execs true; assert_eq "$EXECS" "0" "count_execs: a builtin starts nothing"
case ":$PATH:" in *":$EXEC_SHIMS:"*) fail "the shims stay on PATH after count_execs" ;; *) pass ;; esac
finish
EOF
one x_exec.sh; assert_eq "$RC" "0" "count_execs: $OUT"
assert_eq "$(left)" "0" "cpu_run, assert_linear, count_execs: nothing left"
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

# the real Core: run.sh gives every file a throwaway HOME, so it passes the Core's real place, found before the swap,
# as REAL_CORE_DIR to test_no_personal.sh alone (it only reads it): CORE_DIR when set, else <HOME>/Projects/Core;
# a REAL_CORE_DIR already set (a nested run) is kept. Every other file runs without REAL_CORE_DIR.
fake test_no_personal.sh 'printf "%s\n" "${REAL_CORE_DIR:-unset}" "$HOME" > "$ENVOUT.core"; pass; finish'
fake test_other.sh 'printf "%s\n" "${REAL_CORE_DIR:-unset}" > "$ENVOUT.other"; pass; finish'
core_run() { rm -f "$ENVOUT.core" "$ENVOUT.other"; (cd "$T" && env -u REAL_CORE_DIR -u CORE_DIR TMPDIR="$RT" "$@" bash run.sh no_personal other > /dev/null 2>&1); }
RH="$SANDBOX/real home"; mkdir -p "$RH"
core_run HOME="$RH"
assert_eq "$(sed -n 1p "$ENVOUT.core" 2>/dev/null)" "$RH/Projects/Core" "REAL_CORE_DIR: the Core under the HOME run.sh was started with"
assert_eq "$(cat "$ENVOUT.other" 2>/dev/null)" "unset" "REAL_CORE_DIR: another file does not get it"
case "$(sed -n 2p "$ENVOUT.core" 2>/dev/null)" in "$RH"|"") fail "the file's HOME is not a throwaway one" ;; *) pass ;; esac
core_run HOME="$RH" CORE_DIR="$SANDBOX/my core"
assert_eq "$(sed -n 1p "$ENVOUT.core" 2>/dev/null)" "$SANDBOX/my core" "REAL_CORE_DIR: CORE_DIR when it is set"
core_run HOME="$RH" CORE_DIR="$SANDBOX/my core" REAL_CORE_DIR="$SANDBOX/outer"
assert_eq "$(sed -n 1p "$ENVOUT.core" 2>/dev/null)" "$SANDBOX/outer" "REAL_CORE_DIR: a value already set is kept"
rm -f "$T/test_no_personal.sh" "$T/test_other.sh"
OUT="$(cd "$T" && KEEP_SANDBOX=1 TMPDIR="$RT" bash run.sh env 2>&1)"; has "kept:" "run.sh KEEP_SANDBOX=1"
assert_eq "$(left)" "1" "run.sh KEEP_SANDBOX=1 keeps its root"
chmod -R u+rwx "$RT"; rm -rf "$RT"

# --- snap_tree: two snapshots with no change are identical; each change below alters the snapshot, and undoing it
# gives the first snapshot back. The repo is nested, as a code repo sits under a sandbox.
S="$SANDBOX/snap"; G="$S/a repo"; mkdir -p "$G/sub"
git init -q "$G"; echo one > "$G/f"; ln -s f "$G/l"; printf 'ign\n' > "$G/.gitignore"; ln -s f "$G/ign"
git -C "$G" add -A; git -C "$G" commit -q -m one
echo two > "$G/f"; git -C "$G" commit -q -am two
S0="$(snap_tree "$S")"
assert_eq "$(snap_tree "$S")" "$S0" "snap_tree: no change, same snapshot"
# changed <label> <change> <undo> — the change alters the snapshot; the undo restores it
changed() {
  eval "$2"; [ "$(snap_tree "$S")" != "$S0" ] && pass || fail "snap_tree misses: $1"
  eval "$3"; assert_eq "$(snap_tree "$S")" "$S0" "snap_tree after undoing: $1"
}
changed "a retargeted link" 'ln -sfn sub "$G/l"' 'ln -sfn f "$G/l"'
# each of the next three alters only one part: an ignored link only its target, a commit of the same tree only HEAD,
# an index-only change only the status
changed "a retargeted ignored link" 'ln -sfn sub "$G/ign"' 'ln -sfn f "$G/ign"'
H0="$(git -C "$G" rev-parse HEAD)"; C="$(git -C "$G" commit-tree "$H0^{tree}" -p "$H0" -m same)"
changed "HEAD moved to a commit of the same tree" 'git -C "$G" reset -q --soft "$C"' 'git -C "$G" reset -q --soft "$H0"'
changed "an index-only change" 'git -C "$G" rm -q --cached f' 'git -C "$G" add f'
changed "an empty folder" 'mkdir "$S/empty"' 'rmdir "$S/empty"'
changed ".git/REVERT_HEAD" 'git -C "$G" rev-parse HEAD > "$G/.git/REVERT_HEAD"' 'rm "$G/.git/REVERT_HEAD"'
changed ".git/index.lock" ': > "$G/.git/index.lock"' 'rm "$G/.git/index.lock"'
H="$(git -C "$G" rev-parse HEAD)"
changed "git reset --soft HEAD~1" 'git -C "$G" reset -q --soft HEAD~1' 'git -C "$G" reset -q --soft "$H"'
snap_tree "$SANDBOX/no such folder" | grep -q . && pass || fail "snap_tree prints nothing for a missing folder"

# --- md_section, md_section_has, commit_count, no_git_identity
printf '# T\n## A\none\n### A.1\ntwo\n## B\nthree\n' > "$S/doc.md"
assert_eq "$(md_section "$S/doc.md" A)" "$(printf 'one\n### A.1\ntwo')" "md_section: the body down to the next ## heading"
mkdir -p "$RT"; fake x_sec.sh "md_section_has \"$S/doc.md\" B three; md_section_has \"$S/doc.md\" B one; finish"
one x_sec.sh; has "FAIL: doc.md section 'B' lacks: one"; has "1 passed, 1 failed" "md_section_has"
assert_eq "$(commit_count "$G")" "2" "commit_count of a repo"
assert_eq "$(commit_count "$S")" "0" "commit_count of a folder with no repo"
git init -q "$S/r2"; echo x > "$S/r2/f"; git -C "$S/r2" add f
OUT="$(no_git_identity git -C "$S/r2" commit -q -m x 2>&1)" && fail "no_git_identity: a commit had an identity" || has "user.email" "no_git_identity"
assert_eq "$(commit_count "$S/r2")" "0" "commit_count of a repo with no commit"

# --- skips go through skip (SKIP-1, TEST-7): no test file has an old-style `echo "SKIP ..."` or `echo "  note: ..."`
# line, which run.sh lists only when its words happen to match. The echo must start a command (the fixture above
# that writes such a line into a fake file, and a comment that quotes one, are not matches).
for f in "$ROOT"/tests/test_*.sh; do
  old="$(grep -nE '(^|;|\{|then|else|do)[[:space:]]*echo "[[:space:]]*(note:|SKIP )' "$f" | cut -d: -f1 | tr '\n' ' ')"
  assert_eq "${old:-none}" "none" "$(basename "$f"): old-style skip or note lines (use skip, or note)"
done
finish
