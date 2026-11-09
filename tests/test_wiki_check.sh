#!/usr/bin/env bash
# wiki-check.sh: one good wiki, one broken variant of it per check, drift with --changed, edge cases.
source "$(dirname "$0")/lib.sh"
new_sandbox
W="$SCRIPTS/wiki-check.sh"
# The fixtures keep their CLAUDE.md as CLAUDE.md.in: a tracked CLAUDE.md in this repo would be an
# internal file to corecrew's own guards. The copy in the sandbox gets the real name back.
FX="$SANDBOX/fixtures"; cp -R "$ROOT/tests/fixtures" "$FX"
for f in "$FX"/*/CLAUDE.md.in; do mv "$f" "${f%.in}"; done

# check <fixture> <exact expected output> [args after the project dir...]
check() {
  local fx="$1" want="$2"; shift 2
  assert_exit 1 bash "$W" "$FX/$fx" "$@"
  assert_eq "$OUT" "$want" "$fx output"
}

# Good wiki: silent, exit 0. Knowledge/ has no front matter and broken links; it is skipped.
assert_exit 0 bash "$W" "$FX/wiki-good"
assert_eq "$OUT" "" "good wiki prints nothing"
assert_exit 0 bash "$W" "$FX/wiki-good/"        # trailing slash
cd "$FX/wiki-good/docs" || exit 1       # relative project path from another cwd
assert_exit 0 bash "$W" ..
cd "$ROOT" || exit 1

# Copy a fixture and regenerate its INDEX.md (the title of the INDEX holds the folder name).
clone() { cp -R "$FX/$1" "$2"; bash "$SCRIPTS/wiki-index.sh" "$2" >/dev/null 2>&1; }

# The broken wikis: each is wiki-good with one defect, built here and named after it.
# variant <name>: copy wiki-good to $FX/<name> and set V to it. edit_page <page> <sed args...> edits
# a page of V; page <page> writes one from stdin; reindex regenerates V's INDEX.md.
variant() { V="$FX/$1"; cp -R "$FX/wiki-good" "$V"; }
edit_page() { local p="$V/docs/$1"; shift; sed "$@" "$p" > "$SANDBOX/v.tmp" && mv "$SANDBOX/v.tmp" "$p"; }
page() { cat > "$V/docs/$1"; }
reindex() { bash "$SCRIPTS/wiki-index.sh" "$V" >/dev/null 2>&1; }

variant missing-fields; edit_page features/login.md -e '/^status:/d' -e '/^updated:/d'; reindex
variant stale-index; reindex                  # a page added after INDEX.md was generated
page features/orphan.md <<'EOF'
---
type: feature
status: draft
description: A page nobody regenerated the INDEX for.
files: []
related: []
updated: 2026-11-03
---

# Orphan

## Notes

Not in INDEX.md.
EOF
variant broken-links
printf '\n## Broken things\n\nA [missing page](nope.md), a [[gone|page that is not there]] and [[architecture#No such heading]],\nand with an alias [[login#Nowhere|see there]].\n' >> "$V/docs/architecture.md"; reindex
variant duplicate-heading
printf '\n## Components\n\nListed twice by mistake.\n' >> "$V/docs/architecture.md"; reindex
# Over 8 KB without ## headings: 90 filler lines replace the sections, so the #Flow links go too.
variant long-page; edit_page features/login.md '14,$d'
i=0; while [ $i -lt 90 ]; do
  echo "Line $i of a long page that has no second-level headings, so a reader cannot jump to the part they need."
  i=$((i+1)); done >> "$V/docs/features/login.md"
edit_page architecture.md -e 's/\[\[login#Flow\]\]/[[login]]/' -e 's/\[\[features\/login#Flow|/[[features\/login|/'; reindex
# Not broken: a quoted directory entry in a block list, for the drift checks below.
variant drift-quoted-dir; edit_page features/login.md 's/^  - src\/login\.sh$/&\
  - "src\/auth\/"/'; reindex
variant unclosed-front-matter; edit_page features/login.md '10{/^---$/d;}'; reindex
variant bad-values
edit_page architecture.md 's/^status: active$/status: wip/'
edit_page decisions/001-stack.md 's/^updated: .*/updated: 06.11.2026/'
edit_page features/login.md 's/^type: feature$/type: widget/'
page features/long.md <<'EOF'
---
type: feature
status: active
description: abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcd
files: []
related: []
updated: 2026-11-03
---

# Long

## Notes

The description above is 81 characters.
EOF
reindex
# A decision with the file name of a feature page; architecture.md names the feature by its path.
variant duplicate-name; edit_page architecture.md 's/\[\[login/[[features\/login/g'
page decisions/login.md <<'EOF'
---
type: decision
status: active
description: A decision that happens to share the file name of a feature page.
files: []
related: []
updated: 2026-11-03
---

# Login decision

## Decision

Names are unique within a project, so this is a defect.
EOF
reindex
variant markdown-links
edit_page architecture.md 's/\[\[login#Flow\]\]/[the login page](features\/login.md#flow)/'
edit_page features/login.md 's/\[\[architecture#Components|components\]\]/[components](..\/architecture.md#components)/'; reindex

# One broken variant per check.
check missing-fields "wiki-check: features/login.md: missing front matter field status
wiki-check: features/login.md: missing front matter field updated"
check stale-index "wiki-check: INDEX.md: INDEX.md stale"        # a page added after INDEX.md was generated
check broken-links "wiki-check: architecture.md: broken link nope.md
wiki-check: architecture.md: broken wikilink [[gone]]
wiki-check: architecture.md: broken wikilink [[architecture#No such heading]]
wiki-check: architecture.md: broken wikilink [[login#Nowhere]]"      # target as written, alias dropped
check duplicate-heading "wiki-check: architecture.md: duplicate heading Components"
check long-page "wiki-check: features/login.md: page over 8 KB without ## headings"
check unclosed-front-matter "wiki-check: features/login.md: unclosed front matter"
check bad-values "wiki-check: architecture.md: bad status: wip
wiki-check: decisions/001-stack.md: bad updated: 06.11.2026
wiki-check: features/login.md: bad type: widget
wiki-check: features/long.md: description over 80 chars"
check duplicate-name "wiki-check: features/login.md: duplicate page name login"   # reported on the later page
check markdown-links "wiki-check: architecture.md: use a wikilink: features/login.md#flow
wiki-check: features/login.md: use a wikilink: ../architecture.md#components"

# Removed checks stay gone: no title field, no map-membership checks, no section references.
assert_exit 0 bash "$W" "$FX/wiki-good"
assert_eq "$(grep -rl '^title:' "$FX/wiki-good/docs" --include='*.md' | grep -v '/knowledge/' | wc -l | tr -d ' ')" "0" "fixture pages carry no title"

# Front matter fields outside the six: one line per extra key, in file order, after the page's missing-field lines.
# edit_arch <dir> <sed args...>: edit architecture.md of a clone, then regenerate its INDEX.
edit_arch() { local d="$1"; shift; sed "$@" "$d/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$d/docs/architecture.md"
  bash "$SCRIPTS/wiki-index.sh" "$d" >/dev/null 2>&1; }
clone wiki-good "$SANDBOX/extra1"
edit_arch "$SANDBOX/extra1" 's/^updated: \(.*\)$/updated: \1\
stage: ready/'
assert_contains "$SANDBOX/extra1/docs/architecture.md" "stage: ready"
assert_exit 1 bash "$W" "$SANDBOX/extra1"
assert_eq "$OUT" "wiki-check: architecture.md: unknown front matter field stage" "one extra field"
clone wiki-good "$SANDBOX/extra2"
edit_arch "$SANDBOX/extra2" 's/^updated: \(.*\)$/updated: \1\
tags: x\
stage: ready/'
assert_exit 1 bash "$W" "$SANDBOX/extra2"
assert_eq "$OUT" "wiki-check: architecture.md: unknown front matter field tags
wiki-check: architecture.md: unknown front matter field stage" "two extras in file order"
clone wiki-good "$SANDBOX/extra3"
edit_arch "$SANDBOX/extra3" 's/^type: architecture/title: X\
type: architecture/'
assert_exit 1 bash "$W" "$SANDBOX/extra3"
assert_eq "$OUT" "wiki-check: architecture.md: unknown front matter field title" "title is an unknown field"
# missing lines come first, then the extras
clone wiki-good "$SANDBOX/extra4"
edit_arch "$SANDBOX/extra4" -e '/^updated:/d' -e 's/^type: architecture/stage: ready\
type: architecture/'
assert_exit 1 bash "$W" "$SANDBOX/extra4"
assert_eq "$OUT" "wiki-check: architecture.md: missing front matter field updated
wiki-check: architecture.md: unknown front matter field stage" "missing before unknown"
# an indented continuation line under a folded description is not a field (only "not one line" is reported)
clone wiki-good "$SANDBOX/extra5"
printf -- '---\ntype: feature\nstatus: active\ndescription: >\n  note: folded text\n  other: more\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n\n# F\n' > "$SANDBOX/extra5/docs/features/f.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/extra5" >/dev/null 2>&1
assert_exit 1 bash "$W" "$SANDBOX/extra5"
assert_eq "$OUT" "wiki-check: features/f.md: description not one line" "continuation lines are not fields"
assert_exit 0 bash "$W" "$FX/wiki-good"
assert_eq "$OUT" "" "wiki-good stays silent with the unknown-field check"

# Problem prefixes, exactly as the verifier and release read them.
assert_exit 1 bash "$W" "$FX/broken-links"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken link "
assert_exit 1 bash "$W" "$FX/missing-fields"
assert_contains <(printf '%s' "$OUT") ": missing front matter field "

# A hand-edited or missing INDEX.md is stale too.
clone wiki-good "$SANDBOX/stale1"
echo '[[ghost]] a hand-written line' >> "$SANDBOX/stale1/docs/INDEX.md"
assert_exit 1 bash "$W" "$SANDBOX/stale1"
assert_eq "$OUT" "wiki-check: INDEX.md: INDEX.md stale" "hand-edited INDEX"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/stale1" >/dev/null       # regenerated: green again
assert_exit 0 bash "$W" "$SANDBOX/stale1"
assert_eq "$OUT" "" "regenerated INDEX is green"
# A description edit without regenerating is stale: the index line is the description.
clone wiki-good "$SANDBOX/stale2"
sed 's/^description: Why plain bash.*/description: Another reason./' "$SANDBOX/stale2/docs/decisions/001-stack.md" > "$SANDBOX/s.tmp" \
  && mv "$SANDBOX/s.tmp" "$SANDBOX/stale2/docs/decisions/001-stack.md"
assert_exit 1 bash "$W" "$SANDBOX/stale2"
assert_eq "$OUT" "wiki-check: INDEX.md: INDEX.md stale" "description changed"
# A page whose type/status make it leave the INDEX: done goes to the history line, so stale until regenerated.
clone wiki-good "$SANDBOX/stale3"
sed 's/^status: active/status: done/' "$SANDBOX/stale3/docs/features/login.md" > "$SANDBOX/s.tmp" \
  && mv "$SANDBOX/s.tmp" "$SANDBOX/stale3/docs/features/login.md"
assert_exit 1 bash "$W" "$SANDBOX/stale3"
assert_eq "$OUT" "wiki-check: INDEX.md: INDEX.md stale" "status changed"

# Wikilinks: related is checked like body links (inline list and block list).
clone wiki-good "$SANDBOX/rel"
sed 's/^related: .*/related: ["[[ghost]]"]/' "$SANDBOX/rel/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/rel/docs/architecture.md"
sed 's/^  - "\[\[architecture\]\]"/  - "[[ghost2]]"/' "$SANDBOX/rel/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/rel/docs/features/login.md"
assert_exit 1 bash "$W" "$SANDBOX/rel"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[ghost]]
wiki-check: features/login.md: broken wikilink [[ghost2]]" "related checked"

# Wikilink forms: missing path form, missing embed, missing file with an extension.
clone wiki-good "$SANDBOX/forms"
printf '\nSee [[features/nope]], ![[missing.png]] and [[decisions/001-stack|the stack]].\n' >> "$SANDBOX/forms/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/forms"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[features/nope]]
wiki-check: architecture.md: broken wikilink [[missing.png]]" "wikilink forms"
# A page name does not resolve through the wrong folder.
clone wiki-good "$SANDBOX/wrongdir"
printf '\nSee [[decisions/login]].\n' >> "$SANDBOX/wrongdir/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/wrongdir"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[decisions/login]]" "folder form is exact"

# A heading only inside a code fence does not exist; a heading of any level does.
clone wiki-good "$SANDBOX/fenceh"
printf '\nSee [[architecture#Hidden]] and [[architecture#Deep]].\n\n```text\n## Hidden\n```\n\n###### Deep\n' >> "$SANDBOX/fenceh/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/fenceh"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[architecture#Hidden]]" "fenced heading"
# Heading text is exact: case and trailing words count.
clone wiki-good "$SANDBOX/headcase"
printf '\nSee [[architecture#components]] and [[architecture#Components and more]].\n' >> "$SANDBOX/headcase/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/headcase"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[architecture#components]]
wiki-check: architecture.md: broken wikilink [[architecture#Components and more]]" "heading is exact"

# CLAUDE.md: Markdown links only. Wikilinks and old section references are not read there.
clone wiki-good "$SANDBOX/claude"
printf 'See [[nope]], [[architecture#Nope]] and docs/architecture.md § Nowhere\n' >> "$SANDBOX/claude/CLAUDE.md"
assert_exit 0 bash "$W" "$SANDBOX/claude"
assert_eq "$OUT" "" "CLAUDE.md wikilinks and § not checked"
echo 'See [x](docs/missing.md)' >> "$SANDBOX/claude/CLAUDE.md"
assert_exit 1 bash "$W" "$SANDBOX/claude"
assert_eq "$OUT" "wiki-check: ../CLAUDE.md: broken link docs/missing.md" "CLAUDE.md"
# Old section references in a page are plain text now.
clone wiki-good "$SANDBOX/oldref"
printf '\nSee `docs/features/gone.md § Flow` and docs/architecture.md § Nope\n' >> "$SANDBOX/oldref/docs/architecture.md"
assert_exit 0 bash "$W" "$SANDBOX/oldref"
assert_eq "$OUT" "" "section references are not checked"

# CRLF pages give the same results as LF: green fixtures stay green, broken ones report the same text.
crlf() { local f; for f in $(cd "$1/docs" && find . -name '*.md' ! -name INDEX.md | sed 's|^\./||' | tr ' ' '\001'); do
    f="$(printf '%s' "$f" | tr '\001' ' ')"
    awk '{ printf "%s\r\n", $0 }' "$1/docs/$f" > "$SANDBOX/crlf.tmp" && mv "$SANDBOX/crlf.tmp" "$1/docs/$f"; done; }
clone wiki-good "$SANDBOX/crlf-good"; crlf "$SANDBOX/crlf-good"
assert_exit 0 bash "$W" "$SANDBOX/crlf-good"
assert_eq "$OUT" "" "CRLF good wiki prints nothing"
clone wiki-edge "$SANDBOX/crlf-edge"; crlf "$SANDBOX/crlf-edge"
assert_exit 0 bash "$W" "$SANDBOX/crlf-edge"
assert_eq "$OUT" "" "CRLF edge wiki prints nothing"
clone broken-links "$SANDBOX/crlf-bad3"; crlf "$SANDBOX/crlf-bad3"
assert_exit 1 bash "$W" "$SANDBOX/crlf-bad3"
assert_eq "$OUT" "wiki-check: architecture.md: broken link nope.md
wiki-check: architecture.md: broken wikilink [[gone]]
wiki-check: architecture.md: broken wikilink [[architecture#No such heading]]
wiki-check: architecture.md: broken wikilink [[login#Nowhere]]" "CRLF same problems"
clone bad-values "$SANDBOX/crlf-bad8"; crlf "$SANDBOX/crlf-bad8"
assert_exit 1 bash "$W" "$SANDBOX/crlf-bad8"
assert_eq "$OUT" "wiki-check: architecture.md: bad status: wip
wiki-check: decisions/001-stack.md: bad updated: 06.11.2026
wiki-check: features/login.md: bad type: widget
wiki-check: features/long.md: description over 80 chars" "CRLF values carry no CR"

# Drift: a changed code file listed in a page's files: while the page is not changed.
DRIFT="wiki-check: architecture.md: drift: src/app.sh changed, page not updated"
check wiki-good "$DRIFT" --changed src/app.sh
check wiki-good "wiki-check: features/login.md: drift: src/login.sh changed, page not updated" \
  --changed src/login.sh                                     # block-list files:
check wiki-good "wiki-check: architecture.md: drift: src/lib/util.sh changed, page not updated" \
  --changed src/lib/util.sh                                  # directory entry src/lib/
check wiki-good "$DRIFT
wiki-check: features/login.md: drift: src/login.sh changed, page not updated" \
  --changed src/app.sh src/login.sh docs/decisions/001-stack.md
check drift-quoted-dir "wiki-check: features/login.md: drift: src/auth/token.sh changed, page not updated" \
  --changed src/auth/token.sh                                # quoted dir entry, block list
# Passing the page too (either path form) clears the drift.
assert_exit 0 bash "$W" "$FX/wiki-good" --changed src/app.sh docs/architecture.md
assert_eq "$OUT" "" "page passed as docs/<page>.md"
assert_exit 0 bash "$W" "$FX/wiki-good" --changed src/app.sh ../docs/architecture.md
assert_eq "$OUT" "" "page passed as ../docs/<page>.md"
assert_exit 0 bash "$W" "$FX/wiki-good" --changed ./src/app.sh ../docs/architecture.md src/other.sh
# Unrelated or no changes: nothing to report.
# Absolute <project_dir>/docs/<page>.md counts as that page; an absolute path elsewhere is a code path.
assert_exit 0 bash "$W" "$FX/wiki-good" --changed src/app.sh "$FX/wiki-good/docs/architecture.md"
assert_exit 0 bash "$W" "$FX/wiki-good/" --changed src/app.sh "$FX/wiki-good/docs/architecture.md"
check wiki-good "$DRIFT" --changed src/app.sh "$FX/other/docs/architecture.md"
assert_exit 0 bash "$W" "$FX/wiki-good" --changed src/unrelated.sh
assert_exit 0 bash "$W" "$FX/wiki-good" --changed
assert_exit 0 bash "$W" "$FX/wiki-good" --changed README.md

# Edge cases: quoted descriptions with ": " and "#" (80 chars without the quotes), a page name with a
# space, aliases, embeds, a Cyrillic ### heading, wikilinks in fences and backticks, other schemes.
assert_exit 0 bash "$W" "$FX/wiki-edge"
assert_eq "$OUT" "" "edge wiki prints nothing"
assert_eq "$(sed -n 's/^description: //p' "$FX/wiki-edge/docs/architecture.md" | awk '{ print length($0) }')" "82" "edge description is 82 with quotes"
assert_contains "$FX/wiki-edge/docs/INDEX.md" "[[sign in]] Sign-in: a page whose file name has a space # not a comment"

# The edge links are really checked: rename the targets and they break.
clone wiki-edge "$SANDBOX/edge2"
sed -e 's/^## Storage, sync — what and why/## Storage/' -e 's/^## The `save` command/## Save/' \
  "$SANDBOX/edge2/docs/architecture.md" > "$SANDBOX/arch.tmp" && mv "$SANDBOX/arch.tmp" "$SANDBOX/edge2/docs/architecture.md"
sed 's/^## Overview/## Summary/' "$SANDBOX/edge2/docs/features/sign in.md" > "$SANDBOX/sp.tmp" \
  && mv "$SANDBOX/sp.tmp" "$SANDBOX/edge2/docs/features/sign in.md"
sed 's/^### Заголовок/### Другое/' "$SANDBOX/edge2/docs/features/login.md" > "$SANDBOX/lg.tmp" \
  && mv "$SANDBOX/lg.tmp" "$SANDBOX/edge2/docs/features/login.md"
assert_exit 1 bash "$W" "$SANDBOX/edge2"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[sign in#Overview]]
wiki-check: architecture.md: broken wikilink [[login#Заголовок]]
wiki-check: architecture.md: broken wikilink [[architecture#Storage, sync — what and why]]
wiki-check: architecture.md: broken wikilink [[architecture#The \`save\` command]]" "renamed targets"
# A missing embed target is a broken wikilink, and its Markdown link a broken link.
clone wiki-edge "$SANDBOX/edge4"; rm "$SANDBOX/edge4/docs/diagram.png"
assert_exit 1 bash "$W" "$SANDBOX/edge4"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken wikilink [[diagram.png]]"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken link diagram.png"
# A page renamed: [[sign in]] and the path form break, related too.
clone wiki-edge "$SANDBOX/edge3"
mv "$SANDBOX/edge3/docs/features/sign in.md" "$SANDBOX/edge3/docs/features/sign-in.md"
assert_exit 1 bash "$W" "$SANDBOX/edge3"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken wikilink [[sign in]]"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken wikilink [[features/sign in]]"

# A quoted description of 81 characters is still too long; 80 inside quotes is fine (edge wiki above).
clone wiki-good "$SANDBOX/q81"
sed 's/^description: .*/description: "Components and storage. Read before structural changes and also much more words!."/' \
  "$SANDBOX/q81/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/q81/docs/architecture.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/q81" >/dev/null
assert_exit 1 bash "$W" "$SANDBOX/q81"
assert_eq "$OUT" "wiki-check: architecture.md: description over 80 chars" "quoted 81"

# Wikilink-looking text in knowledge/ and standards/ is not read (those are not wiki pages).
clone wiki-good "$SANDBOX/skipdirs"
mkdir -p "$SANDBOX/skipdirs/docs/standards"
printf 'No front matter. [[nope]] and [x](nope.md)\n' > "$SANDBOX/skipdirs/docs/standards/x.md"
printf 'No front matter. [[nope]]\n' > "$SANDBOX/skipdirs/docs/knowledge/y.md"
assert_exit 0 bash "$W" "$SANDBOX/skipdirs"
assert_eq "$OUT" "" "knowledge/ and standards/ skipped"

# Fix round 1: Cyrillic length, empty quoted value, table-escaped pipe, closing hashes.
cyr() { local i s=""; for ((i = 0; i < $1; i++)); do s="${s}я"; done; printf '%s' "$s"; }   # $1 characters
for n in 80 81; do
  clone wiki-good "$SANDBOX/cyr$n"
  { echo "description: $(cyr $n)"; } > "$SANDBOX/cyr.desc"
  awk -v d="$(cat "$SANDBOX/cyr.desc")" '/^description:/ && !done { print d; done = 1; next } { print }' \
    "$SANDBOX/cyr$n/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/cyr$n/docs/architecture.md"
  bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/cyr$n" >/dev/null
done
LC_ALL=en_US.UTF-8 assert_exit 0 bash "$W" "$SANDBOX/cyr80"
assert_eq "$OUT" "" "Cyrillic description of 80 characters"
LC_ALL=en_US.UTF-8 assert_exit 1 bash "$W" "$SANDBOX/cyr81"
assert_eq "$OUT" "wiki-check: architecture.md: description over 80 chars" "Cyrillic 81"
LC_ALL=C assert_exit 0 bash "$W" "$SANDBOX/cyr80"
assert_eq "$OUT" "" "Cyrillic 80 under LC_ALL=C"

clone wiki-good "$SANDBOX/emptytype"
sed 's/^type: feature/type: ""/' "$SANDBOX/emptytype/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/emptytype/docs/features/login.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/emptytype" >/dev/null
assert_exit 1 bash "$W" "$SANDBOX/emptytype"
assert_eq "$OUT" "wiki-check: features/login.md: missing front matter field type" "empty quoted type"

clone wiki-good "$SANDBOX/tbl"
printf '\n| Page | Note |\n|---|---|\n| [[login\\|alias]] | [[login#Flow\\|see flow]] |\n' >> "$SANDBOX/tbl/docs/architecture.md"
assert_exit 0 bash "$W" "$SANDBOX/tbl"
assert_eq "$OUT" "" "table-escaped pipe in a wikilink"
printf '| [[ghost\\|alias]] |\n' >> "$SANDBOX/tbl/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/tbl"
assert_eq "$OUT" "wiki-check: architecture.md: broken wikilink [[ghost]]" "table-escaped pipe, broken target"

clone wiki-good "$SANDBOX/closed"
printf '\n## Closed ##\n\nSee [[architecture#Closed]].\n' >> "$SANDBOX/closed/docs/architecture.md"
assert_exit 0 bash "$W" "$SANDBOX/closed"
assert_eq "$OUT" "" "heading with closing hashes"

# Fail closed: a broken awk is an error (exit 2), never green.
mkdir "$SANDBOX/stub"
printf '#!/bin/sh\necho boom\nexit 2\n' > "$SANDBOX/stub/awk"; chmod +x "$SANDBOX/stub/awk"
assert_exit 2 env PATH="$SANDBOX/stub:$PATH" bash "$W" "$FX/wiki-good"
assert_contains <(printf '%s' "$OUT") "wiki-check: internal error"
# The checks are one awk program in scripts/wiki-check.awk, loaded from the script's own folder (not
# written to the temp folder on each run); a plugin copy without it is an error too, never green.
assert_file "$SCRIPTS/wiki-check.awk"
grep -qF '/wiki-check.awk' "$W" && pass || fail "wiki-check.sh does not load wiki-check.awk from its own folder"
grep -q "<<'AWKEOF'" "$W" && fail "wiki-check.sh still holds an inline awk program" || pass
cp -R "$PLUGIN" "$SANDBOX/plugin-copy"; rm -f "$SANDBOX/plugin-copy/scripts/wiki-check.awk"
assert_exit 2 bash "$SANDBOX/plugin-copy/scripts/wiki-check.sh" "$FX/wiki-good"
assert_contains <(printf '%s' "$OUT") "wiki-check: internal error"

# A project path with spaces, copied from the fixture.
clone wiki-good "$SANDBOX/my project"
assert_exit 0 bash "$W" "$SANDBOX/my project"
echo '- [x](missing one.md)' >> "$SANDBOX/my project/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/my project"
assert_eq "$OUT" "wiki-check: architecture.md: broken link missing one.md" "spaced target reported whole"

# A big page is fine when it has ## headings.
clone long-page "$SANDBOX/big"
printf '\n## Part\n\nText.\n' >> "$SANDBOX/big/docs/features/login.md"
assert_exit 0 bash "$W" "$SANDBOX/big"

# A missing INDEX.md, an empty docs/ and bad usage.
clone wiki-good "$SANDBOX/c"
rm "$SANDBOX/c/docs/INDEX.md"
assert_exit 1 bash "$W" "$SANDBOX/c"
assert_contains <(printf '%s' "$OUT") "wiki-check: INDEX.md: "
assert_exit 2 bash "$W"
assert_exit 2 bash "$W" "$FX/wiki-good" src/app.sh
assert_exit 2 bash "$W" "$SANDBOX/does-not-exist"
# --code after --changed would be read as a changed path and the existence check skipped: a usage error
assert_exit 2 bash "$W" "$FX/wiki-good" --changed src/app.sh --code "$SANDBOX"
mkdir "$SANDBOX/nodocs"
assert_exit 1 bash "$W" "$SANDBOX/nodocs"

# I3: a folded or literal description (>, |, >-, |-) is not one line; ">" mid-text is fine.
clone wiki-good "$SANDBOX/fold"
i=0
for v in '>' '|' '>-' '|-'; do
  i=$((i + 1))
  printf -- '---\ntype: feature\nstatus: active\ndescription: %s\n  A long text folded\n  over two lines.\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n\n# F%s\n' "$v" "$i" > "$SANDBOX/fold/docs/features/f$i.md"
done
printf -- '---\ntype: feature\nstatus: active\ndescription: a > b and c | d\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n\n# F5\n' > "$SANDBOX/fold/docs/features/f5.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/fold" >/dev/null 2>&1
assert_exit 1 bash "$W" "$SANDBOX/fold"
assert_eq "$OUT" "wiki-check: features/f1.md: description not one line
wiki-check: features/f2.md: description not one line
wiki-check: features/f3.md: description not one line
wiki-check: features/f4.md: description not one line" "folded descriptions"

# M6: a related item that is not a wikilink is reported; [] passes.
clone wiki-good "$SANDBOX/relpath"
sed 's/^related: .*/related: [docs\/features\/login.md, "[[features\/login]]"]/' "$SANDBOX/relpath/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/relpath/docs/architecture.md"
sed 's/^  - "\[\[architecture\]\]"/  - architecture.md/' "$SANDBOX/relpath/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/relpath/docs/features/login.md"
assert_exit 1 bash "$W" "$SANDBOX/relpath"
assert_eq "$OUT" "wiki-check: architecture.md: related is not a wikilink: docs/features/login.md
wiki-check: features/login.md: related is not a wikilink: architecture.md" "related items are wikilinks"
clone wiki-good "$SANDBOX/relempty"
sed 's/^related: .*/related: []/' "$SANDBOX/relempty/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/relempty/docs/architecture.md"
assert_exit 0 bash "$W" "$SANDBOX/relempty"
assert_eq "$OUT" "" "related: [] passes"

# I1: an untyped page is reported once by wiki-check, with no wiki-index noise on stderr.
clone wiki-good "$SANDBOX/untyped"
printf -- '---\nstatus: active\ndescription: no type\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n\n# U\n' > "$SANDBOX/untyped/docs/u.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/untyped" >/dev/null 2>&1
SO="$(bash "$W" "$SANDBOX/untyped" 2>"$SANDBOX/werr")"
assert_eq "$SO" "wiki-check: u.md: missing front matter field type" "untyped page"
assert_eq "$(cat "$SANDBOX/werr")" "" "wiki-check stderr with an untyped page"

# History pages (status done or superseded) give no drift: they describe the past, the code moves on.
clone wiki-good "$SANDBOX/hist"
sed 's/^status: active/status: done/' "$SANDBOX/hist/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/hist/docs/architecture.md"
sed 's/^status: active/status: superseded/' "$SANDBOX/hist/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/hist/docs/features/login.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/hist" >/dev/null
assert_exit 0 bash "$W" "$SANDBOX/hist" --changed src/app.sh src/lib/util.sh src/login.sh
assert_eq "$OUT" "" "done and superseded pages give no drift"

# --code <dir>: every files: entry of an active page must exist in the working tree of the code root.
# The code root of wiki-good: the files and folders its pages list, plus entries with a space.
CR="$SANDBOX/code root"; mkdir -p "$CR/src/lib" "$CR/my dir"
: > "$CR/src/app.sh"; : > "$CR/src/login.sh"; : > "$CR/my file.sh"
clone wiki-good "$FX/codewiki"
sed 's/^  - src\/login\.sh$/&\
  - "my dir\/"\
  - my file.sh/' "$FX/codewiki/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$FX/codewiki/docs/features/login.md"
assert_contains "$FX/codewiki/docs/features/login.md" '  - "my dir/"'
# A legitimate tree passes: present files and folders (a folder entry ends in /, a path with a space).
assert_exit 0 bash "$W" "$FX/codewiki" --code "$CR"
assert_eq "$OUT" "" "present files: entries pass"
cd "$SANDBOX" || exit 1                          # a relative code root
assert_exit 0 bash "$W" "$FX/codewiki" --code "code root/"
cd "$ROOT" || exit 1
# --code alone runs only the existence check (no drift without --changed); with --changed both run.
check codewiki "wiki-check: architecture.md: drift: src/app.sh changed, page not updated" --code "$CR" --changed src/app.sh
# Missing paths: a file, a folder, a folder entry that is a file, an entry with a space.
CM="$SANDBOX/code missing"; cp -R "$CR" "$CM"
rm "$CM/src/login.sh"; rm -r "$CM/src/lib"; : > "$CM/src/lib"; rm -r "$CM/my dir"
check codewiki "wiki-check: architecture.md: missing file src/lib/
wiki-check: features/login.md: missing file src/login.sh
wiki-check: features/login.md: missing file my dir/" --code "$CM"
check codewiki "wiki-check: architecture.md: missing file src/lib/
wiki-check: features/login.md: missing file src/login.sh
wiki-check: features/login.md: missing file my dir/
wiki-check: features/login.md: drift: my file.sh changed, page not updated" --code "$CM" --changed "my file.sh"
# Without --code nothing is checked for existence (wiki-good has no code root at all).
assert_exit 0 bash "$W" "$FX/codewiki"
# Draft pages list files they will create; history pages list files that may be gone: neither is checked.
clone codewiki "$SANDBOX/codedraft"
sed 's/^status: active/status: draft/' "$SANDBOX/codedraft/docs/features/login.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/codedraft/docs/features/login.md"
sed 's/^status: active/status: superseded/' "$SANDBOX/codedraft/docs/architecture.md" > "$SANDBOX/s.tmp" && mv "$SANDBOX/s.tmp" "$SANDBOX/codedraft/docs/architecture.md"
bash "$SCRIPTS/wiki-index.sh" "$SANDBOX/codedraft" >/dev/null
assert_exit 0 bash "$W" "$SANDBOX/codedraft" --code "$CM"
assert_eq "$OUT" "" "draft and history pages are not checked for missing files"
# --code needs a folder that exists, and comes before --changed.
assert_exit 2 bash "$W" "$FX/codewiki" --code
assert_exit 2 bash "$W" "$FX/codewiki" --code ""
assert_exit 2 bash "$W" "$FX/codewiki" --code --changed src/app.sh
assert_exit 2 bash "$W" "$FX/codewiki" --code "$SANDBOX/does-not-exist"
assert_exit 2 bash "$W" "$FX/codewiki" --code "$CR/src/app.sh"

# Rules file and docs.
assert_file "$PLUGIN/reference/wiki.md"
[ "$(wc -l < "$PLUGIN/reference/wiki.md")" -le 80 ] && pass || fail "reference/wiki.md over 80 lines"
assert_contains "$PLUGIN/reference/wiki.md" "git -C <Core> diff --name-only HEAD -- <project>/docs"
assert_contains "$PLUGIN/reference/wiki.md" "git -C <Core> ls-files --others --exclude-standard -- <project>/docs"
finish
