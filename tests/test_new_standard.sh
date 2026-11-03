#!/usr/bin/env bash
# check-standard.sh, the standard template, the new-standard skill and the knowledge format.
source "$(dirname "$0")/lib.sh"
new_sandbox
C="$SCRIPTS/check-standard.sh"
FX="$ROOT/tests/fixtures"
NS="$ROOT/skills/new-standard"
TPL="$NS/references/template.md"
SK="$NS/SKILL.md"

# check <fixture> <exact expected output>
check() {
  assert_exit 1 bash "$C" "$FX/$1"
  assert_eq "$OUT" "$2" "$1 output"
}

# Good standard: silent, exit 0.
assert_exit 0 bash "$C" "$FX/standard-good.md"
assert_eq "$OUT" "" "good standard prints nothing"

# One broken fixture per problem.
check standard-bad-frontmatter.md "check-standard: missing front matter field description
check-standard: missing front matter field updated"
check standard-bad-role.md "check-standard: unknown role wizard in applies-to
check-standard: unknown role mage in applies-to"
check standard-bad-section.md "check-standard: missing section Why"
check standard-bad-order.md "check-standard: sections out of order"
check standard-bad-nocheck.md "check-standard: rule 2 has no check
check-standard: check 3 is malformed (want \"<command> → <expected>\" or \"no guard — <risk>\")"
check standard-bad-long.md "check-standard: over 120 lines"

# Usage errors are exit 2, never "green".
assert_exit 2 bash "$C"
assert_exit 2 bash "$C" "$SANDBOX/nope.md"

# Edge cases, built in the sandbox.
E="$SANDBOX/edge"; mkdir -p "$E"
# No front matter at all: all four fields missing.
printf '# T\n## Rule\n1. a\n' > "$E/nofm.md"
assert_exit 1 bash "$C" "$E/nofm.md"
assert_contains <(printf '%s' "$OUT") "check-standard: missing front matter field name"
assert_contains <(printf '%s' "$OUT") "check-standard: missing front matter field applies-to"
# Unclosed front matter.
printf -- '---\nname: x\n' > "$E/unclosed.md"
assert_exit 1 bash "$C" "$E/unclosed.md"
assert_contains <(printf '%s' "$OUT") "check-standard: unclosed front matter"
# Empty applies-to counts as missing.
sed 's/^applies-to:.*/applies-to: []/' "$FX/standard-good.md" > "$E/emptyroles.md"
assert_exit 1 bash "$C" "$E/emptyroles.md"
assert_eq "$OUT" "check-standard: missing front matter field applies-to" "empty applies-to"
# A heading inside a code fence is not a section; a CRLF file passes.
sed 's/$/\r/' "$FX/standard-good.md" > "$E/crlf.md"
assert_exit 0 bash "$C" "$E/crlf.md"
{ sed '/^## Exceptions/,$d' "$FX/standard-good.md"; printf '```\n## Exceptions\n```\n## Sources\n- x\n'; } > "$E/fence.md"
assert_exit 1 bash "$C" "$E/fence.md"
assert_eq "$OUT" "check-standard: missing section Exceptions" "fenced heading ignored"
# Exactly 120 lines is fine.
{ cat "$FX/standard-good.md"; i=0; while [ $i -lt 92 ]; do echo "- l$i"; i=$((i+1)); done; } > "$E/l120.md"
assert_eq "$(wc -l < "$E/l120.md" | tr -d ' ')" 120 "fixture length"
assert_exit 0 bash "$C" "$E/l120.md"
# All seven roles are accepted.
sed 's/^applies-to:.*/applies-to: [engineer, tester, security, verifier, localizer, designer, release]/' \
  "$FX/standard-good.md" > "$E/roles.md"
assert_exit 0 bash "$C" "$E/roles.md"

# The template itself, with placeholders filled, passes; unfilled it still has every section.
assert_file "$TPL"
sed -e 's/<kebab-case>/demo/' -e 's/<one line[^>]*>/Demo rule./' \
    -e 's/<roles[^>]*>/engineer, tester/' -e 's/YYYY-MM-DD/2026-11-03/' \
    "$TPL" > "$E/template-filled.md"
assert_exit 0 bash "$C" "$E/template-filled.md"
assert_exit 1 bash "$C" "$TPL"        # placeholders left: description/roles are not real values
assert_not_contains <(printf '%s' "$OUT") "missing section"
assert_not_contains <(printf '%s' "$OUT") "out of order"
for w in '→' 'no guard —' 'engineer' 'release' 'designer'; do assert_contains "$TPL" "$w"; done
assert_contains "$C" "unknown role"

# SKILL.md
assert_file "$SK"
assert_contains "$SK" "name: new-standard"
assert_contains "$SK" "disable-model-invocation: true"
assert_contains "$SK" 'argument-hint: "[topic | knowledge line]"'
desc="$(sed -n 's/^description: //p' "$SK" | head -1)"
[ -n "$desc" ] && [ "${#desc}" -le 200 ] && pass || fail "description missing or over 200 chars (${#desc})"
assert_contains "$SK" "check-standard.sh"
assert_contains "$SK" 'git -C "<Core>" add "standards/<name>.md"'
assert_contains "$SK" 'commit -m "Add standard <name>"'
assert_contains "$SK" 'commit -m "Update standard <name>"'
assert_contains "$SK" '${user_config.core_dir}/standards/<name>.md'
assert_contains "$SK" "lib.sh\" ready"
assert_contains "$SK" "/coredev:new-project"
assert_contains "$SK" "general-purpose"
assert_contains "$SK" "300 words"
assert_contains "$SK" "diff -u"
grep -qiE 'never write[s]? into the plugin' "$SK" && pass || fail "SKILL.md must say it never writes into the plugin"
[ "$(wc -l < "$SK")" -lt 500 ] && pass || fail "SKILL.md is 500 lines or more"
assert_not_contains "$SK" "superpowers:"
# new-project points at the knowledge format.
assert_contains "$SKILL/SKILL.md" 'reference/knowledge.md'

# Knowledge format
K="$ROOT/reference/knowledge.md"
assert_file "$K"
assert_contains "$K" 'docs/knowledge/'
assert_contains "$K" '<Core>/knowledge/'
assert_contains "$K" 'symptom → cause → guard'
assert_contains "$K" 'Knowledge line:'
assert_contains "$K" 'How proof is made here'
assert_contains "$K" 'What you must not do here'
[ "$(wc -l < "$K")" -le 80 ] && pass || fail "knowledge.md over 80 lines"

finish
