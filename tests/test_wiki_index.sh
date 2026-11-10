#!/usr/bin/env bash
# wiki-pages.sh and wiki-index.sh: page list, generated docs/INDEX.md, --check, edge cases.
source "$(dirname "$0")/lib.sh"
new_sandbox
P="$SCRIPTS/wiki-pages.sh"
I="$SCRIPTS/wiki-index.sh"
FX="$SANDBOX/fixtures"; mkdir -p "$FX"
for n in wiki-index wiki-index-fresh; do copy_fixture "$n" "$FX/$n"; done

# --- wiki-pages.sh: docs-relative, C-sorted; no INDEX.md, knowledge/, standards/, superpowers/, .obsidian/
assert_exit 0 bash "$P" "$FX/wiki-index/docs"
assert_eq "$OUT" "architecture.md
badtype.md
brief.md
decisions/001-stack.md
features/crlf-page.md
features/login.md
features/sign in.md
glossary.md
notype.md
plans/2026-11-05-rollout.md
specs/2026-11-04-layout.md
specs/old-spec.md" "page list"
assert_exit 2 bash "$P" "$FX/no-such-dir"
assert_exit 2 bash "$P"

# --- wiki-index.sh: first run rewrites the old INDEX with the exact content
WANT="# wiki-index wiki
One line per page; open only the page you need.

## brief
[[brief]] what, for whom, v1 scope
## architecture
[[architecture]] components: parser # and store
## decision
[[001-stack]] why bash: single quotes # kept inside
## feature
[[crlf-page]] written with CRLF: line endings
[[login]] sign-in with email
[[sign in]] page with a space in its name
## spec
[[2026-11-04-layout]] code beside Core; where each file lives
## glossary
[[glossary]] terms used in the wiki
history: 2 done or superseded pages, see wiki.base"
IDX="$FX/wiki-index/docs/INDEX.md"
assert_exit 0 bash "$I" "$FX/wiki-index"
assert_eq "$OUT" "wiki-index: skipped notype.md: no type
updated docs/INDEX.md" "existing INDEX is rewritten; the untyped page is named"
# M3: the untyped page is named on stderr, stdout keeps one line, exit 0
SO="$(bash "$I" "$FX/wiki-index" 2>"$SANDBOX/ierr")"; RC=$?
assert_eq "$RC" "0" "untyped page in a typed wiki: exit"
assert_eq "$SO" "skipped docs/INDEX.md" "untyped page: stdout"
assert_eq "$(cat "$SANDBOX/ierr")" "wiki-index: skipped notype.md: no type" "untyped page: stderr"
assert_eq "$(cat "$IDX")" "$WANT" "INDEX content"
# no CR in the output even for the CRLF page, no front matter noise, no left-out pages
assert_eq "$(grep -c "$(printf '\r')" "$IDX")" "0" "no CR in INDEX"
assert_not_contains "$IDX" "badtype"
assert_not_contains "$IDX" "notype"
assert_not_contains "$IDX" "rollout"
assert_not_contains "$IDX" "old-spec"
assert_not_contains "$IDX" '"'
assert_not_contains "$IDX" "'why"
assert_not_contains "$IDX" "## plan"
# the file ends with a newline
assert_eq "$(tail -c1 "$IDX" | od -An -c | tr -d ' ')" '\n' "ends with newline"

# second run: skipped, file untouched, --check clean
before="$(cksum < "$IDX")"
assert_exit 0 bash "$I" "$FX/wiki-index"
assert_eq "$OUT" "wiki-index: skipped notype.md: no type
skipped docs/INDEX.md" "second run"
assert_eq "$(cksum < "$IDX")" "$before" "INDEX untouched on skip"
assert_exit 0 bash "$I" "$FX/wiki-index" --check
assert_eq "$OUT" "wiki-index: skipped notype.md: no type" "--check: only the untyped page when equal"
assert_exit 0 bash "$I" "$FX/wiki-index/" --check      # trailing slash

# stale after one description edit
cp "$FX/wiki-index/docs/features/login.md" "$SANDBOX/login.bak"
{ sed 's/^description: .*/description: sign-in with a passkey/' "$SANDBOX/login.bak"; } > "$FX/wiki-index/docs/features/login.md"
assert_exit 1 bash "$I" "$FX/wiki-index" --check
assert_eq "$(printf '%s\n' "$OUT" | grep -v 'no type$')" "wiki-index: stale" "--check after edit"
assert_eq "$(cat "$IDX")" "$WANT" "--check does not write"
assert_exit 0 bash "$I" "$FX/wiki-index"
assert_eq "$(printf '%s\n' "$OUT" | grep -v 'no type$')" "updated docs/INDEX.md" "regenerated"
assert_contains "$IDX" "[[login]] sign-in with a passkey"
assert_exit 0 bash "$I" "$FX/wiki-index" --check

# adding a typed page makes the INDEX stale
printf -- '---\ntype: feature\nstatus: active\ndescription: added later\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n' > "$FX/wiki-index/docs/features/added.md"
assert_exit 1 bash "$I" "$FX/wiki-index" --check
assert_eq "$(printf '%s\n' "$OUT" | grep -v 'no type$')" "wiki-index: stale" "new page makes it stale"

# --- missing INDEX: --check is stale and creates nothing; a run says created
assert_exit 1 bash "$I" "$FX/wiki-index-fresh" --check
assert_eq "$OUT" "wiki-index: stale" "--check with no INDEX"
assert_no_file "$FX/wiki-index-fresh/docs/INDEX.md"
assert_exit 0 bash "$I" "$FX/wiki-index-fresh"
assert_eq "$OUT" "created docs/INDEX.md" "fresh run"
assert_eq "$(cat "$FX/wiki-index-fresh/docs/INDEX.md")" "# wiki-index-fresh wiki
One line per page; open only the page you need.

## brief
[[brief]] fresh brief
## feature
[[feature-a]] a draft feature" "fresh INDEX: draft is listed, no history line without old pages"
assert_not_contains "$FX/wiki-index-fresh/docs/INDEX.md" "history:"

# --- I1: a 0.6 wiki (pages, none with a type) is refused: exit 1, one line, INDEX.md byte-identical
OLD6="$SANDBOX/old6"; copy_fixture wiki-old "$OLD6"
rm "$OLD6/docs/features/export.md"        # the one page of the fixture already in the new format
grep -rlq '^type:' "$OLD6/docs" --include='*.md' && fail "0.6 copy still has a typed page" || pass
cp "$OLD6/docs/INDEX.md" "$SANDBOX/old6.index"
for m in "" --check; do
  OUT="$(bash "$I" "$OLD6" $m 2>"$SANDBOX/ierr")"; RC=$?
  assert_eq "$RC" "1" "0.6 wiki ${m:-write}: exit"
  assert_eq "$OUT" "wiki-index: no page has a type; run wiki-migrate.sh first" "0.6 wiki ${m:-write}: stdout"
  assert_eq "$(cat "$SANDBOX/ierr")" "" "0.6 wiki ${m:-write}: stderr"
  cmp -s "$OLD6/docs/INDEX.md" "$SANDBOX/old6.index" && pass || fail "0.6 wiki ${m:-write}: INDEX.md changed"
done
ls "$OLD6/docs" | grep -q 'wiki-index' && fail "0.6 wiki: a temp file was left in docs/" || pass
# an empty docs/ (no pages) still generates the header
mkdir -p "$SANDBOX/emptyw/docs"
assert_exit 0 bash "$I" "$SANDBOX/emptyw"
assert_eq "$OUT" "created docs/INDEX.md" "empty docs/: created"
assert_eq "$(cat "$SANDBOX/emptyw/docs/INDEX.md")" "# emptyw wiki
One line per page; open only the page you need." "empty docs/: header only"

# --- one copy of the fixture with the pages below; the whole INDEX.md and the whole stderr are compared
FM="$SANDBOX/fm"; copy_fixture wiki-index "$FM"; D="$FM/docs"
REST='files: []\nrelated: []\nupdated: 2026-11-06\n'; SPC=' '
# front matter as wiki-check reads it: a fence with a trailing blank or tab, a blank before the colon
printf -- "--- \ntype: feature\nstatus: active\ndescription: fence with a trailing blank\n$REST--- \n\n# Trail\n" > "$D/features/trail.md"
printf -- "---\t\ntype: feature\nstatus: active\ndescription: fence with a trailing tab\n$REST---\t\n\n# Tabs\n" > "$D/features/tabs.md"
printf -- "---\ntype : feature\nstatus\t: active\ndescription : blank before the colon\n$REST---\n\n# Space\n" > "$D/features/space.md"
printf -- "---\ntype: spec\nstatus : done\ndescription: history, with a blank before the colon\n$REST---\n" > "$D/specs/spacedone.md"
# the closing fence has a trailing blank: the body line after it is no field (the page is not history)
printf -- "---\ntype: feature\nstatus: active\ndescription: closing fence with a trailing blank\n$REST--- \n\nstatus: done\n" > "$D/features/close.md"
# fields are read from the front matter only: a body "status: done" or "description:" after the closing --- does
# not count (the page stays listed, with an empty description)
printf -- "---\ntype: feature\n$REST---\n\n# Body fields\n\nstatus: done\ndescription: x\n" > "$D/features/bodyfields.md"
# no front matter at all: a body line "type: feature" gives the page no type
printf '# Plain\n\ntype: feature\nstatus: active\ndescription: from the body\n' > "$D/plain.md"
# a group is sorted by page name, not by path: aaa/ sorts before features/, zzz-last after every feature name
mkdir -p "$D/aaa" "$D/.obsidian/plugins/x"
printf -- "---\ntype: feature\nstatus: active\ndescription: sorted by name, not by path\n$REST---\n" > "$D/aaa/zzz-last.md"
# a Markdown file of an Obsidian plugin is no page, even with a valid type
printf -- "---\ntype: feature\nstatus: active\ndescription: an Obsidian plugin file\n$REST---\n" > "$D/.obsidian/plugins/x/README.md"
assert_exit 0 bash "$P" "$D"
printf '%s\n' "$OUT" | grep -q 'obsidian' && fail "wiki-pages lists a file under .obsidian/: $OUT" || pass
printf '%s\n' "$OUT" | grep -qxF 'aaa/zzz-last.md' && pass || fail "wiki-pages does not list aaa/zzz-last.md: $OUT"
SO="$(bash "$I" "$FM" 2>"$SANDBOX/fmerr")"; RC=$?
assert_eq "$RC" "0" "front matter forms: exit"
assert_eq "$SO" "updated docs/INDEX.md" "front matter forms: stdout"
assert_eq "$(cat "$SANDBOX/fmerr")" "wiki-index: skipped notype.md: no type
wiki-index: skipped plain.md: no type" "front matter forms: only the two pages without a type are skipped"
assert_eq "$(cat "$D/INDEX.md")" "# fm wiki
One line per page; open only the page you need.

## brief
[[brief]] what, for whom, v1 scope
## architecture
[[architecture]] components: parser # and store
## decision
[[001-stack]] why bash: single quotes # kept inside
## feature
[[bodyfields]]$SPC
[[close]] closing fence with a trailing blank
[[crlf-page]] written with CRLF: line endings
[[login]] sign-in with email
[[sign in]] page with a space in its name
[[space]] blank before the colon
[[tabs]] fence with a trailing tab
[[trail]] fence with a trailing blank
[[zzz-last]] sorted by name, not by path
## spec
[[2026-11-04-layout]] code beside Core; where each file lives
## glossary
[[glossary]] terms used in the wiki
history: 3 done or superseded pages, see wiki.base" "front matter forms: INDEX content"

# --- INDEX.md is a plain readable file (rw-r--r--), created or rewritten, whatever the umask
MO="$SANDBOX/mode"; copy_fixture wiki-index-fresh "$MO"
OUT="$(umask 077; bash "$I" "$MO" 2>&1)"; assert_eq "$OUT" "created docs/INDEX.md" "mode case: created"
assert_eq "$(ls -l "$MO/docs/INDEX.md" | cut -c1-10)" "-rw-r--r--" "mode of a created INDEX.md"
printf -- "---\ntype: feature\nstatus: active\ndescription: one more\n$REST---\n" > "$MO/docs/more.md"
OUT="$(umask 077; bash "$I" "$MO" 2>&1)"; assert_eq "$OUT" "updated docs/INDEX.md" "mode case: rewritten"
assert_eq "$(ls -l "$MO/docs/INDEX.md" | cut -c1-10)" "-rw-r--r--" "mode of a rewritten INDEX.md"

# --- no temp file stays behind: after a write, after --check stale, after the 0.6 refusal
TD="$SANDBOX/tmpdir"; mkdir "$TD"
tmp_left() { assert_eq "$(ls -A "$TD")" "" "temp files left after $1"; }
printf -- "---\ntype: feature\nstatus: active\ndescription: and another\n$REST---\n" > "$MO/docs/another.md"
OUT="$(TMPDIR="$TD" bash "$I" "$MO" --check 2>&1)"; assert_eq "$?" "1" "temp case: --check stale exit"; tmp_left "--check stale"
OUT="$(TMPDIR="$TD" bash "$I" "$MO" 2>&1)"; assert_eq "$?" "0" "temp case: write exit"; assert_eq "$OUT" "updated docs/INDEX.md" "temp case: write"; tmp_left "a write"
OUT="$(TMPDIR="$TD" bash "$I" "$MO" 2>&1)"; assert_eq "$OUT" "skipped docs/INDEX.md" "temp case: skip"; tmp_left "a skipped write"
OUT="$(TMPDIR="$TD" bash "$I" "$OLD6" 2>&1)"; assert_eq "$?" "1" "temp case: 0.6 wiki exit"; tmp_left "the 0.6 refusal"

# --- usage: exit 2
assert_exit 2 bash "$I"
assert_exit 2 bash "$I" "$FX/wiki-index" --bogus
assert_exit 2 bash "$I" "$FX/no-such-project"

finish
