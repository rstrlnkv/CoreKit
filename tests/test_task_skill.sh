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

# No superpowers dependency anywhere under skills/task/
if grep -rF "superpowers:" "$T" >/dev/null 2>&1; then fail "superpowers: referenced under skills/task/"; else pass; fi

finish
