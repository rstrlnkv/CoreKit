#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S="$SKILL/scripts/scaffold.sh"

# --- Core not set up: scaffold refuses (exit 3) and creates nothing
new_sandbox
assert_exit 3 bash "$S" --name demo-app
echo "$OUT" | grep -qF "Core is not set up at $CORE_DIR: run setup-core.sh first" && pass || fail "message: $OUT"
assert_no_file "$CORE_DIR"
assert_exit 3 bash "$S" --name demo-app --dry-run
assert_no_file "$CORE_DIR"
# a .coredev without "schema:" still counts as not set up (e.g. only an app id prefix)
mkdir -p "$CORE_DIR"; printf 'app-id-prefix: com.x\n' > "$CORE_DIR/.coredev"
assert_exit 3 bash "$S" --name demo-app
assert_no_file "$CORE_DIR/demo-app"
# an invalid name is reported before the Core check
assert_exit 2 bash "$S" --name "Bad Name"

# --- valid name creates the full layout
new_sandbox; setup_core
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
P="$CORE_DIR/demo-app"
for f in CLAUDE.md docs/INDEX.md docs/brief.md docs/architecture.md \
         docs/decisions/001-stack-and-architecture.md \
         docs/wiki.base docs/.obsidian/app.json docs/.obsidian/.gitignore; do
  assert_file "$P/$f"
done
K="$(dirname "$CORE_DIR")/demo-app"
for f in .gitignore .claude/settings.local.json .worktreeinclude; do assert_file "$K/$f"; done
assert_no_file "$P/code"; assert_no_file "$P/.claude/rules"
assert_dir "$P/docs/features"; assert_dir "$P/docs/specs"; assert_dir "$P/docs/plans"
assert_dir "$K/.git"
assert_dir "$CORE_DIR/.git"
assert_file "$CORE_DIR/.gitignore"
assert_not_contains "$SKILL/templates/core/gitignore" "*/code/"
assert_file "$CORE_DIR/README.md"
# scaffold copies no machinery into Core
assert_no_file "$CORE_DIR/bin"; assert_no_file "$CORE_DIR/hooks"

# docs pages have typed front matter: type first, then status, description, files, related, updated; no title
for f in brief.md architecture.md decisions/001-stack-and-architecture.md; do
  head -1 "$P/docs/$f" | grep -qx -- '---' && pass || fail "$f: no front matter"
  fm="$(awk 'NR==1 { next } /^---[ \t]*$/ { exit } { print }' "$P/docs/$f")"
  keys="$(printf '%s\n' "$fm" | sed -n 's/^\([a-z][a-z]*\):.*/\1/p' | grep -v '^stage$' | tr '\n' ' ')"
  assert_eq "$keys" "type status description files related updated " "$f: front matter fields"
  grep -q '^title:' "$P/docs/$f" && fail "$f: has title:" || pass
done
assert_contains "$P/docs/brief.md" "type: brief"
assert_contains "$P/docs/architecture.md" "type: architecture"
assert_contains "$P/docs/decisions/001-stack-and-architecture.md" "type: decision"
assert_contains "$P/docs/brief.md" "stage:"
# no page in the wiki carries a title: field; INDEX.md and wiki.base have no front matter
grep -rl '^title:' "$P/docs" --include='*.md' >/dev/null 2>&1 && fail "a page has title:" || pass
head -1 "$P/docs/INDEX.md" | grep -qx -- '---' && fail "INDEX.md has front matter" || pass
head -1 "$P/docs/wiki.base" | grep -qx -- '---' && fail "wiki.base has front matter" || pass
# INDEX.md is generated: it equals what wiki-index.sh writes, and --check is silent
cp "$P/docs/INDEX.md" "$SANDBOX/index.scaffolded"
assert_exit 0 bash "$SCRIPTS/wiki-index.sh" "$P" --check
assert_eq "$OUT" "" "wiki-index --check output"
bash "$SCRIPTS/wiki-index.sh" "$P" >/dev/null
cmp -s "$SANDBOX/index.scaffolded" "$P/docs/INDEX.md" && pass || fail "INDEX.md differs from wiki-index.sh output"
assert_contains "$P/docs/INDEX.md" "[[brief]]"
assert_contains "$P/docs/INDEX.md" "[[architecture]]"

# Obsidian vault files (exact values)
assert_eq "$(cat "$P/docs/.obsidian/app.json")" '{"useMarkdownLinks": false, "newLinkFormat": "shortest", "alwaysUpdateLinks": true}' "app.json"
assert_eq "$(cat "$P/docs/.obsidian/.gitignore")" "$(printf 'workspace*\ncache')" ".obsidian/.gitignore"
W="$P/docs/wiki.base"
assert_contains "$W" "type: table"
assert_contains "$W" 'file.ext == "md"'
assert_contains "$W" "INDEX"
assert_contains "$W" "knowledge/"
assert_contains "$W" "standards/"
for col in file.name type status updated description; do assert_contains "$W" "- $col"; done
assert_contains "$W" "groupBy"
grep -A3 'groupBy' "$W" | grep -q 'type' && pass || fail "wiki.base: not grouped by type"
grep -A6 'sort' "$W" | grep -q 'updated' && pass || fail "wiki.base: no sort by updated"
grep -A6 'sort' "$W" | grep -qi 'desc' && pass || fail "wiki.base: sort is not descending"
# the five columns appear in order
assert_eq "$(grep -E '^[[:space:]]*- (file\.name|type|status|updated|description)[[:space:]]*$' "$W" | sed 's/^[[:space:]]*- //' | head -5 | tr '\n' ' ')" "file.name type status updated description " "wiki.base column order"
# the template INDEX.md.tmpl is gone: INDEX is generated, not copied
assert_no_file "$SKILL/templates/docs/INDEX.md.tmpl"
# new-project text templates ship the vault files
for t in wiki.base obsidian-app.json obsidian-gitignore; do assert_file "$SKILL/templates/docs/$t"; done

# CLAUDE.md: plain link to wiki, no @-imports, placeholders filled
assert_contains "$P/CLAUDE.md" "$P/docs/INDEX.md"
assert_contains "$P/CLAUDE.md" "## Rules"
assert_contains "$P/CLAUDE.md" '**/test/**'
assert_contains "$P/CLAUDE.md" "$P/docs/specs/"
assert_contains "$P/CLAUDE.md" "$P/docs/plans/"
assert_contains "$P/CLAUDE.md" "wiki-index.sh"
assert_contains "$P/CLAUDE.md" "wikilink"
assert_not_contains "$P/CLAUDE.md" "superpowers"
grep -qF '../docs/' "$P/CLAUDE.md" && fail "CLAUDE.md has ../docs/" || pass
grep -qE '^\s*-?\s*@' "$P/CLAUDE.md" && fail "CLAUDE.md has @-import" || pass
grep -rq '{{' "$P" --exclude-dir=.git && fail "unfilled placeholder" || pass

# wiki: a fresh scaffold passes wiki-check; CLAUDE.md has the check: line; knowledge/ exists
assert_exit 0 bash "$SCRIPTS/wiki-check.sh" "$P"
[ -z "$OUT" ] && pass || fail "wiki-check printed: $OUT"
grep -q '^check: ' "$P/CLAUDE.md" && pass || fail "CLAUDE.md has no 'check: ' line"
assert_eq "$(grep -c '^check: ' "$P/CLAUDE.md")" "1" "check: lines"
assert_dir "$P/docs/knowledge"
# the map is a plain path in CLAUDE.md, not a link wiki-check would resolve elsewhere
grep -qF '](../docs/INDEX.md' "$P/CLAUDE.md" && fail "CLAUDE.md links INDEX.md" || pass
# a page added without regenerating the index turns wiki-check red; wiki-index.sh makes it green
printf -- '---\ntype: feature\nstatus: draft\ndescription: d\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# T\n' \
  > "$P/docs/features/t.md"
assert_exit 1 bash "$SCRIPTS/wiki-check.sh" "$P"
echo "$OUT" | grep -qF 'wiki-check: INDEX.md: INDEX.md stale' && pass || fail "red output: $OUT"
assert_exit 0 bash "$SCRIPTS/wiki-index.sh" "$P"
assert_contains "$P/docs/INDEX.md" "[[t]] d"
assert_exit 0 bash "$SCRIPTS/wiki-check.sh" "$P"
assert_eq "$OUT" "" "wiki-check after wiki-index"
# an old-format page (title:, no type) is reported
printf -- '---\ntitle: Old\ndescription: d\nstatus: draft\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# Old\n' \
  > "$P/docs/features/old.md"
assert_exit 1 bash "$SCRIPTS/wiki-check.sh" "$P"
echo "$OUT" | grep -qF 'wiki-check: features/old.md: missing front matter field type' && pass || fail "old page not reported: $OUT"
rm -f "$P/docs/features/t.md" "$P/docs/features/old.md"
bash "$SCRIPTS/wiki-index.sh" "$P" >/dev/null

# settings.local.json grants the absolute project dir
assert_contains "$K/.claude/settings.local.json" "\"$P\""
# the private CLAUDE.md reaches the code folder through a symlink
[ -L "$K/CLAUDE.local.md" ] && pass || fail "CLAUDE.local.md is not a symlink"
assert_eq "$(readlink "$K/CLAUDE.local.md")" "$P/CLAUDE.md" "symlink target"
# the same file is the cross-tool AGENTS.md (M7); the scaffold output names it
[ -L "$K/AGENTS.md" ] && pass || fail "AGENTS.md is not a symlink"
assert_eq "$(readlink "$K/AGENTS.md")" "$P/CLAUDE.md" "AGENTS.md target"
assert_no_file "$P/AGENTS.md"
# code .gitignore blocks internal files
for pat in CLAUDE.md CLAUDE.local.md .claude/ docs/superpowers/ .env '*.pem' '*.key' \
           '!.env.example' '!.env.sample' '!.env.template'; do
  assert_contains "$K/.gitignore" "$pat"
done
# the .env templates stay committable; real .env files are ignored
for f in .env.example .env.sample .env.template; do
  git -C "$K" check-ignore -q "$f" && fail "$f is ignored" || pass
done
for f in .env .env.local .env.production; do
  git -C "$K" check-ignore -q "$f" && pass || fail "$f is not ignored"
done
# PROJECTS.md gets exactly one line
c=$(grep -c '^- demo-app ' "$CORE_DIR/PROJECTS.md"); assert_eq "$c" "1" "PROJECTS.md lines"
assert_contains "$CORE_DIR/PROJECTS.md" "Test app"
assert_contains "$CORE_DIR/PROJECTS.md" "- demo-app — Test app — demo-app/"

# --- second run changes nothing
before=$(tree_sum "$CORE_DIR")
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
echo "$OUT" | grep -qxF 'skipped ../demo-app/AGENTS.md' && pass || fail "second run lacks skipped AGENTS.md: $OUT"
echo "$OUT" | grep -q '^created' && fail "second run created files" || pass
echo "$OUT" | grep -q '^skipped' && pass || fail "second run printed no skipped lines"
echo "$OUT" | grep -qxF 'skipped demo-app/docs/wiki.base' && pass || fail "second run lacks skipped wiki.base: $OUT"
echo "$OUT" | grep -qxF 'skipped demo-app/docs/.obsidian/app.json' && pass || fail "second run lacks skipped app.json: $OUT"
echo "$OUT" | grep -qxF 'skipped demo-app/docs/.obsidian/.gitignore' && pass || fail "second run lacks skipped .obsidian/.gitignore: $OUT"
echo "$OUT" | grep -qxF 'skipped demo-app/docs/INDEX.md' && pass || fail "second run lacks skipped INDEX.md: $OUT"
echo "$OUT" | grep -v '^skipped' | grep -q . && fail "second run printed a non-skipped line: $OUT" || pass
after=$(tree_sum "$CORE_DIR")
assert_eq "$before" "$after" "tree changed on re-run"

# --- a folder that is not ours blocks the run; nothing is written
new_sandbox; setup_core
mkdir -p "$(dirname "$CORE_DIR")/taken-app"; echo x > "$(dirname "$CORE_DIR")/taken-app/f"
assert_exit 2 bash "$S" --name taken-app
echo "$OUT" | grep -qF "target exists: $(dirname "$CORE_DIR")/taken-app" && pass || fail "target message: $OUT"
assert_no_file "$CORE_DIR/taken-app"

# --- a real CLAUDE.local.md is kept; the run exits 1 with a plain line
new_sandbox; setup_core
bash "$S" --name real-app >/dev/null
R="$(dirname "$CORE_DIR")/real-app"
rm "$R/CLAUDE.local.md"; printf 'mine\n' > "$R/CLAUDE.local.md"
assert_exit 1 bash "$S" --name real-app
echo "$OUT" | grep -qF "CLAUDE.local.md exists and is not a link to $CORE_DIR/real-app/CLAUDE.md; leave it or remove it yourself" && pass || fail "link message: $OUT"
assert_eq "$(cat "$R/CLAUDE.local.md")" "mine" "real file kept"
[ -L "$R/CLAUDE.local.md" ] && fail "file replaced by link" || pass

# --- a link to another target, and a dangling link: kept as they are, exit 1 with the same line
for tgt in "$SANDBOX/elsewhere.md" "$SANDBOX/no/such/file.md"; do
  [ "$tgt" = "$SANDBOX/elsewhere.md" ] && echo x > "$tgt"
  rm -f "$R/CLAUDE.local.md"; ln -s "$tgt" "$R/CLAUDE.local.md"
  assert_exit 1 bash "$S" --name real-app
  echo "$OUT" | grep -qF "CLAUDE.local.md exists and is not a link to $CORE_DIR/real-app/CLAUDE.md; leave it or remove it yourself" && pass || fail "link message ($tgt): $OUT"
  assert_eq "$(readlink "$R/CLAUDE.local.md")" "$tgt" "link changed"
done

# --- a real AGENTS.md in the code folder is kept; the run exits 1 with a plain line
new_sandbox; setup_core
OUT="$(bash "$S" --name ag-app 2>&1)"
echo "$OUT" | grep -qxF 'created ../ag-app/AGENTS.md' && pass || fail "first run lacks created AGENTS.md: $OUT"
R="$(dirname "$CORE_DIR")/ag-app"
rm "$R/AGENTS.md"; printf 'mine\n' > "$R/AGENTS.md"
assert_exit 1 bash "$S" --name ag-app
echo "$OUT" | grep -qF "AGENTS.md exists and is not a link to $CORE_DIR/ag-app/CLAUDE.md; leave it or remove it yourself" && pass || fail "AGENTS link message: $OUT"
assert_eq "$(cat "$R/AGENTS.md")" "mine" "real AGENTS.md kept"
[ -L "$R/AGENTS.md" ] && fail "AGENTS.md file replaced by link" || pass
# a link elsewhere is kept
rm -f "$R/AGENTS.md"; echo x > "$SANDBOX/elsewhere.md"; ln -s "$SANDBOX/elsewhere.md" "$R/AGENTS.md"
assert_exit 1 bash "$S" --name ag-app
assert_eq "$(readlink "$R/AGENTS.md")" "$SANDBOX/elsewhere.md" "AGENTS.md link changed"
# a Core AGENTS.md blocks the link and stays; the message names it
rm -f "$R/AGENTS.md"; printf 'core\n' > "$CORE_DIR/ag-app/AGENTS.md"
assert_exit 1 bash "$S" --name ag-app
echo "$OUT" | grep -qF "$CORE_DIR/ag-app/AGENTS.md" && pass || fail "message does not name the Core AGENTS.md: $OUT"
assert_eq "$(cat "$CORE_DIR/ag-app/AGENTS.md")" "core" "Core AGENTS.md changed"
[ -e "$R/AGENTS.md" ] || [ -L "$R/AGENTS.md" ] && fail "AGENTS.md linked despite Core copy" || pass

# --- invalid names
for bad in MyApp "my app" проект 1app a -app app- ; do
  new_sandbox; setup_core
  assert_exit 2 bash "$S" --name "$bad"
  assert_no_file "$CORE_DIR/$bad"
done

# --- dry run touches nothing
new_sandbox; setup_core
assert_exit 0 bash "$S" --name dry-app --dry-run
assert_no_file "$CORE_DIR/dry-app"
assert_no_file "$(dirname "$CORE_DIR")/dry-app"
echo "$OUT" | grep -q 'would create' && pass || fail "dry-run printed nothing"
for f in docs/INDEX.md docs/specs/ docs/plans/ docs/wiki.base docs/.obsidian/app.json docs/.obsidian/.gitignore; do
  echo "$OUT" | grep -qxF "would create dry-app/$f" && pass || fail "dry-run lacks 'would create dry-app/$f': $OUT"
done
echo "$OUT" | grep -qxF 'would create ../dry-app/CLAUDE.local.md' && pass || fail "dry-run link line: $OUT"
echo "$OUT" | grep -qxF 'would create ../dry-app/AGENTS.md' && pass || fail "dry-run AGENTS.md line: $OUT"

# a purpose with line breaks becomes one line
new_sandbox; setup_core
assert_exit 0 bash "$S" --name nl-app --purpose "$(printf 'First line.\r\nSecond line.')"
assert_eq "$(grep -c 'nl-app' "$CORE_DIR/PROJECTS.md")" "1" "PROJECTS.md entry split"
assert_contains "$CORE_DIR/PROJECTS.md" "First line. Second line."
assert_contains "$CORE_DIR/nl-app/CLAUDE.md" "First line. Second line."

# the wiki has one place for all worktrees: <Core>/<p>/docs/, which the task skill updates from a
# worktree too (no "never edit ../docs/ from a worktree" that contradicts it)
T="$SKILL/templates/CLAUDE.md.tmpl"
assert_not_contains "$T" "Never edit \`../docs/\` from a worktree"
assert_contains "$T" "one wiki for every worktree"
assert_contains "$T" "{{PROJECT_DIR}}/docs/"
finish
