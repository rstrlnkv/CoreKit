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
for v in brief architecture decision feature spec plan glossary draft active done superseded; do assert_contains "$WK" "$v"; done
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
assert_contains "$REL" '"migrate at Start"'
assert_contains "$REL" 'baseline'
assert_contains "$REL" 'pre-existing problem'
assert_contains "$REL" 'Only new lines are ✗'
grep -qiE '0\.6' "$REL" && pass || fail "release.md does not name the 0.6 format"
# SKILL.md Start: dry run, the owner's ok, its own save step, and the wiki-check baseline
SK="$PLUGIN/skills/task/SKILL.md"
st="$(awk '$0 == "## Start" {f=1; next} /^## /{f=0} f' "$SK")"
for w in 'wiki-index.sh" "<Core>/<project>" --check' 'no page has a type' \
         '<plugin>/reference/older-formats.md' 'Without that "ok", stop the chain' \
         'wiki-check.sh" "<Core>/<project>"' '**baseline**'; do
  printf '%s\n' "$st" | grep -qF -- "$w" && pass || fail "SKILL.md Start lacks: $w"
done
# the migration itself (dry run, the user's ok, its own save step) lives in the Older formats reference
OF="$PLUGIN/reference/older-formats.md"
ofw="$(awk '$0 == "## Wiki without types" {f=1; next} /^## /{f=0} f' "$OF")"
for w in 'wiki-migrate.sh" "<Core>/<project>" --dry-run' 'show its output to the user' \
         'wiki: migrate to the 0.7 format' '--no-attribution' 'Without that "ok", stop the chain'; do
  printf '%s\n' "$ofw" | grep -qF -- "$w" && pass || fail "older-formats.md, Wiki without types, lacks: $w"
done
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
# adopt.md: a wiki-migrate failure is not only a warning in the new layout
grep -q 'wiki-migrate' "$ADO" && pass || fail "adopt.md never names wiki-migrate"
grep -E 'wiki-migrate' "$ADO" | grep -qiE 'a failure is a `warning:` line\)?;?$' && fail "adopt.md claims a wiki-migrate failure is only a warning" || pass
grep -qiE 'new layout[^.]*(stops|nothing (is )?changed)|(stops|nothing (is )?changed)[^.]*new layout' "$ADO" && pass || fail "adopt.md does not say adopt stops with nothing changed when wiki-migrate fails in the new layout"
grep -qiE 'old layout[^.]*warning|warning[^.]*old layout' "$ADO" && pass || fail "adopt.md does not say a failure is a warning in the old layout"
# no plugin file points at the private spec path
if grep -rlF 'md-structure-design' "$PLUGIN" >/dev/null 2>&1; then
  for f in $(grep -rlF 'md-structure-design' "$PLUGIN"); do fail "$f names the private spec path md-structure-design"; done
else pass; fi
# all six agents call INDEX.md the generated map
for f in "$PLUGIN"/agents/*.md; do
  grep -F 'docs/INDEX.md' "$f" | grep -qi 'generated' && pass || fail "$(basename "$f") does not call docs/INDEX.md the generated map"
done

finish
