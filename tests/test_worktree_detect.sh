#!/usr/bin/env bash
# lib.sh worktree_of / project_of / code_root_of and the hooks in a git worktree that lives anywhere
# (Codex puts worktrees outside <Projects>), with real `git worktree add`.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
setup_core
bash "$SKILL/scripts/scaffold.sh" --name wtapp >/dev/null
PR="$(dirname "$CORE_DIR")"; C="$PR/wtapp"
git -C "$C" commit -q --allow-empty -m init
mkdir -p "$SANDBOX/elsewhere"

# proj, wt_of and guard: tests/lib-hook.sh

# --- a worktree outside Projects (the Codex place)
W="$SANDBOX/codex-home/worktrees/ab12/wtapp"
git -C "$C" worktree add -q "$W" -b b1 || fail "worktree add"
assert_eq "$(proj "$W")" "wtapp" "project_of in a worktree outside Projects"
assert_eq "$(proj "$W/src/not/yet")" "wtapp" "project_of for a path that does not exist yet"
assert_eq "$(wt_of "$W")" "0 $W $C" "worktree_of root and main"
guard Write "$W/docs/a.md" "$W"; assert_eq "$RC" "2" "guard-code blocks docs/a.md in the worktree"
case "$ERR" in *"$W/docs/a.md"*) pass ;; *) fail "message names the worktree path: $ERR" ;; esac
guard Write "$W/CLAUDE.md" "$W"; assert_eq "$RC" "2" "guard-code blocks CLAUDE.md in the worktree"
guard Write "$W/sub/AGENTS.md" "$W"; assert_eq "$RC" "2" "guard-code blocks sub/AGENTS.md in the worktree"
guard Write "$W/src/a.swift" "$W"; assert_eq "$RC" "0" "guard-code lets source through in the worktree"
guard Write "$W/.claude/settings.local.json" "$W"; assert_eq "$RC" "0" "settings.local.json allowed in the worktree"
guard Write "$C/docs/a.md" "$C"; assert_eq "$RC" "2" "main folder still guarded"
# the Bash path of guard-code
printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x > docs/a.md"}}' "$W" | bash "$HOOKS/guard-code.sh" >/dev/null 2>&1
assert_eq "$?" "2" "guard-code blocks a redirect into docs/ from the worktree cwd"
# guard-secrets
echo "FAKE=1" > "$W/.env"
printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat .env"}}' "$W" | bash "$HOOKS/guard-secrets.sh" >/dev/null 2>&1
assert_eq "$?" "2" "guard-secrets blocks cat .env in the worktree"
# stop-remind: dirty code in the worktree
echo x > "$W/new.txt"
printf '{"session_id":"x","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$W" | bash "$HOOKS/stop-remind.sh" >/dev/null 2>&1
assert_eq "$?" "2" "stop-remind is active in the worktree"
rm -f "$W/new.txt" "$W/.env"
# one-suite: a run is on, a test command is refused in the worktree
FAKE="onesuite-fake-run-$$"; fake "$W" "$FAKE"; dummy=$FAKE_PID
printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test","description":"r"}}' "$W" \
  | ONE_SUITE_PROCS="$FAKE" ONE_SUITE_WAIT=0 ONE_SUITE_GRACE=0 ONE_SUITE_TURN="$SANDBOX/turn" bash "$HOOKS/one-suite.sh" >/dev/null 2>&1
assert_eq "$?" "2" "one-suite is active in the worktree"
stop "$dummy"

# --- Claude's own place, unchanged
CW="$C/.claude/worktrees/w1"
git -C "$C" worktree add -q "$CW" -b b2 || fail "claude worktree add"
assert_eq "$(proj "$CW")" "wtapp" "project_of in .claude/worktrees"
guard Write "$CW/docs/a.md" "$CW"; assert_eq "$RC" "2" "guard-code blocks docs/ in a .claude worktree"
guard Write "$CW/src/a.swift" "$CW"; assert_eq "$RC" "0" "source passes in a .claude worktree"
# --- a sibling in Projects
SW="$PR/wtapp-wt"
git -C "$C" worktree add -q "$SW" -b b3 || fail "sibling worktree add"
assert_eq "$(proj "$SW")" "wtapp" "project_of in a sibling worktree"
guard Write "$SW/docs/a.md" "$SW"; assert_eq "$RC" "2" "guard-code blocks docs/ in a sibling worktree"
guard Write "$SW/src/a.swift" "$SW"; assert_eq "$RC" "0" "source passes in a sibling worktree"
# --- a path with spaces
SPW="$SANDBOX/with space/wtapp"
git -C "$C" worktree add -q "$SPW" -b b4 || fail "space worktree add"
assert_eq "$(wt_of "$SPW/x")" "0 $SPW $C" "worktree_of with spaces"
guard Write "$SPW/docs/a.md" "$SPW"; assert_eq "$RC" "2" "guard-code blocks docs/ in a worktree with spaces"

# --- inert: a plain clone outside Projects, a submodule, dangling, unreadable, forged
git clone -q "$C" "$SANDBOX/clone/wtapp"
proj "$SANDBOX/clone/wtapp" >/dev/null; assert_eq "$?" "1" "a normal clone outside Projects is not a project"
guard Write "$SANDBOX/clone/wtapp/docs/a.md" "$SANDBOX/clone/wtapp"; assert_eq "$RC" "0" "guard-code inert in a plain clone"
assert_eq "$(wt_of "$SANDBOX/clone/wtapp")" "1  " "worktree_of: .git directory"
mkdir -p "$SANDBOX/sub1" "$SANDBOX/sub2" "$SANDBOX/sub3" "$SANDBOX/sub4"
echo "gitdir: $C/.git/modules/lib" > "$SANDBOX/sub1/.git"
echo "gitdir: $SANDBOX/nothing/here" > "$SANDBOX/sub2/.git"
echo "gitdir: $SANDBOX/nowhere/.git/worktrees/x" > "$SANDBOX/sub3/.git"
echo "gitdir: $C/.git/worktrees/b1" > "$SANDBOX/sub4/.git"; chmod 000 "$SANDBOX/sub4/.git"
for d in sub1 sub2 sub3 sub4; do
  proj "$SANDBOX/$d" >/dev/null; assert_eq "$?" "1" "$d: inert"
  assert_eq "$(wt_of "$SANDBOX/$d")" "1  " "$d: worktree_of fails cleanly"
  guard Write "$SANDBOX/$d/docs/a.md" "$SANDBOX/$d"; assert_eq "$RC" "0" "$d: guard-code passes"
done
# a worktree whose .git file is relative
assert_eq "$(wt_of "$SANDBOX/does/not/exist")" "1  " "worktree_of: missing path"
assert_eq "$(wt_of "/")" "1  " "worktree_of: /"
assert_eq "$(wt_of "")" "1  " "worktree_of: empty path"
# an existing worktree whose main is gone is inert
git clone -q "$C" "$SANDBOX/gone-main/wtapp" && git -C "$SANDBOX/gone-main/wtapp" commit -q --allow-empty -m i
git -C "$SANDBOX/gone-main/wtapp" worktree add -q "$SANDBOX/gone-wt/wtapp" -b g1
mv "$SANDBOX/gone-main" "$SANDBOX/gone-main.moved"
proj "$SANDBOX/gone-wt/wtapp" >/dev/null; assert_eq "$?" "1" "worktree of a missing main folder is inert"
# a main folder that is not a project: inert
git init -q "$SANDBOX/other/plain" && git -C "$SANDBOX/other/plain" commit -q --allow-empty -m i
git -C "$SANDBOX/other/plain" worktree add -q "$SANDBOX/other-wt/plain" -b o1
proj "$SANDBOX/other-wt/plain" >/dev/null; assert_eq "$?" "1" "worktree of a non-project is inert"

# --- lib.sh code-root
mkdir -p "$W/src"
assert_eq "$(bash "$SCRIPTS/lib.sh" code-root "$W/src" 2>/dev/null)" "$W" "code-root from a worktree subfolder"
assert_eq "$(bash "$SCRIPTS/lib.sh" code-root "$C" 2>/dev/null)" "$C" "code-root in the main folder"
assert_eq "$(bash "$SCRIPTS/lib.sh" code-root "$CW" 2>/dev/null)" "$CW" "code-root in a .claude worktree"
bash "$SCRIPTS/lib.sh" code-root "$SANDBOX/clone/wtapp" >/dev/null 2>&1; assert_eq "$?" "1" "code-root of a plain clone fails"
bash "$SCRIPTS/lib.sh" code-root "$SANDBOX/elsewhere" >/dev/null 2>&1; assert_eq "$?" "1" "code-root outside a repo fails"
finish
