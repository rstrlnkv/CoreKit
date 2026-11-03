#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
bash "$SKILL/scripts/scaffold.sh" --name save-app >/dev/null
P="$CORE_DIR/save-app"; C="$P/code"; SAVE="$CORE_DIR/bin/save"; UNDO="$CORE_DIR/bin/undo-step"
assert_file "$SAVE"; assert_file "$UNDO"; assert_file "$CORE_DIR/bin/install-hooks"
assert_file "$CORE_DIR/hooks/pre-commit-code"
step_ids() { git -C "$1" log --format=%B | sed -n 's/^Step-Id: //p'; }
cnt() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }

# first save: both repos get one commit with the same Step-Id; hooks get installed
(cd "$C" && bash "$SAVE" "Initial scaffold") >/dev/null 2>&1
assert_file "$C/.git/hooks/pre-commit"
a=$(step_ids "$C" | head -1); b=$(step_ids "$CORE_DIR" | head -1)
[ -n "$a" ] && pass || fail "no Step-Id in code"; assert_eq "$a" "$b" "Step-Id mismatch"

# changes in both repos
sleep 1; echo "v1" > "$C/app.txt"; echo "feature" > "$P/docs/features/f.md"
nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Add feature") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "saved code"; assert_contains "$SANDBOX/out" "saved docs"
assert_eq "$(cnt "$C")" "$((nc+1))"; assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Add feature"

# only docs changed -> one commit
sleep 1; echo "more" >> "$P/docs/features/f.md"; nc=$(cnt "$C")
(cd "$C" && bash "$SAVE" "Docs only") >/dev/null 2>&1
assert_eq "$(cnt "$C")" "$nc" "code got an empty commit"

# nothing to save
nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Nothing") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "nothing to save"
assert_eq "$(cnt "$C")" "$nc"; assert_eq "$(cnt "$CORE_DIR")" "$nd"

# Core commit touches only this project's folder (other project's changes stay uncommitted)
mkdir -p "$CORE_DIR/other"; echo x > "$CORE_DIR/other/x.md"
sleep 1; echo "v2" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "Only mine") >/dev/null 2>&1
files=$(git -C "$CORE_DIR" show --name-only --format= HEAD)
echo "$files" | grep -vE '^(save-app/|PROJECTS.md$|README.md$|.gitignore$|bin/|hooks/)' | grep -q . && fail "Core commit touched: $files" || pass
git -C "$CORE_DIR" log --format= --name-only | grep -qx 'PROJECTS.md' && pass || fail "PROJECTS.md never committed"
git -C "$CORE_DIR" status --porcelain | grep -q 'other/' && pass || fail "other project's file was committed"

# save from a worktree commits the worktree branch
git -C "$C" worktree add -q .claude/worktrees/w1 -b w1 2>/dev/null
W="$C/.claude/worktrees/w1"; echo "wt" > "$W/wt.txt"
(cd "$W" && bash "$SAVE" "From worktree") >/dev/null 2>&1
assert_eq "$(git -C "$W" log -1 --format=%s)" "From worktree"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Only mine" "main branch changed by worktree save"

# undo last step (Only mine): code file back to v1, history grows
nc=$(cnt "$C")
(cd "$C" && bash "$UNDO") > "$SANDBOX/out" 2>&1
assert_eq "$(cat "$C/app.txt")" "v1" "undo did not restore code"
assert_eq "$(cnt "$C")" "$((nc+1))" "undo should add a revert commit"
# undo again: reverts the previous step (Docs only touched docs only) -> code unchanged, docs reverted
(cd "$C" && bash "$UNDO") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "docs"
assert_eq "$(cat "$P/docs/features/f.md")" "feature" "undo did not restore docs"
assert_not_contains "$SANDBOX/out" "reverted code"

# save restores a missing code pre-push hook (protection layer 4)
rm -f "$C/.git/hooks/pre-push"
sleep 1; echo "hook" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "Restore hook") >/dev/null 2>&1
[ -x "$C/.git/hooks/pre-push" ] && pass || fail "save did not restore code pre-push hook"
assert_contains "$C/.git/hooks/pre-push" "new-project hook"
# save restores a missing blocked-patterns file (hooks block every commit without it)
rm -f "$C/.git/hooks/blocked-patterns"
sleep 1; echo "patterns" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "Restore patterns") >/dev/null 2>&1
assert_file "$C/.git/hooks/blocked-patterns"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Restore patterns" "save failed without blocked-patterns"

# --push pushes both to their remotes
git init -q --bare "$SANDBOX/code.git"; git -C "$C" remote add origin "$SANDBOX/code.git"
git init -q --bare "$SANDBOX/core.git"; git -C "$CORE_DIR" remote add origin "$SANDBOX/core.git"
printf '#!/bin/sh\n# new-project hook (test no-op)\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"  # privacy hook needs GitHub; tested in test_hooks
sleep 1; echo "v3" > "$C/app.txt"; echo y >> "$P/docs/brief.md"
(cd "$C" && bash "$SAVE" "Publish" --push) > "$SANDBOX/out" 2>&1
assert_eq "$(git -C "$SANDBOX/code.git" log -1 --format=%s main 2>/dev/null)" "Publish"
assert_eq "$(git -C "$SANDBOX/core.git" log -1 --format=%s main 2>/dev/null)" "Publish"
finish
