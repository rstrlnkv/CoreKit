#!/usr/bin/env bash
# Shell commands written in the skills must run when Claude Code leaves ${user_config.*} literal
# (an unconfigured --plugin-dir, or a CLI install with unset options): a double-quoted
# "${user_config.core_dir}" is a "bad substitution" in bash and zsh; a single-quoted one reaches
# lib.sh as text, which treats it as unset.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR

for sk in "$PLUGIN"/skills/*/SKILL.md; do
  if grep -nF '"${user_config.' "$sk" >/dev/null; then
    fail "$sk double-quotes a \${user_config.} placeholder: $(grep -nF '"${user_config.' "$sk" | head -3 | tr '\n' ' ')"
  else pass; fi
done

# Every `CORE_DIR=…${user_config.core_dir}… bash ".../lib.sh" core-dir|ready` span, copied from the
# skill as the model would run it: <scripts>, <plugin>, <skill> filled in (see subst), ${user_config.*} left literal.
# subst <skill dir>: what the model does with the placeholders after `lib.sh plugin-root`
subst() { sed -e "s|<scripts>|$PLUGIN/scripts|g" -e "s|<plugin>|$PLUGIN|g" -e "s|<skill>|$1|g"; }
shells="bash"; command -v zsh >/dev/null 2>&1 && shells="bash zsh"
n=0
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n + 1))
    cmd="$(printf '%s' "$cmd" | subst "$d")"
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
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  grep -qF "CORE_DIR='\${user_config.core_dir}' bash \"<scripts>/lib.sh\" core-dir" "$sk" \
    && pass || fail "$(basename "$(dirname "$sk")"): no core-dir command with the single-quoted placeholder"
done

# new-project and new-standard say what a literal placeholder means.
for sk in "$PLUGIN/skills/new-project/SKILL.md" "$PLUGIN/skills/new-standard/SKILL.md" "$PLUGIN/skills/task/SKILL.md"; do
  assert_contains "$sk" 'still reads literally `${user_config.`'
done
# new-project resolves <Core> once (core-dir) before anything else, and uses the absolute path after.
NP="$PLUGIN/skills/new-project/SKILL.md"
c="$(grep -n 'lib.sh" core-dir' "$NP" | head -1 | cut -d: -f1)"; r="$(grep -n 'lib.sh" ready' "$NP" | head -1 | cut -d: -f1)"
[ -n "$c" ] && [ -n "$r" ] && [ "$c" -lt "$r" ] && pass || fail "new-project: core-dir must come before ready"
assert_eq "$(grep -c 'user_config.core_dir' "$NP")" "2" "new-project: user_config.core_dir only in Settings and the core-dir command"
assert_contains "$NP" 'gh repo create <CoreName> --private --source "<Core>" --push'
assert_contains "$NP" 'setup-core.sh" "<Core>"'
# scaffold's exit 2 "target exists": a folder of that name beside the Core is never touched
assert_contains "$NP" '`target exists: <path>`'
assert_contains "$NP" '/corecrew:task adopt <path>'

# `lib.sh" settings key='${user_config.key}' ...` spans: run with literal placeholders, defaults come out.
n=0
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n + 1))
    cmd="$(printf '%s' "$cmd" | subst "$d")"
    for sh in $shells; do
      out="$(cd "$SANDBOX" && "$sh" -c "$cmd" 2>&1)"
      case "$out" in *"bad substitution"*) fail "$sh: bad substitution: $cmd" ;; *) pass ;; esac
      case "$cmd" in
        *attribution=*) case "$out" in *"attribution: allow"*) pass ;; *) fail "$sh: settings command prints no default attribution: $out" ;; esac ;;
      esac
      case "$cmd" in
        *model_profile=*) case "$out" in *"model_profile: balanced"*) pass ;; *) fail "$sh: settings command prints no default model_profile: $out" ;; esac ;;
      esac
    done
  done <<< "$(grep -oE "\`bash \"[^\`]*lib\.sh\" settings [^\`]*user_config[^\`]*\`" "$sk" | tr -d '`')"
done
[ "$n" -ge 1 ] && pass || fail "expected a settings command with placeholders in the skills, found $n"
assert_contains "$PLUGIN/skills/task/SKILL.md" 'lib.sh" settings'

# One way to name the plugin folder: `${CLAUDE_SKILL_DIR}` once per skill, in ## Paths, never in a
# command; every command uses <scripts>/<plugin>/<skill>, filled in after `lib.sh plugin-root`.
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  nm="$(basename "$(dirname "$sk")")"
  assert_eq "$(grep -c '\${CLAUDE_SKILL_DIR}' "$sk")" "1" "$nm: \${CLAUDE_SKILL_DIR} appears once"
  paths="$(awk '/^## /{on = ($0 == "## Paths")} on' "$sk")"
  case "$paths" in *'${CLAUDE_SKILL_DIR}'*'lib.sh" plugin-root'*) pass ;; *) fail "$nm: ## Paths lacks CLAUDE_SKILL_DIR and plugin-root" ;; esac
  # the location check (cache folder, no quote, $ or backtick) comes before the plugin-root command
  case "$paths" in *'Check it'*'plugins/cache/'*'no `"`'*'run nothing'*'lib.sh" plugin-root'*) pass ;; *) fail "$nm: ## Paths must check <skill> before running plugin-root" ;; esac
  if grep -nE 'bash "[^<"]' "$sk" | grep -v '^[0-9]*:.*bash "\$' >/dev/null; then
    fail "$nm: a bash command not starting with a placeholder: $(grep -nE 'bash "[^<"]' "$sk" | head -2 | tr '\n' ' ')"
  else pass; fi
done
# plugin-root: the physical plugin folder, in bash and zsh; loud when the folder is not one
for sh in $shells; do
  out="$("$sh" -c "bash \"$PLUGIN/skills/task/../../scripts/lib.sh\" plugin-root" 2>&1)"
  assert_eq "$out" "$(cd -P "$PLUGIN" && pwd)" "$sh: plugin-root prints the plugin folder"
done
err="$(bash "/../../scripts/lib.sh" plugin-root 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ -n "$err" ] && pass || fail "an empty skill folder must fail with a message (rc=$rc)"
err="$(bash "<skill>/../../scripts/lib.sh" plugin-root 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ -n "$err" ] && pass || fail "a placeholder left in must fail with a message (rc=$rc)"
mkdir -p "$SANDBOX/x/scripts"; cp "$PLUGIN/scripts/lib.sh" "$SANDBOX/x/scripts/lib.sh"
err="$(bash "$SANDBOX/x/scripts/lib.sh" plugin-root 2>&1)"; rc=$?
assert_eq "$rc" "1" "a folder that is not a plugin: exit 1"
case "$err" in *"not a plugin folder"*) pass ;; *) fail "no 'not a plugin folder' message: $err" ;; esac
finish
