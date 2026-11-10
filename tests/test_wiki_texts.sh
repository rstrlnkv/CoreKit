#!/usr/bin/env bash
# The texts that teach the wiki (agents, skills, reference/wiki.md, README) match the 0.7 wiki:
# typed front matter, wikilinks, generated INDEX.md, wiki.base, wiki-migrate.sh.
# Spec: the maintainer's design notes (private).
source "$(dirname "$0")/lib.sh"
WK="$PLUGIN/reference/wiki.md"
ENG="$PLUGIN/agents/engineer.md"
REL="$PLUGIN/skills/task/references/release.md"
ADO="$PLUGIN/skills/task/references/adopt.md"
NP="$PLUGIN/skills/new-project/SKILL.md"
CHECK="$SCRIPTS/wiki-check.sh"
TEXTS="$PLUGIN/agents $PLUGIN/skills $PLUGIN/reference"
# the teaching texts only: markdown, not scripts or templates (templates have their own tests)
textfiles() { find $TEXTS -name '*.md' -not -path '*/templates/*'; }

# 1. No old instruction survives: § references, hand-written INDEX / map lines.
for f in $(textfiles); do
  grep -q '§' "$f" && fail "$f still has a § reference form" || pass
  grep -qiE 'add (a|an) [^.]*INDEX' "$f" && fail "$f still tells to add a line to INDEX" || pass
  grep -qi 'map line' "$f" && fail "$f still tells to add a map line" || pass
  grep -qE 'not in INDEX\.md|INDEX\.md links missing page|broken reference' "$f" && fail "$f names a removed wiki-check problem" || pass
  grep -qE '^[[:space:]-]*`?title`?[:,]|`title`' "$f" && fail "$f names title as a wiki field" || pass
done

# 2. docs/superpowers is named only as the 0.6 location wiki-migrate moves.
for f in $(textfiles); do
  if grep -q 'docs/superpowers' "$f"; then
    grep -q 'wiki-migrate' "$f" && pass || fail "$f names docs/superpowers without saying wiki-migrate moves it"
  fi
done
grep -q 'docs/superpowers/\(plans\|specs\)' "$NP" && fail "new-project SKILL.md sends plans/specs to docs/superpowers" || pass
assert_contains "$NP" 'docs/plans/'

# 3. wiki-index.sh is named where pages are made.
assert_contains "$ENG" 'wiki-index.sh'
assert_contains "$NP" 'wiki-index.sh'
assert_contains "$REL" 'wiki-index.sh'
wi="$(grep -n 'wiki-index\.sh' "$REL" | head -1 | cut -d: -f1)"
wc="$(grep -n 'wiki-check\.sh' "$REL" | head -1 | cut -d: -f1)"
[ -n "$wi" ] && [ -n "$wc" ] && [ "$wi" -le "$wc" ] && pass || fail "release.md: wiki-index.sh must come before wiki-check.sh (index=$wi check=$wc)"
# the same line (the release wiki step) may hold both, in that order
l="$(grep -n 'wiki-check\.sh' "$REL" | head -1 | cut -d: -f2-)"
case "$l" in *wiki-check.sh*wiki-index.sh*) fail "release.md: wiki-check.sh named before wiki-index.sh on one line" ;; *) pass ;; esac

# 4. reference/wiki.md teaches the new wiki.
for fld in type status description files related updated; do assert_contains "$WK" "\`$fld\`"; done
for v in brief architecture decision feature spec plan glossary draft active 'done' superseded; do assert_contains "$WK" "$v"; done
assert_contains "$WK" 'YYYY-MM-DD'
grep -qiE '80 char' "$WK" && pass || fail "wiki.md lacks the 80-character description limit"
assert_contains "$WK" '[[name]]'
assert_contains "$WK" '[[name#Heading]]'
assert_contains "$WK" '[[name|alias]]'
assert_contains "$WK" 'wiki-index.sh'
assert_contains "$WK" 'wiki.base'
assert_contains "$WK" 'wiki-migrate.sh'
assert_contains "$WK" 'generated'
assert_contains "$WK" 'unique'
# the field list order is stated: type before status before description before files before related before updated
grep -qE '`type`.*`status`.*`description`.*`files`.*`related`.*`updated`' "$WK" && pass || fail "wiki.md does not list the six fields in order on one line"

# 5. The checks table lists exactly the problem texts of wiki-check.sh's header (derived, not copied).
want="$(awk '/^# Checks \(/ {f=1; next} /^# Two lines stand alone/ {f=0} f && /^#   [^ ]/ {
  s=substr($0, 5); i=index(s, "  "); if (i>0) s=substr(s, 1, i-1); print s }' "$CHECK")"
n="$(printf '%s\n' "$want" | grep -c .)"
[ "$n" -ge 14 ] && pass || fail "could not derive the problem list from wiki-check.sh header ($n lines)"
printf '%s\n' "$want" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -qF -- "$p" "$WK" && echo ok || echo "  FAIL: wiki.md checks table lacks wiki-check problem: $p"
done > "${TMPDIR:-/tmp}/wt.$$"
PASSES=$((PASSES + $(grep -c '^ok$' "${TMPDIR:-/tmp}/wt.$$")))
while IFS= read -r l; do case "$l" in *FAIL*) FAILS=$((FAILS + 1)); echo "$l";; esac; done < "${TMPDIR:-/tmp}/wt.$$"
rm -f "${TMPDIR:-/tmp}/wt.$$"
assert_contains "$WK" 'INDEX.md: missing'
assert_contains "$WK" 'missing docs/ directory'

# 6. AGENTS.md link is taught next to CLAUDE.local.md.
for f in "$NP" "$ADO"; do
  grep 'CLAUDE.local.md' "$f" | grep -q 'AGENTS.md' && pass || fail "$f never names AGENTS.md next to CLAUDE.local.md"
done

# 7. corecrew's README names no removed behaviour in its wiki lines.
R="$ROOT/plugins/corecrew/README.md"   # the wiki is a corecrew feature
w="$(grep -iE 'wiki|INDEX|docs/' "$R")"
for bad in '§' 'map line' 'hand-written' 'by hand' 'title'; do
  printf '%s\n' "$w" | grep -qiF -- "$bad" && fail "README wiki line names removed behaviour: $bad" || pass
done
printf '%s\n' "$w" | grep -qF 'front matter' && pass || fail "README does not mention front matter"
grep -qE 'wikilink|\[\[|Obsidian' "$R" && pass || fail "README does not mention wikilinks or Obsidian"
{ grep -qF 'wiki-index' "$R" || grep -qi 'generated' "$R"; } && pass || fail "README does not say INDEX.md is generated"

# 8. Round 1 rulings.
# release.md: a 0.6 wiki is migrated at task Start, never at release (I1)
grep -qF 'converted first with' "$REL" && fail "release.md still migrates the wiki at release" || pass
assert_contains "$REL" '`no page has a type`'
assert_contains "$REL" 'baseline'
assert_contains "$REL" 'pre-existing problem'
assert_contains "$REL" 'Only new lines are ✗'
grep -qF 'wiki-migrate.sh' "$REL" && pass || fail "release.md: a refused wiki names wiki-migrate.sh"
# SKILL.md Start: a wiki without types (corecrew 0.6 and older) stops the chain with the command that converts it
# (corecrew 1.0, P3: task no longer runs the conversion); then the wiki-check baseline
SK="$PLUGIN/skills/task/SKILL.md"
st="$(awk '$0 == "## Start" {f=1; next} /^## /{f=0} f' "$SK")"
for w in 'wiki-index.sh" "<Core>/<project>" --check' 'no page has a type' \
         'wiki-migrate.sh" "<Core>/<project>"' 'stop the chain' \
         'wiki-check.sh" "<Core>/<project>"' '**baseline**'; do
  printf '%s\n' "$st" | grep -qF -- "$w" && pass || fail "SKILL.md Start lacks: $w"
done
# corecrew 1.0 (P3): the older-formats reference is gone, and nothing in the plugin points at it
assert_no_file "$PLUGIN/reference/older-formats.md"
assert_eq "$(grep -rl 'older-formats' "$PLUGIN" 2>/dev/null)" "" "no plugin file names older-formats.md"
# the wiki step comes before the base commits are recorded (the migration commit is not chain work)
ws="$(printf '%s\n' "$st" | grep -n 'wiki-migrate.sh' | head -1 | cut -d: -f1)"
bs="$(printf '%s\n' "$st" | grep -n 'Base commits' | head -1 | cut -d: -f1)"
[ -n "$ws" ] && [ -n "$bs" ] && [ "$ws" -lt "$bs" ] && pass || fail "SKILL.md Start: the wiki step must come before Base commits (wiki=$ws base=$bs)"
# verifier does not report baseline lines as the task's findings; the brief carries the baseline
VER="$PLUGIN/agents/verifier.md"
grep 'wiki-check:' "$VER" | grep -qF 'baseline' && pass || fail "verifier.md still quotes every wiki-check line as a finding"
grep -qF 'baseline' "$PLUGIN/skills/task/references/brief.md" && pass || fail "brief.md does not pass the Start baseline to verifier"
# wiki.md: the refusal and the Start migration are taught
assert_contains "$WK" 'no page has a type'
# wiki.md: only ## headings must be unique
grep -qiE 'all headings|every heading|(^|[^#`] )Headings are unique' "$WK" && fail "wiki.md says all headings are unique; only ## headings are" || pass
grep -qE '`##` headings are unique|## headings are unique' "$WK" && pass || fail "wiki.md does not say the ## headings are unique"
# adopt.md: a wiki-migrate failure stops adopt with nothing changed (it is not only a warning)
grep -q 'wiki-migrate' "$ADO" && pass || fail "adopt.md never names wiki-migrate"
grep -E 'wiki-migrate' "$ADO" | grep -qiE 'a failure is a `warning:` line\)?;?$' && fail "adopt.md claims a wiki-migrate failure is only a warning" || pass
grep -E 'wiki-migrate' "$ADO" | grep -qiE 'failure stops adopt with nothing changed' && pass || fail "adopt.md does not say adopt stops with nothing changed when wiki-migrate fails"
# no plugin file points at the private spec path
if grep -rlF 'md-structure-design' "$PLUGIN" >/dev/null 2>&1; then
  for f in $(grep -rlF 'md-structure-design' "$PLUGIN"); do fail "$f names the private spec path md-structure-design"; done
else pass; fi
# R3-34: every wiki-check run of the chain checks the files: paths against the code root (--code):
# the Start baseline, release, engineer and verifier; the brief hands the code root to both agents.
printf '%s\n' "$st" | grep -qF 'wiki-check.sh" "<Core>/<project>" --code "<code root>"' && pass || fail "SKILL.md Start: the baseline wiki-check lacks --code \"<code root>\""
for f in "$REL" "$ENG" "$VER" "$WK"; do
  grep 'wiki-check' "$f" | grep -qF -- '--code' && pass || fail "$(basename "$f"): no wiki-check line names --code"
done
grep -qF 'wiki-check.sh <project_dir> [--code <dir>] [--changed <path>...]' "$WK" && pass || fail "wiki.md usage line lacks --code"
b5="$(awk '/^5\. \*\*Plugin paths\*\*/ {f=1} /^6\. / {f=0} f' "$PLUGIN/skills/task/references/brief.md")"
printf '%s\n' "$b5" | grep -qF 'code root' && pass || fail "brief.md item 5 does not give the code root"
# all six agents call INDEX.md the generated map
for f in "$PLUGIN"/agents/*.md; do
  grep -F 'docs/INDEX.md' "$f" | grep -qi 'generated' && pass || fail "$(basename "$f") does not call docs/INDEX.md the generated map"
done

# 9. wiki.md's command that lists the changed pages prints them in a form wiki-check --changed reads as pages:
# run as written (only <Core> and <project> filled in) in a Core whose path holds a space, & and |, its lines
# and the changed code file give no drift line. One page is edited (git diff lists it), one is new (ls-files).
new_sandbox
TC="$SANDBOX/My & Co/Core|x"; TP=proj; TCODE="$SANDBOX/code dir"
mkdir -p "$TC/$TP/docs/features" "$TCODE/src"; : > "$TCODE/src/a.c"
wpage() { printf -- '---\ntype: feature\nstatus: active\ndescription: %s\nfiles: [src/a.c]\nrelated: []\nupdated: 2026-11-0%s\n---\n\n## Notes\n\n%s\n' "$2" "$3" "$4" > "$TC/$TP/docs/features/$1.md"; }
wpage login "the login page" 1 "First text."
bash "$SCRIPTS/wiki-index.sh" "$TC/$TP" >/dev/null
git init -q "$TC" && git -C "$TC" add -A && git -C "$TC" commit -q -m one || fail "could not build the Core fixture"
wpage login "the login page" 2 "Text after the code change."
wpage signup "the sign-up page" 2 "A new page."
bash "$SCRIPTS/wiki-index.sh" "$TC/$TP" >/dev/null
cmd="$(grep -o '`{ git -C [^`]*`' "$WK" | tr -d '`')"
assert_eq "$(printf '%s\n' "$cmd" | grep -c .)" "1" "wiki.md holds one command that lists the changed pages"
# shellcheck disable=SC2016  # the variable names are put into the command text; eval expands them
cmd="$(printf '%s\n' "$cmd" | sed -e 's/<Core>/"$TC"/g' -e 's/<project>/"$TP"/g')"
listed="$(eval "$cmd" 2>&1)"
printf '%s\n' "$listed" | grep -q 'features/login\.md$' && pass || fail "the command does not list the edited page: $listed"
printf '%s\n' "$listed" | grep -q 'features/signup\.md$' && pass || fail "the command does not list the new page: $listed"
set --; while IFS= read -r l; do [ -z "$l" ] || set -- "$@" "$l"; done <<EOF
$listed
EOF
assert_exit 0 bash "$CHECK" "$TC/$TP" --code "$TCODE" --changed "$@" src/a.c
assert_eq "$OUT" "" "the listed pages are read as changed pages: no drift"
# the fixture is live: without the page paths both pages drift
assert_exit 1 bash "$CHECK" "$TC/$TP" --code "$TCODE" --changed src/a.c
assert_eq "$OUT" "wiki-check: features/login.md: drift: src/a.c changed, page not updated
wiki-check: features/signup.md: drift: src/a.c changed, page not updated" "without the pages: drift"
assert_contains "$WK" 'or `docs/<page>.md`'

finish
