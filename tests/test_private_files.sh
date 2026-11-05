#!/usr/bin/env bash
# The repo's internal files (the root CLAUDE.md, AGENTS.md, .claude/ and docs/) live in the private
# Core after adopt; only the public docs (docs/migration-*, docs/icons/) stay in the repo. A test
# that reads an internal file fails in a fresh clone, or passes without checking anything, so no
# test may read one, and no public README may name one.
source "$(dirname "$0")/lib.sh"

# private_reads <dir> — lines of <dir>/test_*.sh that read an internal file of the repo root
private_reads() {
  LC_ALL=C grep -nE '\$ROOT/(CLAUDE\.md|CLAUDE\.local\.md|AGENTS\.md|\.claude/|docs/)' "$1"/test_*.sh 2>/dev/null \
    | LC_ALL=C grep -vE '\$ROOT/docs/(migration-[^/"]*\.md|icons/)' \
    | LC_ALL=C grep -vF "$1/test_private_files.sh:"
}

# the check itself: a public doc passes, an internal file is caught
T="$(mktemp -d)"
printf 'assert_file "$ROOT/docs/migration-0.3.md"\nassert_file "$ROOT/docs/icons/a.svg"\nassert_file "$ROOT/README.md"\n' > "$T/test_ok.sh"
assert_eq "$(private_reads "$T")" "" "public docs are allowed"
printf 'assert_contains "$ROOT/CLAUDE.md" x\nassert_file "$ROOT/docs/specs/s.md"\n' > "$T/test_bad.sh"
assert_eq "$(private_reads "$T" | wc -l | tr -d ' ')" "2" "internal files are caught"
rm -rf "$T"

# the real tests
BAD="$(private_reads "$ROOT/tests")"
[ -z "$BAD" ] && pass || fail "tests read internal repo files (they move to the Core on adopt):
$BAD"

# The public READMEs name no private doc (specs, plans): a reader of the repo cannot open it.
for f in "$ROOT/README.md" "$ROOT"/plugins/*/README.md; do
  NAMED="$(LC_ALL=C grep -noE '(^|[^A-Za-z0-9_./~<-])docs/[A-Za-z0-9_./-]*[A-Za-z0-9_]/?' "$f" \
    | LC_ALL=C grep -vE 'docs/(migration-[^/]*\.md|icons/)')"
  [ -z "$NAMED" ] && pass || fail "${f#$ROOT/} names private docs: $NAMED"
done
finish
