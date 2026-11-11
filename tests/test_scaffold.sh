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
# (first a project whose name starts with the next one's name, with a purpose that holds every character sed
# treats specially in a replacement: the files hold it as typed, and the shorter name still gets its own line)
TRICKY='A | tricky & purpose \ here'
assert_exit 0 bash "$S" --name demo-app-two --purpose "$TRICKY"
for f in CLAUDE.md docs/brief.md; do
  grep -qxF -- "$TRICKY" "$CORE_DIR/demo-app-two/$f" && pass || fail "purpose kept as typed: $f: $(grep -n tricky "$CORE_DIR/demo-app-two/$f")"
done
grep -qxF -- "- demo-app-two — $TRICKY — demo-app-two/" "$CORE_DIR/PROJECTS.md" && pass || fail "purpose kept as typed: PROJECTS.md: $(cat "$CORE_DIR/PROJECTS.md")"
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
want1="$(cat <<'W'
created demo-app/CLAUDE.md
created demo-app/docs/brief.md
created demo-app/docs/architecture.md
created demo-app/docs/decisions/001-stack-and-architecture.md
created demo-app/docs/wiki.base
created demo-app/docs/.obsidian/app.json
created demo-app/docs/.obsidian/.gitignore
created demo-app/docs/features/
created demo-app/docs/specs/
created demo-app/docs/plans/
created demo-app/docs/knowledge/
created demo-app/docs/INDEX.md
created ../demo-app/
created ../demo-app/.git
created ../demo-app/.gitignore
created ../demo-app/.claude/settings.local.json
created ../demo-app/.worktreeinclude
created ../demo-app/CLAUDE.local.md
created ../demo-app/AGENTS.md
created PROJECTS.md entry
W
)"
assert_eq "$OUT" "$want1" "first run output"
assert_eq "$(grep -c '^- demo-app ' "$CORE_DIR/PROJECTS.md") $(grep -c '^- demo-app-two ' "$CORE_DIR/PROJECTS.md")" "1 1" "two PROJECTS.md lines"
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
assert_not_contains "$PLUGIN/templates/core/gitignore" "*/code/"
assert_file "$CORE_DIR/README.md"
# scaffold copies no machinery into Core
assert_no_file "$CORE_DIR/bin"; assert_no_file "$CORE_DIR/hooks"

# docs pages have typed front matter: type first, then status, description, files, related, updated; no title
for f in brief.md architecture.md decisions/001-stack-and-architecture.md; do
  head -1 "$P/docs/$f" | grep -qx -- '---' && pass || fail "$f: no front matter"
  fm="$(awk 'NR==1 { next } /^---[ \t]*$/ { exit } { print }' "$P/docs/$f")"
  keys="$(printf '%s\n' "$fm" | sed -n 's/^\([a-z][a-z]*\):.*/\1/p' | tr '\n' ' ')"
  assert_eq "$keys" "type status description files related updated " "$f: front matter fields"
  grep -q '^title:' "$P/docs/$f" && fail "$f: has title:" || pass
done
assert_contains "$P/docs/brief.md" "type: brief"
assert_contains "$P/docs/architecture.md" "type: architecture"
assert_contains "$P/docs/decisions/001-stack-and-architecture.md" "type: decision"
grep -q '^stage:' "$P/docs/brief.md" && fail "brief.md: front matter has a stage: field" || pass
# progress is the last body section of the brief: ## Progress with one line "Stage: <v>"
assert_contains "$P/docs/brief.md" "## Progress"
assert_contains "$P/docs/brief.md" "Stage: interviewed"
assert_eq "$(grep '^## ' "$P/docs/brief.md" | tail -1)" "## Progress" "brief.md: ## Progress is not the last ## heading"
# CLAUDE.md: specs and plans are wiki pages with the six fields; no 0.6 wording wiki-migrate warns about
grep 'docs/specs/' "$P/CLAUDE.md" | grep -qF 'six front-matter fields (`type: spec` / `type: plan`)' && pass || fail "CLAUDE.md: the specs/plans line does not name the six fields"
grep -qE 'docs/superpowers|map line' "$P/CLAUDE.md" && fail "CLAUDE.md still has a 0.6 line: $(grep -nE 'docs/superpowers|map line' "$P/CLAUDE.md")" || pass
# wiki.base excludes only the top-level INDEX.md, by path
W0="$P/docs/wiki.base"
assert_contains "$W0" "'!file.path.startsWith(\"INDEX.md\")'"
assert_not_contains "$W0" 'file.basename != "INDEX"'
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
assert_no_file "$PLUGIN/templates/docs/INDEX.md.tmpl"
# new-project text templates ship the vault files
for t in wiki.base obsidian-app.json obsidian-gitignore; do assert_file "$PLUGIN/templates/docs/$t"; done

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

# --- second run changes nothing (tree_sum skips links: their targets are read separately)
before=$(tree_sum "$CORE_DIR")
before_k=$(tree_sum "$K"); before_l="$(readlink "$K/CLAUDE.local.md") $(readlink "$K/AGENTS.md")"
assert_exit 0 bash "$S" --name demo-app --purpose "Test app"
want2="$(cat <<'W'
skipped demo-app/CLAUDE.md
skipped demo-app/docs/brief.md
skipped demo-app/docs/architecture.md
skipped demo-app/docs/decisions/001-stack-and-architecture.md
skipped demo-app/docs/wiki.base
skipped demo-app/docs/.obsidian/app.json
skipped demo-app/docs/.obsidian/.gitignore
skipped demo-app/docs/INDEX.md
skipped ../demo-app/.git
skipped ../demo-app/.gitignore
skipped ../demo-app/.claude/settings.local.json
skipped ../demo-app/.worktreeinclude
skipped ../demo-app/CLAUDE.local.md
skipped ../demo-app/AGENTS.md
skipped PROJECTS.md entry
W
)"
assert_eq "$OUT" "$want2" "second run output"
after=$(tree_sum "$CORE_DIR")
assert_eq "$before" "$after" "tree changed on re-run"
assert_eq "$(tree_sum "$K")" "$before_k" "code folder changed on re-run"
assert_eq "$(readlink "$K/CLAUDE.local.md") $(readlink "$K/AGENTS.md")" "$before_l" "links changed on re-run"
[ "$before_l" = "$P/CLAUDE.md $P/CLAUDE.md" ] && pass || fail "links do not point to the private CLAUDE.md: $before_l"

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

# --- wiki-index.sh fails during scaffold: non-zero exit and a plain message, no silent success
new_sandbox; setup_core
cp -R "$PLUGIN" "$SANDBOX/plugin-copy"
printf '#!/usr/bin/env bash\necho "stub: boom" >&2\nexit 2\n' > "$SANDBOX/plugin-copy/scripts/wiki-index.sh"
OUT="$(bash "$SANDBOX/plugin-copy/skills/new-project/scripts/scaffold.sh" --name idx-fail 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass || fail "scaffold exited 0 although wiki-index.sh failed: $OUT"
echo "$OUT" | grep -qi 'wiki-index' && pass || fail "scaffold output does not mention wiki-index: $OUT"
echo "$OUT" | grep -q 'created.*INDEX.md' && fail "scaffold claims INDEX.md was created: $OUT" || pass

# wiki.base leaves out superpowers/ like knowledge/ and standards/
assert_contains "$PLUGIN/templates/docs/wiki.base" "superpowers/"
# the rendered CLAUDE.md names wiki-index.sh by its plugin path and does not say it is printed at session start
new_sandbox; setup_core
bash "$S" --name cm-app >/dev/null
CM="$CORE_DIR/cm-app/CLAUDE.md"
assert_contains "$CM" "<plugin>/scripts/wiki-index.sh"
grep -q 'wiki-index.sh.*printed at session start\|printed at session start.*wiki-index' "$CM" && fail "CLAUDE.md says wiki-index.sh is printed at session start" || pass
sed -n '/wiki-index.sh/,/^- /p' "$CM" | grep -qi 'printed at session start' && fail "CLAUDE.md: wiki-index bullet says printed at session start" || pass

# a purpose with line breaks becomes one line
new_sandbox; setup_core
assert_exit 0 bash "$S" --name nl-app --purpose "$(printf 'First line.\r\nSecond line.')"
assert_eq "$(grep -c 'nl-app' "$CORE_DIR/PROJECTS.md")" "1" "PROJECTS.md entry split"
assert_contains "$CORE_DIR/PROJECTS.md" "First line. Second line."
assert_contains "$CORE_DIR/nl-app/CLAUDE.md" "First line. Second line."

# --- --name or --purpose without a value: a usage error, never an endless loop (time limit 10 s)
new_sandbox; setup_core
for args in "--name" "--purpose" "--name lim-app --purpose"; do
  # shellcheck disable=SC2086
  bash "$S" $args > "$SANDBOX/out" 2>&1 & pid=$!
  i=0; while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fail "scaffold.sh $args still runs after 10 s"
  else
    wait "$pid"; assert_eq "$?" "2" "scaffold.sh $args exit"
    grep -qi 'usage' "$SANDBOX/out" && pass || fail "scaffold.sh $args: no usage line: $(cat "$SANDBOX/out")"
  fi
done
assert_no_file "$CORE_DIR/lim-app"
# an argument scaffold does not know is a usage error too
assert_exit 2 bash "$S" --bogus
assert_exit 2 bash "$S" --name lim-app --bogus
assert_no_file "$CORE_DIR/lim-app"

# --- a code-side step that fails stops the run: non-zero exit, no PROJECTS.md entry added after it
new_sandbox; setup_core
bash "$S" --name cs-app >/dev/null
K2="$(dirname "$CORE_DIR")/cs-app"
rm -rf "$K2/.claude"; : > "$K2/.claude"   # .claude is a file: settings.local.json cannot be written
grep -v '^- cs-app ' "$CORE_DIR/PROJECTS.md" > "$SANDBOX/pm"; mv "$SANDBOX/pm" "$CORE_DIR/PROJECTS.md"
assert_exit 1 bash "$S" --name cs-app
assert_eq "$(grep -c '^- cs-app ' "$CORE_DIR/PROJECTS.md")" "0" "PROJECTS.md entry added after a failed code-side step"
[ -f "$K2/.claude" ] && pass || fail "the .claude file was replaced"

# --- a template that cannot be read: exit 1, no empty page and no temp file left; a rerun creates the page
if [ "$(id -u)" -eq 0 ]; then
  skip unreadable-template "running as root"
else
  new_sandbox; setup_core
  cp -R "$PLUGIN" "$SANDBOX/plugin-copy"
  AT="$SANDBOX/plugin-copy/templates/docs/architecture.md.tmpl"
  SC="$SANDBOX/plugin-copy/skills/new-project/scripts/scaffold.sh"
  chmod 000 "$AT"
  assert_exit 1 bash "$SC" --name tf-app
  assert_no_file "$CORE_DIR/tf-app/docs/architecture.md"
  left="$(find "$CORE_DIR" -name '*.tmp.*' -print)"
  [ -z "$left" ] && pass || fail "temp files left after a failed write: $left"
  chmod 644 "$AT"
  assert_exit 0 bash "$SC" --name tf-app
  echo "$OUT" | grep -qxF 'created tf-app/docs/architecture.md' && pass || fail "rerun did not create architecture.md: $OUT"
  [ -s "$CORE_DIR/tf-app/docs/architecture.md" ] && pass || fail "architecture.md is empty after the rerun"
  assert_exit 0 bash "$SCRIPTS/wiki-check.sh" "$CORE_DIR/tf-app"
  [ -z "$OUT" ] && pass || fail "wiki-check after the rerun printed: $OUT"
fi

# --- a dangling symlink at a destination stays a link: the page is written to the link's target
new_sandbox
mkdir -p "$CORE_DIR" "$SANDBOX/dots"
ln -s "$SANDBOX/dots/core-readme.md" "$CORE_DIR/README.md"
assert_exit 0 bash "$SCRIPTS/setup-core.sh" "$CORE_DIR"
echo "$OUT" | grep -qxF 'created README.md' && pass || fail "setup-core did not report README.md: $OUT"
[ -L "$CORE_DIR/README.md" ] && pass || fail "the user's README.md link was replaced by a file"
[ -s "$SANDBOX/dots/core-readme.md" ] && pass || fail "the link's target was not written"
left="$(find "$CORE_DIR" "$SANDBOX/dots" -name '*.tmp.*' -print)"
[ -z "$left" ] && pass || fail "temp files left after writing through a link: $left"

# --- a link loop at a destination (README.md -> README.md) and a chain of more than 16 links: setup-core exits 1,
# names the file, and changes nothing; a rerun after the link is fixed creates the page. A chain of 16 links works.
new_sandbox; setup_core
rm "$CORE_DIR/README.md"; ln -s README.md "$CORE_DIR/README.md"
# chain <n> — README.md and the links of $SANDBOX/chain: <n> links in all, the last one pointing to nothing
chain() {
  local i=1; rm -rf "$SANDBOX/chain" "$CORE_DIR/README.md"; mkdir -p "$SANDBOX/chain"
  ln -s "$SANDBOX/chain/1" "$CORE_DIR/README.md"
  while [ "$i" -lt "$1" ]; do ln -s "$SANDBOX/chain/$((i + 1))" "$SANDBOX/chain/$i"; i=$((i + 1)); done
}
# bad_link <label> — setup-core refuses the link at README.md with a message that names it and changes nothing
bad_link() {
  local before; before="$(snap_tree "$CORE_DIR" "$SANDBOX/chain")"
  assert_exit 1 bash "$SCRIPTS/setup-core.sh" "$CORE_DIR"
  echo "$OUT" | grep -qF "$CORE_DIR/README.md" && pass || fail "$1: the message does not name README.md: $OUT"
  assert_eq "$(snap_tree "$CORE_DIR" "$SANDBOX/chain")" "$before" "$1: setup-core changed something"
}
bad_link "a link loop"
chain 17; bad_link "a chain of 17 links"
chain 16
assert_exit 0 bash "$SCRIPTS/setup-core.sh" "$CORE_DIR"
[ -s "$SANDBOX/chain/16" ] && pass || fail "a chain of 16 links: the page was not written at its end: $OUT"
rm -rf "$SANDBOX/chain" "$CORE_DIR/README.md"
assert_exit 0 bash "$SCRIPTS/setup-core.sh" "$CORE_DIR"
echo "$OUT" | grep -qxF 'created README.md' && pass || fail "the rerun after the fix did not create README.md: $OUT"

# the wiki has one place for all worktrees: <Core>/<p>/docs/, which the task skill updates from a
# worktree too (no "never edit ../docs/ from a worktree" that contradicts it)
T="$PLUGIN/templates/CLAUDE.md.tmpl"
assert_not_contains "$T" "Never edit \`../docs/\` from a worktree"
assert_contains "$T" "one wiki for every worktree"
assert_contains "$T" "{{PROJECT_DIR}}/docs/"
# coding discipline for the main session of a new project: assumptions said, ambiguity asked, no
# speculative code, surgical edits
[ "$(grep -ciF -- 'reads two ways' "$T")" = 1 ] && pass || fail "CLAUDE.md.tmpl does not state once: reads two ways"
[ "$(grep -ciF -- 'nobody asked for' "$T")" = 1 ] && pass || fail "CLAUDE.md.tmpl does not state once: nobody asked for"
[ "$(grep -ciF -- 'left unused' "$T")" = 1 ] && pass || fail "CLAUDE.md.tmpl does not state once: left unused"
finish
