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
git -C "$B" init -q; cp "$PLUGIN/skills/new-project/templates/code/gitignore-common" "$B/.gitignore"
ln -s "$CORE_DIR/bar/CLAUDE.md" "$B/CLAUDE.local.md"
cd "$B" || exit 1
echo 1 > one.txt; bash "$SAVE" "Bar first" >/dev/null
echo 2 > two.txt; bash "$SAVE" "Bar second" >/dev/null
git worktree add -q .claude/worktrees/w -b w 2>/dev/null
(cd "$B/.claude/worktrees/w" && bash "$UNDO") >/dev/null 2>&1
assert_no_file "$B/.claude/worktrees/w/two.txt"; assert_file "$B/.claude/worktrees/w/one.txt"

# --- the Core is shared: undo touches only the step's own paths, and finds its shared Core files ---
scaffold_old u-app; P="$CORE_DIR/u-app"; C="$P/code"; K="$CORE_DIR/knowledge"
cd "$C" || exit 1
bash "$SAVE" init >/dev/null 2>&1
step_id() { git -C "$1" log -1 --format=%B | sed -n 's/^Step-Id: //p'; }
state() { git -C "$C" status --porcelain; git -C "$CORE_DIR" status --porcelain; tree_sum "$C"; tree_sum "$CORE_DIR"; }
no_revert_left() { local r; for r in "$C" "$CORE_DIR"; do
  git -C "$r" rev-parse -q --verify REVERT_HEAD >/dev/null && fail "revert left in progress in $r" || pass; done; }
echo two > "$C/two.txt"; echo two > "$P/docs/f.md"; bash "$SAVE" two >/dev/null 2>&1; TWO=$(step_id "$C")
echo three > "$P/docs/f.md"; bash "$SAVE" three >/dev/null 2>&1
# another project's work in the Core: a staged file, an untracked one, an unsaved edit
mkdir -p "$CORE_DIR/other"; echo notes > "$CORE_DIR/other/notes.md"; git -C "$CORE_DIR" add other/notes.md
echo loose > "$CORE_DIR/other/loose.md"; echo edited >> "$CORE_DIR/edge-app/CLAUDE.md"

# failure path: a conflicting undo (code revert applied, Core revert conflicts) leaves both repos
# exactly as they were, the other project's staged file included
before=$(state)
assert_exit 1 bash "$UNDO" "$TWO"
echo "$OUT" | grep -q 'conflicts' && pass || fail "no conflict message: $OUT"
assert_eq "$(state)" "$before" "a failed undo changed the repos"
assert_eq "$(git -C "$CORE_DIR" diff --cached --name-only)" "other/notes.md" "another project's staged file lost"
no_revert_left

# an unrelated staged Core file does not block the undo and is not swept into the Undo commit
[ -f "$CORE_DIR/other/notes.md" ] || echo notes > "$CORE_DIR/other/notes.md"
git -C "$CORE_DIR" add other/notes.md
assert_exit 0 bash "$UNDO"
assert_eq "$(cat "$P/docs/f.md")" "two" "step three not undone"
git -C "$CORE_DIR" log -1 --format=%s | grep -q '^Undo step' && pass || fail "no Undo commit in the Core"
git -C "$CORE_DIR" show --name-only --format= HEAD | grep -q '^other/' && fail "unrelated staged file in the Undo commit" || pass
assert_eq "$(git -C "$CORE_DIR" diff --cached --name-only)" "other/notes.md" "unrelated staged file not left staged"
assert_file "$CORE_DIR/other/loose.md"; assert_contains "$CORE_DIR/edge-app/CLAUDE.md" edited
no_revert_left

# unsaved changes in a shared Core file the step could include block the undo
echo unsaved > "$K/unsaved.md"
before=$(state)
assert_exit 1 bash "$UNDO"
echo "$OUT" | grep -q 'Unsaved changes' && pass || fail "no unsaved-changes message: $OUT"
assert_eq "$(state)" "$before" "a refused undo changed the repos"
rm -f "$K/unsaved.md"

# a step with code and a shared Core file (knowledge/) is undone in full
echo k > "$C/k.txt"; echo note > "$K/git-undo.md"; bash "$SAVE" "with knowledge" >/dev/null 2>&1
assert_exit 0 bash "$UNDO"
assert_no_file "$C/k.txt"; assert_no_file "$K/git-undo.md"

# another project's step (its folder plus a shared file) is never undone from this project
(cd "$CORE_DIR/edge-app/code" && echo e > "$K/edge.md" && bash "$SAVE" "edge knowledge") >/dev/null 2>&1
EDGE=$(step_id "$CORE_DIR")
assert_exit 0 bash "$UNDO" "$EDGE"
assert_file "$K/edge.md"; assert_contains "$CORE_DIR/edge-app/CLAUDE.md" edited

# two projects that save in the same second get different Step-Ids (a fake date pins the clock)
FD="$SANDBOX/fakedate"; mkdir -p "$FD"
# (a past time: a step saved later in the same real second must still sort after these two)
printf '#!/bin/sh\necho 20000101-000000\n' > "$FD/date"; chmod +x "$FD/date"
echo s1 > "$C/same1.txt"; PATH="$FD:$PATH" bash "$SAVE" "same second A" >/dev/null 2>&1
SA=$(git -C "$C" log -1 --format=%B | sed -n 's/^Step-Id: //p')
(cd "$CORE_DIR/edge-app/code" && echo s2 > same2.txt && PATH="$FD:$PATH" bash "$SAVE" "same second B") >/dev/null 2>&1
SB=$(git -C "$CORE_DIR/edge-app/code" log -1 --format=%B | sed -n 's/^Step-Id: //p')
[ -n "$SA" ] && [ -n "$SB" ] && [ "$SA" != "$SB" ] && pass || fail "same-second saves share a Step-Id: '$SA' '$SB'"

# another project's step whose Core commit touches only shared files (its code + knowledge/): plain
# undo-step here still undoes this project's own last step, the other step's Step-Id changes nothing,
# and the other project undoes its step in full
E="$CORE_DIR/edge-app/code"
echo a1 > "$C/a1.txt"; bash "$SAVE" "A step" >/dev/null 2>&1
(cd "$E" && echo b1 > b1.txt && echo b > "$K/b.md" && bash "$SAVE" "B step") >/dev/null 2>&1
BID=$(step_id "$CORE_DIR")
assert_eq "$(git -C "$CORE_DIR" show --name-only --format= HEAD)" "knowledge/b.md" "B's Core commit is not shared-only"
before=$(state)
assert_exit 0 bash "$UNDO" "$BID"
assert_eq "$(state)" "$before" "another project's shared-only step was touched"
assert_exit 0 bash "$UNDO"
assert_no_file "$C/a1.txt"; assert_file "$K/b.md"; assert_file "$E/b1.txt"
(cd "$E" && bash "$UNDO") >/dev/null 2>&1
assert_no_file "$E/b1.txt"; assert_no_file "$K/b.md"

# a step that changed only shared Core files and no code: its Core commit's "Project:" trailer makes it
# this project's, so plain undo-step undoes it; another project never takes it; it is undone once only
echo s > "$K/shared-only.md"; bash "$SAVE" "shared only" >/dev/null 2>&1
SO=$(step_id "$CORE_DIR")
assert_eq "$(git -C "$CORE_DIR" show --name-only --format= HEAD)" "knowledge/shared-only.md" "the step's Core commit is not shared-only"
[ "$(step_id "$C")" != "$SO" ] && pass || fail "the shared-only step made a code commit"
(cd "$E" && bash "$UNDO" "$SO") >/dev/null 2>&1
assert_file "$K/shared-only.md"
before_c=$(git -C "$C" rev-parse HEAD)
assert_exit 0 bash "$UNDO"
assert_no_file "$K/shared-only.md"
assert_eq "$(git -C "$C" rev-parse HEAD)" "$before_c" "undo of a shared-only step changed the code repo"
git -C "$CORE_DIR" log -1 --format=%B | grep -qxF "Undo-Of: $SO" && pass || fail "the shared-only step was not the one undone"
git -C "$CORE_DIR" log -1 --format=%B | grep -qxF "Project: u-app" && pass || fail "the Undo commit lacks the Project trailer"
assert_exit 0 bash "$UNDO" "$SO"
echo "$OUT" | grep -q 'already undone' && pass || fail "a shared-only step undone twice: $OUT"

# a later step renamed a file the step changed: the undo changes it under its new name and commits it
echo x > "$C/r.txt"; bash "$SAVE" r1 >/dev/null 2>&1
echo y > "$C/r.txt"; echo o > "$C/o.txt"; bash "$SAVE" r2 >/dev/null 2>&1; R2=$(step_id "$C")
git -C "$C" mv r.txt s.txt; bash "$SAVE" r3 >/dev/null 2>&1
assert_exit 0 bash "$UNDO" "$R2"
assert_eq "$(git -C "$C" status --porcelain)" "" "the undo left a renamed file uncommitted"
assert_eq "$(cat "$C/s.txt")" "x" "renamed file not undone"; assert_no_file "$C/o.txt"

# failure path with a renamed file: a conflicting undo puts the renamed file back too
echo x > "$C/r2.txt"; echo q1 > "$C/q.txt"; bash "$SAVE" c1 >/dev/null 2>&1
echo y > "$C/r2.txt"; echo q2 > "$C/q.txt"; bash "$SAVE" c2 >/dev/null 2>&1; C2=$(step_id "$C")
git -C "$C" mv r2.txt s2.txt; echo q3 > "$C/q.txt"; bash "$SAVE" c3 >/dev/null 2>&1
before=$(state)
assert_exit 1 bash "$UNDO" "$C2"
assert_eq "$(state)" "$before" "a failed undo changed a renamed file"
no_revert_left

# failure path: folders the revert created for a file it brought back are removed again
mkdir -p "$C/gone/deep"; echo 1 > "$C/gone/deep/only.txt"; echo h1 > "$C/h.txt"; bash "$SAVE" d1 >/dev/null 2>&1
rm -r "$C/gone"; echo h2 > "$C/h.txt"; bash "$SAVE" d2 >/dev/null 2>&1; D2=$(step_id "$C")
echo h3 > "$C/h.txt"; bash "$SAVE" d3 >/dev/null 2>&1
assert_exit 1 bash "$UNDO" "$D2"
assert_no_file "$C/gone"; no_revert_left

# failure path with a modify/delete conflict: the file the revert brought back is removed again
echo 1 > "$C/g.txt"; bash "$SAVE" g1 >/dev/null 2>&1
echo 2 > "$C/g.txt"; bash "$SAVE" g2 >/dev/null 2>&1; G2=$(step_id "$C")
rm "$C/g.txt"; bash "$SAVE" g3 >/dev/null 2>&1
before=$(state)
assert_exit 1 bash "$UNDO" "$G2"
assert_eq "$(state)" "$before" "a failed modify/delete undo changed the repos"
assert_no_file "$C/g.txt"; no_revert_left

# an ignored local file where the undo would bring a saved file back is never overwritten
echo saved > "$C/keep.me"; bash "$SAVE" k1 >/dev/null 2>&1
rm "$C/keep.me"; bash "$SAVE" k2 >/dev/null 2>&1
echo keep.me >> "$C/.git/info/exclude"; echo local > "$C/keep.me"
assert_exit 1 bash "$UNDO"
assert_eq "$(cat "$C/keep.me")" "local" "ignored local file overwritten"
no_revert_left

# an old shared-only Core commit has no Project trailer, only a Step-Id of this project's code step. A
# "Project: other" line in its message body (not in the trailer block) does not name a project: the
# Step-Id rule still makes the commit this project's, and the undo reverts it with the code commit.
OLD="20000102-000000-01-abc1"
echo old > "$C/old.txt"; git -C "$C" add old.txt; git -C "$C" commit -q -m "old step" -m "Step-Id: $OLD"
echo old > "$K/old-step.md"; git -C "$CORE_DIR" add knowledge/old-step.md
git -C "$CORE_DIR" commit -q -m "old step" -m "$(printf 'Project: other\nwas a folder name in an old message.')" \
  -m "Step-Id: $OLD" -- knowledge/old-step.md
assert_eq "$(git -C "$CORE_DIR" log -1 --format='%(trailers:key=Project,valueonly)')" "" "the old commit has a Project trailer"
assert_exit 0 bash "$UNDO" "$OLD"
assert_no_file "$C/old.txt"
assert_no_file "$K/old-step.md"

finish
