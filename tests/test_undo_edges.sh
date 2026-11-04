#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
scaffold_old edge-app
C="$CORE_DIR/edge-app/code"; SAVE="$SCRIPTS/save"; UNDO="$SCRIPTS/undo-step"
cd "$C" || exit 1
bash "$SAVE" "Scaffold" >/dev/null
# two saves within the same second get different Step-Ids
echo a > a.txt; bash "$SAVE" "Step A" >/dev/null
echo b > b.txt; bash "$SAVE" "Step B" >/dev/null
ids=$(git log --format=%B | sed -n 's/^Step-Id: //p' | sort -u | wc -l | tr -d ' ')
assert_eq "$ids" "3" "Step-Ids must be unique"
bash "$UNDO" >/dev/null
assert_file "$C/a.txt"; assert_no_file "$C/b.txt"
# the very first step (project creation) cannot be undone; shared Core files survive
bash "$UNDO" >/dev/null; assert_no_file "$C/a.txt"
assert_exit 1 bash "$UNDO"
echo "$OUT" | grep -qi 'first step' && pass || fail "no first-step message"
assert_file "$SAVE"; assert_file "$CORE_DIR/edge-app/CLAUDE.md"

# new layout: undo-step from a worktree under <Projects>/Bar reverts the main checkout's step
B="$SANDBOX/Projects/Bar"; mkdir -p "$B" "$CORE_DIR/bar"; echo "# bar" > "$CORE_DIR/bar/CLAUDE.md"
git -C "$B" init -q; cp "$ROOT/skills/new-project/templates/code/gitignore-common" "$B/.gitignore"
ln -s "$CORE_DIR/bar/CLAUDE.md" "$B/CLAUDE.local.md"
cd "$B" || exit 1
echo 1 > one.txt; bash "$SAVE" "Bar first" >/dev/null
echo 2 > two.txt; bash "$SAVE" "Bar second" >/dev/null
git worktree add -q .claude/worktrees/w -b w 2>/dev/null
(cd "$B/.claude/worktrees/w" && bash "$UNDO") >/dev/null 2>&1
assert_no_file "$B/.claude/worktrees/w/two.txt"; assert_file "$B/.claude/worktrees/w/one.txt"

finish
