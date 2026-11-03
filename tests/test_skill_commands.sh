#!/usr/bin/env bash
# Shell commands written in the skills must run when Claude Code leaves ${user_config.*} literal
# (an unconfigured --plugin-dir, or a CLI install with unset options): a double-quoted
# "${user_config.core_dir}" is a "bad substitution" in bash and zsh; a single-quoted one reaches
# lib.sh as text, which treats it as unset.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR

for sk in "$ROOT"/skills/*/SKILL.md; do
  if grep -nF '"${user_config.' "$sk" >/dev/null; then
    fail "$sk double-quotes a \${user_config.} placeholder: $(grep -nF '"${user_config.' "$sk" | head -3 | tr '\n' ' ')"
  else pass; fi
done

# Every `CORE_DIR=…${user_config.core_dir}… bash ".../lib.sh" core-dir|ready` span, copied from the
# skill as the model would run it: ${CLAUDE_SKILL_DIR} substituted, ${user_config.*} left literal.
shells="bash"; command -v zsh >/dev/null 2>&1 && shells="bash zsh"
n=0
for sk in "$ROOT"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n + 1))
    cmd="$(printf '%s' "$cmd" | sed "s|\${CLAUDE_SKILL_DIR}|$d|g")"
    for sh in $shells; do
      out="$(cd "$SANDBOX" && "$sh" -c "$cmd" 2>&1)"
      case "$out" in *"bad substitution"*) fail "$sh: bad substitution in $(basename "$d"): $cmd" ;; *) pass ;; esac
      case "$cmd" in
        *core-dir) assert_eq "$out" "$HOME/Projects/Core" "$sh: core-dir from $(basename "$d") with the literal placeholder" ;;
      esac
    done
  done <<< "$(grep -oE '`CORE_DIR=[^`]*user_config[^`]*lib\.sh" (core-dir|ready)`' "$sk" | tr -d '`')"
done
[ "$n" -ge 3 ] && pass || fail "expected core-dir/ready commands with the placeholder in the skills, found $n"
for sk in "$ROOT"/skills/*/SKILL.md; do
  grep -qF "CORE_DIR='\${user_config.core_dir}' bash \"\${CLAUDE_SKILL_DIR}/../../scripts/lib.sh\" core-dir" "$sk" \
    && pass || fail "$(basename "$(dirname "$sk")"): no core-dir command with the single-quoted placeholder"
done

# new-project and new-standard say what a literal placeholder means.
for sk in "$ROOT/skills/new-project/SKILL.md" "$ROOT/skills/new-standard/SKILL.md" "$ROOT/skills/task/SKILL.md"; do
  assert_contains "$sk" 'still reads literally `${user_config.`'
done
# new-project resolves <Core> once (core-dir) before anything else, and uses the absolute path after.
NP="$ROOT/skills/new-project/SKILL.md"
c="$(grep -n 'lib.sh" core-dir' "$NP" | head -1 | cut -d: -f1)"; r="$(grep -n 'lib.sh" ready' "$NP" | head -1 | cut -d: -f1)"
[ -n "$c" ] && [ -n "$r" ] && [ "$c" -lt "$r" ] && pass || fail "new-project: core-dir must come before ready"
assert_eq "$(grep -c 'user_config.core_dir' "$NP")" "2" "new-project: user_config.core_dir only in Settings and the core-dir command"
assert_contains "$NP" 'gh repo create <CoreName> --private --source "<Core>" --push'
assert_contains "$NP" 'setup-core.sh" "<Core>"'
finish
