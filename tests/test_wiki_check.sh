#!/usr/bin/env bash
# wiki-check.sh: one good wiki, one broken fixture per check, drift with --changed, edge cases.
source "$(dirname "$0")/lib.sh"
new_sandbox
W="$SCRIPTS/wiki-check.sh"
FX="$ROOT/tests/fixtures"

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

# One broken fixture per check.
check wiki-bad-1 "wiki-check: features/login.md: missing front matter field status
wiki-check: features/login.md: missing front matter field updated"
check wiki-bad-2 "wiki-check: INDEX.md: INDEX.md links missing page features/ghost.md
wiki-check: features/orphan.md: not in INDEX.md"
check wiki-bad-3 "wiki-check: architecture.md: broken link nope.md
wiki-check: architecture.md: broken reference § No such heading (no such heading in docs/architecture.md)
wiki-check: architecture.md: broken reference § Flow (no such page docs/features/gone.md)"
check wiki-bad-4 "wiki-check: architecture.md: duplicate heading Components"
check wiki-bad-5 "wiki-check: features/login.md: page over 8 KB without ## headings"

check wiki-bad-7 "wiki-check: features/login.md: unclosed front matter"

# Problem prefixes, exactly as the verifier and release read them.
assert_exit 1 bash "$W" "$FX/wiki-bad-3"
assert_contains <(printf '%s' "$OUT") "wiki-check: architecture.md: broken link "
assert_exit 1 bash "$W" "$FX/wiki-bad-1"
assert_contains <(printf '%s' "$OUT") ": missing front matter field "

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
check wiki-bad-6 "wiki-check: features/login.md: drift: src/auth/token.sh changed, page not updated" \
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

# Edge cases: comma/em dash/backtick headings, spaced page name, anchors, schemes, fences.
assert_exit 0 bash "$W" "$FX/wiki-edge"
assert_eq "$OUT" "" "edge wiki prints nothing"

# The edge references are really checked: rename the headings and they break.
cp -R "$FX/wiki-edge" "$SANDBOX/edge2"
sed -e 's/^## Storage, sync — what and why/## Storage/' -e 's/^## The `save` command/## Save/' \
  "$SANDBOX/edge2/docs/architecture.md" > "$SANDBOX/arch.tmp" && mv "$SANDBOX/arch.tmp" "$SANDBOX/edge2/docs/architecture.md"
sed 's/^## Overview/## Summary/' "$SANDBOX/edge2/docs/features/space page.md" > "$SANDBOX/sp.tmp" \
  && mv "$SANDBOX/sp.tmp" "$SANDBOX/edge2/docs/features/space page.md"
assert_exit 1 bash "$W" "$SANDBOX/edge2"
assert_eq "$OUT" "wiki-check: architecture.md: broken reference § Overview (no such heading in docs/features/space page.md)
wiki-check: architecture.md: broken reference § Overview (no such heading in docs/features/space page.md)
wiki-check: architecture.md: broken reference § Storage, sync — what and why (no such heading in docs/architecture.md)
wiki-check: architecture.md: broken reference § Storage, sync — what and why (no such heading in docs/architecture.md)
wiki-check: architecture.md: broken reference § The (no such heading in docs/architecture.md)" "renamed headings"   # shown up to the first backtick

# A reference at the end of a sentence: one trailing . , ; : ) is forgiven; exact text wins.
cp -R "$FX/wiki-good" "$SANDBOX/punct"
printf '\nSee docs/architecture.md § Components.\n(see docs/architecture.md § Storage)\nSee docs/architecture.md § Storage;\n' >> "$SANDBOX/punct/CLAUDE.md"
assert_exit 0 bash "$W" "$SANDBOX/punct"
assert_eq "$OUT" "" "trailing punctuation"
printf 'See docs/architecture.md § Nowhere.\n' >> "$SANDBOX/punct/CLAUDE.md"
assert_exit 1 bash "$W" "$SANDBOX/punct"
assert_eq "$OUT" "wiki-check: ../CLAUDE.md: broken reference § Nowhere. (no such heading in docs/architecture.md)" "still broken"
# A heading that itself ends in a period matches exactly.
cp -R "$FX/wiki-good" "$SANDBOX/period"
printf '\n## Done.\n' >> "$SANDBOX/period/docs/architecture.md"
printf 'See docs/architecture.md § Done.\n' >> "$SANDBOX/period/CLAUDE.md"
assert_exit 0 bash "$W" "$SANDBOX/period"

# Fail closed: a broken awk is an error (exit 2), never green.
mkdir "$SANDBOX/stub"
printf '#!/bin/sh\necho boom\nexit 2\n' > "$SANDBOX/stub/awk"; chmod +x "$SANDBOX/stub/awk"
assert_exit 2 env PATH="$SANDBOX/stub:$PATH" bash "$W" "$FX/wiki-good"
assert_contains <(printf '%s' "$OUT") "wiki-check: internal error"

# A project path with spaces, copied from the fixture.
cp -R "$FX/wiki-good" "$SANDBOX/my project"
assert_exit 0 bash "$W" "$SANDBOX/my project"
echo '- [x](missing one.md)' >> "$SANDBOX/my project/docs/architecture.md"
assert_exit 1 bash "$W" "$SANDBOX/my project"
assert_eq "$OUT" "wiki-check: architecture.md: broken link missing one.md" "spaced target reported whole"

# A big page is fine when it has ## headings.
cp -R "$FX/wiki-bad-5" "$SANDBOX/big"
printf '\n## Part\n\nText.\n' >> "$SANDBOX/big/docs/features/login.md"
assert_exit 0 bash "$W" "$SANDBOX/big"

# Problem in CLAUDE.md is reported as ../CLAUDE.md; a missing INDEX.md and bad usage.
cp -R "$FX/wiki-good" "$SANDBOX/c"
echo 'See docs/architecture.md § Nowhere' >> "$SANDBOX/c/CLAUDE.md"
assert_exit 1 bash "$W" "$SANDBOX/c"
assert_eq "$OUT" "wiki-check: ../CLAUDE.md: broken reference § Nowhere (no such heading in docs/architecture.md)" "CLAUDE.md"
rm "$SANDBOX/c/docs/INDEX.md"
assert_exit 1 bash "$W" "$SANDBOX/c"
assert_contains <(printf '%s' "$OUT") "wiki-check: INDEX.md: missing"
assert_exit 2 bash "$W"
assert_exit 2 bash "$W" "$FX/wiki-good" src/app.sh
assert_exit 2 bash "$W" "$SANDBOX/does-not-exist"
mkdir "$SANDBOX/nodocs"
assert_exit 1 bash "$W" "$SANDBOX/nodocs"

# Rules file and docs.
assert_file "$PLUGIN/reference/wiki.md"
[ "$(wc -l < "$PLUGIN/reference/wiki.md")" -le 80 ] && pass || fail "reference/wiki.md over 80 lines"
assert_contains "$PLUGIN/reference/wiki.md" "docs/<page>.md § <exact heading>"
assert_contains "$PLUGIN/reference/wiki.md" "git -C <Core> diff --name-only HEAD -- <project>/docs"
assert_contains "$PLUGIN/reference/wiki.md" "git -C <Core> ls-files --others --exclude-standard -- <project>/docs"
assert_not_contains "$ROOT/CLAUDE.md" "cross-marketplace allowance"
assert_not_contains "$ROOT/CLAUDE.md" "userConfig, dependencies"
assert_contains "$ROOT/CLAUDE.md" "wiki-check.sh"
finish
