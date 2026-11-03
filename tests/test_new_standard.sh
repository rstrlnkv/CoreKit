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

# The template itself: fully filled (placeholders and comments gone) passes.
assert_file "$TPL"
FILL_FM=(-e 's/<kebab-case>/demo/' -e 's/<one line[^>]*>/Demo rule./' \
    -e 's/<roles[^>]*>/engineer, tester/' -e 's/YYYY-MM-DD/2026-11-03/')
sed "${FILL_FM[@]}" "$TPL" > "$E/template-fm.md"      # only the front matter filled
sed "${FILL_FM[@]}" -e 's/<Title>/Demo/' -e 's/<imperative rule>/Do it./' \
    -e 's/<the failure this rule prevents>/It breaks./' -e 's/<command> → <expected output>/true → exit 0/' \
    -e 's/<the risk that stays>/It may break./' -e 's/<what the rules rest on[^>]*>/my notes/' \
    "$TPL" | awk '/^<!--/{c=1} !c{print} c&&/-->/{c=0}' > "$E/template-filled.md"
assert_exit 0 bash "$C" "$E/template-filled.md"
# Front matter only: placeholders and comments are reported.
assert_exit 1 bash "$C" "$E/template-fm.md"
assert_eq "$OUT" "check-standard: placeholder left: <Title>
check-standard: placeholder left: <imperative rule>
check-standard: placeholder left: <the failure this rule prevents>
check-standard: placeholder left: <expected output>
check-standard: placeholder left: <the risk that stays>
check-standard: placeholder left: <what the rules rest on: a link, a document, or your own experience>
check-standard: comment left" "front-matter-only template"
# A comment alone is reported; legitimate <Core>-style text is not a placeholder.
sed 's/^none$/none <!-- todo -->/' "$FX/standard-good.md" > "$E/comment.md"
assert_exit 1 bash "$C" "$E/comment.md"
assert_eq "$OUT" "check-standard: comment left" "comment left"
sed 's|^- The owner.s own habit.|- Legitimate <Core>/standards/<name>.md text is not a placeholder|' "$FX/standard-good.md" > "$E/angle.md"
assert_exit 0 bash "$C" "$E/angle.md"
assert_exit 1 bash "$C" "$TPL"        # the raw template is never green
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
assert_contains "$SK" '<Core>/standards/<name>.md'
assert_contains "$SK" "lib.sh\" ready"
assert_contains "$SK" "/coredev:new-project"
assert_contains "$SK" "general-purpose"
assert_contains "$SK" "300 words"
assert_contains "$SK" "lib.sh\" core-dir"
assert_contains "$SK" "TMPDIR"
assert_contains "$SK" "at most 120 lines"
assert_not_contains "$SK" "under 120"
assert_not_contains "$TPL" "under 120"
assert_not_contains "$ROOT/docs/specs/2026-11-03-coredev-design.md" "under 120 lines"
assert_contains "$SK" "imperative rule"
assert_contains "$SK" "writes nothing"
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
