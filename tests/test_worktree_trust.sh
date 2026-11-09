#!/usr/bin/env bash
# A linked worktree is trusted only when its main folder knows it and is the project's own code folder; code-root
# stays inside its root; link creation and the tools swap survive runs at the same time; sync failures are translated.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR COREKIT_HOST
setup_core
bash "$SKILL/scripts/scaffold.sh" --name trust >/dev/null
PR="$(dirname "$CORE_DIR")"; C="$PR/trust"; P="$CORE_DIR/trust"
git -C "$C" commit -q --allow-empty -m init
# wt_of: tests/lib-hook.sh
guard() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$3" "$1" "$2" | bash "$HOOKS/guard-code.sh" >/dev/null 2>"$SANDBOX/err"; RC=$?; }
mkdir -p "$SANDBOX/elsewhere"

# --- a real worktree whose entry does not point back to this folder is not a worktree
W="$SANDBOX/ext/w1"; git -C "$C" worktree add -q "$W" -b t1 || fail "worktree add"
GD="$(sed -n 's/^gitdir: //p' "$W/.git")"
mkdir -p "$SANDBOX/forged"; printf 'gitdir: %s\n' "$GD" > "$SANDBOX/forged/.git"
assert_eq "$(wt_of "$SANDBOX/forged" | cut -c1)" "1" "a gitfile whose main entry names another folder"
assert_eq "$(wt_of "$W" | cut -c1)" "0" "the real worktree still counts"

# --- a worktree of some other repository is not the project's: no project, no links, no guard root
git init -q "$SANDBOX/other"; git -C "$SANDBOX/other" commit -q --allow-empty -m i
mkdir -p "$PR/Downloaded"; git -C "$SANDBOX/other" worktree add -q "$PR/Downloaded/wt" -b o1 || fail "other add"
assert_eq "$(wt_of "$PR/Downloaded/wt" | cut -c1)" "0" "a worktree of another repo is a worktree"
assert_eq "$(bash "$SCRIPTS/lib.sh" project-of "$PR/Downloaded/wt" 2>/dev/null)" "" "...but of no project"
# a forged gitfile in a folder beside the project, naming the project's real entry shape
mkdir -p "$PR/Foreign"; printf 'gitdir: %s/.git/worktrees/x\n' "$C" > "$PR/Foreign/.git"
assert_eq "$(wt_of "$PR/Foreign" | cut -c1)" "1" "forged gitfile naming a missing entry of the project"
OUT="$(bash "$SCRIPTS/prepare.sh" --cwd "$PR/Foreign" 2>&1)"; assert_eq "$OUT" "" "prepare: forged folder, silent"
[ ! -e "$PR/Foreign/CLAUDE.local.md" ] && [ ! -e "$PR/Foreign/AGENTS.md" ] && pass || fail "links made in a forged folder"
# a worktree of another repo placed under <Projects>/<Name>/ (its project by path) gets no links either
mkdir -p "$C/vendor"; git -C "$SANDBOX/other" worktree add -q "$C/vendor/o" -b o2 || fail "other add 2"
OUT="$(bash "$SCRIPTS/prepare.sh" --cwd "$C/vendor/o" 2>&1)"
[ ! -e "$C/vendor/o/CLAUDE.local.md" ] && pass || fail "link made in a foreign worktree under the project: $OUT"
git -C "$SANDBOX/other" worktree remove --force "$C/vendor/o" 2>/dev/null

# --- the guard: forged .git files inside docs/ and .claude/ do not move the root
mkdir -p "$C/docs/forged" "$C/.claude/forged"
for f in docs/forged .claude/forged; do
  printf 'gitdir: %s/.git/worktrees/z\n' "$SANDBOX/other" > "$C/$f/.git"
  guard Write "$C/$f/../a.md" "$C"; assert_eq "$RC" "2" "forged $f/.git: a file next to it stays blocked"
  guard Write "$C/$f/a.md" "$C"; assert_eq "$RC" "2" "forged $f/.git: a file below it stays blocked"
done
GOD="$SANDBOX/other/.git/worktrees/z"; mkdir -p "$GOD"; printf '%s\n' "$C/docs/forged/.git" > "$GOD/gitdir"   # even with a back-pointer
guard Write "$C/docs/forged/a.md" "$C"; assert_eq "$RC" "2" "forged docs/.git with a back-pointer to another repo: still blocked"
guard Write "$C/.claude/hooks/x.sh" "$C"; assert_eq "$RC" "2" ".claude/hooks stays blocked"
rm -rf "$C/docs/forged" "$C/.claude/forged" "$GOD"

# --- a real worktree placed inside docs/ or .claude/ of the main folder keeps the main folder's root
WD="$C/docs/wt"; git -C "$C" worktree add -q "$WD" -b t2 || fail "add in docs"
guard Write "$WD/a.md" "$WD"; assert_eq "$RC" "2" "a worktree placed in docs/ does not unprotect docs/"
git -C "$C" worktree remove --force "$WD" 2>/dev/null
WK="$C/.claude/wt"; git -C "$C" worktree add -q "$WK" -b t3 || fail "add in .claude"
guard Write "$WK/src/a.md" "$WK"; assert_eq "$RC" "2" "a worktree placed in .claude/ does not unprotect .claude/"
git -C "$C" worktree remove --force "$WK" 2>/dev/null
# legitimate: Claude's own place, and one beside it
WCL="$C/.claude/worktrees/cw"; git -C "$C" worktree add -q "$WCL" -b t4 || fail "add claude"
guard Write "$WCL/src/a.md" "$WCL"; assert_eq "$RC" "0" "source in a .claude/worktrees worktree"
guard Write "$WCL/docs/a.md" "$WCL"; assert_eq "$RC" "2" "docs/ in a .claude/worktrees worktree"
git -C "$C" worktree remove --force "$WCL" 2>/dev/null

# --- code-root stays inside the root it prints
mkdir -p "$W/x"; assert_eq "$(bash "$SCRIPTS/lib.sh" code-root "$W/x" 2>/dev/null)" "$W" "code-root in a worktree subfolder"
assert_eq "$(bash "$SCRIPTS/lib.sh" code-root "$P" 2>/dev/null)" "$C" "code-root from the Core project folder (legit)"
# core.worktree in a hostile .git/config: git sees a toplevel that does not hold the folder asked about
mkdir -p "$SANDBOX/hostile/sub"; git init -q "$SANDBOX/hostile"; git -C "$SANDBOX/hostile" config core.worktree "$C"
OUT="$(bash "$SCRIPTS/lib.sh" code-root "$SANDBOX/hostile/sub" 2>&1)"; RC=$?
assert_eq "$RC" "1" "code-root with core.worktree elsewhere: refused"
case "$OUT" in "$C"*) fail "printed the root: $OUT" ;; *) pass ;; esac
# a forged gitfile in a plain folder
mkdir -p "$SANDBOX/forgedcr"; printf 'gitdir: %s\n' "$GD" > "$SANDBOX/forgedcr/.git"
OUT="$(cd "$SANDBOX/forgedcr" && bash "$SCRIPTS/lib.sh" code-root "$SANDBOX/forgedcr" 2>&1)"; RC=$?
assert_eq "$RC" "1" "code-root with a forged gitfile: refused"
case "$OUT" in "$W"*|"$C"*) fail "printed the root: $OUT" ;; *) pass ;; esac

# --- a link made by another run in the meantime counts as skipped, no warning
STUB="$SANDBOX/stubbin"; mkdir -p "$STUB" "$SANDBOX/lk"
cat > "$STUB/ln" <<STUBEOF
#!/bin/sh
/bin/ln "\$@"; echo "ln: File exists" >&2; exit 1
STUBEOF
chmod +x "$STUB/ln"
OUT="$(PATH="$STUB:$PATH" bash -c '. "$1"; load_settings; link_local_claude "$2" "$3"' _ "$SCRIPTS/lib.sh" "$SANDBOX/lk" "$P" 2>&1)"
case "$OUT" in skipped*) pass ;; *) fail "link made by another run: expected skipped, got: $OUT" ;; esac
# failure path: the link is not there and ln fails: exit 1, a line on stderr
printf '#!/bin/sh\necho "ln: no space" >&2; exit 1\n' > "$STUB/ln"
mkdir -p "$SANDBOX/lk2"
PATH="$STUB:$PATH" bash -c '. "$1"; load_settings; link_local_claude "$2" "$3"' _ "$SCRIPTS/lib.sh" "$SANDBOX/lk2" "$P" >/dev/null 2>"$SANDBOX/err"; RC=$?
assert_eq "$RC" "1" "ln fails and nothing is there: exit 1"
assert_contains "$SANDBOX/err" "no space"
# a link to somewhere else is still refused
ln -s /nowhere "$SANDBOX/lk2/AGENTS.md"
bash -c '. "$1"; load_settings; link_agents "$2" "$3"' _ "$SCRIPTS/lib.sh" "$SANDBOX/lk2" "$P" >/dev/null 2>&1; assert_eq "$?" "1" "link elsewhere: refused"
assert_eq "$(readlink "$SANDBOX/lk2/AGENTS.md")" "/nowhere" "link elsewhere: untouched"

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

# --- failing sync, translated: no English sentence in ru, no host-specific advice, one prefix
mkdir -p "$SANDBOX/foreign-tools"; : > "$SANDBOX/foreign-tools/mine.txt"
for L in en ru; do
  OUT="$(CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=$L COREKIT_HOST=codex COREDEV_TOOLS="$SANDBOX/foreign-tools" bash "$SCRIPTS/prepare.sh" --part tools 2>&1)"
  echo "$OUT" | grep -qF "$SANDBOX/foreign-tools" && pass || fail "$L: folder not named: $OUT"
  case "$OUT" in *"Claude Code"*) fail "$L: host named: $OUT" ;; *) pass ;; esac
  assert_eq "$(printf '%s' "$OUT" | grep -o 'corecrew:' | wc -l | tr -d ' ')" "1" "$L: one corecrew: prefix"
  [ "$L" = ru ] && { case "$OUT" in *"not a corecrew"*|*"was not replaced"*|*"Move it away"*|*"tools folder"*) fail "ru output has English: $OUT" ;; *) pass ;; esac; }
done
case "$OUT" in *"не папка инструментов"*) pass ;; *) fail "ru text: $OUT" ;; esac
assert_eq "$(ls "$SANDBOX/foreign-tools")" "mine.txt" "foreign folder untouched"
# the other kind: the plugin files are missing
mkdir -p "$SANDBOX/emptyroot/scripts"
OUT="$(CLAUDE_PLUGIN_ROOT="$SANDBOX/emptyroot" CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru bash "$SCRIPTS/prepare.sh" --part tools 2>&1)"
case "$OUT" in "corecrew: инструменты не обновлены: не удалось обновить "*) pass ;; *) fail "ru sync_failed: $OUT" ;; esac

# --- AGENTS.md in the Core: a translated message, not silence
printf 'x\n' > "$P/AGENTS.md"; rm -f "$C/AGENTS.md"
for L in en ru; do
  OUT="$(CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=$L bash "$SCRIPTS/prepare.sh" --part project --cwd "$C" 2>&1)"
  echo "$OUT" | grep -qF "$P/AGENTS.md" && pass || fail "$L: AGENTS.md in the Core not named: $OUT"
done
case "$OUT" in *"перенесите"*) pass ;; *) fail "ru AGENTS.md text: $OUT" ;; esac
[ ! -e "$C/AGENTS.md" ] && pass || fail "link made over the Core's AGENTS.md"
rm -f "$P/AGENTS.md"
finish
