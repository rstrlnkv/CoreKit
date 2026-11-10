#!/usr/bin/env bash
# The task skill: frontmatter, paths, brief, report, flags.
source "$(dirname "$0")/lib.sh"
new_sandbox
T="$PLUGIN/skills/task"
SK="$T/SKILL.md"
PA="$T/references/paths.md"
BR="$T/references/brief.md"
RP="$T/references/report.md"


# SKILL.md frontmatter
assert_file "$SK"
assert_contains "$SK" "name: task"
assert_contains "$SK" "disable-model-invocation: true"
assert_contains "$SK" 'argument-hint: "<task> | release <version> | adopt <folder>"'
desc="$(sed -n 's/^description: //p' "$SK" | head -1)"
[ -n "$desc" ] && [ "${#desc}" -le 200 ] && pass || fail "description missing or over 200 chars (${#desc})"

# SKILL.md body
for w in 'maxTurns' 'three engineer passes' 'foreground' \
         'feature-dev:code-architect' 'feature-dev:code-explorer' \
         '/plugin install feature-dev@claude-plugins-official' \
         'new-standard' 'without `Standards:`' 'once' \
         '${user_config.core_dir}' '${user_config.attribution}' '${user_config.model_profile}' \
         'lib.sh" ready' 'lib.sh" core-dir' 'setup-core.sh' \
         'references/paths.md' 'references/brief.md' 'references/report.md' \
         'reference/wiki.md' 'reference/knowledge.md' 'wiki-check.sh' \
         'corecrew:engineer' 'corecrew:tester' 'corecrew:security' 'corecrew:verifier' \
         'corecrew:localizer' 'corecrew:designer' \
         'economy' 'balanced' 'strong' 'haiku' 'opus' \
         '/corecrew:new-project' '/corecrew:task adopt <folder>' 'check: <set after scaffolding>'; do
  assert_contains "$SK" "$w"
done

# paths.md: one section per path, plus the checkers' wave
assert_file "$PA"
for p in fix full question batch release adopt; do
  [ -n "$(md_section "$PA" "$p")" ] && pass || fail "paths.md lacks section '## $p'"
done
[ -n "$(md_section "$PA" "checkers' wave")" ] && pass || fail "paths.md lacks section '## checkers' wave'"
md_section_has "$PA" fix "red"
md_section_has "$PA" fix "mutations"
md_section_has "$PA" full "3–5"
md_section_has "$PA" full "5 tasks"
md_section_has "$PA" full "3 modules"
md_section_has "$PA" release 'references/release.md'
md_section_has "$PA" adopt 'references/adopt.md'
assert_contains "$PA" 'check: <set after scaffolding>'
assert_not_contains "$PA" "superpowers:"

# brief.md: the exact opening sentence
assert_file "$BR"
assert_contains "$BR" 'This brief comes from corecrew:task, path: <path>, project: <name>, core: <Core>, and IS your task.'

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
rule "subagent_type for feature-dev" '`corecrew:<role>` for corecrew roles, the full name for'
rule "no model for the architect and explorer" 'Do not pass `model` to the architect and explorer agents'
# feature-dev is optional: the built-in Plan and Explore agents with the shared role text stand in, nothing stops
md_section_has "$SK" Start '`Plan`'
md_section_has "$SK" Start '`Explore`'
md_section_has "$SK" Start 'references/architect-explorer.md'
for f in "$SK" "$PA"; do grep -qiE 'stop[^.]*until it is installed|Without feature-dev stop' "$f" && fail "$f still stops without feature-dev" || pass; done
assert_contains "$SK" 'applies-to'
assert_not_contains "$SK" 'docs/specs/'
assert_contains "$SK" 'lib.sh" code-root "$PWD"'
assert_contains "$SK" 'prepare.sh'
assert_contains "$SK" 'If the user declines'
c="$(grep -n 'lib.sh" core-dir' "$SK" | head -1 | cut -d: -f1)"; r="$(grep -n 'lib.sh" ready' "$SK" | head -1 | cut -d: -f1)"
[ -n "$c" ] && [ -n "$r" ] && [ "$c" -lt "$r" ] && pass || fail "core-dir must come before ready in Start"
# Each task-skill rule is stated once (Decision 11): count it over the task folder plus codex-host.md,
# and check that the other places point at the one that states it.
once() {
  n="$(cat "$SK" "$T"/references/*.md "$PLUGIN/reference/codex-host.md" | grep -ciF -- "$1")"
  assert_eq "$n" 1 "stated once in the task skill and codex-host.md: $1"
}
# block <file> <first-line ERE> <next-line ERE>: the lines from the first match up to the next one.
block() { awk -v a="$2" -v b="$3" '$0 ~ b {f=0} $0 ~ a {f=1} f' "$1"; }
# The unset check: line is asked about once; paths.md (the preamble) says when and where it is written.
once 'before the first tester call'
awk '/^## /{exit} 1' "$PA" | grep -qF 'before the first tester call' && pass || fail "paths.md preamble lacks the unset check: rule"
awk '/^## /{exit} 1' "$PA" | grep -qF 'into the `check:` line' && pass || fail "paths.md preamble lacks where the check: line is written"
block "$SK" '^4[.] [*][*]Read' '^5[.] ' | grep -qF 'paths.md' && pass || fail "SKILL.md Start, Read does not point at paths.md for the unset check:"
# Release path runs release.md in full; postcondition 4 applies.
md_section_has "$PA" release 'in full'
md_section_has "$PA" release 'postcondition 4'
md_section "$PA" release | grep -qF 'from the version step' && fail "release section still skips postconditions" || pass
# Question path and knowledge: the rule lives in SKILL.md Knowledge; paths.md points at it.
once 'the tree was clean at Start, so `save` commits only the chain'
md_section_has "$SK" Knowledge 'was clean at Start'
md_section_has "$SK" Knowledge '`save` commits only the chain'"'"'s files'
md_section_has "$PA" question 'SKILL.md, section Knowledge'
md_section "$PA" question | grep -qF 'No release, no commit' && fail "question section contradicts SKILL.md" || pass
# The Codex commit stop lives in codex-host.md, Approval outside the sandbox; codex.md points at it.
once 'Codex sandbox keeps .git read-only'
once 'only the commit stops'
md_section "$PLUGIN/reference/codex-host.md" 'Approval outside the sandbox' | grep -qiF 'only the commit stops' && pass ||
  fail "codex-host.md Approval lacks: only the commit stops"
md_section_has "$T/references/codex.md" 'Commit in Codex' 'section Approval outside the sandbox'
assert_contains "$RP" 'none — no files changed'
# full and batch point at the wave; the large-plan stop runs the first task whole.
md_section_has "$PA" full "checkers' wave"
md_section "$PA" full | grep -qF 'one repair pass' && fail "full duplicates the wave repair" || pass
md_section_has "$PA" full 'whole chain'
md_section_has "$PA" batch "checkers' wave"
md_section_has "$PA" batch 'grep'
# fix: a red test before, green after.
md_section_has "$PA" fix 'show it red'
md_section_has "$PA" fix 'green after the fix'
# brief.md: the opening sentence is the first instruction.
first="$(md_section "$BR" 'Opening sentence' | awk 'NF{print; exit}')"
assert_eq "$first" '`This brief comes from corecrew:task, path: <path>, project: <name>, core: <Core>, and IS your task.`' "brief opening is first"
# REV-16: the brief never retells session-rules.md either; the engineer reads it
md_section_has "$BR" Never 'session-rules.md'
# REV-5: task no longer asks the level; knowledge.md gives it (one source), and the standard offer stays
md_section "$SK" Knowledge | grep -qF 'this project / all projects' && fail "SKILL.md still asks the knowledge level" || pass
md_section_has "$SK" Knowledge 'reference/knowledge.md'
md_section_has "$SK" Knowledge '/corecrew:new-standard'
md_section_has "$SK" Knowledge 'ok / no'

# No superpowers dependency anywhere under skills/task/
if grep -rF "superpowers:" "$T" >/dev/null 2>&1; then fail "superpowers: referenced under skills/task/"; else pass; fi

# release.md: the seven release postconditions, in order, with the exact commands.
REL="$T/references/release.md"
assert_file "$REL"
prev=0
for n in 1 2 3 4 5 6 7; do
  l="$(grep -nE "^$n\\. " "$REL" | head -1 | cut -d: -f1)"
  if [ -n "$l" ] && [ "$l" -gt "$prev" ]; then pass; else fail "release.md postcondition $n missing or out of order"; fi
  prev="${l:-$prev}"
done
for w in 'wiki-check.sh' '--changed' '<Core>/<project>/docs/<page>.md' 'git diff --name-only' \
         "git log --format=%B <range> | grep -icE '^[[:space:]]*(co-authored-by:|(🤖[[:space:]]*)?generated with)'" \
         'attribution=forbid' 'skipped (attribution=allow)' 'the attribution value resolved at Start' \
         'bash "<scripts>/save"' 'never tags' 'never pushes' 'Step-Id' '72 characters' 'commit standard' \
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
block "$REL" '^1[.] [*][*]Tests' '^2[.] ' | grep -qF 'paths.md' && pass || fail "release.md postcondition 1 does not point at paths.md for the unset check:"
# SKILL.md Start records the base commits; both files agree with release.md.
assert_contains "$SK" 'git rev-parse HEAD'
assert_contains "$SK" 'base commit'
md_section_has "$PA" release 'postcondition 4'
md_section "$PA" release | grep -qF 'wiki-check' && fail "paths.md release duplicates postconditions" || pass
assert_contains "$SK" 'Never tag, never push'

# Fix round 1: scoped Core checks, explicit changed-file lists, no repair after the commit.
assert_contains "$REL" 'git -C "<Core>" status --short -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)'
assert_contains "$REL" 'git -C "<Core>" log --format=%B <Core base>..HEAD -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)'
assert_contains "$REL" "{ git diff --name-only <code base>; git ls-files --others --exclude-standard; }"
assert_contains "$REL" "{ git -C <Core> diff --name-only <Core base> -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }"
assert_contains "$REL" 'prefix each path with'
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
md_section_has "$PA" release 'one engineer call'
md_section_has "$PA" release '<version>'

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
md_section_has "$SK" Paths 'lib.sh" plugin-root'
md_section_has "$SK" Paths '`<scripts>` is `<plugin>/scripts`'
md_section_has "$SK" Start 'opened with Read'
md_section_has "$SK" Start 'bash "<scripts>/lib.sh" settings attribution='"'"'${user_config.attribution}'"'"' model_profile='"'"'${user_config.model_profile}'"'"
assert_contains "$REL" '<scripts>/save'
assert_contains "$REL" '<scripts>/wiki-check.sh'
assert_contains "$T/references/adopt.md" '<scripts>/adopt.sh'
assert_contains "$BR" '<plugin>/reference/wiki.md'

# New layout: the code lives beside the Core
md_section_has "$SK" Start 'lib.sh" project-of'
md_section_has "$SK" Start '<Projects>/<Name>'
md_section_has "$SK" Start 'old layout'
md_section_has "$SK" Start 'lib.sh" layout'
md_section_has "$SK" Start 'lib.sh" code-dir'
# a non-zero exit of layout / code-dir: no code folder (exit 1) or a case clash (exit 3)
md_section_has "$SK" Start 'exit 1 from `layout` or `code-dir`'
md_section_has "$SK" Start 'the code is not cloned'
md_section_has "$SK" Start '`<Projects>/<Name>`'
md_section_has "$SK" Start 'exit 3'
md_section_has "$SK" Start 'two folders differ only in case'
md_section_has "$SK" Start 'the output of'
md_section "$SK" Start | grep -qF 'the printed' && fail "Start step 2 still says 'the printed'" || pass
md_section "$SK" Start | grep -qF 'must be inside `<Core>/<project>/`' && fail "Start step 2 still demands <Core>/<project>/" || pass
assert_not_contains "$BR" '<Core>/<project>/code/'
assert_not_contains "$REL" '../docs/'
assert_not_contains "$PA" '<Core>/<project>/code'
assert_not_contains "$PLUGIN/reference/wiki.md" 'relative to `code/`'
# Start steps 1-8 in order; the wiki step (6) sits between the clean tree and the base commits.
prev=0
for n in 1 2 3 4 5 6 7 8; do
  l="$(md_section "$SK" Start | grep -nE "^$n\\. " | head -1 | cut -d: -f1)"
  if [ -n "$l" ] && [ "$l" -gt "$prev" ]; then pass; else fail "SKILL.md Start step $n missing or out of order"; fi
  prev="${l:-$prev}"
done
md_section "$SK" Start | grep -E '^6\. ' | grep -qF '**Wiki.**' && pass || fail "SKILL.md Start step 6 is not the wiki step"
md_section "$SK" Start | grep -E '^7\. ' | grep -qF '**Base commits.**' && pass || fail "SKILL.md Start step 7 is not Base commits"
assert_contains "$REL" 'Start, **Wiki**'
# 0.7 wiki: the release wiki step regenerates INDEX.md before the check (more in test_wiki_texts.sh)
assert_contains "$REL" 'wiki-index.sh'
# Cross-file references name steps, never their numbers (numbers move when a step is added):
# "Start, **<Name>**" must name a bold step of Start in task/SKILL.md; "postcondition N" a numbered postcondition of
# release.md; "rule N" a numbered rule of task/SKILL.md. Checked in every corecrew prompt.
start_names="$(md_section "$SK" Start | sed -nE 's/^[0-9]+\. \*\*([^*]+)\.\*\*.*/\1/p')"
[ "$(printf '%s\n' "$start_names" | grep -c .)" -ge 7 ] && pass || fail "Start steps have bold names: $start_names"
npost="$(grep -cE '^[1-9]\. \*\*' "$REL")"
nrule="$(md_section "$SK" Rules | grep -cE '^[0-9]+\. ')"
bad=""
for f in "$PLUGIN"/skills/*/SKILL.md "$PLUGIN"/skills/*/references/*.md "$PLUGIN"/reference/*.md "$PLUGIN"/agents/*.md; do
  nm="${f#"$PLUGIN"/}"
  hit="$(grep -noE '[Ss]tart step [0-9]|steps? [0-9][0-9, –-]*(and [0-9–-]+ )?of Start|Start, step [0-9]' "$f")"
  [ -n "$hit" ] && bad="$bad $nm:$hit"
  for n in $(grep -oE 'Start, \*\*[^*]+\*\*' "$f" | sed -E 's/^Start, \*\*//; s/\*\*$//; s/\.$//' | tr ' ' '_'); do
    printf '%s\n' "$start_names" | tr ' ' '_' | grep -qxF "$n" || bad="$bad $nm:Start,$n"
  done
  for n in $(grep -oE 'postconditions? [0-9]+([–-][0-9]+)?' "$f" | grep -oE '[0-9]+'); do
    [ "$n" -ge 1 ] && [ "$n" -le "$npost" ] || bad="$bad $nm:postcondition$n"
  done
  for n in $(grep -oE '(^|[^a-z])rules? [0-9]+' "$f" | grep -oE '[0-9]+'); do
    [ "$n" -ge 1 ] && [ "$n" -le "$nrule" ] || bad="$bad $nm:rule$n"
  done
done
assert_eq "$bad" "" "cross-file step, postcondition and rule references resolve (no Start step numbers)"
# the check catches a stale name
T="$(mktemp -d)"; printf 'See Start, **Gone** and Start step 3.\n' > "$T/x.md"
case "$(grep -oE 'Start, \*\*[^*]+\*\*|[Ss]tart step [0-9]' "$T/x.md" | tr '\n' ' ')" in *Gone*'Start step 3'*) pass ;; *) fail "the reference check reads both forms" ;; esac
rm -rf "$T"
# Release writes the changelog in Keep a Changelog 1.1.0 when the project's own standard does not say otherwise
for w in '[Unreleased]' Added Changed Deprecated Removed Fixed Security 'Keep a Changelog'; do assert_contains "$REL" "$w"; done

# The Codex README section agrees with codex-host.md: without approval only the commit stops (the same line),
# and it says the guards are off until /hooks trust, with the skills that remind (the ones that run prepare.sh).
CX_STOP="$(md_section "$PLUGIN/reference/codex-host.md" 'Approval outside the sandbox' | grep -oE '`Commit: stopped[^`]*`' | head -1)"
[ -n "$CX_STOP" ] && pass || fail "codex-host.md Approval outside the sandbox lacks the stop line"
RCX="$(awk '/^### /{on = ($0 == "### Codex")} /^## /{on=0} on' "$PLUGIN/README.md")"
case "$RCX" in *"$CX_STOP"*) pass ;; *) fail "README Codex section does not name $CX_STOP" ;; esac
printf '%s\n' "$RCX" | grep -F 'codex exec' | grep -qiE 'task stops' &&
  fail "README Codex: codex exec must stop only the commit, not the task" || pass
case "$RCX" in *'/hooks'*) pass ;; *) fail "README Codex section: no /hooks trust step" ;; esac
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  n="$(basename "$(dirname "$sk")")"
  if grep -qF 'prepare.sh' "$sk"; then
    case "$RCX" in *"$n"*remind*|*remind*"$n"*) pass ;; *) fail "README Codex: does not say $n reminds about untrusted hooks" ;; esac
  fi
done
finish
