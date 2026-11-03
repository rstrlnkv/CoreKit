#!/usr/bin/env bash
# The task skill: frontmatter, paths, brief, report, flags.
source "$(dirname "$0")/lib.sh"
T="$ROOT/skills/task"
SK="$T/SKILL.md"
PA="$T/references/paths.md"
BR="$T/references/brief.md"
RP="$T/references/report.md"

# section <file> <name>: the body of "## <name>" up to the next "## " heading.
section() { awk -v n="$2" '$0 == "## " n {f=1; next} /^## /{f=0} f' "$1"; }
sec_has() { section "$1" "$2" | grep -qF -- "$3" && pass || fail "$1 section '$2' lacks: $3"; }

# SKILL.md frontmatter
assert_file "$SK"
assert_contains "$SK" "name: task"
assert_contains "$SK" "disable-model-invocation: true"
assert_contains "$SK" 'argument-hint: "<task> | release <version> | adopt <folder>"'
desc="$(sed -n 's/^description: //p' "$SK" | head -1)"
[ -n "$desc" ] && [ "${#desc}" -le 200 ] && pass || fail "description missing or over 200 chars (${#desc})"
[ "$(wc -l < "$SK")" -lt 500 ] && pass || fail "SKILL.md is 500 lines or more"

# SKILL.md body
for w in 'maxTurns' 'three engineer passes' 'foreground' 'this project / all projects' \
         'feature-dev:code-architect' 'feature-dev:code-explorer' \
         '/plugin install feature-dev@claude-plugins-official' \
         'new-standard' 'without `Standards:`' 'once' \
         '${user_config.core_dir}' '${user_config.attribution}' '${user_config.model_profile}' \
         'lib.sh" ready' 'lib.sh" core-dir' 'setup-core.sh' \
         'references/paths.md' 'references/brief.md' 'references/report.md' \
         'reference/wiki.md' 'reference/knowledge.md' 'wiki-check.sh' \
         'coredev:engineer' 'coredev:tester' 'coredev:security' 'coredev:verifier' \
         'coredev:localizer' 'coredev:designer' \
         'economy' 'balanced' 'strong' 'haiku' 'opus' \
         '/coredev:new-project' '/coredev:task adopt <folder>' 'check: <set after scaffolding>'; do
  assert_contains "$SK" "$w"
done

# paths.md: one section per path, plus the checkers' wave
assert_file "$PA"
for p in fix full question batch release adopt; do
  [ -n "$(section "$PA" "$p")" ] && pass || fail "paths.md lacks section '## $p'"
done
[ -n "$(section "$PA" "checkers' wave")" ] && pass || fail "paths.md lacks section '## checkers' wave'"
sec_has "$PA" fix "red"
sec_has "$PA" fix "mutations"
sec_has "$PA" full "3–5"
sec_has "$PA" full "5 tasks"
sec_has "$PA" full "3 modules"
sec_has "$PA" release 'references/release.md'
sec_has "$PA" adopt 'references/adopt.md'
assert_contains "$PA" 'check: <set after scaffolding>'
assert_not_contains "$PA" "superpowers:"

# brief.md: the exact opening sentence
assert_file "$BR"
assert_contains "$BR" 'This brief comes from coredev:task, path: <path>, project: <name>, core: <Core>, and IS your task.'

# report.md: nine labels in order
assert_file "$RP"
prev=0
for l in 'Path:' 'Chain:' 'Done:' 'Proof:' 'Standards:' 'Open:' 'Knowledge:' 'Cost:' 'Commit:'; do
  n="$(grep -nF -- "$l" "$RP" | head -1 | cut -d: -f1)"
  if [ -n "$n" ] && [ "$n" -gt "$prev" ]; then pass; else fail "report.md label '$l' missing or out of order"; fi
  prev="${n:-$prev}"
done

# Fix round 1: pin the specific sentences, not only words.
rule() { grep -qE -- "$2" "$SK" && pass || fail "SKILL.md rule missing: $1"; }
rule "foreground rule" '^5\. Dispatch in the foreground'
rule "maxTurns rule" '^3\. Budget: each agent has `maxTurns: 60`'
rule "three passes rule" '^4\. At most three engineer passes per chain'
rule "Standards once rule" '^9\. A reply without `Standards:` .*goes back once'
rule "subagent_type for feature-dev" '`coredev:<role>` for coredev roles, the full name for'
rule "no model for feature-dev" 'Do not pass `model` to feature-dev agents'
assert_contains "$SK" 'applies-to'
assert_not_contains "$SK" 'docs/specs/'
assert_contains "$SK" 'first path component'
assert_contains "$SK" 'worktrees/<w>'
assert_contains "$SK" 'If the user declines'
c="$(grep -n 'lib.sh" core-dir' "$SK" | head -1 | cut -d: -f1)"; r="$(grep -n 'lib.sh" ready' "$SK" | head -1 | cut -d: -f1)"
[ -n "$c" ] && [ -n "$r" ] && [ "$c" -lt "$r" ] && pass || fail "core-dir must come before ready in Start"
# Unset check: both files agree on when to ask and where it is written.
for f in "$SK" "$PA"; do
  assert_contains "$f" 'before the first tester call'
  assert_contains "$f" 'into the `check:` line'
done
# Release path runs release.md in full; postcondition 4 applies.
sec_has "$PA" release 'in full'
sec_has "$PA" release 'postcondition 4'
section "$PA" release | grep -qF 'from the version step' && fail "release section still skips postconditions" || pass
# Question path and knowledge: accepted lines are committed through save.
sec_has "$PA" question 'save'
sec_has "$PA" question 'Commit: none — no files changed'
section "$PA" question | grep -qF 'No release, no commit' && fail "question section contradicts SKILL.md" || pass
sec_has "$PA" question 'accepted'
assert_contains "$SK" 'was clean at Start'
assert_contains "$SK" '`save` commits only the chain'"'"'s files'
assert_contains "$RP" 'none — no files changed'
# full and batch point at the wave; the large-plan stop runs the first task whole.
sec_has "$PA" full "checkers' wave"
section "$PA" full | grep -qF 'one repair pass' && fail "full duplicates the wave repair" || pass
sec_has "$PA" full 'whole chain'
sec_has "$PA" batch "checkers' wave"
sec_has "$PA" batch 'grep'
# fix: a red test before, green after.
sec_has "$PA" fix 'show it red'
sec_has "$PA" fix 'green after the fix'
# brief.md: the opening sentence is the first instruction.
first="$(section "$BR" 'Opening sentence' | awk 'NF{print; exit}')"
assert_eq "$first" '`This brief comes from coredev:task, path: <path>, project: <name>, core: <Core>, and IS your task.`' "brief opening is first"

# No superpowers dependency anywhere under skills/task/
if grep -rF "superpowers:" "$T" >/dev/null 2>&1; then fail "superpowers: referenced under skills/task/"; else pass; fi

# release.md: the seven postconditions of spec section 10, in order, with the exact commands.
REL="$T/references/release.md"
assert_file "$REL"
[ "$(wc -l < "$REL")" -le 80 ] && pass || fail "release.md is over 80 lines"
prev=0
for n in 1 2 3 4 5 6 7; do
  l="$(grep -nE "^$n\\. " "$REL" | head -1 | cut -d: -f1)"
  if [ -n "$l" ] && [ "$l" -gt "$prev" ]; then pass; else fail "release.md postcondition $n missing or out of order"; fi
  prev="${l:-$prev}"
done
for w in 'wiki-check.sh' '--changed' '../docs/' 'git diff --name-only' \
         "git log --format=%B <range> | grep -icE 'co-authored-by|generated with'" \
         'attribution=forbid' 'skipped (attribution=allow)' 'the attribution value resolved at Start' \
         'bash "<scripts>/save"' 'never tags' 'never pushes' 'Step-Id' \
         'versioning' 'applies-to' 'ask the user' 'git status --short' \
         'check: <set after scaffolding>' 'git rev-parse HEAD' '<code base>..HEAD' \
         'lib.sh" get schema' 'lib.sh" schema' 'old-schema' 'warning' \
         'command → output → ✓/✗' 'one repair' 'Commit: stopped'; do
  assert_contains "$REL" "$w"
done
# The attribution check is guarded: it runs only with forbid.
grep -E "grep -icE" "$REL" | grep -qF 'forbid' && pass || fail "release.md: attribution check line is not guarded by forbid"
# Question path with accepted lines runs only postconditions 5-7.
assert_contains "$REL" '5–7'
# SKILL.md Start records the base commits; both files agree with release.md.
assert_contains "$SK" 'git rev-parse HEAD'
assert_contains "$SK" 'base commit'
sec_has "$PA" release 'postcondition 4'
section "$PA" release | grep -qF 'wiki-check' && fail "paths.md release duplicates postconditions" || pass
assert_contains "$SK" 'Never tag, never push'

# Fix round 1: scoped Core checks, explicit changed-file lists, no repair after the commit.
assert_contains "$REL" 'git -C <Core> status --short -- <project>'
assert_contains "$REL" 'git -C <Core> log --format=%B <Core base>..HEAD -- <project>'
assert_contains "$REL" "{ git diff --name-only <code base>; git ls-files --others --exclude-standard; }"
assert_contains "$REL" "{ git -C <Core> diff --name-only <Core base> -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }"
assert_contains "$REL" '`<project>/docs/` prefix'
assert_contains "$REL" "git log -1 --format='%h %s'"
assert_contains "$REL" 'final tester'
assert_contains "$REL" '`<version>`'
assert_contains "$REL" 'no repair'
assert_contains "$REL" 'rerun from postcondition 1'
assert_contains "$REL" 'save` failed'
grep -qE 'git status --short$|git status --short`' "$REL" && pass || fail "release.md: code root keeps plain git status --short"
# Start stops on an unclean tree; paths.md release matches the version order.
assert_contains "$SK" 'uncommitted changes'
assert_contains "$SK" 'git status --short'
sec_has "$PA" release 'one engineer call'
sec_has "$PA" release '<version>'
assert_contains "$PA" 'was clean at Start'

# brief.md passes the plugin file paths that engineer and verifier cannot find by themselves.
assert_contains "$BR" 'Plugin paths'
assert_contains "$BR" '(engineer and verifier only)'
assert_contains "$BR" 'reference/wiki.md'
assert_contains "$BR" 'scripts/wiki-check.sh'
# Budget is unconditional: a capped agent returns no report, so it stops early on its own.
assert_contains "$BR" 'You have about 60 turns; by about turn 50 stop and write your reply: what is done, what is left.'
assert_not_contains "$BR" 'only if'
# A capped agent gets one SendMessage asking for its report; then the chain stops.
assert_contains "$SK" 'Report now: what is done, what is left; no more tool calls.'
assert_contains "$SK" 'SendMessage'
assert_contains "$SK" 'with no report'
assert_contains "$SK" 'same pass'
assert_contains "$SK" 'stop the chain and put it in `Open`'
rule "turn-limit note rule" 'turn-limit note'

# attribution=forbid: save drops attribution lines; agents are never sent to the background
assert_contains "$T/references/release.md" '--no-attribution'
assert_contains "$SK" 'run_in_background: false'

# Reference files are opened with Read, which substitutes nothing: no ${...} placeholders there.
# Start notes the resolved values once (plugin folder, attribution, model profile).
for f in "$T"/references/*.md; do
  if grep -qF '${' "$f"; then fail "$(basename "$f") holds a \${...} placeholder: $(grep -nF '${' "$f" | head -2 | tr '\n' ' ')"; else pass; fi
done
sec_has "$SK" Start 'cd "${CLAUDE_SKILL_DIR}/../.." && pwd'
sec_has "$SK" Start '`<scripts>` is `<plugin>/scripts`'
sec_has "$SK" Start 'opened with Read'
sec_has "$SK" Start 'attribution: `${user_config.attribution}`'
sec_has "$SK" Start 'model profile: `${user_config.model_profile}`'
assert_contains "$REL" '<scripts>/save'
assert_contains "$REL" '<scripts>/wiki-check.sh'
assert_contains "$T/references/adopt.md" '<scripts>/adopt.sh'
assert_contains "$BR" '<plugin>/reference/wiki.md'
finish
