#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
bash "$SKILL/scripts/scaffold.sh" --name save-app >/dev/null
P="$CORE_DIR/save-app"; C="$P/code"; SAVE="$SCRIPTS/save"; UNDO="$SCRIPTS/undo-step"
assert_file "$SAVE"; assert_file "$UNDO"; assert_no_file "$CORE_DIR/bin"; assert_no_file "$CORE_DIR/hooks"
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
assert_contains "$C/.git/hooks/pre-push" "# corecrew hook shim"
# save restores a deleted pre-commit shim; blocked-patterns is not a hook-folder file any more
rm -f "$C/.git/hooks/pre-commit"
sleep 1; echo "patterns" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "Restore pre-commit") >/dev/null 2>&1
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_no_file "$C/.git/hooks/blocked-patterns"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Restore pre-commit" "save failed after restoring the shim"

# --push pushes both to their remotes
git init -q --bare "$SANDBOX/code.git"; git -C "$C" remote add origin "$SANDBOX/code.git"
git init -q --bare "$SANDBOX/core.git"; git -C "$CORE_DIR" remote add origin "$SANDBOX/core.git"
printf '#!/bin/sh\n# corecrew hook shim (test no-op)\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"  # privacy hook needs GitHub; tested in test_hooks
sleep 1; echo "v3" > "$C/app.txt"; echo y >> "$P/docs/brief.md"
(cd "$C" && bash "$SAVE" "Publish" --push) > "$SANDBOX/out" 2>&1
assert_eq "$(git -C "$SANDBOX/code.git" log -1 --format=%s main 2>/dev/null)" "Publish"
assert_eq "$(git -C "$SANDBOX/core.git" log -1 --format=%s main 2>/dev/null)" "Publish"
# knowledge/standards/.coredev changes ride along with the step
mkdir -p "$CORE_DIR/knowledge"; echo "symptom -> cause -> guard" > "$CORE_DIR/knowledge/engineer.md"
echo "a note" >> "$CORE_DIR/standards/README.md"; printf 'x\n' > "$CORE_DIR/session-rules.md"
sleep 1; echo "v3" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "With knowledge") >/dev/null 2>&1
files=$(git -C "$CORE_DIR" show --name-only --format= HEAD)
for f in knowledge/engineer.md standards/README.md session-rules.md; do
  echo "$files" | grep -qx "$f" && pass || fail "$f not in the step commit: $files"
done
assert_eq "$(git -C "$CORE_DIR" status --porcelain | grep -v 'other/')" "" "knowledge changes left uncommitted"
# a knowledge-only change is a step of its own
echo "more" >> "$CORE_DIR/knowledge/engineer.md"; nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Knowledge only") >/dev/null 2>&1
assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "knowledge-only change not saved"

# --no-attribution drops Co-Authored-By / Generated with lines from the message (both repos)
sleep 1; echo "v2" > "$C/app.txt"; echo "x" >> "$P/docs/features/f.md"
msg="$(printf 'Fix thing\n\nWhy it was wrong.\n\nCo-Authored-By: Someone <a@b.c>\nco-authored-by: Other <d@e.f>\n\360\237\244\226 Generated with [Claude Code](https://x)')"
(cd "$C" && bash "$SAVE" "$msg" --no-attribution) > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "saved code"
assert_eq "$(git -C "$C" log -1 --format=%B | grep -icE 'co-authored-by|generated with')" "0" "attribution left in code commit"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%B | grep -icE 'co-authored-by|generated with')" "0" "attribution left in docs commit"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Fix thing"
git -C "$C" log -1 --format=%B | grep -q 'Why it was wrong.' && pass || fail "body lost by --no-attribution"
# without the flag the message is kept as given
sleep 1; echo "v3" > "$C/app.txt"
(cd "$C" && bash "$SAVE" "$(printf 'Keep\n\nCo-Authored-By: A <a@b.c>')") >/dev/null 2>&1
assert_eq "$(git -C "$C" log -1 --format=%B | grep -ic 'co-authored-by')" "1" "message changed without the flag"

# One Core path set: `lib.sh core-paths <project>` prints what save commits (CORE_PATHS), and the
# clean-tree check written in task Start and release postcondition 7 uses it, so an uncommitted
# session-rules.md (or standards/) stops the chain instead of riding along in its commit.
LIB="$SCRIPTS/lib.sh"
CHK='git -C "<Core>" status --short -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)'
assert_contains "$ROOT/skills/task/SKILL.md" "$CHK"
assert_contains "$ROOT/skills/task/references/release.md" "$CHK"
assert_not_contains "$ROOT/skills/task/SKILL.md" 'status --short -- <project> knowledge'
cp_locate() { (cd "$C" && . "$SCRIPTS/_locate.sh" && locate && printf '%s\n' "$CORE_PATHS"); }
assert_eq "$(CORE_DIR="$CORE_DIR" bash "$LIB" core-paths save-app)" "$(cp_locate)" "core-paths differs from save's CORE_PATHS"
# the documented command, with <Core>, <scripts> and <project> filled in
run_chk() { (cd "$C" && eval "$(printf '%s' "$CHK" | sed -e "s|<Core>|$CORE_DIR|g" -e "s|<scripts>|$SCRIPTS|g" -e 's|<project>|save-app|g')"); }
assert_eq "$(run_chk | grep -v 'other/')" "" "clean Core: the check prints nothing"
echo "a new rule" >> "$CORE_DIR/session-rules.md"
run_chk | grep -qF 'session-rules.md' && pass || fail "check misses an uncommitted session-rules.md: $(run_chk)"
git -C "$CORE_DIR" checkout -q -- session-rules.md
echo "x" >> "$CORE_DIR/standards/README.md"
run_chk | grep -qF 'standards/README.md' && pass || fail "check misses an uncommitted standards/ file"
git -C "$CORE_DIR" checkout -q -- standards/README.md
# a deleted tracked file still counts (save commits the deletion; the check shows it)
rm "$CORE_DIR/session-rules.md"
CORE_DIR="$CORE_DIR" bash "$LIB" core-paths save-app | tr ' ' '\n' | grep -qx 'session-rules.md' && pass || fail "core-paths drops a deleted tracked file"
run_chk | grep -qF 'session-rules.md' && pass || fail "check misses a deleted session-rules.md"
(cd "$C" && bash "$SAVE" "Drop session rules") >/dev/null 2>&1
git -C "$CORE_DIR" show --name-only --format= HEAD | grep -qx 'session-rules.md' && pass || fail "save did not commit the deletion"
assert_eq "$(CORE_DIR="$CORE_DIR" bash "$LIB" core-paths 2>&1 >/dev/null | head -1)" "Usage: lib.sh core-paths <project>" "core-paths without a project"

# --no-attribution drops only attribution lines: "Generated with" is matched at the start of a line
# (an optional robot emoji before it), so a subject or body that says "generated with" stays.
sleep 1; echo "csv" > "$C/app.txt"
msg="$(printf 'Fix CSV generated with a wrong delimiter\n\nRows generated with the old tool had commas.\n\n  \360\237\244\226 Generated with [Claude Code](https://x)\nGENERATED WITH a tool\nCo-Authored-By: A <a@b.c>')"
(cd "$C" && bash "$SAVE" "$msg" --no-attribution) >/dev/null 2>&1
assert_eq "$(git -C "$C" log -1 --format=%s)" "Fix CSV generated with a wrong delimiter" "subject with 'generated with' dropped"
git -C "$C" log -1 --format=%B | grep -qxF 'Rows generated with the old tool had commas.' && pass || fail "body line with 'generated with' dropped"
assert_eq "$(git -C "$C" log -1 --format=%B | grep -ciE 'generated with \[claude|generated with a tool|co-authored-by')" "0" "attribution lines left"

# --- new layout: code in <Projects>/Foo beside the Core, docs in <Core>/foo, CLAUDE.local.md symlink
F="$SANDBOX/Projects/Foo"; mkdir -p "$F" "$CORE_DIR/foo"
echo "# foo" > "$CORE_DIR/foo/CLAUDE.md"
git -C "$F" init -q; cp "$ROOT/skills/new-project/templates/code/gitignore-common" "$F/.gitignore"
ln -s "$CORE_DIR/foo/CLAUDE.md" "$F/CLAUDE.local.md"
for h in pre-commit pre-push; do printf '#!/bin/sh\nexit 0\n' > "$F/.git/hooks/$h"; chmod +x "$F/.git/hooks/$h"; done
[ -x "$CORE_DIR/.git/hooks/pre-push" ] || { printf '#!/bin/sh\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"; chmod +x "$CORE_DIR/.git/hooks/pre-push"; }
echo "n1" > "$F/n.txt"; echo "doc1" > "$CORE_DIR/foo/d.md"
(cd "$F" && bash "$SAVE" "New layout step") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "saved code"; assert_contains "$SANDBOX/out" "saved docs"
a=$(step_ids "$F" | head -1); b=$(step_ids "$CORE_DIR" | head -1)
[ -n "$a" ] && pass || fail "new layout: no Step-Id in code"; assert_eq "$a" "$b" "new layout: Step-Id mismatch"
git -C "$F" ls-files | grep -q 'CLAUDE.local.md' && fail "symlink committed to code" || pass

# worktree under Projects/Foo/.claude/worktrees
git -C "$F" worktree add -q .claude/worktrees/w -b w 2>/dev/null
FW="$F/.claude/worktrees/w"; echo wt > "$FW/wt.txt"
(cd "$FW" && bash "$SAVE" "New layout worktree") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "saved code"
assert_eq "$(git -C "$FW" log -1 --format=%s)" "New layout worktree"
assert_eq "$(git -C "$F" log -1 --format=%s)" "New layout step" "main branch changed by worktree save"

# CORE_DIR unset: the CLAUDE.local.md symlink finds the Core
echo "n2" > "$F/n.txt"; echo "doc2" > "$CORE_DIR/foo/d.md"
(cd "$F" && env -u CORE_DIR -u CLAUDE_PLUGIN_OPTION_CORE_DIR bash "$SAVE" "No env") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "saved docs"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "No env"

# undo-step reverts both
(cd "$F" && bash "$UNDO") > "$SANDBOX/out" 2>&1
assert_eq "$(cat "$F/n.txt")" "n1" "new layout: undo did not restore code"
assert_eq "$(cat "$CORE_DIR/foo/d.md")" "doc1" "new layout: undo did not restore docs"

# a git repo beside the Core that is not a project
mkdir -p "$SANDBOX/Projects/Brain"; git -C "$SANDBOX/Projects/Brain" init -q
(cd "$SANDBOX/Projects/Brain" && bash "$SAVE" "x") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "1" "save in a non-project repo"
assert_contains "$SANDBOX/out" "This folder is not a corecrew project (<Projects>/<Name> with <Core>/<name>/CLAUDE.md)."
mkdir -p "$SANDBOX/plain"
(cd "$SANDBOX/plain" && bash "$SAVE" "x") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "Run this inside a project's code folder."

finish
