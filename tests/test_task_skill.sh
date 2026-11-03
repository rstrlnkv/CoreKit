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
assert_contains "$SK" 'only those files through `save`'
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

finish
