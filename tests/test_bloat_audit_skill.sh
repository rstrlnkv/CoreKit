#!/usr/bin/env bash
# The bloat-audit skill: frontmatter, read-only tools, sections in order, the report line, the never-cut list.
source "$(dirname "$0")/lib.sh"
new_sandbox
SK="$PLUGIN/skills/bloat-audit/SKILL.md"

# frontmatter: triggers by meaning (no disable-model-invocation, no Codex openai.yaml turning it off)
assert_file "$SK"
fm="$(awk 'NR == 1 && $0 == "---" {on = 1; next} on && $0 == "---" {exit} on' "$SK")"
printf '%s\n' "$fm" | grep -qx 'name: bloat-audit' && pass || fail "frontmatter lacks name: bloat-audit"
printf '%s\n' "$fm" | grep -q 'disable-model-invocation' && fail "bloat-audit must trigger by meaning" || pass
assert_no_file "$PLUGIN/skills/bloat-audit/agents/openai.yaml"
desc="$(printf '%s\n' "$fm" | sed -n 's/^description: //p')"
[ -n "$desc" ] && [ "${#desc}" -le 380 ] && pass || fail "description missing or over 380 chars (${#desc})"
for w in 'Use when' 'in any language' '/simplify'; do
  case "$desc" in *"$w"*) pass ;; *) fail "description lacks: $w" ;; esac
done
# read-only: the skill may read and run commands, never edit or write files
at="$(printf '%s\n' "$fm" | sed -n 's/^allowed-tools: //p')"
assert_eq "$at" "Read, Grep, Glob, Bash" "allowed-tools"

# body: sections in this order
secs="$(grep '^## ' "$SK" | tr '\n' '|')"
assert_eq "$secs" "## Paths|## Scope|## Order|## Report|## After the report|" "bloat-audit sections"

# the five kinds, each named once in Order
for k in 'duplicated logic' 'reinvented standard library or platform' 'an abstraction with one user' \
         'configuration nobody changes' 'dead code'; do
  n="$(md_section "$SK" Order | grep -cF -- "**$k**")"
  assert_eq "$n" "1" "Order names '$k' once"
done
# the report line and what is never cut
md_section_has "$SK" Report '`<file:line> — <what> → <what replaces it or where it moves> — <lines saved> — <risk>`'
for w in 'trust boundaries' 'data loss' 'security' 'accessibility' 'localization'; do
  md_section_has "$SK" Report "$w"
done
md_section_has "$SK" "After the report" '/corecrew:task'
md_section_has "$SK" Scope 'changes nothing'

finish
