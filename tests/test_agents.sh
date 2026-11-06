#!/usr/bin/env bash
# The six corecrew agents (spec section 13): frontmatter, sections, tools, reply format, wording.
source "$(dirname "$0")/lib.sh"
AG="$PLUGIN/agents"
ROLES="engineer tester security verifier localizer designer"
READONLY="security verifier localizer designer"

section() { awk -v n="$2" '$0 == "## " n {f=1; next} /^## /{f=0} f' "$1"; }
sec_has() { section "$1" "$2" | grep -qF -- "$3" && pass || fail "$(basename "$1") section '$2' lacks: $3"; }
has() { grep -qiF -- "$2" "$1" && pass || fail "$(basename "$1") lacks: $2"; }
# front <file>: the lines between the first two '---' lines.
front() { awk '/^---$/ {n++; next} n==1' "$1"; }

# Exactly six agent files, one per role.
n="$(ls "$AG"/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$n" "6" "number of agents/*.md files"
for r in $ROLES; do
  f="$AG/$r.md"
  assert_file "$f"
  [ -f "$f" ] || continue
  # size
  [ "$(wc -l < "$f")" -le 60 ] && pass || fail "$r.md is over 60 lines"
  # frontmatter: opens on line 1, exactly these keys in this order, nothing else
  [ "$(sed -n 1p "$f")" = "---" ] && pass || fail "$r.md does not open with ---"
  keys="$(front "$f" | sed -n 's/^\([A-Za-z]*\):.*/\1/p' | tr '\n' ' ')"
  assert_eq "$keys" "name description model tools disallowedTools maxTurns " "$r.md frontmatter keys"
  [ "$(front "$f" | wc -l | tr -d ' ')" = "6" ] && pass || fail "$r.md frontmatter is not six one-line keys"
  assert_eq "$(front "$f" | sed -n 's/^name: //p')" "$r" "$r.md name"
  d="$(front "$f" | sed -n 's/^description: //p')"
  # the description is listed to the main model in every session, project or not: short, and it says who calls the agent
  [ -n "$d" ] && [ "${#d}" -le 120 ] && pass || fail "$r.md description missing or over 120 chars (${#d})"
  case "$d" in *"/corecrew:task"*) pass ;; *) fail "$r.md description does not say /corecrew:task calls it" ;; esac
  case "$d" in *": "*|*" #"*) fail "$r.md description has ': ' or ' #' (breaks a plain YAML scalar)";; *) pass;; esac
  assert_eq "$(front "$f" | sed -n 's/^model: //p')" "sonnet" "$r.md model"
  assert_eq "$(front "$f" | sed -n 's/^disallowedTools: //p')" "Agent" "$r.md disallowedTools"
  assert_eq "$(front "$f" | sed -n 's/^maxTurns: //p')" "60" "$r.md maxTurns"
  # tools per spec 13.2
  want="Read, Grep, Glob, Bash"
  case "$r" in engineer|tester) want="Read, Edit, Write, Grep, Glob, Bash";; esac
  assert_eq "$(front "$f" | sed -n 's/^tools: //p')" "$want" "$r.md tools"
  # the six sections, in order, nothing else at level 2
  secs="$(grep '^## ' "$f" | tr '\n' '|')"
  assert_eq "$secs" "## Question|## What to show|## What to read first|## How you work|## What not to do|## Reply format|" "$r.md sections"
  # reading order (spec 13.1)
  sec_has "$f" "What to read first" 'CLAUDE.md'
  sec_has "$f" "What to read first" 'docs/INDEX.md'
  sec_has "$f" "What to read first" 'applies-to'
  sec_has "$f" "What to read first" "docs/knowledge/$r.md"
  sec_has "$f" "What to read first" "<Core>/knowledge/$r.md"
  sec_has "$f" "What to read first" 'no knowledge'
  rd="$(section "$f" "What to read first")"
  a="$(printf '%s\n' "$rd" | grep -n 'CLAUDE.md' | head -1 | cut -d: -f1)"
  b="$(printf '%s\n' "$rd" | grep -n 'docs/INDEX.md' | head -1 | cut -d: -f1)"
  p="$(printf '%s\n' "$rd" | grep -n 'wiki page' | head -1 | cut -d: -f1)"
  c="$(printf '%s\n' "$rd" | grep -n 'applies-to' | head -1 | cut -d: -f1)"
  k="$(printf '%s\n' "$rd" | grep -n "docs/knowledge/$r.md" | head -1 | cut -d: -f1)"
  kc="$(printf '%s\n' "$rd" | grep -n "<Core>/knowledge/$r.md" | head -1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$p" ] && [ -n "$c" ] && [ -n "$k" ] && [ -n "$kc" ] \
    && [ "$a" -lt "$b" ] && [ "$b" -lt "$p" ] && [ "$p" -lt "$c" ] && [ "$c" -lt "$k" ] && [ "$k" -le "$kc" ] \
    && printf "%s\n" "$rd" | awk -v a="docs/knowledge/$r.md" -v b="<Core>/knowledge/$r.md" '{s = s $0 "\n"} END {i = index(s, a); j = index(s, b); exit !(i > 0 && j > 0 && i < j)}' \
    && pass || fail "$r.md reading order is not CLAUDE.md, INDEX, page, standards, project knowledge, Core knowledge"
  # knowledge of another stack is skipped; a one-stack line is tagged (spec 12.3)
  sec_has "$f" "What to read first" 'skip lines tagged `[<stack>]` for another stack'
  sec_has "$f" "How you work" 'Tag a Knowledge line `[<stack>]` when it holds for one stack only'
  # reply format ends with the two lines, in this order
  last2="$(section "$f" "Reply format" | grep -v '^```' | awk 'NF' | tail -2)"
  assert_eq "$(printf '%s\n' "$last2" | sed -n 1p)" 'Standards: <name — the rule applied, quoted | none needed | none in Core>' "$r.md second-to-last reply line"
  assert_eq "$(printf '%s\n' "$last2" | sed -n 2p)" 'Knowledge line: <symptom → cause → guard | none>' "$r.md last reply line"
  sec_has "$f" "Reply format" 'Open:'
  # shared practice, language, budget, brief is the task
  sec_has "$f" "How you work" 'foreground'
  sec_has "$f" "How you work" 'retried, never polled'
  sec_has "$f" "How you work" 'by range'
  sec_has "$f" "How you work" 'one Bash call'
  sec_has "$f" "How you work" "user's language"
  sec_has "$f" "How you work" 'keep the reply labels in English'
  sec_has "$f" "How you work" 'write files in English'
  sec_has "$f" "How you work" 'By about turn 50'
  sec_has "$f" "How you work" 'what is done and what is left'
  sec_has "$f" "How you work" 'hard limit is 60 and gives no reply'
  sec_has "$f" "What not to do" 'brief'
  sec_has "$f" "What not to do" 'Open'
  sec_has "$f" "What not to do" 'path: question'
  sec_has "$f" "What not to do" 'change no files'
  sec_has "$f" "What not to do" '`file:line`'
  # forbidden strings (home paths and archive project names: tests/test_no_personal.sh scans all)
  for s in '.claude/crew' 'CoreCrew' 'superpowers' '${CLAUDE_'; do
    grep -qF -- "$s" "$f" && fail "$r.md contains: $s" || pass
  done
  # no plugin-relative path (wiki pages are passed as absolute <Core>/<project>/docs/<page>.md)
  grep -qF -- '../' "$f" && fail "$r.md contains a ../ path" || pass
done

# Read-only roles: no Edit/Write, say so, and have a "nothing found" form.
for r in $READONLY; do
  f="$AG/$r.md"; [ -f "$f" ] || continue
  tl="$(front "$f" | sed -n 's/^tools: //p')"
  case "$tl" in *Edit*|*Write*) fail "$r.md tools include Edit or Write";; *) pass;; esac
  has "$f" 'never edit project files'
  has "$f" 'logs to a file are fine'
  has "$f" 'for engineer'
  sec_has "$f" "Reply format" 'nothing found'
done
sec_has "$AG/security.md" "Reply format" 'Not checked'
sec_has "$AG/verifier.md" "Reply format" 'Not resolved'
sec_has "$AG/localizer.md" "Reply format" 'Not confirmed'
sec_has "$AG/designer.md" "Reply format" 'Not measured'

# Role specifics the spec pins (section 13.2, 8.2, 9.3).
E="$AG/engineer.md"
has "$E" 'only author of changes'
has "$E" 'wiki'
has "$E" 'git diff --name-only'
has "$E" 'git ls-files --others --exclude-standard'
has "$E" '<Core>/<project>/docs/<page>.md'
grep -qF -- '../docs/<page>.md' "$E" && fail "engineer.md passes pages as ../docs/<page>.md" || pass
has "$E" 'where the checker pointed'
has "$E" 'same check the checker ran'
has "$E" 'files:'
has "$E" 'red test first'
has "$E" 'command and its output'
has "$E" 'never commit'
has "$E" 'save'
has "$E" 'never weaken'
sec_has "$E" "Reply format" 'Screens:'
T="$AG/tester.md"
has "$T" 'only checks'
has "$T" 'red first'
has "$T" 'mutations'
has "$T" 'reverted'
has "$T" 'hollow'
has "$T" 'nobody fed'
has "$T" 'touched modules'
has "$T" 'final full'
S="$AG/security.md"
has "$S" 'dangerous operations'
has "$S" 'input → effect'
V="$AG/verifier.md"
has "$V" 'address'
has "$V" 'number'
has "$V" 'quotation'
has "$V" 'conditional'
has "$V" 'wiki-check.sh'
has "$V" '--changed'
has "$V" 'git diff --name-only'
has "$V" 'git ls-files --others --exclude-standard'
has "$V" '<Core>/<project>/docs/<page>.md'
grep -qF -- '../docs/<page>.md' "$V" && fail "verifier.md passes pages as ../docs/<page>.md" || pass
has "$V" '`Knowledge line:` proposals in the reports'
has "$V" 'the brief gives'
has "$V" 'dead'
L="$AG/localizer.md"
has "$L" 'built artifact'
has "$L" 'key by key'
has "$L" 'language by language'
D="$AG/designer.md"
has "$D" 'measure'
has "$D" 'contrast'
has "$D" 'hit area'
has "$D" 'states'
has "$D" 'at most 6 images'
has "$D" 'Screens'

# 0.7 wiki: the engineer runs the generator, not a hand-written INDEX line (more in test_wiki_texts.sh)
has "$AG/engineer.md" 'wiki-index.sh'
assert_not_contains "$AG/engineer.md" 'INDEX.md` line'
finish
