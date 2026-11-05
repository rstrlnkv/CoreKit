#!/usr/bin/env bash
# wiki-pages.sh and wiki-index.sh: page list, generated docs/INDEX.md, --check, edge cases.
source "$(dirname "$0")/lib.sh"
new_sandbox
P="$SCRIPTS/wiki-pages.sh"
I="$SCRIPTS/wiki-index.sh"
FX="$SANDBOX/fixtures"; cp -R "$ROOT/tests/fixtures" "$FX"
for f in "$FX"/*/CLAUDE.md.in; do mv "$f" "${f%.in}"; done

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

# --- wiki-index.sh: first run creates the exact INDEX
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
assert_eq "$OUT" "updated docs/INDEX.md" "existing INDEX is rewritten"
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
assert_eq "$OUT" "skipped docs/INDEX.md" "second run"
assert_eq "$(cksum < "$IDX")" "$before" "INDEX untouched on skip"
assert_exit 0 bash "$I" "$FX/wiki-index" --check
assert_eq "$OUT" "" "--check silent when equal"
assert_exit 0 bash "$I" "$FX/wiki-index/" --check      # trailing slash

# stale after one description edit
cp "$FX/wiki-index/docs/features/login.md" "$SANDBOX/login.bak"
{ sed 's/^description: .*/description: sign-in with a passkey/' "$SANDBOX/login.bak"; } > "$FX/wiki-index/docs/features/login.md"
assert_exit 1 bash "$I" "$FX/wiki-index" --check
assert_eq "$OUT" "wiki-index: stale" "--check after edit"
assert_eq "$(cat "$IDX")" "$WANT" "--check does not write"
assert_exit 0 bash "$I" "$FX/wiki-index"
assert_eq "$OUT" "updated docs/INDEX.md" "regenerated"
assert_contains "$IDX" "[[login]] sign-in with a passkey"
assert_exit 0 bash "$I" "$FX/wiki-index" --check

# a page without type, or with an unknown type, is not in the INDEX; adding a typed page is
printf -- '---\ntype: feature\nstatus: active\ndescription: added later\nfiles: []\nrelated: []\nupdated: 2026-11-06\n---\n' > "$FX/wiki-index/docs/features/added.md"
assert_exit 1 bash "$I" "$FX/wiki-index" --check
assert_eq "$OUT" "wiki-index: stale" "new page makes it stale"

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

# --- usage: exit 2
assert_exit 2 bash "$I"
assert_exit 2 bash "$I" "$FX/wiki-index" --bogus
assert_exit 2 bash "$I" "$FX/no-such-project"

finish
