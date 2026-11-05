#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
AD="$SCRIPTS/adopt.sh"
WC="$SCRIPTS/wiki-check.sh"

# mkrepo <dir> — a small repo: CLAUDE.md, docs/guide.md (no front matter), .claude/ files, a
# tracked worktree file, src/a.sh; one commit.
mkrepo() {
  mkdir -p "$1/docs" "$1/.claude/worktrees/w" "$1/src"
  git init -q "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main
  printf '# Old project\n\nRules here.\n' > "$1/CLAUDE.md"
  printf '# Guide\n\nHow to use it.\n' > "$1/docs/guide.md"
  printf '{}\n' > "$1/.claude/settings.json"
  printf '{"local":true}\n' > "$1/.claude/settings.local.json"
  printf 'x\n' > "$1/.claude/worktrees/w/f.txt"
  printf 'echo a\n' > "$1/src/a.sh"
  git -C "$1" add -A && git -C "$1" commit -q -m "initial"
}
# mkold <name> — an old-layout project: <Core>/<name>/ (committed in the Core, PROJECTS.md line
# "<name>/code/") and its code repo in <Core>/<name>/code with one commit and an old .gitignore.
mkold() {
  scaffold_old "$1" || return 1
  local c="$CORE_DIR/$1/code" t
  t="$CORE_DIR/PROJECTS.md.tmp"
  grep -v "^- $1 " "$CORE_DIR/PROJECTS.md" > "$t"; printf -- '- %s — Old app — %s/code/\n' "$1" "$1" >> "$t"
  mv "$t" "$CORE_DIR/PROJECTS.md"
  git -C "$CORE_DIR" add -A && git -C "$CORE_DIR" commit -q -m "old $1"
  grep -vxF 'CLAUDE.local.md' "$c/.gitignore" > "$c/.gitignore.tmp"; mv "$c/.gitignore.tmp" "$c/.gitignore"
  echo 'echo a' > "$c/main.sh"
  git -C "$c" add -A && git -C "$c" commit -q -m "initial"
}
# snap — everything a refusal must not change: file contents, the file list, HEAD and status of every repo
snap() {
  tree_sum "$SANDBOX"
  find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort
  find "$SANDBOX" -name .git -print | LC_ALL=C sort | while IFS= read -r g; do
    git -C "$(dirname "$g")" rev-parse HEAD 2>&1; git -C "$(dirname "$g")" status --porcelain 2>&1
  done
}
last_line() { printf '%s\n' "$1" | tail -1; }
# refuses <want line> <args...> — exit 2, exactly that one line, nothing changed in $SANDBOX
refuses() {
  local want="$1"; shift
  local before after
  before="$(snap)"
  OUT="$(bash "$AD" "$@" 2>&1)"; local rc=$?
  after="$(snap)"
  assert_eq "$rc" "2" "refusal exit ($want)"
  assert_eq "$OUT" "$want" "refusal message"
  assert_eq "$after" "$before" "refusal changed something ($want)"
}
inode() { ls -di "$1" | awk '{ print $1 }'; }

# --- success: the repo stays where it is; internal files go to the Core; rules fold into CLAUDE.md
new_sandbox; setup_core
PR="$SANDBOX/Projects"
F="$PR/Foo"; mkdir -p "$F/docs" "$F/.claude/rules" "$F/.claude/commands" "$F/src"
git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
printf '# Foo\n\nOwn instructions.\n' > "$F/CLAUDE.md"
printf '# A\n\nPage a.\n' > "$F/docs/a.md"
printf -- '---\npaths: ["src/**"]\n---\n\n# Tests\n\nWrite the test first.\n' > "$F/.claude/rules/t.md"
printf 'Always on.\n' > "$F/.claude/rules/always.md"
printf 'Do x.\n' > "$F/.claude/commands/x.md"
echo 'echo a' > "$F/src/a.sh"
git -C "$F" add -A && git -C "$F" commit -q -m "initial"
N0="$(git -C "$F" rev-list --count HEAD)"; I0="$(inode "$F")"
assert_exit 0 bash "$AD" --from "$F" --dry-run
DRY_OUT="$OUT"
echo "$DRY_OUT" | grep -qxF "kept in Core, no longer loaded:" && pass || fail "plan lacks the kept list: $DRY_OUT"
echo "$DRY_OUT" | grep -qxF "  .claude/commands/x.md" && pass || fail "plan lacks x.md: $DRY_OUT"
echo "$DRY_OUT" | grep -qxF "  .claude/rules/t.md" && pass || fail "plan lacks the rule: $DRY_OUT"
echo "$DRY_OUT" | grep -q '^move:' && fail "plan moves the folder: $DRY_OUT" || pass
echo "$DRY_OUT" | grep -qF "$F/CLAUDE.local.md" && pass || fail "plan lacks the link: $DRY_OUT"
assert_no_file "$F/CLAUDE.local.md"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/foo"
assert_eq "$(last_line "$OUT")" "open: $F" "last line"
echo "$OUT" | grep -qxF "kept in Core, no longer loaded:" && pass || fail "report lacks the kept list: $OUT"
echo "$OUT" | grep -qxF "  .claude/commands/x.md" && pass || fail "report lacks x.md: $OUT"
echo "$OUT" | grep -q '^warning:' && fail "warning printed: $OUT" || pass
assert_dir "$F"
assert_eq "$(cd "$F" && pwd -P)" "$F" "folder path"
assert_eq "$(inode "$F")" "$I0" "folder inode"
assert_eq "$(git -C "$F" rev-list --count HEAD)" "$((N0 + 1))" "commit count"
assert_eq "$(git -C "$F" log -1 --format=%s)" "Move internal Claude files to Core" "repo commit subject"
assert_eq "$(git -C "$F" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" \
  ".claude/commands/x.md;.claude/rules/always.md;.claude/rules/t.md;.gitignore;.worktreeinclude;CLAUDE.md;docs/a.md;" "repo commit files"
assert_no_file "$F/CLAUDE.md"; assert_no_file "$F/docs"; assert_no_file "$F/.claude/rules"
assert_eq "$(git -C "$F" ls-files -- CLAUDE.md)" "" "CLAUDE.md still tracked"
assert_eq "$(git -C "$F" status --porcelain)" "" "repo dirty"
assert_contains "$P/CLAUDE.md" "Own instructions."
assert_contains "$P/CLAUDE.md" "### t"
assert_contains "$P/CLAUDE.md" "Applies to: src/**"
assert_contains "$P/CLAUDE.md" "Write the test first."
assert_contains "$P/CLAUDE.md" "### always"
assert_contains "$P/CLAUDE.md" "Always on."
assert_not_contains "$P/CLAUDE.md" "paths:"
assert_eq "$(grep -c '^## Rules$' "$P/CLAUDE.md")" "1" "one Rules section"
# the rules come after the Rules heading, the rule's own heading sits below ### t
awk '/^## Rules$/ { r = NR } /^### t$/ { t = NR } /^#### Tests$/ { h = NR } END { exit !(r && t > r && h > t) }' \
  "$P/CLAUDE.md" && pass || fail "rules not under ## Rules: $(cat "$P/CLAUDE.md")"
assert_file "$P/.claude/commands/x.md"
assert_no_file "$P/.claude/rules"
assert_file "$P/docs/a.md"
[ -L "$F/CLAUDE.local.md" ] && pass || fail "no CLAUDE.local.md link"
assert_eq "$(readlink "$F/CLAUDE.local.md")" "$P/CLAUDE.md" "link target"
[ -L "$F/AGENTS.md" ] && pass || fail "no AGENTS.md link"
assert_eq "$(readlink "$F/AGENTS.md")" "$P/CLAUDE.md" "AGENTS.md link target"
assert_contains "$F/.claude/settings.local.json" "\"$P\""
assert_eq "$(cat "$F/.worktreeinclude")" "$(cat "$SKILL/templates/code/worktreeinclude")" ".worktreeinclude from the template"
echo "$DRY_OUT" | grep -qF ".worktreeinclude" && pass || fail "plan lacks .worktreeinclude: $DRY_OUT"
grep -qxF -- "- foo — Adopted existing project — Foo/" "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md line: $(cat "$CORE_DIR/PROJECTS.md")"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Adopt foo" "Core commit"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "Core dirty"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check not green: $(bash "$WC" "$P" 2>&1)"
assert_contains "$F/.git/hooks/pre-commit" "corecrew hook shim"
assert_contains "$CORE_DIR/.git/hooks/pre-push" "corecrew hook shim"
ls -A "$CORE_DIR" | grep -q '^\.adopt' && fail "temp dir left in Core" || pass
assert_eq "$(bash "$SCRIPTS/lib.sh" project-of "$F")" "foo" "project_of after adopt"

# --- the classic repo: files move, history stays, wiki is green; a settings.local.json of the user's
# is left as is with a warning
new_sandbox; setup_core
F="$SANDBOX/Projects/my-app"; mkrepo "$F"
N0="$(git -C "$F" rev-list --count HEAD)"
assert_exit 0 bash "$AD" --from "$F"
OUT1="$OUT"
P="$CORE_DIR/my-app"
assert_eq "$(last_line "$OUT1")" "open: $F" "last line"
for f in CLAUDE.md docs/guide.md .claude/settings.json docs/INDEX.md docs/brief.md docs/architecture.md \
         docs/decisions/001-stack-and-architecture.md; do
  assert_file "$P/$f"
done
assert_dir "$P/docs/knowledge"; assert_dir "$P/docs/features"
assert_no_file "$P/.claude/settings.local.json"
assert_no_file "$P/.claude/worktrees"
assert_eq "$(git -C "$F" rev-list --count HEAD)" "$((N0 + 1))" "commit count"
assert_eq "$(git -C "$F" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" \
  ".claude/settings.json;.gitignore;.worktreeinclude;CLAUDE.md;docs/guide.md;" "removed files (and the .gitignore lines)"
assert_eq "$(cat "$F/.claude/settings.local.json")" '{"local":true}' "settings.local.json changed"
echo "$OUT1" | grep -qF "warning: $F/.claude/settings.local.json exists and was left as is; add \"$P\" to permissions.additionalDirectories in it" && pass || fail "no settings warning: $OUT1"
assert_file "$F/.claude/worktrees/w/f.txt"
assert_file "$F/src/a.sh"
assert_no_file "$F/CLAUDE.md"; assert_no_file "$F/docs"
assert_eq "$(git -C "$F" status --porcelain)" "" "code repo dirty"
assert_eq "$(git -C "$F" log --format=%s | tail -1)" "initial" "history kept"
assert_contains "$P/CLAUDE.md" "# Old project"
assert_contains "$P/CLAUDE.md" "check: <set after scaffolding>"
assert_not_contains "$P/CLAUDE.md" "public-docs:"
assert_contains "$P/docs/guide.md" "How to use it."
head -1 "$P/docs/guide.md" | grep -qx -- '---' && pass || fail "guide.md: no front matter added"
assert_contains "$P/docs/INDEX.md" "guide.md"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check not green: $(bash "$WC" "$P" 2>&1)"
echo "$OUT1" | grep -q 'wiki-check:' && fail "wiki problems printed: $OUT1" || pass
assert_contains "$F/.git/hooks/pre-push" "corecrew hook shim"
grep -q '^- my-app — .* — my-app/$' "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md line"
assert_eq "$(git -C "$CORE_DIR" show --name-only --format= HEAD | sed 's|/.*||' | LC_ALL=C sort -u | tr '\n' ';')" \
  "PROJECTS.md;my-app;" "Core commit scope"

# --- --check, --public-docs: docs/ stays in the repo and is listed in CLAUDE.md
new_sandbox; setup_core
F="$SANDBOX/Projects/Foo"; mkdir -p "$F/docs"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
printf '# Foo\n' > "$F/CLAUDE.md"; printf '# A\n\nPage a.\n' > "$F/docs/a.md"
git -C "$F" add -A && git -C "$F" commit -q -m initial
assert_exit 0 bash "$AD" --from "$F" --public-docs "docs/" --check "bash tests/run.sh"
P="$CORE_DIR/foo"
assert_file "$F/docs/a.md"
assert_eq "$(git -C "$F" ls-files -- docs/a.md)" "docs/a.md" "public page still tracked"
assert_no_file "$P/docs/a.md"
assert_contains "$P/CLAUDE.md" "public-docs: docs/"
assert_contains "$P/CLAUDE.md" "check: bash tests/run.sh"
assert_not_contains "$P/CLAUDE.md" "check: <set after scaffolding>"
assert_eq "$(git -C "$F" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" \
  ".gitignore;.worktreeinclude;CLAUDE.md;" "removed files (public docs kept)"
assert_file "$P/docs/INDEX.md"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (public docs): $(bash "$WC" "$P" 2>&1)"

# --- rules folding: a CLAUDE.md with a Rules section in the middle; a list of paths; front matter dropped
new_sandbox; setup_core
F="$SANDBOX/Projects/rules-app"; mkdir -p "$F/.claude/rules/web"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
printf '# R\n\n## Rules\n- Mine.\n\n## Later\nText.\n' > "$F/CLAUDE.md"
printf -- '---\ndescription: web\npaths:\n  - "src/**/*.{ts,tsx}"\n  - lib/**\n---\nUse tabs.\n' > "$F/.claude/rules/web/style.md"
printf -- '---\npaths: [ "a/**", '"'"'b/**'"'"' ]\n---\n## Sub\nB.\n' > "$F/.claude/rules/two.md"
git -C "$F" add -A && git -C "$F" commit -q -m initial
assert_exit 0 bash "$AD" --from "$F"
C="$CORE_DIR/rules-app/CLAUDE.md"
assert_contains "$C" "### web/style"
assert_contains "$C" "Applies to: src/**/*.{ts,tsx}, lib/**"
assert_contains "$C" "Applies to: a/**, b/**"
grep -qx '##### Sub' "$C" && pass || fail "rule heading not moved down: $(cat "$C")"
assert_not_contains "$C" "description: web"
assert_eq "$(grep -c '^## Rules$' "$C")" "1" "one Rules section"
awk '/^## Rules$/ { r = NR } /^- Mine\.$/ { m = NR } /^### two$/ { t = NR } /^### web\/style$/ { w = NR } /^## Later$/ { l = NR }
  END { exit !(r < m && m < t && t < w && w < l) }' "$C" && pass || fail "rules not inside ## Rules: $(cat "$C")"
assert_contains "$C" "Text."

# --- --dry-run changes nothing, prints the plan
new_sandbox; setup_core
F="$SANDBOX/Projects/dry-app"; mkrepo "$F"
before="$(snap)"
assert_exit 0 bash "$AD" --from "$F" --dry-run --public-docs "docs/guide.md"
after="$(snap)"
assert_eq "$after" "$before" "dry run changed something"
echo "$OUT" | grep -qF "CLAUDE.md" && pass || fail "plan lacks CLAUDE.md: $OUT"
echo "$OUT" | grep -qF "docs/guide.md" && pass || fail "plan lacks the public page: $OUT"
echo "$OUT" | grep -qF "$F" && pass || fail "plan lacks the folder: $OUT"
echo "$OUT" | grep -q "^open:" && fail "dry run printed open:" || pass
assert_exit 0 bash "$AD" --from "$F" --public-docs "docs/guide.md"
bash "$WC" "$CORE_DIR/dry-app" >/dev/null 2>&1 && pass || fail "wiki-check (public page): $(bash "$WC" "$CORE_DIR/dry-app" 2>&1)"

# --- refusals: one line, exit 2, nothing changed
new_sandbox; setup_core
PR="$SANDBOX/Projects"
mkdir -p "$PR/plain"; echo hi > "$PR/plain/a.txt"
refuses "not a git repo" --from "$PR/plain"
refuses "not a git repo" --from "$PR/missing"
F="$PR/dirty-app"; mkrepo "$F"; echo more >> "$F/src/a.sh"
refuses "uncommitted changes" --from "$F"
echo new > "$F/untracked.txt"; git -C "$F" checkout -q -- src/a.sh
refuses "uncommitted changes" --from "$F"
rm "$F/untracked.txt"
mkdir -p "$CORE_DIR/inner"; mkrepo "$CORE_DIR/inner/code"
refuses "already inside Core" --from "$CORE_DIR/inner/code"
ln -s "$CORE_DIR" "$PR/link"
refuses "already inside Core" --from "$PR/link/inner/code"
rm "$PR/link"
# outside <Projects>, or deeper than one level in it
mkrepo "$SANDBOX/elsewhere/Bar"
refuses "not in $PR: move the folder to $PR/Bar first" --from "$SANDBOX/elsewhere/Bar"
refuses "not in $PR: move the folder to $PR/Bar first" --from "$SANDBOX/elsewhere/Bar" --dry-run
mkrepo "$PR/group/deep-app"
refuses "not in $PR: move the folder to $PR/deep-app first" --from "$PR/group/deep-app"
mkrepo "$PR/My App"
refuses "invalid project name 'my app' (rename the folder)" --from "$PR/My App"
refuses "invalid project name 'Bad_Name' (rename the folder)" --from "$F" --name Bad_Name
refuses "invalid project name 'ab' (rename the folder)" --from "$F" --name ab
refuses "invalid project name 'core' (rename the folder)" --from "$F" --name core
refuses "name 'my-app' does not match the folder 'My App': rename the folder to $PR/my-app first" --from "$PR/My App" --name my-app
mkdir -p "$CORE_DIR/dirty-app"
refuses "target exists: $CORE_DIR/dirty-app" --from "$F"
rmdir "$CORE_DIR/dirty-app"
# a name that is a dangling symlink also counts as existing
ln -s "$SANDBOX/nowhere" "$CORE_DIR/dirty-app"
refuses "target exists: $CORE_DIR/dirty-app" --from "$F"
rm "$CORE_DIR/dirty-app"
# a CLAUDE.local.md of the user's is never replaced by the link
mkrepo "$PR/loc-app"; echo mine > "$PR/loc-app/CLAUDE.local.md"; echo CLAUDE.local.md >> "$PR/loc-app/.git/info/exclude"
refuses "CLAUDE.local.md exists in $PR/loc-app: move it away first (adopt links that name to $CORE_DIR/loc-app/CLAUDE.md)" --from "$PR/loc-app"
# --dry-run refuses too
mkrepo "$PR/ok-app"
refuses "invalid project name 'Bad Name' (rename the folder)" --from "$PR/ok-app" --name "Bad Name" --dry-run

# two folders that differ only in case (a case-sensitive disk): refuse
mkdir -p "$PR/Casetest" "$PR/casetest" 2>/dev/null
if [ "$(ls "$PR" | grep -ci '^casetest$')" = "2" ]; then
  rmdir "$PR/Casetest"; mkrepo "$PR/Casetest"
  refuses "two folders differ only in case: Casetest, casetest" --from "$PR/Casetest"
fi
rm -rf "$PR/Casetest" "$PR/casetest"

# Core not set up
new_sandbox
F="$SANDBOX/Projects/lonely"; mkrepo "$F"
refuses "Core is not set up" --from "$F"
refuses "Core is not set up" --from "$F" --dry-run
mkdir -p "$CORE_DIR"; printf 'app-id-prefix: com.x\n' > "$CORE_DIR/.coredev"
refuses "Core is not set up" --from "$F"

# usage errors
new_sandbox; setup_core
assert_exit 2 bash "$AD"
assert_exit 2 bash "$AD" --from
assert_exit 2 bash "$AD" --from "$SANDBOX" --bogus

# --- a failing commit in the repo: nothing changes (the copy is undone, the files come back)
new_sandbox; setup_core
F="$SANDBOX/Projects/hook-app"; mkrepo "$F"
printf '#!/bin/sh\necho no >&2\nexit 1\n' > "$F/.git/hooks/pre-commit"; chmod +x "$F/.git/hooks/pre-commit"
before="$(snap)"
OUT="$(bash "$AD" --from "$F" 2>&1)"; rc=$?
assert_eq "$rc" "2" "commit failure exit"
echo "$OUT" | grep -q "could not commit" && pass || fail "commit failure message: $OUT"
after="$(snap)"
assert_eq "$after" "$before" "commit failure changed something"
assert_eq "$(git -C "$F" diff --cached --name-only)" "" "index not restored"
assert_no_file "$F/.worktreeinclude"
# the same with a .gitignore of the user's: it comes back byte for byte
printf 'build/\n' > "$F/.gitignore"; git -C "$F" add .gitignore; git -C "$F" commit -q --no-verify -m gi
before="$(snap)"
assert_exit 2 bash "$AD" --from "$F"
after="$(snap)"
assert_eq "$after" "$before" "commit failure changed something (existing .gitignore)"
assert_eq "$(cat "$F/.gitignore")" "build/" ".gitignore not restored"

# --- spaces and non-ASCII characters in file names
new_sandbox; setup_core
F="$SANDBOX/Projects/My-Proj"; mkrepo "$F"
printf '# Заметки\n\nТекст.\n' > "$F/docs/гайд app.md"
git -C "$F" add -A && git -C "$F" commit -q -m "add note"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/my-proj"
assert_eq "$(last_line "$OUT")" "open: $F" "last line (non-ASCII)"
assert_file "$P/docs/гайд app.md"
assert_contains "$P/docs/гайд app.md" "Текст."
assert_contains "$P/docs/INDEX.md" "гайд app.md"
assert_eq "$(git -C "$F" status --porcelain)" "" "code repo dirty"
grep -q '^- my-proj — .* — My-Proj/$' "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md line keeps the folder's case"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (non-ASCII): $(bash "$WC" "$P" 2>&1)"
# --from typed in another letter case (a case-insensitive disk): accepted; paths keep the case on disk
F="$SANDBOX/Projects/Case-App"; mkrepo "$F"
if [ -d "$SANDBOX/projects/case-app/.git" ]; then
  assert_exit 0 bash "$AD" --from "$SANDBOX/projects/case-app"
  assert_eq "$(last_line "$OUT")" "open: $F" "last line (--from in another case)"
  grep -qxF -- '- case-app — Adopted existing project — Case-App/' "$CORE_DIR/PROJECTS.md" && pass \
    || fail "PROJECTS.md entry lacks the on-disk case: $(cat "$CORE_DIR/PROJECTS.md")"
  assert_eq "$(readlink "$F/CLAUDE.local.md")" "$CORE_DIR/case-app/CLAUDE.md" "link (--from in another case)"
else
  echo "  note: case-sensitive disk, --from letter-case check skipped"
fi
# a Cyrillic folder name: refused (it is not a project name, and --name cannot rename the folder)
F="$SANDBOX/Projects/Мой проект"; mkrepo "$F"
refuses "invalid project name 'Мой проект' (rename the folder)" --from "$F"

# --- a repo with no internal files: the repo commit only adds the .gitignore lines; CLAUDE.md comes
# from the template
new_sandbox; setup_core
F="$SANDBOX/Projects/bare-app"; mkdir -p "$F"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
echo code > "$F/main.sh"; git -C "$F" add -A && git -C "$F" commit -q -m "initial"
assert_exit 0 bash "$AD" --from "$F" --check "make test"
P="$CORE_DIR/bare-app"
assert_eq "$(git -C "$F" rev-list --count HEAD)" "2" "one repo commit"
assert_eq "$(git -C "$F" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" ".gitignore;.worktreeinclude;" "the repo commit holds .gitignore and .worktreeinclude"
assert_contains "$P/CLAUDE.md" "# bare-app"
assert_contains "$P/CLAUDE.md" "check: make test"
assert_contains "$P/CLAUDE.md" "## Rules"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (bare): $(bash "$WC" "$P" 2>&1)"

# --- an existing check: line stays unless --check is given; existing wiki front matter is kept
new_sandbox; setup_core
F="$SANDBOX/Projects/keep-app"; mkrepo "$F"
printf '# Old\n\ncheck: npm test\n' > "$F/CLAUDE.md"
printf -- '---\ntitle: Mine\ndescription: Does things.\nstatus: active\n---\n\n# Mine\n' > "$F/docs/guide.md"
git -C "$F" add -A && git -C "$F" commit -q -m "wiki"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/keep-app"
assert_contains "$P/CLAUDE.md" "check: npm test"
assert_eq "$(grep -c '^check:' "$P/CLAUDE.md")" "1" "check lines"
assert_contains "$P/docs/guide.md" "title: Mine"
assert_eq "$(grep -c '^title:' "$P/docs/guide.md")" "1" "title lines"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (front matter): $(bash "$WC" "$P" 2>&1)"

# --- tracked files only: ignored files stay in the repo and never reach the Core or its git
new_sandbox; setup_core
F="$SANDBOX/Projects/ign-app"; mkrepo "$F"
printf '.claude/secret.json\ndocs/node_modules/\n' > "$F/.gitignore"
git -C "$F" add -A && git -C "$F" commit -q -m "ignore"
printf 'SECRET\n' > "$F/.claude/secret.json"
mkdir -p "$F/docs/node_modules"; echo 'x' > "$F/docs/node_modules/x.js"
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qF "stays in the repo (ignored by git):" && pass || fail "plan lacks ignored list: $OUT"
echo "$OUT" | grep -qF ".claude/secret.json" && pass || fail "plan lacks secret.json: $OUT"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/ign-app"
assert_no_file "$P/.claude/secret.json"; assert_no_file "$P/docs/node_modules"
assert_eq "$(cat "$F/.claude/secret.json")" "SECRET" "ignored file changed"
assert_file "$F/docs/node_modules/x.js"
assert_eq "$(git -C "$CORE_DIR" ls-files | grep -c 'secret\|node_modules')" "0" "ignored file in the Core git"
assert_eq "$(git -C "$F" status --porcelain)" "" "code repo dirty"

# --- symlinks among the internal files: refuse
new_sandbox; setup_core
F="$SANDBOX/Projects/link-app"; mkrepo "$F"
echo "agents" > "$F/AGENTS.md"; rm "$F/CLAUDE.md"; ln -s AGENTS.md "$F/CLAUDE.md"
git -C "$F" add -A && git -C "$F" commit -q -m "link"
refuses "symlink: CLAUDE.md -> AGENTS.md; replace it with a file first" --from "$F"
refuses "symlink: CLAUDE.md -> AGENTS.md; replace it with a file first" --from "$F" --dry-run
rm "$F/CLAUDE.md"; echo real > "$F/CLAUDE.md"; ln -s ../src/a.sh "$F/docs/lnk.md"
git -C "$F" add -A && git -C "$F" commit -q -m "link2"
refuses "symlink: docs/lnk.md -> ../src/a.sh; replace it with a file first" --from "$F"
rm "$F/docs/lnk.md"; mkdir -p "$F/.claude/rules"; ln -s ../../src/a.sh "$F/.claude/rules/r.md"
git -C "$F" add -A && git -C "$F" commit -q -m "link3"
refuses "symlink: .claude/rules/r.md -> ../../src/a.sh; replace it with a file first" --from "$F"

# --- a --public-docs path that does not exist: refuse
new_sandbox; setup_core
F="$SANDBOX/Projects/nf-app"; mkrepo "$F"
refuses "not found: docs/nope.md" --from "$F" --public-docs "docs/guide.md,docs/nope.md"
refuses "not found: nope" --from "$F" --public-docs "nope/" --dry-run

# --- Core inside the folder
new_sandbox; setup_core
git init -q "$SANDBOX/Projects" && git -C "$SANDBOX/Projects" symbolic-ref HEAD refs/heads/main
echo 'Core/' > "$SANDBOX/Projects/.gitignore"; echo x > "$SANDBOX/Projects/p.txt"
git -C "$SANDBOX/Projects" add -A && git -C "$SANDBOX/Projects" commit -q -m i
refuses "Core is inside the folder" --from "$SANDBOX/Projects" --name projects-x

# --- git identity unknown: refuse (repo needs a commit; Core needs a commit)
new_sandbox; setup_core
F="$SANDBOX/Projects/id-app"; mkrepo "$F"
G="$SANDBOX/Projects/id-bare"; mkdir -p "$G"; git init -q "$G"; git -C "$G" symbolic-ref HEAD refs/heads/main
echo c > "$G/main.sh"; git -C "$G" add -A && git -C "$G" commit -q -m i
git -C "$G" config user.name Local; git -C "$G" config user.email local@example.com
mkdir -p "$SANDBOX/h"
SAVE_HOME="$HOME"
export HOME="$SANDBOX/h" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
refuses "git does not know your name and email (git config --global user.name / user.email)" --from "$F"
refuses "git does not know your name and email (git config --global user.name / user.email)" --from "$G"
export HOME="$SAVE_HOME" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset GIT_CONFIG_NOSYSTEM GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

# --- a tracked submodule among the internal files: refuse
new_sandbox; setup_core
F="$SANDBOX/Projects/sub-app"; mkrepo "$F"
SUB="$SANDBOX/sub-origin"; mkdir -p "$SUB"; git init -q "$SUB"; echo s > "$SUB/s.txt"
git -C "$SUB" add -A && git -C "$SUB" commit -q -m s
git -C "$F" -c protocol.file.allow=always submodule add -q "$SUB" docs/vendor >/dev/null 2>&1
git -C "$F" commit -q -m "submodule"
assert_eq "$(git -C "$F" ls-files -s docs/vendor | cut -c1-6)" "160000" "fixture: gitlink"
refuses "submodule: docs/vendor; adopt cannot move it" --from "$F"
refuses "submodule: docs/vendor; adopt cannot move it" --from "$F" --dry-run

# --- a failing move of the staged copy into the Core: nothing is deleted; the output says where things are
new_sandbox; setup_core
F="$SANDBOX/Projects/mv-app"; mkrepo "$F"
mkdir -p "$SANDBOX/stub"
cat > "$SANDBOX/stub/mv" <<'STUB'
#!/bin/sh
case "$1" in */.adopt.*/p) echo "mv: stub failure" >&2; exit 1 ;; esac
exec /bin/mv "$@"
STUB
chmod +x "$SANDBOX/stub/mv"
SAVE_PATH="$PATH"; PATH="$SANDBOX/stub:$PATH"
OUT="$(bash "$AD" --from "$F" 2>&1)"; rc=$?
PATH="$SAVE_PATH"
assert_eq "$rc" "1" "mv failure exit"
echo "$OUT" | grep -qF "$F" && pass || fail "message lacks the folder: $OUT"
STAGED="$(ls -d "$CORE_DIR"/.adopt.*/p 2>/dev/null)"
[ -n "$STAGED" ] && pass || fail "staged copy gone"
echo "$OUT" | grep -qF "$STAGED" && pass || fail "message lacks the staged copy: $OUT"
assert_file "$STAGED/CLAUDE.md"; assert_file "$STAGED/docs/guide.md"; assert_file "$STAGED/.claude/settings.json"
assert_file "$F/src/a.sh"; assert_dir "$F/.git"
assert_eq "$(git -C "$F" log -1 --format=%s)" "Move internal Claude files to Core" "repo commit kept"
git -C "$F" cat-file -e HEAD~1:CLAUDE.md 2>/dev/null && pass || fail "history lost"
assert_no_file "$F/CLAUDE.local.md"

# =====================================================================================
# Old layout: <Core>/<name>/code moves to <Projects>/<name>
# =====================================================================================

new_sandbox; setup_core; sync_tools
mkold old-app
C0="$CORE_DIR/old-app/code"; K="$SANDBOX/Projects/old-app"
echo '.claude/worktrees/w1/' >> "$C0/.git/info/exclude"
git -C "$C0" worktree add -q "$C0/.claude/worktrees/w1" -b w1
assert_exit 0 bash "$AD" --from "$C0" --dry-run
echo "$OUT" | grep -qxF "move: $C0 -> $K" && pass || fail "plan lacks the move: $OUT"
assert_dir "$C0"; assert_no_file "$K"
assert_exit 0 bash "$AD" --from "$C0"
assert_eq "$(last_line "$OUT")" "open: $K" "last line (old layout)"
echo "$OUT" | grep -q '^warning:' && fail "warning: $OUT" || pass
assert_no_file "$C0"
assert_dir "$K/.git"; assert_file "$K/main.sh"
git -C "$K/.claude/worktrees/w1" status >/dev/null 2>&1 && pass || fail "worktree broken: $(git -C "$K/.claude/worktrees/w1" status 2>&1)"
assert_eq "$(git -C "$K/.claude/worktrees/w1" rev-parse --path-format=absolute --git-common-dir)" "$K/.git" "worktree points at the moved repo"
assert_eq "$(readlink "$K/CLAUDE.local.md")" "$CORE_DIR/old-app/CLAUDE.md" "link (old layout)"
assert_contains "$K/.claude/settings.local.json" "\"$CORE_DIR/old-app\""
assert_eq "$(git -C "$K" status --porcelain)" "" "moved repo dirty"
assert_eq "$(git -C "$K" log -1 --format=%s)" "Move internal Claude files to Core" "ignore lines commit"
assert_eq "$(git -C "$K" show --name-only --format= HEAD)" ".gitignore" "the repo commit holds only .gitignore"
grep -qxF CLAUDE.local.md "$K/.gitignore" && pass || fail ".gitignore lacks CLAUDE.local.md"
grep -qxF -- "- old-app — Old app — old-app/" "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md line: $(cat "$CORE_DIR/PROJECTS.md")"
assert_eq "$(grep -c '^- old-app ' "$CORE_DIR/PROJECTS.md")" "1" "one PROJECTS.md line"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Adopt old-app" "Core commit (old layout)"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "Core dirty (old layout)"
assert_contains "$K/.git/hooks/pre-commit" "corecrew hook shim"
assert_eq "$(bash "$SCRIPTS/lib.sh" layout old-app)" "new" "layout after the move"
bash "$WC" "$CORE_DIR/old-app" >/dev/null 2>&1 && pass || fail "wiki-check (old layout): $(bash "$WC" "$CORE_DIR/old-app" 2>&1)"

# old layout: <Core>/<name>/.claude/rules/*.md (0.4 and older) stop loading after the move, so they are
# folded into <Core>/<name>/CLAUDE.md under ## Rules in the "Adopt <name>" commit; the files are kept
new_sandbox; setup_core; sync_tools
mkold rule-old
RP="$CORE_DIR/rule-old"; mkdir -p "$RP/.claude/rules/web"
printf -- '---\npaths: ["src/**"]\n---\n\n# Tests\n\nWrite the test first.\n' > "$RP/.claude/rules/tests.md"
printf 'Use tabs.\n' > "$RP/.claude/rules/web/style.md"
printf '{}\n' > "$RP/.claude/settings.json"
git -C "$CORE_DIR" add -A && git -C "$CORE_DIR" commit -q -m "old rules"
assert_exit 0 bash "$AD" --from "$RP/code" --dry-run
echo "$OUT" | grep -qxF "fold into $RP/CLAUDE.md under ## Rules:" && pass || fail "old-layout plan lacks the fold: $OUT"
echo "$OUT" | grep -qxF "  .claude/rules/tests.md" && pass || fail "old-layout plan lacks tests.md: $OUT"
echo "$OUT" | grep -qxF "  .claude/rules/web/style.md" && pass || fail "old-layout plan lacks web/style.md: $OUT"
assert_eq "$(printf '%s\n' "$OUT" | sed -n '/^kept in Core, no longer loaded:$/,/^[^ ]/p' | grep -c 'rules/')" "0" "folded rules listed as kept: $OUT"
echo "$OUT" | grep -qxF "  .claude/settings.json" && pass || fail "old-layout plan lacks settings.json as kept: $OUT"
assert_not_contains "$RP/CLAUDE.md" "### tests"
assert_exit 0 bash "$AD" --from "$RP/code"
echo "$OUT" | grep -qxF "folded 2 rule file(s) into $RP/CLAUDE.md (## Rules)" && pass || fail "old-layout report lacks the fold: $OUT"
assert_contains "$RP/CLAUDE.md" "### tests"
assert_contains "$RP/CLAUDE.md" "Applies to: src/**"
assert_contains "$RP/CLAUDE.md" "#### Tests"
assert_contains "$RP/CLAUDE.md" "### web/style"
assert_contains "$RP/CLAUDE.md" "Use tabs."
assert_eq "$(grep -c '^## Rules$' "$RP/CLAUDE.md")" "1" "one Rules section (old layout)"
assert_file "$RP/.claude/rules/tests.md"; assert_file "$RP/.claude/rules/web/style.md"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Adopt rule-old" "Core commit (old-layout rules)"
git -C "$CORE_DIR" show --name-only --format= HEAD | grep -qxF rule-old/CLAUDE.md && pass || fail "the fold is not in the Adopt commit"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "Core dirty (old-layout rules)"
assert_eq "$(ls -A "$CORE_DIR" | grep -c '^\.adopt\.')" "0" "temp folder left in the Core"

# old layout: the target folder exists (in any letter case) -> refuse, nothing changed
new_sandbox; setup_core
mkold old-app
mkdir -p "$SANDBOX/Projects/old-app"
refuses "target exists: $SANDBOX/Projects/old-app" --from "$CORE_DIR/old-app/code"
refuses "target exists: $SANDBOX/Projects/old-app" --from "$CORE_DIR/old-app/code" --dry-run
rmdir "$SANDBOX/Projects/old-app"; mkdir -p "$SANDBOX/Projects/Old-App"
refuses "target exists: $SANDBOX/Projects/Old-App" --from "$CORE_DIR/old-app/code"
rmdir "$SANDBOX/Projects/Old-App"
# old layout: --name, --public-docs and --check do not apply
refuses "old layout: only --purpose and --dry-run apply" --from "$CORE_DIR/old-app/code" --check "make"
refuses "old layout: only --purpose and --dry-run apply" --from "$CORE_DIR/old-app/code" --name other-app

# old layout: df gives nothing usable -> the disk check fails closed; another disk -> refuse
mkdir -p "$SANDBOX/stub"; printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/stub/df"; chmod +x "$SANDBOX/stub/df"
SAVE_PATH="$PATH"; PATH="$SANDBOX/stub:$PATH"
refuses "different disk: could not compare the disks of $CORE_DIR and $SANDBOX/Projects" --from "$CORE_DIR/old-app/code"
PATH="$SAVE_PATH"
cat > "$SANDBOX/stub/df" <<'STUB'
#!/bin/sh
case "$*" in
  */Projects/Core*) printf 'Filesystem 512-blocks Used Available Capacity Mounted on\n/dev/fake 100 1 99 1%% /Volumes/Other Disk\n' ;;
  *) exec /bin/df "$@" ;;
esac
STUB
chmod +x "$SANDBOX/stub/df"
PATH="$SANDBOX/stub:$PATH"
refuses "different disk: $CORE_DIR and $SANDBOX/Projects are on different disks; put the Core on the same disk as $SANDBOX/Projects first" --from "$CORE_DIR/old-app/code"
refuses "different disk: $CORE_DIR and $SANDBOX/Projects are on different disks; put the Core on the same disk as $SANDBOX/Projects first" --from "$CORE_DIR/old-app/code" --dry-run
# the new layout moves no folder: another disk for the Core does not matter
mkrepo "$SANDBOX/Projects/disk-app"
assert_exit 0 bash "$AD" --from "$SANDBOX/Projects/disk-app" --dry-run
PATH="$SAVE_PATH"
rm -rf "$SANDBOX/stub"

# old layout: a failing mv -> nothing deleted, the output says where the project is
cat > "$SANDBOX/mvstub" <<'STUB'
#!/bin/sh
if [ "$1" = "$FAIL_MV_SRC" ]; then echo "mv: stub failure" >&2; exit 1; fi
exec /bin/mv "$@"
STUB
mkdir -p "$SANDBOX/stub"; mv "$SANDBOX/mvstub" "$SANDBOX/stub/mv"; chmod +x "$SANDBOX/stub/mv"
C0="$CORE_DIR/old-app/code"
SAVE_PATH="$PATH"; PATH="$SANDBOX/stub:$PATH"; export FAIL_MV_SRC="$C0"
OUT="$(bash "$AD" --from "$C0" 2>&1)"; rc=$?
PATH="$SAVE_PATH"; unset FAIL_MV_SRC
assert_eq "$rc" "1" "old layout mv failure exit"
echo "$OUT" | grep -qF "$C0" && pass || fail "message lacks the folder: $OUT"
assert_file "$C0/main.sh"; assert_no_file "$SANDBOX/Projects/old-app"
grep -qxF -- "- old-app — Old app — old-app/code/" "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md changed after a failed move"

# =====================================================================================
# The corecrew ignore lines
# =====================================================================================

# adopt adds the missing ones (never removes a user line), so a local .claude/settings.local.json,
# CLAUDE.local.md or a .claude/worktrees/<w> worktree never blocks `save`
new_sandbox; setup_core; sync_tools
F="$SANDBOX/Projects/gi-app"; mkdir -p "$F/src"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
printf 'node_modules/\n.env.*\n' > "$F/.gitignore"
printf '# Old\n' > "$F/CLAUDE.md"; echo 'echo a' > "$F/src/a.sh"
git -C "$F" add -A && git -C "$F" commit -q -m initial
WANT="$(grep -E '^(CLAUDE|AGENTS\.md$|\.claude/|docs/superpowers/|!?\.env)' "$SKILL/templates/code/gitignore-common")"
printf '%s\n' "$WANT" | grep -qxF CLAUDE.local.md && pass || fail "fixture: template lacks CLAUDE.local.md: $WANT"
[ "$(printf '%s\n' "$WANT" | grep -c .)" -ge 8 ] && pass || fail "fixture: template ignore lines: $WANT"
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qF "add to .gitignore (in the same commit):" && pass || fail "plan lacks the .gitignore lines: $OUT"
echo "$OUT" | grep -qxF "  .claude/" && pass || fail "plan lacks .claude/: $OUT"
echo "$OUT" | grep -qxF "  .env.*" && fail "plan re-adds a line the file has: $OUT" || pass
assert_eq "$(cat "$F/.gitignore")" "$(printf 'node_modules/\n.env.*')" "dry run changed .gitignore"
assert_exit 0 bash "$AD" --from "$F"
assert_eq "$(sed -n 1,2p "$F/.gitignore")" "$(printf 'node_modules/\n.env.*')" "user lines kept first"
while IFS= read -r l; do
  [ -n "$l" ] || continue
  grep -qxF -- "$l" "$F/.gitignore" && pass || fail ".gitignore lacks: $l"
done <<< "$WANT"
assert_eq "$(grep -cxF '.env.*' "$F/.gitignore")" "1" ".env.* duplicated"
assert_eq "$(git -C "$F" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" ".gitignore;.worktreeinclude;CLAUDE.md;" "repo commit files"
assert_eq "$(git -C "$F" status --porcelain)" "" "code repo dirty after adopt"
git -C "$F" worktree add -q "$F/.claude/worktrees/w1" -b w1 2>/dev/null
echo 'echo b' > "$F/src/b.sh"
OUT="$(cd "$F" && bash "$SCRIPTS/save" "Add b" 2>&1)"; rc=$?
assert_eq "$rc" "0" "save after adopt: $OUT"
echo "$OUT" | grep -qF "saved code" && pass || fail "save did not commit the code: $OUT"
assert_eq "$(git -C "$F" ls-files -- .claude CLAUDE.local.md)" "" "local Claude files were committed"
assert_eq "$(git -C "$F" status --porcelain)" "" "code repo dirty after save"
# a .gitignore that already has every line: nothing added, no repo commit
new_sandbox; setup_core
F="$SANDBOX/Projects/gi-full"; mkdir -p "$F"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
grep -v '^#' "$SKILL/templates/code/gitignore-common" > "$F/.gitignore"; echo x > "$F/main.sh"
printf 'mine\n' > "$F/.worktreeinclude"
git -C "$F" add -A && git -C "$F" commit -q -m initial
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qF "add to .gitignore" && fail "plan touches a complete .gitignore: $OUT" || pass
echo "$OUT" | grep -qF ".worktreeinclude" && fail "plan touches an existing .worktreeinclude: $OUT" || pass
assert_exit 0 bash "$AD" --from "$F"
assert_eq "$(git -C "$F" rev-list --count HEAD)" "1" "commit made without changes"
assert_eq "$(git -C "$F" status --porcelain)" "" "repo dirty (complete .gitignore)"
assert_eq "$(cat "$F/.worktreeinclude")" "mine" ".worktreeinclude of the user's changed"

# --- tracked nested CLAUDE.md / AGENTS.md stay in the repo; the plan and the report warn that the hooks
# will block changing them
new_sandbox; setup_core
F="$SANDBOX/Projects/nest-app"; mkrepo "$F"
mkdir -p "$F/tests/fixtures/w1" "$F/lib"
echo fx > "$F/tests/fixtures/w1/CLAUDE.md"; echo ag > "$F/lib/AGENTS.md"
git -C "$F" add -A && git -C "$F" commit -q -m fixtures
NW="warning: git tracks 2 CLAUDE.md / AGENTS.md file(s) that stay in the repo; after adopt, corecrew's hooks block changing or adding such files:"
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qxF "$NW" && pass || fail "plan lacks the nested warning: $OUT"
echo "$OUT" | grep -qxF "  tests/fixtures/w1/CLAUDE.md" && pass || fail "plan lacks the fixture: $OUT"
echo "$OUT" | grep -qxF "  lib/AGENTS.md" && pass || fail "plan lacks lib/AGENTS.md: $OUT"
echo "$OUT" | grep -qxF "  CLAUDE.md" && pass || fail "plan lacks the root CLAUDE.md copy: $OUT"
assert_exit 0 bash "$AD" --from "$F"
echo "$OUT" | grep -qxF "$NW" && pass || fail "report lacks the nested warning: $OUT"
echo "$OUT" | grep -qxF "  tests/fixtures/w1/CLAUDE.md" && pass || fail "report lacks the fixture: $OUT"
assert_eq "$(git -C "$F" ls-files -- tests/fixtures/w1/CLAUDE.md)" "tests/fixtures/w1/CLAUDE.md" "fixture still tracked"
# many: at most 15 listed, then a count
new_sandbox; setup_core
F="$SANDBOX/Projects/many-app"; mkrepo "$F"
i=1; while [ $i -le 17 ]; do mkdir -p "$F/fx/$i"; echo x > "$F/fx/$i/CLAUDE.md"; i=$((i + 1)); done
git -C "$F" add -A && git -C "$F" commit -q -m fixtures
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qxF "  ... and 2 more" && pass || fail "plan lacks the count: $OUT"
# the count is the full number
echo "$OUT" | grep -q "git tracks 17 CLAUDE.md" && pass || fail "plan count: $OUT"

# --- old layout: a CLAUDE.md that still names ../docs/ or `code/` paths gets a warning (not rewritten)
new_sandbox; setup_core
mkold stale-app
printf '\nSee ../docs/INDEX.md and `code/`.\n' >> "$CORE_DIR/stale-app/CLAUDE.md"
git -C "$CORE_DIR" add -A && git -C "$CORE_DIR" commit -q -m stale
BEFORE="$(cat "$CORE_DIR/stale-app/CLAUDE.md")"
SW="warning: $CORE_DIR/stale-app/CLAUDE.md still names ../docs/ or \`code/\` paths from the old layout; they now point to the wrong place: write them as $CORE_DIR/stale-app/docs/... and the code folder $SANDBOX/Projects/stale-app"
assert_exit 0 bash "$AD" --from "$CORE_DIR/stale-app/code"
echo "$OUT" | grep -qxF "$SW" && pass || fail "no stale-path warning: $OUT"
assert_eq "$(cat "$CORE_DIR/stale-app/CLAUDE.md")" "$BEFORE" "CLAUDE.md rewritten"

# --- AGENTS.md moves to the Core like CLAUDE.md (personal agent instructions; guard-code blocks it)
new_sandbox; setup_core
F="$SANDBOX/Projects/ag-app"; mkrepo "$F"
printf '# Agents\n\nCross-tool rules.\n' > "$F/AGENTS.md"; printf 'sub\n' > "$F/src/AGENTS.md"
git -C "$F" add -A && git -C "$F" commit -q -m agents
assert_exit 0 bash "$AD" --from "$F" --dry-run
echo "$OUT" | grep -qxF "  AGENTS.md" && pass || fail "plan lacks AGENTS.md: $OUT"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/ag-app"
assert_contains "$P/AGENTS.md" "Cross-tool rules."
# M7: the Core copy blocks the AGENTS.md link; it is kept and a warning names it (adopt goes on)
echo "$OUT" | grep -q "^warning:.*$P/AGENTS.md" && pass || fail "no warning naming the Core AGENTS.md: $OUT"
[ -L "$F/AGENTS.md" ] && fail "AGENTS.md linked despite the Core copy" || pass
assert_no_file "$F/AGENTS.md"
git -C "$F" show --name-only --format= HEAD | grep -qxF AGENTS.md && pass || fail "repo commit lacks AGENTS.md"
grep -qxF AGENTS.md "$F/.gitignore" && pass || fail ".gitignore lacks AGENTS.md"
git -C "$CORE_DIR" ls-files -- ag-app/AGENTS.md | grep -qxF ag-app/AGENTS.md && pass || fail "AGENTS.md not in the Core commit"
# like a nested CLAUDE.md, a nested AGENTS.md is not moved (only the root one is)
assert_file "$F/src/AGENTS.md"

finish
