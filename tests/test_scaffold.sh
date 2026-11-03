#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S="$SKILL/scripts/scaffold.sh"

# --- valid name creates the full layout
new_sandbox
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
P="$CORE_DIR/demo-app"
for f in CLAUDE.md docs/INDEX.md docs/brief.md docs/architecture.md \
         docs/decisions/001-stack-and-architecture.md .claude/rules/tests.md \
         code/.gitignore code/.claude/settings.local.json code/.worktreeinclude; do
  assert_file "$P/$f"
done
assert_dir "$P/docs/features"
assert_dir "$P/code/.git"
assert_dir "$CORE_DIR/.git"
assert_file "$CORE_DIR/.gitignore"
assert_contains "$CORE_DIR/.gitignore" "*/code/"
assert_file "$CORE_DIR/README.md"

# docs pages have full YAML front matter
for f in INDEX.md brief.md architecture.md decisions/001-stack-and-architecture.md; do
  head -1 "$P/docs/$f" | grep -qx -- '---' && pass || fail "$f: no front matter"
  for k in title: description: status: files: related: updated:; do
    assert_contains "$P/docs/$f" "$k"
  done
done
assert_contains "$P/docs/brief.md" "stage:"

# CLAUDE.md: plain link to wiki, no @-imports, placeholders filled
assert_contains "$P/CLAUDE.md" "../docs/INDEX.md"
grep -qE '^\s*-?\s*@' "$P/CLAUDE.md" && fail "CLAUDE.md has @-import" || pass
grep -rq '{{' "$P" --exclude-dir=.git && fail "unfilled placeholder" || pass

# settings.local.json grants the absolute project dir
assert_contains "$P/code/.claude/settings.local.json" "\"$P\""
# rules use worktree-safe path pattern
assert_contains "$P/.claude/rules/tests.md" "code/**/"
# code .gitignore blocks internal files
for pat in CLAUDE.md CLAUDE.local.md .claude/ docs/superpowers/ .env '*.pem' '*.key'; do
  assert_contains "$P/code/.gitignore" "$pat"
done
# PROJECTS.md gets exactly one line
c=$(grep -c '^- demo-app ' "$CORE_DIR/PROJECTS.md"); assert_eq "$c" "1" "PROJECTS.md lines"
assert_contains "$CORE_DIR/PROJECTS.md" "Test app"

# --- second run changes nothing
before=$(tree_sum "$CORE_DIR")
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
echo "$OUT" | grep -q '^created' && fail "second run created files" || pass
echo "$OUT" | grep -q '^skipped' && pass || fail "second run printed no skipped lines"
after=$(tree_sum "$CORE_DIR")
assert_eq "$before" "$after" "tree changed on re-run"

# --- invalid names
for bad in MyApp "my app" проект 1app a -app app- ; do
  new_sandbox
  assert_exit 2 bash "$S" --name "$bad"
  assert_no_file "$CORE_DIR/$bad"
done

# --- dry run touches nothing
new_sandbox
assert_exit 0 bash "$S" --name dry-app --dry-run
assert_no_file "$CORE_DIR"
echo "$OUT" | grep -q 'would create' && pass || fail "dry-run printed nothing"

# a purpose with line breaks becomes one line
new_sandbox
assert_exit 0 bash "$S" --name nl-app --purpose "$(printf 'First line.\r\nSecond line.')"
assert_eq "$(grep -c 'nl-app' "$CORE_DIR/PROJECTS.md")" "1" "PROJECTS.md entry split"
assert_contains "$CORE_DIR/PROJECTS.md" "First line. Second line."
assert_contains "$CORE_DIR/nl-app/CLAUDE.md" "First line. Second line."

finish
