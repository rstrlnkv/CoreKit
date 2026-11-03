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
# state <dir>... — everything a refusal must not change: files, HEAD, status, branches
state() {
  local d; for d in "$@"; do
    [ -d "$d" ] || { echo "no $d"; continue; }
    tree_sum "$d"
    [ -d "$d/.git" ] && { git -C "$d" rev-parse HEAD 2>&1; git -C "$d" status --porcelain 2>&1; }
  done
}
last_line() { printf '%s\n' "$1" | tail -1; }
# refuses <want line> <args...> — exit 2, exactly that one line, nothing changed in $SANDBOX
refuses() {
  local want="$1"; shift
  local before after
  before="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
  OUT="$(bash "$AD" "$@" 2>&1)"; local rc=$?
  after="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
  assert_eq "$rc" "2" "refusal exit ($want)"
  assert_eq "$OUT" "$want" "refusal message"
  assert_eq "$after" "$before" "refusal changed something ($want)"
}

# --- success: files move, history stays, wiki is green
new_sandbox; setup_core
F="$SANDBOX/in/my-app"; mkrepo "$F"
N0="$(git -C "$F" rev-list --count HEAD)"
assert_exit 0 bash "$AD" --from "$F"
OUT1="$OUT"
P="$CORE_DIR/my-app"
assert_eq "$(last_line "$OUT1")" "open: $P/code" "last line"
echo "$OUT1" | grep -qxF "old: $F" && pass || fail "no old: line: $OUT1"
echo "$OUT1" | grep -qxF "new: $P/code" && pass || fail "no new: line: $OUT1"
assert_no_file "$F"
for f in CLAUDE.md docs/guide.md .claude/settings.json docs/INDEX.md docs/brief.md docs/architecture.md \
         docs/decisions/001-stack-and-architecture.md .claude/rules/tests.md; do
  assert_file "$P/$f"
done
assert_dir "$P/docs/knowledge"; assert_dir "$P/docs/features"
assert_no_file "$P/.claude/settings.local.json"
assert_no_file "$P/.claude/worktrees"
C="$P/code"
assert_eq "$(git -C "$C" rev-list --count HEAD)" "$((N0 + 1))" "commit count"
assert_eq "$(git -C "$C" log -1 --format=%s)" "Move internal Claude files to Core" "repo commit subject"
assert_eq "$(git -C "$C" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" \
  ".claude/settings.json;CLAUDE.md;docs/guide.md;" "removed files"
assert_file "$C/.claude/settings.local.json"
assert_file "$C/.claude/worktrees/w/f.txt"
assert_file "$C/src/a.sh"
assert_no_file "$C/CLAUDE.md"; assert_no_file "$C/docs"
assert_eq "$(git -C "$C" status --porcelain)" "" "code repo dirty"
assert_eq "$(git -C "$C" log --format=%s | tail -1)" "initial" "history kept"
assert_contains "$P/CLAUDE.md" "# Old project"
assert_contains "$P/CLAUDE.md" "check: <set after scaffolding>"
assert_not_contains "$P/CLAUDE.md" "public-docs:"
assert_contains "$P/docs/guide.md" "# Guide"
assert_contains "$P/docs/guide.md" "How to use it."
head -1 "$P/docs/guide.md" | grep -qx -- '---' && pass || fail "guide.md: no front matter added"
assert_contains "$P/docs/INDEX.md" "guide.md"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check not green: $(bash "$WC" "$P" 2>&1)"
echo "$OUT1" | grep -q 'wiki-check:' && fail "wiki problems printed: $OUT1" || pass
assert_contains "$C/.git/hooks/pre-commit" "coredev hook shim"
assert_contains "$C/.git/hooks/pre-push" "coredev hook shim"
assert_contains "$CORE_DIR/.git/hooks/pre-push" "coredev hook shim"
grep -q '^- my-app — .* — my-app/code/$' "$CORE_DIR/PROJECTS.md" && pass || fail "PROJECTS.md line"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Adopt my-app" "Core commit"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "Core dirty"
assert_eq "$(git -C "$CORE_DIR" show --name-only --format= HEAD | sed 's|/.*||' | LC_ALL=C sort -u | tr '\n' ';')" \
  "PROJECTS.md;my-app;" "Core commit scope"
ls -A "$CORE_DIR" | grep -q '^\.adopt' && fail "temp dir left in Core" || pass

# --- --check, --public-docs: docs/ stays in the repo and is listed in CLAUDE.md
new_sandbox; setup_core
F="$SANDBOX/in/pub-app"; mkrepo "$F"
assert_exit 0 bash "$AD" --from "$F" --public-docs "docs/" --check "bash tests/run.sh"
P="$CORE_DIR/pub-app"; C="$P/code"
assert_file "$C/docs/guide.md"
assert_no_file "$P/docs/guide.md"
assert_contains "$P/CLAUDE.md" "public-docs: docs/"
assert_contains "$P/CLAUDE.md" "check: bash tests/run.sh"
assert_not_contains "$P/CLAUDE.md" "check: <set after scaffolding>"
assert_eq "$(git -C "$C" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ';')" \
  ".claude/settings.json;CLAUDE.md;" "removed files (public docs kept)"
assert_file "$P/docs/INDEX.md"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (public docs): $(bash "$WC" "$P" 2>&1)"

# --- --dry-run changes nothing, prints the plan
new_sandbox; setup_core
F="$SANDBOX/in/dry-app"; mkrepo "$F"
before="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
assert_exit 0 bash "$AD" --from "$F" --dry-run --public-docs "docs/guide.md"
after="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
assert_eq "$after" "$before" "dry run changed something"
echo "$OUT" | grep -qF "CLAUDE.md" && pass || fail "plan lacks CLAUDE.md: $OUT"
echo "$OUT" | grep -qF "$CORE_DIR/dry-app/code" && pass || fail "plan lacks the new path: $OUT"
echo "$OUT" | grep -qF "docs/guide.md" && pass || fail "plan lacks the public page: $OUT"
echo "$OUT" | grep -qxF "open: $CORE_DIR/dry-app/code" && fail "dry run printed open:" || pass
assert_exit 0 bash "$AD" --from "$F" --public-docs "docs/guide.md"
bash "$WC" "$CORE_DIR/dry-app" >/dev/null 2>&1 && pass || fail "wiki-check (public page): $(bash "$WC" "$CORE_DIR/dry-app" 2>&1)"

# --- refusals: one line, exit 2, nothing changed
new_sandbox; setup_core
mkdir -p "$SANDBOX/in/plain"; echo hi > "$SANDBOX/in/plain/a.txt"
refuses "not a git repo" --from "$SANDBOX/in/plain"
refuses "not a git repo" --from "$SANDBOX/in/missing"
F="$SANDBOX/in/dirty-app"; mkrepo "$F"; echo more >> "$F/src/a.sh"
refuses "uncommitted changes" --from "$F"
echo new > "$F/untracked.txt"; git -C "$F" checkout -q -- src/a.sh
refuses "uncommitted changes" --from "$F"
rm "$F/untracked.txt"
mkdir -p "$CORE_DIR/inner"; mkrepo "$CORE_DIR/inner/code"
refuses "already inside Core" --from "$CORE_DIR/inner/code"
ln -s "$CORE_DIR" "$SANDBOX/in/link"
refuses "already inside Core" --from "$SANDBOX/in/link/inner/code"
rm "$SANDBOX/in/link"
mkrepo "$SANDBOX/in/My App"
refuses "invalid project name 'My App' (use --name)" --from "$SANDBOX/in/My App"
refuses "invalid project name 'Bad_Name' (use --name)" --from "$F" --name Bad_Name
refuses "invalid project name 'ab' (use --name)" --from "$F" --name ab
mkdir -p "$CORE_DIR/taken"
refuses "target exists: $CORE_DIR/taken" --from "$F" --name taken
# a name that is a dangling symlink also counts as existing
ln -s "$SANDBOX/nowhere" "$CORE_DIR/dangling"
refuses "target exists: $CORE_DIR/dangling" --from "$F" --name dangling
rm "$CORE_DIR/dangling"
# --dry-run refuses too
mkrepo "$SANDBOX/in/ok-app"
refuses "invalid project name 'Bad Name' (use --name)" --from "$SANDBOX/in/ok-app" --name "Bad Name" --dry-run

# Core not set up
new_sandbox
F="$SANDBOX/in/lonely"; mkrepo "$F"
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
F="$SANDBOX/in/hook-app"; mkrepo "$F"
printf '#!/bin/sh\necho no >&2\nexit 1\n' > "$F/.git/hooks/pre-commit"; chmod +x "$F/.git/hooks/pre-commit"
before="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
OUT="$(bash "$AD" --from "$F" 2>&1)"; rc=$?
assert_eq "$rc" "2" "commit failure exit"
echo "$OUT" | grep -q "could not commit" && pass || fail "commit failure message: $OUT"
after="$(state "$SANDBOX/in" "$CORE_DIR"; find "$SANDBOX" -not -path '*/.git/*' | LC_ALL=C sort)"
assert_eq "$after" "$before" "commit failure changed something"
assert_eq "$(git -C "$F" diff --cached --name-only)" "" "index not restored"

# --- spaces and non-ASCII characters in the folder and in file names
new_sandbox; setup_core
F="$SANDBOX/in/Мой проект"; mkrepo "$F"
printf '# Заметки\n\nТекст.\n' > "$F/docs/гайд app.md"
git -C "$F" add -A && git -C "$F" commit -q -m "add note"
assert_exit 2 bash "$AD" --from "$F"
assert_eq "$OUT" "invalid project name 'Мой проект' (use --name)" "non-ASCII name refused"
assert_exit 0 bash "$AD" --from "$F" --name my-proj
P="$CORE_DIR/my-proj"
assert_eq "$(last_line "$OUT")" "open: $P/code" "last line (spaces)"
echo "$OUT" | grep -qxF "old: $F" && pass || fail "old: line: $OUT"
assert_file "$P/docs/гайд app.md"
assert_contains "$P/docs/гайд app.md" "Текст."
assert_contains "$P/docs/INDEX.md" "гайд app.md"
assert_file "$P/code/src/a.sh"
assert_eq "$(git -C "$P/code" status --porcelain)" "" "code repo dirty"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (non-ASCII): $(bash "$WC" "$P" 2>&1)"

# --- a repo with no internal files: no repo commit; CLAUDE.md comes from the template
new_sandbox; setup_core
F="$SANDBOX/in/bare-app"; mkdir -p "$F"; git init -q "$F" && git -C "$F" symbolic-ref HEAD refs/heads/main
echo code > "$F/main.sh"; git -C "$F" add -A && git -C "$F" commit -q -m "initial"
assert_exit 0 bash "$AD" --from "$F" --check "make test"
P="$CORE_DIR/bare-app"
assert_eq "$(git -C "$P/code" rev-list --count HEAD)" "1" "no repo commit"
assert_contains "$P/CLAUDE.md" "# bare-app"
assert_contains "$P/CLAUDE.md" "check: make test"
assert_not_contains "$P/CLAUDE.md" "check: <set after scaffolding>"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (bare): $(bash "$WC" "$P" 2>&1)"

# --- an existing check: line stays unless --check is given; existing wiki front matter is kept
new_sandbox; setup_core
F="$SANDBOX/in/keep-app"; mkrepo "$F"
printf '# Old\n\ncheck: npm test\n' > "$F/CLAUDE.md"
printf -- '---\ntitle: Mine\ndescription: Does things.\nstatus: active\n---\n\n# Mine\n' > "$F/docs/guide.md"
git -C "$F" add -A && git -C "$F" commit -q -m "wiki"
assert_exit 0 bash "$AD" --from "$F"
P="$CORE_DIR/keep-app"
assert_contains "$P/CLAUDE.md" "check: npm test"
assert_eq "$(grep -c '^check:' "$P/CLAUDE.md")" "1" "check lines"
assert_contains "$P/docs/guide.md" "title: Mine"
assert_contains "$P/docs/guide.md" "description: Does things."
assert_eq "$(grep -c '^title:' "$P/docs/guide.md")" "1" "title lines"
bash "$WC" "$P" >/dev/null 2>&1 && pass || fail "wiki-check (front matter): $(bash "$WC" "$P" 2>&1)"

finish
