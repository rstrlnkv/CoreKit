#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
scaffold_old save-app
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

# --push pushes the Core only: the code leaves through ship. The output says so.
git init -q --bare "$SANDBOX/code.git"; git -C "$C" remote add origin "$SANDBOX/code.git"
git init -q --bare "$SANDBOX/core.git"; git -C "$CORE_DIR" remote add origin "$SANDBOX/core.git"
printf '#!/bin/sh\n# corecrew hook shim (test no-op)\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"  # privacy hook needs GitHub; tested in test_hooks
sleep 1; echo "v3" > "$C/app.txt"; echo y >> "$P/docs/brief.md"
(cd "$C" && bash "$SAVE" "Publish" --push) > "$SANDBOX/out" 2>&1
assert_eq "$(git -C "$SANDBOX/code.git" rev-list --all --count)" "0" "save --push must not push the code"
assert_eq "$(git -C "$SANDBOX/core.git" log -1 --format=%s main 2>/dev/null)" "Publish"
assert_contains "$SANDBOX/out" "pushed Core"; assert_contains "$SANDBOX/out" "ship"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Publish" "save --push: the code commit"
# --push alone (no message) with nothing to save: pushes the Core; with changes to save it is refused (2)
sleep 1; echo z >> "$P/docs/brief.md"; (cd "$C" && bash "$SAVE" "Core only") >/dev/null 2>&1
(cd "$C" && bash "$SAVE" --push) > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "0" "save --push with nothing to save: $(cat "$SANDBOX/out")"
assert_contains "$SANDBOX/out" "nothing to save"; assert_contains "$SANDBOX/out" "pushed Core"
assert_eq "$(git -C "$SANDBOX/core.git" log -1 --format=%s main 2>/dev/null)" "Core only" "save --push alone did not push the Core"
echo "v4" > "$C/app.txt"; nc=$(cnt "$C")
(cd "$C" && bash "$SAVE" --push) > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "2" "save --push with changes and no message must be refused"
assert_eq "$(cnt "$C")" "$nc" "a refused save --push made a commit"; assert_contains "$SANDBOX/out" "message"
git -C "$C" status --porcelain | grep -q app.txt && pass || fail "the refused save staged or lost app.txt"
(cd "$C" && bash "$SAVE") > "$SANDBOX/out" 2>&1; assert_eq "$?" "2" "save with no message and no --push: usage"
# failure path: a Core remote that is gone. The commits of both repos stay; the code remote is untouched.
git -C "$CORE_DIR" remote set-url origin "$SANDBOX/missing.git"
sleep 1; echo w >> "$P/docs/brief.md"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Push fails" --push) > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "1" "save --push with a missing Core remote"
assert_contains "$SANDBOX/out" "Push failed"
assert_eq "$(cnt "$C")" "$((nc+1))" "the code commit of a failed push"; assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "the Core commit of a failed push"
assert_eq "$(cat "$C/app.txt")" "v4" "a failed push changed a file"
assert_eq "$(git -C "$SANDBOX/code.git" rev-list --all --count)" "0" "a failed push touched the code remote"
assert_contains "$SANDBOX/out" "code not pushed"   # the user learns where the code goes even when the Core push fails
git -C "$CORE_DIR" remote set-url origin "$SANDBOX/core.git"
# failure path: the Core pre-push hook refuses the push (pre-push-core on a non-GitHub remote). The line that
# says the code leaves through ship is printed anyway; the exit is non-zero; both commits stay.
printf '#!/bin/sh\n# corecrew hook shim (test: refuse)\necho "Push blocked: test" >&2\nexit 1\n' > "$CORE_DIR/.git/hooks/pre-push"
sleep 1; echo "v5" > "$C/app.txt"; echo w >> "$P/docs/brief.md"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Hook refuses" --push) > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "1" "save --push with a Core pre-push hook that refuses"
assert_contains "$SANDBOX/out" "Push failed"; assert_contains "$SANDBOX/out" "code not pushed"
assert_eq "$(cnt "$C")" "$((nc+1))" "the code commit when the hook refuses"; assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "the Core commit when the hook refuses"
assert_eq "$(cat "$C/app.txt")" "v5" "a refused push changed a file"
assert_eq "$(git -C "$SANDBOX/core.git" log -1 --format=%s main 2>/dev/null)" "Core only" "a refused push reached the Core remote"
printf '#!/bin/sh\n# corecrew hook shim (test no-op)\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"
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
assert_contains "$PLUGIN/skills/task/SKILL.md" "$CHK"
assert_contains "$PLUGIN/skills/task/references/release.md" "$CHK"
assert_not_contains "$PLUGIN/skills/task/SKILL.md" 'status --short -- <project> knowledge'
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
git -C "$F" init -q; cp "$PLUGIN/skills/new-project/templates/code/gitignore-common" "$F/.gitignore"
ln -s "$CORE_DIR/foo/CLAUDE.md" "$F/CLAUDE.local.md"
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

# a session in <Core>/<name>/ of a new-layout project: save and undo-step use the code folder beside the Core
echo "n3" > "$F/n.txt"; echo "doc3" > "$CORE_DIR/foo/d.md"
(cd "$CORE_DIR/foo" && bash "$SAVE" "From the Core folder") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "0" "save from <Core>/foo: $(cat "$SANDBOX/out")"
assert_contains "$SANDBOX/out" "saved code"; assert_contains "$SANDBOX/out" "saved docs"
assert_eq "$(git -C "$F" log -1 --format=%s)" "From the Core folder" "save from <Core>/foo: code commit"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "From the Core folder" "save from <Core>/foo: docs commit"
(cd "$CORE_DIR/foo" && bash "$UNDO") > "$SANDBOX/out" 2>&1
assert_eq "$(cat "$F/n.txt")" "n1" "undo from <Core>/foo did not restore code"
assert_eq "$(cat "$CORE_DIR/foo/d.md")" "doc1" "undo from <Core>/foo did not restore docs"

# an old-layout project plus an unrelated repo of the same name beside the Core: save works in
# <Core>/<name>/code and writes nothing into the unrelated repo
scaffold_old twin-app
T="$SANDBOX/Projects/Twin-App"; mkdir -p "$T"; git -C "$T" init -q
echo "t1" > "$CORE_DIR/twin-app/code/t.txt"
(cd "$CORE_DIR/twin-app/code" && bash "$SAVE" "Twin step") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "0" "save in an old-layout project with an unrelated twin: $(cat "$SANDBOX/out")"
assert_eq "$(git -C "$CORE_DIR/twin-app/code" log -1 --format=%s 2>/dev/null)" "Twin step" "twin: code not saved"
assert_file "$CORE_DIR/twin-app/code/.git/hooks/pre-commit"
assert_no_file "$T/.git/hooks/pre-commit"; assert_no_file "$T/CLAUDE.local.md"

# install-hooks lets a case-clash line through and exits non-zero (it does not swallow code_dir_of's exit 3)
grep -q 'code_dir_of "$NAME" 2>/dev/null' "$SCRIPTS/install-hooks.sh" && fail "install-hooks swallows the case-clash line" || pass
mkdir -p "$SANDBOX/Projects/Clash" "$SANDBOX/Projects/clash" "$CORE_DIR/clash"; : > "$CORE_DIR/clash/CLAUDE.md"
if [ "$(ls "$SANDBOX/Projects" | grep -ci '^clash$')" -eq 2 ]; then
  bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/clash" > "$SANDBOX/out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] && pass || fail "install-hooks with a case clash exited 0"
  assert_contains "$SANDBOX/out" "two folders differ only in case"
else
  echo "  note: case-insensitive disk, install-hooks case-clash check skipped"
fi

# a git repo beside the Core that is not a project
mkdir -p "$SANDBOX/Projects/Brain"; git -C "$SANDBOX/Projects/Brain" init -q
(cd "$SANDBOX/Projects/Brain" && bash "$SAVE" "x") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "1" "save in a non-project repo"
assert_contains "$SANDBOX/out" "This folder is not a corecrew project (<Projects>/<Name> with <Core>/<name>/CLAUDE.md)."
mkdir -p "$SANDBOX/plain"
(cd "$SANDBOX/plain" && bash "$SAVE" "x") > "$SANDBOX/out" 2>&1
assert_contains "$SANDBOX/out" "Run this inside a project's code folder."

# git cannot write .git (Codex sandbox keeps it read-only): save fails loudly, never "nothing to save"
if [ "$(id -u)" != 0 ]; then
  echo "ro" > "$C/ro.txt"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
  chmod a-w "$C/.git"
  (cd "$C" && bash "$SAVE" "Read-only git") > "$SANDBOX/out" 2>&1; rc=$?
  chmod u+w "$C/.git"
  [ "$rc" != 0 ] && pass || fail "save exited 0 with a read-only .git"
  assert_not_contains "$SANDBOX/out" "nothing to save"
  assert_contains "$SANDBOX/out" "save: git could not write"
  assert_eq "$(cat "$C/ro.txt")" "ro" "file changed by a failed save"
  assert_eq "$(cnt "$C")" "$nc"; assert_eq "$(cnt "$CORE_DIR")" "$nd"
  git -C "$C" status --porcelain | grep -q 'ro.txt' && pass || fail "ro.txt not left uncommitted"
  rm -f "$C/ro.txt"
fi

# core.hooksPath set by another tool (husky, lefthook): corecrew cannot install its shims there, so save
# still commits and says on stderr that the hooks are not installed (it does not fail every time)
mkdir -p "$C/.husky"; git -C "$C" config core.hooksPath .husky
sleep 1; echo "hp" > "$C/hp.txt"; nc=$(cnt "$C")
(cd "$C" && bash "$SAVE" "With hooksPath") > "$SANDBOX/out" 2>"$SANDBOX/err"; rc=$?
assert_eq "$rc" "0" "save failed with core.hooksPath set"
assert_eq "$(cnt "$C")" "$((nc+1))" "no commit with core.hooksPath set"
assert_contains "$SANDBOX/err" "core.hooksPath"
assert_no_file "$C/.husky/pre-commit"
git -C "$C" config --unset core.hooksPath

# The Core commit carries a "Project: <name>" trailer (undo-step uses it for a step with no code commit)
sleep 1; echo "pt" > "$C/pt.txt"; echo "pt" >> "$P/docs/brief.md"
(cd "$C" && bash "$SAVE" "Project trailer") >/dev/null 2>&1
git -C "$CORE_DIR" log -1 --format=%B | grep -qxF "Project: save-app" && pass || fail "no Project trailer in the Core commit: $(git -C "$CORE_DIR" log -1 --format=%B)"
git -C "$CORE_DIR" log -1 --format=%B | grep -qx "Step-Id: $(step_ids "$C" | head -1)" && pass || fail "Core commit lost its Step-Id"

# Both repos must be able to commit before the code commit is made. Failure path: a Core that
# cannot commit leaves both repos as they were (no code commit without its docs commit).
# no identity in the Core (the code repo has one of its own)
sleep 1; echo "id" > "$C/id.txt"; echo "id" >> "$P/docs/brief.md"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
git -C "$C" config user.name tester; git -C "$C" config user.email tester@example.com
git -C "$CORE_DIR" config user.useConfigOnly true
(cd "$C" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  bash "$SAVE" "No identity") > "$SANDBOX/out" 2>&1; rc=$?
[ "$rc" != 0 ] && pass || fail "save exited 0 with no identity in the Core"
assert_eq "$(cnt "$C")" "$nc" "code commit made although the Core cannot commit"
assert_eq "$(cnt "$CORE_DIR")" "$nd" "Core commit made with no identity"
assert_contains "$SANDBOX/out" "identity"; assert_contains "$SANDBOX/out" "nothing saved"
git -C "$CORE_DIR" config --unset user.useConfigOnly
# a stale index.lock in the Core
: > "$CORE_DIR/.git/index.lock"
(cd "$C" && bash "$SAVE" "Locked Core") > "$SANDBOX/out" 2>&1; rc=$?
rm -f "$CORE_DIR/.git/index.lock"
[ "$rc" != 0 ] && pass || fail "save exited 0 with a Core index.lock"
assert_eq "$(cnt "$C")" "$nc" "code commit made although the Core index is locked"
assert_contains "$SANDBOX/out" "index.lock"
# a stale index.lock in the code repo
: > "$C/.git/index.lock"
(cd "$C" && bash "$SAVE" "Locked code") > "$SANDBOX/out" 2>&1; rc=$?
rm -f "$C/.git/index.lock"
[ "$rc" != 0 ] && pass || fail "save exited 0 with a code index.lock"
assert_contains "$SANDBOX/out" "index.lock"
# a read-only Core .git
if [ "$(id -u)" != 0 ]; then
  chmod a-w "$CORE_DIR/.git"
  (cd "$C" && bash "$SAVE" "Read-only Core") > "$SANDBOX/out" 2>&1; rc=$?
  chmod u+w "$CORE_DIR/.git"
  [ "$rc" != 0 ] && pass || fail "save exited 0 with a read-only Core .git"
  assert_eq "$(cnt "$C")" "$nc" "code commit made although the Core .git is read-only"
  assert_contains "$SANDBOX/out" "save: git could not write $CORE_DIR/.git"
fi
assert_eq "$(cat "$C/id.txt")" "id" "a refused save changed a file"
# the legitimate save of the same changes goes through
(cd "$C" && bash "$SAVE" "With identity") > "$SANDBOX/out" 2>&1
assert_eq "$(cnt "$C")" "$((nc+1))" "save after the fixes: no code commit"
assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "save after the fixes: no Core commit"

# The Core is checked only when it has docs to commit. With no identity in the Core (user.useConfigOnly,
# the identity set per repo) a code-only step still saves. A step with docs is refused before the code
# commit: nothing is saved and both trees stay as they were.
git -C "$CORE_DIR" config user.useConfigOnly true
noid_save() { (cd "$C" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  bash "$SAVE" "$1") > "$SANDBOX/out" 2>&1; }
trees() { git -C "$C" status --porcelain; git -C "$CORE_DIR" status --porcelain; tree_sum "$C"; tree_sum "$CORE_DIR"; }
sleep 1; echo "code only" > "$C/noid.txt"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
noid_save "Code only, no Core identity"; rc=$?
assert_eq "$rc" "0" "a code-only step was refused for the Core's identity: $(cat "$SANDBOX/out")"
assert_eq "$(cnt "$C")" "$((nc+1))" "code-only step with no Core identity: no code commit"
assert_eq "$(cnt "$CORE_DIR")" "$nd" "code-only step made a Core commit"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Code only, no Core identity"
echo "noid 2" > "$C/noid.txt"; echo "noid" >> "$P/docs/brief.md"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
before=$(trees)
noid_save "Docs, no Core identity"; rc=$?
[ "$rc" != 0 ] && pass || fail "a step with docs saved with no identity in the Core"
assert_contains "$SANDBOX/out" "identity"; assert_contains "$SANDBOX/out" "nothing saved"
assert_eq "$(cnt "$C")" "$nc" "code commit made although the Core cannot commit the docs"
assert_eq "$(cnt "$CORE_DIR")" "$nd" "Core commit made with no identity"
assert_eq "$(trees)" "$before" "a refused save changed a tree"
git -C "$CORE_DIR" config --unset user.useConfigOnly
(cd "$C" && bash "$SAVE" "Docs with identity") >/dev/null 2>&1
assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "save with the Core identity back: no Core commit"

# CDPATH exported with "." in it: bash's cd then prints the folder it went to. The Core's git folder
# is found by a relative path (.git), so a cd that prints would break the check. Saved from a linked
# worktree, whose git folders are absolute paths.
sleep 1; echo "cdpath" > "$W/cdpath.txt"; echo "cdpath" >> "$P/docs/brief.md"; nd=$(cnt "$CORE_DIR")
(cd "$W" && CDPATH=".:$SANDBOX" bash "$SAVE" "With CDPATH") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "0" "save with CDPATH exported: $(cat "$SANDBOX/out")"
assert_eq "$(git -C "$W" log -1 --format=%s)" "With CDPATH" "save with CDPATH: no code commit"
assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "save with CDPATH: no Core commit"
# the same from the main code folder, whose git folder is the relative .git
sleep 1; echo "cdpath main" > "$C/cdpath.txt"; nd=$(cnt "$CORE_DIR")
(cd "$C" && CDPATH=".:$SANDBOX" bash "$SAVE" "With CDPATH main") > "$SANDBOX/out" 2>&1; rc=$?
assert_eq "$rc" "0" "save with CDPATH exported, main folder: $(cat "$SANDBOX/out")"
assert_eq "$(git -C "$C" log -1 --format=%s)" "With CDPATH main" "save with CDPATH, main folder: no code commit"
git -C "$C" config --unset user.name; git -C "$C" config --unset user.email

# A Core commit that fails after the code commit (here a Core pre-commit hook): save exits non-zero,
# names the code commit and its Step-Id, and says a rerun commits the docs; the rerun does.
printf '#!/bin/sh\necho "core hook refused" >&2\nexit 1\n' > "$CORE_DIR/.git/hooks/pre-commit"
chmod +x "$CORE_DIR/.git/hooks/pre-commit"
sleep 1; echo "half" > "$C/half.txt"; echo "half" >> "$P/docs/brief.md"; nc=$(cnt "$C"); nd=$(cnt "$CORE_DIR")
(cd "$C" && bash "$SAVE" "Half step") > "$SANDBOX/out" 2>&1; rc=$?
rm -f "$CORE_DIR/.git/hooks/pre-commit"
[ "$rc" != 0 ] && pass || fail "save exited 0 although the docs commit failed"
assert_eq "$(cnt "$C")" "$((nc+1))" "half step: no code commit"
assert_eq "$(cnt "$CORE_DIR")" "$nd" "half step: Core commit made"
assert_contains "$SANDBOX/out" "$(git -C "$C" rev-parse --short HEAD)"
assert_contains "$SANDBOX/out" "Step-Id: $(step_ids "$C" | head -1)"
assert_contains "$SANDBOX/out" "run save again"
(cd "$C" && bash "$SAVE" "Half step docs") > "$SANDBOX/out" 2>&1
assert_eq "$(cnt "$CORE_DIR")" "$((nd+1))" "rerun did not commit the docs"
assert_contains "$SANDBOX/out" "saved docs"
assert_eq "$(git -C "$CORE_DIR" status --porcelain -- save-app)" "" "docs left uncommitted after the rerun"

# The Step-Id loop reads a bounded part of the history (every git log save runs has a count
# limit), not the whole history of all refs on every call. A git wrapper records the calls.
GW="$SANDBOX/gitwrap"; mkdir -p "$GW"; REALGIT="$(command -v git)"
{ echo '#!/bin/sh'; printf 'printf "%%s\\n" "$*" >> "%s/git-calls"\n' "$SANDBOX"; printf 'exec "%s" "$@"\n' "$REALGIT"; } > "$GW/git"
chmod +x "$GW/git"; : > "$SANDBOX/git-calls"
sleep 1; echo "bounded" > "$C/bounded.txt"; echo "bounded" >> "$P/docs/brief.md"
(cd "$C" && PATH="$GW:$PATH" bash "$SAVE" "Bounded") >/dev/null 2>&1
grep -qE '(^| )log( |$)' "$SANDBOX/git-calls" && pass || fail "the git wrapper saw no git log call"
unbounded=$(grep -E '(^| )log( |$)' "$SANDBOX/git-calls" | grep -vE '(^| )(-n [0-9]+|-[0-9]+|--max-count=[0-9]+)( |$)')
assert_eq "$unbounded" "" "save ran git log without a count limit"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Bounded" "save through the wrapper did not commit"

finish
