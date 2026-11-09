#!/usr/bin/env bash
# sync-tools.sh keeps a stable copy of the plugin's scripts in the data folder. Its lock (runs at the same time, a live
# or dead holder) and a copy or swap that fails halfway are tested here too.
source "$(dirname "$0")/lib.sh"
new_sandbox
SYNC="$SCRIPTS/sync-tools.sh"
T="$SANDBOX/data/tools"
V="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json" | head -1)"
[ -n "$V" ] && pass || fail "no version in plugin.json"
grep -nE '(tools (updated|current) |VERSION.*")[0-9]+\.[0-9]+\.[0-9]+' "$0" | grep -v '0\.1\.0' | grep -q . \
  && fail "$(basename "$0") hard-codes the plugin version; use \$V" || pass
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools updated $V" "first sync output"
for f in save undo-step _locate.sh lib.sh install-hooks.sh \
         git-hooks/pre-commit-code git-hooks/pre-push-code git-hooks/pre-push-core git-hooks/blocked-patterns \
         git-hooks/allowed-patterns; do
  assert_file "$T/$f"
done
assert_eq "$(head -1 "$T/VERSION")" "$V" "VERSION file: the version on line 1"
sed -n 2p "$T/VERSION" | grep -qE '^[0-9]+ [0-9]+$' && pass || fail "VERSION file: no content checksum on line 2: $(cat "$T/VERSION")"
for f in save undo-step install-hooks.sh git-hooks/pre-commit-code git-hooks/pre-push-code git-hooks/pre-push-core; do
  [ -x "$T/$f" ] && pass || fail "not executable: $T/$f"
done
for f in git-hooks/blocked-patterns git-hooks/allowed-patterns; do
  [ -x "$T/$f" ] && fail "a pattern list is executable: $T/$f" || pass
done
assert_eq "$(ls "$SANDBOX/data" | tr '\n' ' ')" "tools " "no temp dir left behind"

# second run: current, nothing rewritten
echo marker > "$T/marker"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools current $V" "second sync output"
assert_file "$T/marker"

# a damaged copy is healed: same VERSION, but a file is gone -> updated and restored
for f in git-hooks/blocked-patterns git-hooks/allowed-patterns git-hooks/pre-push-core _locate.sh lib.sh install-hooks.sh undo-step; do
  rm -f "$T/$f"
  assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
  assert_eq "$OUT" "tools updated $V" "sync after deleting $f"
  assert_file "$T/$f"
done
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools current $V" "intact copy is current again"
# lib.sh sources its parts: the copy holds every one (save, undo-step and install-hooks source the copied lib.sh), a missing
# part is healed, and the copied lib.sh runs on its own
PARTS="$(grep -oE '\$_LIB_DIR/[A-Za-z_][A-Za-z0-9._-]*' "$SCRIPTS/lib.sh" | sed 's|^\$_LIB_DIR/||' | LC_ALL=C sort -u)"
[ -n "$PARTS" ] && pass || fail "lib.sh names no parts"
for f in $PARTS; do
  assert_file "$T/$f"
  rm -f "$T/$f"
  assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
  assert_eq "$OUT" "tools updated $V" "sync after deleting $f"
  assert_file "$T/$f"
done
assert_eq "$(bash "$T/lib.sh" schema)" "$(bash "$SCRIPTS/lib.sh" schema)" "the copied lib.sh runs"
# shellcheck disable=SC1091
assert_eq "$( ( . "$T/lib.sh"; json_str '{"k":"v"}' k ) )" "v" "the copied lib.sh reads JSON"
# The copy knows its data folder (.data-dir, written at sync time): a tools copy run by hand, with no CLAUDE_PLUGIN_DATA
# or COREDEV_TOOLS, finds itself whatever the marketplace is called. The plugin's own lib.sh keeps the host default.
assert_eq "$(cat "$T/.data-dir" 2>/dev/null)" "$SANDBOX/data" ".data-dir names the data folder"
# shellcheck disable=SC2016
OUT="$(env -u COREDEV_TOOLS -u CLAUDE_PLUGIN_DATA bash -c '. "$1/lib.sh"; tools_dir' _ "$T")"
assert_eq "$OUT" "$T" "tools_dir of a tools copy run by hand"
# shellcheck disable=SC2016
OUT="$(env -u COREDEV_TOOLS -u CLAUDE_PLUGIN_DATA COREKIT_HOST=claude bash -c '. "$1/lib.sh"; tools_dir' _ "$SCRIPTS")"
assert_eq "$OUT" "$HOME/.claude/plugins/data/corecrew-corekit/tools" "tools_dir of the plugin run by hand"
# a copy from an older sync (no .data-dir) is refreshed; a wrong one too
rm -f "$T/.data-dir"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools updated $V" "copy without .data-dir: updated"
assert_eq "$(cat "$T/.data-dir" 2>/dev/null)" "$SANDBOX/data" ".data-dir written again"
echo /elsewhere > "$T/.data-dir"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools updated $V" "copy with a wrong .data-dir: updated"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools current $V" "current after .data-dir is right"
echo marker > "$T/marker"

# a different VERSION triggers an update that replaces the folder
echo 0.1.0 > "$T/VERSION"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T"
assert_eq "$OUT" "tools updated $V" "version change output"
assert_eq "$(head -1 "$T/VERSION")" "$V"
assert_no_file "$T/marker"

# a tools dir whose path has a space
T2="$SANDBOX/my data/tools dir"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$T2"
assert_file "$T2/save"; assert_file "$T2/git-hooks/blocked-patterns"
# a tools folder not named tools has no .data-dir (its parent's tools/ would be another folder)
assert_no_file "$T2/.data-dir"

# the synced save runs standalone (reads _locate.sh next to itself)
(cd "$SANDBOX" && bash "$T2/save" 2>&1 | grep -q 'Usage') && pass || fail "synced save does not run"

# a broken plugin root fails loudly and leaves the target alone
assert_exit 1 bash "$SYNC" "$SANDBOX/nope" "$T"
assert_eq "$(head -1 "$T/VERSION")" "$V" "target untouched after failure"

# Same version, changed content (a fix shipped without a version bump, or a --plugin-dir checkout):
# the copy is refreshed. A plugin root copied into the sandbox, so its scripts can change.
R="$SANDBOX/plugin"; mkdir -p "$R"; cp -R "$PLUGIN/.claude-plugin" "$PLUGIN/scripts" "$R/"
T3="$SANDBOX/data3/tools"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools current $V" "unchanged plugin: current"
printf '# changed\n' >> "$R/scripts/save"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated $V" "changed save, same version: updated"
assert_eq "$(tail -1 "$T3/save")" "# changed" "the changed save was copied"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools current $V" "current again after the refresh"
printf '# changed\n' >> "$R/scripts/git-hooks/blocked-patterns"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated $V" "changed git-hooks file, same version: updated"
# a copy edited in place (same version, same file set) is rebuilt too
printf 'echo tampered\n' >> "$T3/lib.sh"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated $V" "edited copy: updated"
assert_not_contains "$T3/lib.sh" "echo tampered"
# backward compatible: a VERSION from an older sync holds only the version -> stale, rebuilt
printf '%s\n' "$V" > "$T3/VERSION"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated $V" "version-only VERSION: updated"
assert_eq "$(wc -l < "$T3/VERSION" | tr -d ' ')" "2" "VERSION rewritten with the checksum"
# A copy or a swap that fails halfway leaves the old tools working: the plugin changes again (else the copy is current and
# nothing is copied), then (1) cp fails on its third call, (2) mv fails only to move the new copy in.
REALCP="$(command -v cp)"; REALMV="$(command -v mv)"
printf '# changed again\n' >> "$R/scripts/save"
CPF="$SANDBOX/cpfail"; mkdir -p "$CPF"
printf '#!/bin/sh\nn=$(cat "%s/cp.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "%s/cp.n"\n[ "$n" -eq 3 ] && exit 1\nexec "%s" "$@"\n' \
  "$SANDBOX" "$SANDBOX" "$REALCP" > "$CPF/cp"; chmod +x "$CPF/cp"
before="$(tree_sum "$T3")"
PATH="$CPF:$PATH" bash "$SYNC" "$R" "$T3" >/dev/null 2>"$SANDBOX/cpfail.err"; assert_eq "$?" "1" "cp fails halfway: exit 1"
assert_eq "$(cat "$SANDBOX/cp.n")" "3" "cp fails halfway: the stub failed the third copy"
assert_eq "$(tree_sum "$T3")" "$before" "cp fails halfway: the old copy changed"
assert_eq "$(ls -A "$(dirname "$T3")")" "tools" "cp fails halfway: something left beside tools"
assert_contains "$SANDBOX/cpfail.err" "tools not updated"
MVF="$SANDBOX/mvfail"; mkdir -p "$MVF"
printf '#!/bin/sh\ncase "$1" in *.new.*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REALMV" > "$MVF/mv"; chmod +x "$MVF/mv"
PATH="$MVF:$PATH" bash "$SYNC" "$R" "$T3" >/dev/null 2>"$SANDBOX/mvfail.err"; assert_eq "$?" "1" "mv of the new copy fails: exit 1"
assert_eq "$(tree_sum "$T3")" "$before" "mv of the new copy fails: the old copy is not back as it was"
assert_eq "$(ls -A "$(dirname "$T3")")" "tools" "mv of the new copy fails: something left beside tools"
assert_contains "$SANDBOX/mvfail.err" "could not replace"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated $V" "after the failures: updated"
assert_eq "$(tail -1 "$T3/save")" "# changed again" "after the failures: the new save was copied"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools current $V" "after the failures: current"

# A target folder that is not ours (non-empty, no VERSION) is never replaced: exit 2, nothing changed.
F="$SANDBOX/foreign"; mkdir -p "$F/sub"; echo mine > "$F/notes.txt"; echo x > "$F/sub/y"
before="$(tree_sum "$F")"
assert_exit 2 bash "$SYNC" "$PLUGIN" "$F"
echo "$OUT" | grep -qF "$F" && pass || fail "refusal does not name the folder: $OUT"
echo "$OUT" | grep -qi 'not replaced\|not a corecrew' && pass || fail "refusal is not a plain message: $OUT"
assert_eq "$(tree_sum "$F")" "$before" "foreign folder changed"
assert_eq "$(ls -A "$SANDBOX" | grep -c 'foreign\.')" "0" "temp dir left next to the foreign folder"
# a file in place of the target: refused too
echo file > "$SANDBOX/tfile"
assert_exit 2 bash "$SYNC" "$PLUGIN" "$SANDBOX/tfile"
assert_eq "$(cat "$SANDBOX/tfile")" "file" "file target changed"
# an empty folder is fine (made by hand or by an earlier mkdir)
mkdir -p "$SANDBOX/empty/tools"
assert_exit 0 bash "$SYNC" "$PLUGIN" "$SANDBOX/empty/tools"
assert_file "$SANDBOX/empty/tools/save"

# --- a stale lock (dead owner) is taken over by an atomic rename, so only one waiter wins
SL="$SANDBOX/stale"; mkdir -p "$SL"; STUB="$SANDBOX/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "$@" >> "%s/mv.log"\nexec "%s" "$@"\n' "$SANDBOX" "$REALMV" > "$STUB/mv"; chmod +x "$STUB/mv"
mkdir "$SL/tools.lock"; echo 99999999 > "$SL/tools.lock/pid"
PATH="$STUB:$PATH" bash "$SYNC" "$PLUGIN" "$SL/tools" > "$SANDBOX/stale.out" 2>&1
assert_contains "$SANDBOX/stale.out" "tools updated" "stale lock: tools made"
assert_contains "$SANDBOX/mv.log" "$SL/tools.lock $SL/tools.lock.dead." "stale lock: taken over with an atomic mv"
assert_eq "$(ls -A "$SL" | grep -c 'lock\|\.dead\|\.new')" "0" "stale lock: no leftovers"
for i in 1 2 3 4 5 6; do
  rm -rf "$SL/tools"; mkdir "$SL/tools.lock"; echo 99999999 > "$SL/tools.lock/pid"
  bash "$SYNC" "$PLUGIN" "$SL/tools" > "$SANDBOX/w1" 2>&1 & bash "$SYNC" "$PLUGIN" "$SL/tools" > "$SANDBOX/w2" 2>&1 & wait
  assert_eq "$(ls -A "$SL" | grep -vc '^tools$')" "0" "two waiters on a dead lock, round $i: nothing but tools in the folder"
  assert_eq "$(ls -A "$SL/tools" | grep -c 'new')" "0" "two waiters, round $i: no stray .new in tools"
done
# The lock changes hands between a waiter's read of the dead pid and its rename: the first waiter to read the pid
# stalls (stub cat), the other takes the dead lock over and copies slowly (stub cp). The stalled waiter must not move
# the new owner's live lock away, or both copy at once and one copy lands inside tools/.
RS="$SANDBOX/racestub"; mkdir -p "$RS"; REALCAT="$(command -v cat)"
printf '#!/bin/sh\n"%s" "$@"; case "$*" in *tools.lock/pid*) mkdir "%s/stalled" 2>/dev/null && sleep 2 ;; esac\n' "$REALCAT" "$SANDBOX" > "$RS/cat"
printf '#!/bin/sh\nsleep 0.2\nexec "%s" "$@"\n' "$REALCP" > "$RS/cp"; chmod +x "$RS/cat" "$RS/cp"
for i in 1 2; do
  rm -rf "$SL/tools" "$SANDBOX/stalled"; mkdir "$SL/tools.lock"; echo 99999999 > "$SL/tools.lock/pid"
  PATH="$RS:$PATH" bash "$SYNC" "$PLUGIN" "$SL/tools" > "$SANDBOX/r1" 2>&1 &
  PATH="$RS:$PATH" bash "$SYNC" "$PLUGIN" "$SL/tools" > "$SANDBOX/r2" 2>&1 & wait
  assert_eq "$("$REALCAT" "$SANDBOX/r1" "$SANDBOX/r2" | grep -c 'tools updated')" "1" "lock changes hands, round $i: only one run made the copy"
  assert_eq "$(ls -A "$SL/tools" | grep -c 'new')" "0" "lock changes hands, round $i: no copy inside tools"
  assert_eq "$(ls -A "$SL" | grep -vc '^tools$')" "0" "lock changes hands, round $i: nothing but tools in the folder"
done

# --- sync-tools: the lock
SYNC="$SCRIPTS/sync-tools.sh"; T="$SANDBOX/lt/tools"
# legitimate: a first run, a second run, no lock and no temp left
mkdir -p "$SANDBOX/lt"; bash "$SYNC" "$PLUGIN" "$T" >/dev/null; assert_eq "$?" "0" "sync: first run"
assert_eq "$(ls -A "$SANDBOX/lt")" "tools" "sync: nothing but tools left beside it"
# a live holder: a stale copy is not touched by a run that cannot get the lock, which exits 0 after the wait
printf 'x\n' > "$T/extra"; : > "$T/save"          # damaged copy
mkdir "$T.lock"; sleep 30 & HOLD=$!; echo $HOLD > "$T.lock/pid"
# Wall time on purpose: this times a real wait, not work.
before="$(tree_sum "$T")"; t0=$SECONDS
OUT="$(bash "$SYNC" "$PLUGIN" "$T" 2>&1)"; RC=$?
assert_eq "$RC" "0" "sync: busy lock: clean skip"
case "$OUT" in "tools busy"*) pass ;; *) fail "busy lock: $OUT" ;; esac
[ $((SECONDS - t0)) -le 14 ] && pass || fail "busy wait too long: $((SECONDS - t0))"
assert_eq "$(tree_sum "$T")" "$before" "sync: busy lock: tools untouched"
assert_eq "$(ls -A "$SANDBOX/lt" | grep -c '\.new\.\|\.old\.')" "0" "sync: busy lock: no temp folders"
[ -d "$T.lock" ] && pass || fail "the holder's lock was removed"
kill $HOLD 2>/dev/null; wait $HOLD 2>/dev/null
# a dead holder: the lock is taken over and the copy repaired
OUT="$(bash "$SYNC" "$PLUGIN" "$T" 2>&1)"; assert_eq "$OUT" "tools updated $(sed -n 1p "$T/VERSION")" "sync: dead holder's lock taken over"
assert_eq "$(ls -A "$SANDBOX/lt")" "tools" "sync: lock and temp folders gone"
[ ! -e "$T/extra" ] && pass || fail "damaged copy not rebuilt"
# several at once, three rounds: all exit 0, one copy, nothing left beside or inside it
for round in 1 2 3; do
  rm -rf "$T"
  for i in 1 2 3 4 5 6; do bash "$SYNC" "$PLUGIN" "$T" > "$SANDBOX/s$i" 2>&1 & done; wait
  assert_eq "$(cat "$SANDBOX"/s? | grep -vc '^tools \(updated\|current\) ')" "0" "sync round $round: only plain lines"
  assert_eq "$(ls -A "$SANDBOX/lt")" "tools" "sync round $round: nothing beside tools"
  assert_eq "$(ls -A "$T" | grep -c 'tmp\|\.new\|\.part\|lock')" "0" "sync round $round: nothing inside tools"
  assert_file "$T/VERSION"
done

# --- install-hooks.sh writes the shims where git runs hooks: core.hooksPath and linked worktrees
IH="$SCRIPTS/install-hooks.sh"
setup_core && sync_tools && pass || fail "setup for install-hooks"
# 1. A local core.hooksPath (husky): nothing is written to .git/hooks or the husky folder, the message
#    names the folder and gives the chaining lines, exit 4, no success line. The Core has no hooksPath.
scaffold_old ihp; P="$CORE_DIR/ihp"; C="$P/code"
mkdir -p "$C/.husky"; printf '#!/bin/sh\nnpx lint-staged\n' > "$C/.husky/pre-commit"
git -C "$C" config core.hooksPath .husky
husky_before="$(tree_sum "$C/.husky")"
assert_exit 4 bash "$IH" "$P"
assert_no_file "$C/.git/hooks/pre-commit"; assert_no_file "$C/.git/hooks/pre-push"
assert_eq "$(tree_sum "$C/.husky")" "$husky_before" "the hooksPath folder was written"
assert_no_file "$C/.husky/pre-push"
echo "$OUT" | grep -qF "$C/.husky" && pass || fail "message does not name the hooksPath folder: $OUT"
echo "$OUT" | grep -qF "core.hooksPath" && pass || fail "message does not name core.hooksPath: $OUT"
echo "$OUT" | grep -qF "bash '$COREDEV_TOOLS/git-hooks/pre-commit-code' || exit 1" && pass || fail "no pre-commit chaining line: $OUT"
echo "$OUT" | grep -qF "bash '$COREDEV_TOOLS/git-hooks/pre-push-code' \"\$@\" < \"\$f\"" && pass || fail "no pre-push chaining line: $OUT"
echo "$OUT" | grep -qF "hooks installed" && fail "claims success with core.hooksPath set: $OUT" || pass
assert_contains "$CORE_DIR/.git/hooks/pre-push" "# corecrew hook shim"
# a hooksPath that is git's own folder is fine: the shims go there, exit 0
git -C "$C" config core.hooksPath .git/hooks
assert_exit 0 bash "$IH" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_eq "$(tree_sum "$C/.husky")" "$husky_before" "the husky folder was written"
git -C "$C" config --unset core.hooksPath

# 2. A global core.hooksPath (only in the sandbox's own global config): both repos refused, nothing written
case "$GIT_CONFIG_GLOBAL" in "$SANDBOX"/*) pass ;; *) fail "GIT_CONFIG_GLOBAL is not in the sandbox: $GIT_CONFIG_GLOBAL"; finish; exit 1 ;; esac
GH="$SANDBOX/global hooks"; mkdir -p "$GH"
scaffold_old ihg; P="$CORE_DIR/ihg"; C="$P/code"
rm -f "$CORE_DIR/.git/hooks/pre-push"
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$GH"
assert_exit 4 bash "$IH" "$P"
assert_no_file "$C/.git/hooks/pre-commit"; assert_no_file "$C/.git/hooks/pre-push"
assert_no_file "$CORE_DIR/.git/hooks/pre-push"
assert_eq "$(ls -A "$GH")" "" "the global hooks folder was written"
echo "$OUT" | grep -qF "$GH" && pass || fail "message does not name the global hooksPath: $OUT"
echo "$OUT" | grep -qF "bash '$COREDEV_TOOLS/git-hooks/pre-push-core' \"\$@\" < \"\$f\"" && pass || fail "no Core chaining line: $OUT"
echo "$OUT" | grep -qF "hooks installed" && fail "claims success with a global hooksPath: $OUT" || pass
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath

# 3. The code folder is a linked worktree (.git is a file): the shims land in the common hooks folder
#    git runs, and a commit in the worktree is checked by them.
scaffold_old ihw; P="$CORE_DIR/ihw"; C="$P/code"; M="$SANDBOX/ihw main"
mv "$C" "$M" && git -C "$M" worktree add -q "$C" -b wt && pass || fail "linked worktree setup"
[ -f "$C/.git" ] && pass || fail "the worktree's .git is not a file"
assert_exit 0 bash "$IH" "$P"
assert_contains "$M/.git/hooks/pre-commit" "# corecrew hook shim"
assert_contains "$M/.git/hooks/pre-push" "# corecrew hook shim"
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md
git -C "$C" commit -q -m "add CLAUDE.md" >/dev/null 2>&1 && fail "worktree commit of CLAUDE.md allowed: shim not run" || pass
git -C "$C" reset -q; rm -f "$C/CLAUDE.md"
mkdir -p "$C/src"; echo x > "$C/src/ok.txt"; git -C "$C" add src/ok.txt
git -C "$C" commit -q -m "add ok" >/dev/null 2>&1 && pass || fail "a legitimate commit in the worktree was blocked"
assert_exit 0 bash "$IH" "$P"

# 4. No hooksPath: installs, prints the success line, is idempotent, and keeps a user's own hook
scaffold_old ihok; P="$CORE_DIR/ihok"; C="$P/code"
printf '#!/bin/sh\necho mine\n' > "$C/.git/hooks/pre-push"
assert_exit 0 bash "$IH" "$P"
echo "$OUT" | grep -qF "hooks installed" && pass || fail "no success line: $OUT"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_eq "$(cat "$C/.git/hooks/pre-push")" "$(printf '#!/bin/sh\necho mine')" "the user's own pre-push hook was replaced"
first="$(cat "$C/.git/hooks/pre-commit")"
assert_exit 0 bash "$IH" "$P"
assert_eq "$(cat "$C/.git/hooks/pre-commit")" "$first" "second run changed the shim"

# 5. An empty core.hooksPath (set to cancel a global one): git then runs no hooks from .git/hooks and
#    rev-parse names the work tree root. Nothing is written anywhere, exit 4, no success line.
scaffold_old ihe; P="$CORE_DIR/ihe"; C="$P/code"
git -C "$C" config core.hooksPath ""
assert_exit 4 bash "$IH" "$P"
assert_no_file "$C/pre-commit"; assert_no_file "$C/pre-push"
assert_no_file "$C/.git/hooks/pre-commit"; assert_no_file "$C/.git/hooks/pre-push"
git -C "$C" status --porcelain | grep -qE 'pre-(commit|push)' && fail "an empty hooksPath left hook files in the work tree" || pass
echo "$OUT" | grep -qF "core.hooksPath" && pass || fail "message does not name core.hooksPath: $OUT"
echo "$OUT" | grep -qF "hooks installed" && fail "claims success with an empty hooksPath: $OUT" || pass
git -C "$C" config --unset core.hooksPath

# 6. The pre-push chaining line from the message, put in a user's own pre-push hook: it runs the
#    corecrew check (a blocked file stops the push) and the rest of the user's hook still gets the
#    refs on stdin (git lfs pre-push needs them).
scaffold_old ihc; P="$CORE_DIR/ihc"; C="$P/code"; HPD="$SANDBOX/ihc hooks"; mkdir -p "$HPD"
git -C "$C" config core.hooksPath "$HPD"
assert_exit 4 bash "$IH" "$P"
line="$(echo "$OUT" | sed -n 's/^    pre-push: //p')"
[ -n "$line" ] && pass || fail "no pre-push chaining line to test: $OUT"
printf '#!/bin/sh\n%s\ncat > "%s"\n' "$line" "$SANDBOX/ihc seen" > "$HPD/pre-push"; chmod +x "$HPD/pre-push"
git init -q --bare "$SANDBOX/ihc remote.git"
mkdir -p "$C/src"; echo x > "$C/src/ok.txt"; git -C "$C" add src/ok.txt; git -C "$C" commit -q --no-verify -m "add ok"
git -C "$C" push -q "$SANDBOX/ihc remote.git" HEAD:refs/heads/main >/dev/null 2>&1 && pass || fail "a legitimate push through the chained hook failed"
assert_eq "$(grep -c 'refs/heads/main' "$SANDBOX/ihc seen" 2>/dev/null)" "1" "the user's hook after the chained line did not get the refs on stdin"
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md; git -C "$C" commit -q --no-verify -m "add CLAUDE.md"
git -C "$C" push -q "$SANDBOX/ihc remote.git" HEAD:refs/heads/main >/dev/null 2>&1 && fail "the chained line did not block a push of CLAUDE.md" || pass
git -C "$C" config --unset core.hooksPath
finish
