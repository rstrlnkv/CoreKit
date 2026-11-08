#!/usr/bin/env bash
# tests/fixtures/make-test-coredev.sh: the hand-made end-to-end project.
source "$(dirname "$0")/lib.sh"
B="$ROOT/tests/fixtures/make-test-coredev.sh"
WC="$SCRIPTS/wiki-check.sh"

# state <dir> — everything a refusal must not change: files, HEAD, status
state() { tree_sum "$1"; git -C "$1" rev-parse HEAD 2>&1; git -C "$1" status --porcelain 2>&1; }

# --- success
new_sandbox; setup_core
P="$CORE_DIR/test-coredev"; C="$SANDBOX/Projects/test-coredev"
assert_exit 0 bash "$B" "$CORE_DIR"
OUT1="$OUT"
assert_eq "$(printf '%s\n' "$OUT1" | tail -1)" "$C" "last line is the code folder"
echo "$OUT1" | grep -q '^created ' && pass || fail "no created lines: $OUT1"

# Core side
assert_file "$P/CLAUDE.md"
assert_contains "$P/CLAUDE.md" "check: bash tests/run.sh"
assert_file "$P/docs/INDEX.md"; assert_dir "$P/docs/knowledge"
assert_exit 0 bash "$WC" "$P"
assert_eq "$OUT" "" "wiki-check output"
# typed front matter, generated INDEX listing the feature page, Obsidian vault files
head -3 "$P/docs/features/add.md" | grep -qx 'type: feature' && pass || fail "add.md: type: feature is not first"
grep -q '^title:' "$P/docs/features/add.md" && fail "add.md has title:" || pass
assert_exit 0 bash "$SCRIPTS/wiki-index.sh" "$P" --check
assert_eq "$OUT" "" "wiki-index --check output"
assert_contains "$P/docs/INDEX.md" "[[add]]"
assert_file "$P/docs/wiki.base"; assert_file "$P/docs/.obsidian/app.json"; assert_file "$P/docs/.obsidian/.gitignore"
grep -rl '^title:' "$P/docs" --include='*.md' >/dev/null 2>&1 && fail "a fixture page has title:" || pass
grep -l '^files:' "$P"/docs/features/*.md >/dev/null 2>&1 && pass || fail "no feature page with files:"
grep -rq -e '^  - add.sh$' -e "^files: \\[add.sh\\]$" "$P/docs/features" && pass || fail "no page lists add.sh"
assert_contains "$CORE_DIR/PROJECTS.md" "- test-coredev — "
assert_eq "$(grep -c '^- test-coredev ' "$CORE_DIR/PROJECTS.md")" "1" "PROJECTS.md lines"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Add test-coredev fixture" "Core commit"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "Core dirty after build"
assert_eq "$(git -C "$CORE_DIR" ls-files | grep -c '^test-coredev/code')" "0" "code files in the Core repo"
assert_no_file "$P/code"
assert_eq "$(bash "$SCRIPTS/lib.sh" layout test-coredev)" "new" "layout"
assert_eq "$(bash "$SCRIPTS/lib.sh" code-dir test-coredev)" "$C" "code dir"
assert_eq "$(readlink "$C/CLAUDE.local.md")" "$P/CLAUDE.md" "CLAUDE.local.md link"
assert_contains "$C/.gitignore" "CLAUDE.local.md"
assert_file "$C/.claude/settings.local.json"; assert_file "$C/.worktreeinclude"
assert_contains "$CORE_DIR/PROJECTS.md" "— test-coredev/"

# Code side
assert_eq "$(git -C "$C" rev-list --count HEAD)" "1" "code commits"
assert_eq "$(git -C "$C" symbolic-ref --short HEAD)" "main" "code branch"
assert_eq "$(git -C "$C" status --porcelain)" "" "code repo dirty"
assert_file "$C/add.sh"; assert_file "$C/tests/run.sh"
assert_no_file "$C/CLAUDE.md"; assert_no_file "$C/docs"
assert_eq "$(git -C "$C" ls-files | grep -c -e CLAUDE.local.md -e settings.local.json)" "0" "private files tracked"
assert_exit 0 bash -c "cd '$C' && bash tests/run.sh"
echo "$OUT" | grep -q 'ALL TESTS PASSED' && pass || fail "run.sh did not print ALL TESTS PASSED: $OUT"
assert_eq "$(cd "$C" && bash add.sh 2 3)" "6" "planted bug: add 2 3"
assert_eq "$(cd "$C" && bash add.sh 2 2)" "4" "add 2 2"

# Hooks: shims in both repos
assert_contains "$C/.git/hooks/pre-commit" "corecrew hook shim"
assert_contains "$C/.git/hooks/pre-push" "corecrew hook shim"
assert_contains "$CORE_DIR/.git/hooks/pre-push" "corecrew hook shim"

# --- second run: refused, exit 2, one plain line, nothing changed
before="$(state "$CORE_DIR"; state "$C")"
assert_exit 2 bash "$B" "$CORE_DIR"
assert_eq "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1" "refusal is one line: $OUT"
after="$(state "$CORE_DIR"; state "$C")"
assert_eq "$after" "$before" "second run changed something"

# --- a Core that is not set up: refused, nothing created
new_sandbox
mkdir -p "$CORE_DIR"
assert_exit 2 bash "$B" "$CORE_DIR"
assert_eq "$(find "$CORE_DIR" | wc -l | tr -d ' ')" "1" "not-ready Core was touched"
new_sandbox
assert_exit 2 bash "$B" "$CORE_DIR"
assert_no_file "$CORE_DIR"
new_sandbox; setup_core
assert_exit 2 bash "$B"       # no argument
assert_no_file "$CORE_DIR/test-coredev"
assert_no_file "$SANDBOX/Projects/test-coredev"

# --- a folder beside the Core in the way: refused, exit 2, nothing changed
new_sandbox; setup_core
mkdir -p "$SANDBOX/Projects/test-coredev"; echo mine > "$SANDBOX/Projects/test-coredev/x"
before="$(state "$CORE_DIR")"
assert_exit 2 bash "$B" "$CORE_DIR"
assert_eq "$(state "$CORE_DIR")" "$before" "Core changed on refusal"
assert_no_file "$CORE_DIR/test-coredev"
assert_eq "$(ls "$SANDBOX/Projects/test-coredev")" "x" "foreign folder touched"

# --- an existing PROJECTS.md line is kept, not doubled (a folder removed by hand, line left)
new_sandbox; setup_core
printf -- '- test-coredev — mine — test-coredev/\n' >> "$CORE_DIR/PROJECTS.md"
git -C "$CORE_DIR" add PROJECTS.md; git -C "$CORE_DIR" commit -q -m "line"
assert_exit 0 bash "$B" "$CORE_DIR"
assert_eq "$(grep -c '^- test-coredev ' "$CORE_DIR/PROJECTS.md")" "1" "PROJECTS.md line doubled"
assert_contains "$CORE_DIR/PROJECTS.md" "mine"

# --- other Core content is not touched, not even unrelated uncommitted files
new_sandbox; setup_core
printf 'keep\n' > "$CORE_DIR/notes.txt"
assert_exit 0 bash "$B" "$CORE_DIR"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "?? notes.txt" "unrelated file committed or lost"
assert_eq "$(cat "$CORE_DIR/notes.txt")" "keep" "notes.txt"

# --- no git identity: plain message, exit 1, nothing created
new_sandbox; setup_core
noid() { env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$SANDBOX/nohome" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true "$@"; }
assert_exit 1 noid bash "$B" "$CORE_DIR"
echo "$OUT" | grep -q 'user.name' && pass || fail "no hint about git identity: $OUT"
assert_no_file "$CORE_DIR/test-coredev"
assert_no_file "$SANDBOX/Projects/test-coredev"

finish
