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

# --- setup_core builds the first Core of a file and publishes a copy (core-cache.<key> in TEST_TMP, a link made at
# once with ln -sn); a later fresh Core with the same key is copied from it. The key holds what can change the
# Core: the GIT_* variables, the global git config, PATH, umask and the scripts folder. A publish over a cache
# already there changes nothing and leaves no folder behind; a copy is a real folder, equal to the built one.
export HC_SCRIPTS="$SCRIPTS"
cat > "$T/x_cache.sh" <<'EOF'
source "$(dirname "$0")/lib.sh"
SCRIPTS="$HC_SCRIPTS"
caches() { find "$TEST_TMP" -mindepth 1 -maxdepth 1 -name 'core-cache.*' | wc -l | tr -d ' '; }
tmps() { find "$TEST_TMP" -mindepth 1 -maxdepth 1 -name 'corecache.*' | wc -l | tr -d ' '; }
new_sandbox; setup_core || fail "the first setup_core"; C1="$CORE_DIR"
assert_eq "$(caches)/$(tmps)" "1/1" "the first build publishes one cache (a link to one folder)"
CACHE="$(find "$TEST_TMP" -mindepth 1 -maxdepth 1 -name 'core-cache.*')"
[ -n "$CACHE" ] && [ -L "$CACHE" ] && pass || { fail "no cache, or the cache is not a link"; finish; }
new_sandbox; setup_core || fail "the second setup_core"; C2="$CORE_DIR"
new_sandbox; setup_core || fail "the third setup_core"; C3="$CORE_DIR"
for c in "$C2" "$C3"; do
  [ -d "$c/.git" ] && [ ! -L "$c" ] && pass || fail "$c is not a real folder with a repo"
  assert_eq "$(git -C "$c" status --porcelain)" "" "a copied Core: git status"
  assert_eq "$(tree_sum "$c")" "$(tree_sum "$C1")" "a copied Core: the same files as the built one"
  assert_eq "$(git -C "$c" rev-parse HEAD)" "$(git -C "$C1" rev-parse HEAD)" "a copied Core: the same commit"
  assert_eq "$(git -C "$c" ls-files -s)" "$(git -C "$C1" ls-files -s)" "a copied Core: the same index"
  assert_eq "$(cat "$c/.git/config")" "$(cat "$C1/.git/config")" "a copied Core: the same repo config"
done
assert_eq "$(caches)/$(tmps)" "1/1" "copies publish nothing"
# a fresh build that publishes over the cache: the cache stays as it was, with no nested folder, and no copy is left
before="$(tree_sum "$CACHE/")"
core_cache_publish "$C1" "$CACHE"
assert_eq "$(find "$CACHE/" -mindepth 1 -maxdepth 1 -name 'corecache.*' | wc -l | tr -d ' ')" "0" "a second publish: no nested folder"
assert_eq "$(tree_sum "$CACHE/")" "$before" "a second publish: the cache is unchanged"
assert_eq "$(caches)/$(tmps)" "1/1" "a second publish: its copy is removed"
# setup_core on a Core folder that exists builds as before and publishes nothing
new_sandbox; mkdir -p "$CORE_DIR"; setup_core || fail "setup_core on an empty folder"
[ -f "$CORE_DIR/.coredev" ] && pass || fail "setup_core on an empty folder: no .coredev"
assert_eq "$(caches)" "1" "a Core folder that existed is not published"
# another git identity is another key: the commit carries the new name, never the cached one
new_sandbox; export GIT_AUTHOR_NAME=other; setup_core || fail "setup_core with another identity"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%an)" "other" "another identity: the commit's author"
assert_eq "$(caches)" "2" "another identity: a cache of its own"
finish
EOF
one x_cache.sh; assert_eq "$RC" "0" "core cache: $OUT"
# core_cache_key: the same inputs give the same key; each part of the key, changed alone, gives a new one
K0="$(core_cache_key)"
assert_eq "$(core_cache_key)" "$K0" "core_cache_key: the same inputs, the same key"
key_differs() { [ -n "$2" ] && [ "$2" != "$K0" ] && pass || fail "core_cache_key ignores $1"; }
key_differs "PATH" "$(PATH="$SANDBOX/fake git:$PATH" core_cache_key)"
[ "$(umask)" = 0077 ] && U=022 || U=077
key_differs "umask" "$(umask "$U"; core_cache_key)"
key_differs "SCRIPTS" "$(SCRIPTS="$SANDBOX/other scripts" core_cache_key)"
key_differs "a GIT_* variable" "$(export GIT_COMMITTER_DATE=2000-01-01T00:00:00; core_cache_key)"
GC="$SANDBOX/global gitconfig"; printf '[init]\n\tdefaultBranch = a\n' > "$GC"; K0="$(GIT_CONFIG_GLOBAL="$GC" core_cache_key)"
printf '[init]\n\tdefaultBranch = b\n' > "$GC"; key_differs "the global git config" "$(GIT_CONFIG_GLOBAL="$GC" core_cache_key)"
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

# -j N hands xargs the files largest first ("n file", ties by n), so a slow file does not start last. A logging xargs
# ahead on PATH sees what run.sh feeds it; the alphabetical order and the sizes differ on purpose.
XL="$SANDBOX/xargs log"; mkdir -p "$XL"
printf '#!/bin/sh\ntee "%s/in" | "%s" "$@"\n' "$XL" "$(command -v xargs)" > "$XL/xargs"; chmod +x "$XL/xargs"
pad() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "# pad" }'; }
fake test_ord_a.sh 'pass; finish'
fake test_ord_b.sh "$(pad 300; echo 'pass; finish')"
fake test_ord_c.sh "$(pad 100; echo 'pass; finish')"
OUT="$(cd "$T" && PATH="$XL:$PATH" TMPDIR="$RT" bash run.sh -j 2 ord 2>&1)"; RC=$?
assert_eq "$RC" "0" "-j 2 ord: exit 0 :: $OUT"
assert_eq "$(cat "$XL/in" 2>/dev/null)" "$(printf '2 test_ord_b.sh\n3 test_ord_c.sh\n1 test_ord_a.sh')" "-j: the largest file first"
rm -f "$T"/test_ord_*.sh

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
echo one > "$S/plain"   # outside any repo: only the file sums see its content
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
H0="$(git -C "$G" rev-parse HEAD)"
# shellcheck disable=SC2034  # read in the eval strings of changed
C="$(git -C "$G" commit-tree "$H0^{tree}" -p "$H0" -m same)"
changed "HEAD moved to a commit of the same tree" 'git -C "$G" reset -q --soft "$C"' 'git -C "$G" reset -q --soft "$H0"'
changed "an index-only change" 'git -C "$G" rm -q --cached f' 'git -C "$G" add f'
changed "an empty folder" 'mkdir "$S/empty"' 'rmdir "$S/empty"'
# the same size, the same path, no repo: only the file sums (tree_sum) see a change of content
changed "the content of a file outside a repo" 'echo two > "$S/plain"' 'echo one > "$S/plain"'
changed ".git/REVERT_HEAD" 'git -C "$G" rev-parse HEAD > "$G/.git/REVERT_HEAD"' 'rm "$G/.git/REVERT_HEAD"'
changed ".git/index.lock" ': > "$G/.git/index.lock"' 'rm "$G/.git/index.lock"'
# shellcheck disable=SC2034  # read in the eval string of changed
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
# line. The echo must start a command (the fixture above
# that writes such a line into a fake file, and a comment that quotes one, are not matches).
for f in "$ROOT"/tests/test_*.sh; do
  old="$(grep -nE '(^|;|\{|then|else|do)[[:space:]]*echo "[[:space:]]*(note:|SKIP )' "$f" | cut -d: -f1 | tr '\n' ' ')"
  assert_eq "${old:-none}" "none" "$(basename "$f"): old-style skip or note lines (use skip, or note)"
done
# --- bg and bg_wait: a section's counts are added, also when the section uses the variable names bg uses itself
fake x_bg.sh 'a() { n=7; p=1; f=2; pass; }; b() { for n in 1 2; do pass; done; fail "b fails"; }; bg a; bg b; bg_wait; finish'
one x_bg.sh; assert_eq "$RC" "1" "bg sections: the failure of a section fails the file"
has "x_bg.sh: 3 passed, 1 failed" "bg sections that set n"; lacks "did not finish" "bg sections that set n"

# --- a part behind a tool or root gate says so when it does not run (R4-114): every `if command -v <tool>` and every
# `if [ "$(id -u)" ...` block of a test file holds a skip call (the block: from the `if` line that ends in `then` to
# the `fi` at the same indent; a one-line `if ...; fi` holds it itself). A gate that only picks one of two tools
# inside one line is no block and is not read. The short form `command -v <tool> >/dev/null 2>&1 && ...` outside an
# `if` is a gate with no place for a skip call, so it is always open; `... || <fallback>` is a choice and is not read.
# open_gates <file> — the line numbers of the gate blocks with no skip call, on one line
open_gates() {
  awk '
    function isgate(l) { return l ~ /^[ \t]*if .*(command -v [A-Za-z0-9_.-]+ >\/dev\/null|\$\(id -u\))/ }
    function hasskip(l) { return l !~ /^[ \t]*#/ && l ~ /(^|[ \t;])skip [^ ]/ }
    {
      if (inb) {
        if (hasskip($0)) ok = 1
        if ($0 ~ ("^" ind "fi([ \t;]|$)")) { if (!ok) printf "%d ", start; inb = 0 }
        next
      }
      if ($0 !~ /^[ \t]*(#|if |elif |while )/ && $0 ~ /command -v [A-Za-z0-9_.-]+ >\/dev\/null( 2>&1)?[ \t]*&&/) { printf "%d ", NR; next }
      if (!isgate($0)) next
      if ($0 ~ /then[ \t]*$/) { inb = 1; ok = 0; start = NR; ind = $0; sub(/[^ \t].*$/, "", ind); next }
      if ($0 ~ /;[ \t]*fi[ \t]*$/ && !hasskip($0)) printf "%d ", NR
    }
    END { if (inb && !ok) printf "%d ", start }' "$1"
}
G="$SANDBOX/gates.sh"
printf '%s\n' 'if command -v zsh >/dev/null 2>&1; then' '  zsh -c :' 'fi' > "$G"
assert_eq "$(open_gates "$G")" "1 " "a tool gate with no skip is found"
printf '%s\n' 'x=1' 'if [ "$(id -u)" != 0 ]; then' '  if true; then :; fi' '  chmod a-w x' 'fi' 'skip later "not in the block"' > "$G"
assert_eq "$(open_gates "$G")" "2 " "a root gate with no skip is found (a skip after the block does not count)"
printf '%s\n' 'if ! command -v node >/dev/null 2>&1; then echo no; fi' > "$G"
assert_eq "$(open_gates "$G")" "1 " "a one-line gate with no skip is found"
printf '%s\n' 'if command -v zsh >/dev/null 2>&1; then' '  zsh -c :' 'else' '  skip zsh "zsh not on PATH"' 'fi' \
  'if [ "$(id -u)" -eq 0 ]; then skip ro "running as root"; else' '  chmod a-w x' 'fi' \
  'if ! command -v node >/dev/null 2>&1; then skip node "node not on PATH"; finish; fi' \
  'if command -v zsh >/dev/null 2>&1; then' '  # skip nothing here' '  zsh -c :' 'fi' \
  'f() {' '  if command -v node >/dev/null 2>&1; then node "$1"' '  else python3 "$1"; fi' '}' > "$G"
assert_eq "$(open_gates "$G")" "10 " "gates that skip and a one-line choice between two tools pass; a comment is no skip"
# the fixture is written with %s for the tool check, so that these lines are not short gates of this file themselves
cv='command -v'
{ printf 'shells="bash"; %s zsh >/dev/null 2>&1 && shells="bash zsh"\n' "$cv"
  printf '%s timeout >/dev/null 2>&1 || timeout() { shift; "$@"; }\n' "$cv"
  printf '# %s zsh >/dev/null 2>&1 && shells="bash zsh"\n' "$cv"
  printf 'shells="bash"; if %s zsh >/dev/null 2>&1; then shells="bash zsh"; else skip zsh "zsh not on PATH"; fi\n' "$cv"
  printf 'if %s git >/dev/null 2>&1 && %s zsh >/dev/null 2>&1; then skip x "y"; fi\n' "$cv" "$cv"
  printf '  %s node >/dev/null && node x\n' "$cv"
} > "$G"
assert_eq "$(open_gates "$G")" "1 6 " "a short '&&' gate is open; a fallback, a comment and an if with a skip are not"
for f in "$ROOT"/tests/test_*.sh; do
  assert_eq "$(open_gates "$f")" "" "$(basename "$f"): gated parts with no skip call, at lines"
done
finish
