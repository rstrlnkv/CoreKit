#!/usr/bin/env bash
# Regression tests for the final-review findings (C1, I1–I5).
source "$(dirname "$0")/lib.sh"

# C1: undo-step must only touch the current project's steps
new_sandbox; setup_core; sync_tools; S="$SKILL/scripts/scaffold.sh"
scaffold_old app-a; scaffold_old app-b
SAVE="$SCRIPTS/save"; UNDO="$SCRIPTS/undo-step"
(cd "$CORE_DIR/app-a/code" && bash "$SAVE" init) >/dev/null 2>&1
(cd "$CORE_DIR/app-b/code" && bash "$SAVE" init) >/dev/null 2>&1
echo a1 > "$CORE_DIR/app-a/docs/a.md"; (cd "$CORE_DIR/app-a/code" && bash "$SAVE" a1) >/dev/null 2>&1
echo b1 > "$CORE_DIR/app-b/docs/b.md"; (cd "$CORE_DIR/app-b/code" && bash "$SAVE" b1) >/dev/null 2>&1
(cd "$CORE_DIR/app-a/code" && bash "$UNDO") >/dev/null 2>&1
assert_no_file "$CORE_DIR/app-a/docs/a.md"; assert_file "$CORE_DIR/app-b/docs/b.md"

# I1: non-ASCII paths, case variants, missing patterns file
new_sandbox; setup_core; sync_tools; scaffold_old hk-app; C="$CORE_DIR/hk-app/code"
bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/hk-app" >/dev/null
blocked() { mkdir -p "$C/$(dirname "$1")"; echo x > "$C/$1"; git -C "$C" add -f -- "$1"
  git -C "$C" commit -q -m t >/dev/null 2>&1; local rc=$?; git -C "$C" reset -q; rm -f "$C/$1"; [ $rc -ne 0 ]; }
blocked "папка/CLAUDE.md" && pass || fail "non-ASCII path CLAUDE.md allowed"
blocked "é/.env" && pass || fail "non-ASCII .env allowed"
blocked "Claude.md" && pass || fail "Claude.md allowed"
blocked ".ENV" && pass || fail ".ENV allowed"
mv "$COREDEV_TOOLS/git-hooks/blocked-patterns" "$SANDBOX/bp"
blocked "src/ok.txt" && pass || fail "missing patterns file must fail closed"
mv "$SANDBOX/bp" "$COREDEV_TOOLS/git-hooks/blocked-patterns"

# I2: undo from a worktree reverts the worktree commit
new_sandbox; setup_core; sync_tools; scaffold_old wt-app; C="$CORE_DIR/wt-app/code"
(cd "$C" && bash "$SCRIPTS/save" init) >/dev/null 2>&1
git -C "$C" worktree add -q .claude/worktrees/w -b w 2>/dev/null; W="$C/.claude/worktrees/w"
echo w > "$W/w.txt"; (cd "$W" && bash "$SCRIPTS/save" "wt step") >/dev/null 2>&1
(cd "$W" && bash "$SCRIPTS/undo-step") >/dev/null 2>&1
assert_no_file "$W/w.txt"

# I3: a conflict leaves neither repo half-undone
new_sandbox; setup_core; sync_tools; scaffold_old cf-app; P="$CORE_DIR/cf-app"; C="$P/code"
(cd "$C" && bash "$SCRIPTS/save" init) >/dev/null 2>&1
echo one > "$C/x.txt"; echo one > "$P/docs/f.md"; (cd "$C" && bash "$SCRIPTS/save" X) >/dev/null 2>&1
X=$(git -C "$C" log -1 --format=%B | sed -n 's/^Step-Id: //p')
echo two > "$P/docs/f.md"; (cd "$C" && bash "$SCRIPTS/save" Y) >/dev/null 2>&1
(cd "$C" && bash "$SCRIPTS/undo-step" "$X") >/dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "conflicting undo should fail"
git -C "$C" log --format=%B | grep -q "^Undo-Of: $X" && fail "code half-undone" || pass
assert_eq "$(git -C "$C" status --porcelain)" "" "code left dirty"
assert_eq "$(git -C "$CORE_DIR" status --porcelain -- cf-app)" "" "docs left dirty"

# I4: paths with spaces
SANDBOX="$(mktemp -d)"; export CORE_DIR="$SANDBOX/my projects/Core"
export CLAUDE_PLUGIN_DATA="$SANDBOX/plugin data"; export COREDEV_TOOLS="$CLAUDE_PLUGIN_DATA/tools"; sync_tools; setup_core
scaffold_old sp-app; C="$CORE_DIR/sp-app/code"
(cd "$C" && bash "$SCRIPTS/save" init) >/dev/null 2>&1
echo s > "$C/s.txt"; (cd "$C" && bash "$SCRIPTS/save" s) >/dev/null 2>&1
(cd "$C" && bash "$SCRIPTS/undo-step") >/dev/null 2>&1
assert_no_file "$C/s.txt"

# I5: merge-generated keeps nested .gitignore files
new_sandbox; setup_core; scaffold_old mg-app; G="$SANDBOX/g"; mkdir -p "$G/android"
printf 'key.properties\n' > "$G/android/.gitignore"; echo k > "$G/android/key.properties"
bash "$SKILL/scripts/merge-generated.sh" "$G" "$CORE_DIR/mg-app/code" >/dev/null
assert_file "$CORE_DIR/mg-app/code/android/.gitignore"
git -C "$CORE_DIR/mg-app/code" status --porcelain | grep -q key.properties && fail "key.properties not ignored" || pass
finish
