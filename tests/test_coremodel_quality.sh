#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
assert_exit 0 python3 "$ROOT/scripts/coremodel-quality.py" --check
assert_contains "$ROOT/evals/coremodel-quality/cases.jsonl" '"lang":"ru"'
assert_contains "$ROOT/evals/coremodel-quality/cases.jsonl" '"lang":"en"'
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "${TEST_ANSWER:-invalid}"
STUB
chmod +x "$SANDBOX/bin/codex"
check_case() {
  assert_exit "$1" env PATH="$SANDBOX/bin:$PATH" TEST_ANSWER="$2" python3 "$ROOT/scripts/coremodel-quality.py" --case "$3"
}
check_case 0 '{"keep":false,"model":"gpt-6-luna","effort":"low"}' mro-en
check_case 1 '{"keep":false,"model":"gpt-6.2-sol","effort":"low"}' mro-ru
check_case 0 '{"keep":true,"model":"gpt-6.2-sol","effort":"medium"}' option-en
check_case 1 'invalid' option-ru
case "$OUT" in *'no valid response: 1'*) pass ;; *) fail "invalid response was scored as a recommendation" ;; esac
finish
