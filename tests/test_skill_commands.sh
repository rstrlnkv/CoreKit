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
shells="bash"
if command -v zsh >/dev/null 2>&1; then shells="bash zsh"; else skip zsh-commands "zsh not on PATH"; fi
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
  # in Codex the folder is found and checked by the shared host reference, before plugin-root runs
  case "$paths" in *'reference/codex-host.md'*'Skill folder'*'lib.sh" plugin-root'*) pass ;; *) fail "$nm: ## Paths must send Codex to codex-host.md (Skill folder) before plugin-root" ;; esac
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
# One Paths section, the same in every skill (kept short: the Codex rules live in reference/codex-host.md).
first=""
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  paths="$(awk '/^## /{on = ($0 == "## Paths")} on' "$sk")"
  if [ -z "$first" ]; then first="$paths"; firstn="$(basename "$(dirname "$sk")")"; continue; fi
  assert_eq "$paths" "$first" "## Paths of $(basename "$(dirname "$sk")") is the same as in $firstn"
done
w="$(printf '%s\n' "$first" | wc -w | tr -d ' ')"
[ "$w" -le 130 ] && pass || fail "## Paths is $w words; keep it under 130 (details go to codex-host.md)"
# the shared Codex reference: its sections, and the location check of the skill folder before anything runs
CH="$PLUGIN/reference/codex-host.md"
assert_file "$CH"
secs="$(grep '^## ' "$CH" | tr '\n' '|')"
assert_eq "$secs" "## Skill folder|## Settings and skill names|## Writable folders|## Approval outside the sandbox|## Questions|## Subagents|" "codex-host.md sections"
sf="$(awk '/^## /{on = ($0 == "## Skill folder")} on' "$CH")"
case "$sf" in *'plugins/cache/'*'no `..`'*'no `"`'*'run nothing'*) pass ;; *) fail "codex-host.md Skill folder lacks the location check" ;; esac
grep -qF '${' "$CH" && fail "codex-host.md is read with Read, which substitutes nothing: no \${...} in it" || pass
# The location check shows a filled-in example path (no placeholders), so a model does not read the template literally.
printf '%s\n' "$sf" | grep -qE '(^|[^<])plugins/cache/[a-z0-9-]+/corecrew/[0-9]+\.[0-9]+\.[0-9]+/skills/[a-z-]+' && pass ||
  fail "codex-host.md Skill folder: no concrete example path (plugins/cache/<name>/corecrew/<x.y.z>/skills/<skill>)"
# No approval (codex exec): only the step that needs it stops, the same stop line the task chain reports;
# the Approval section never tells the model to stop the whole skill.
ap="$(awk '/^## /{on = ($0 == "## Approval outside the sandbox")} on' "$CH")"
cx_stop="$(printf '%s\n' "$ap" | grep -oE '`Commit: stopped[^`]*`' | head -1)"
[ -n "$cx_stop" ] && pass || fail "codex-host.md Approval lacks the Commit: stopped line"
case "$ap" in *'codex exec'*"$cx_stop"*) pass ;; *) fail "codex-host.md Approval: the codex exec case must name $cx_stop" ;; esac
printf '%s\n' "$ap" | tr '\n' ' ' | grep -qiE 'not possible[^.]*, stop and report' &&
  fail "codex-host.md Approval: a missing approval must stop only that step, not the whole skill" || pass
# Codex 0.166 keeps spawn_agent with --disable multi_agent: no text promises what the feature switch does.
# Nor does any text say which tool set is Codex's default, that the feature is on by default, or send the reader to
# `codex features list` (R4-069: none of the three was shown by a run).
for f in "$CH" "$PLUGIN/README.md" "$PLUGIN/../../README.md" "$PLUGIN/skills/task/references/codex.md"; do
  grep -qE -- '--disable multi_agent|multi_agent` turns them on' "$f" && fail "$f promises what the multi_agent switch does" || pass
  grep -qE -- "features list|Codex's default|multi_agent[^.]*on by default" "$f" \
    && fail "${f#"$ROOT"/} makes an unproven claim about Codex subagents (features list, Codex's default, on by default)" || pass
done

# new-project: the open command is written out for both hosts, not left to another file.
vf="$(awk '/^\*\*6\. Verify\.\*\*/{on=1} /^\*\*7\./{on=0} on' "$NP")"
for w in 'cd "<Projects>/<name>" && claude' 'cd "<Projects>/<name>" && codex --add-dir "<Core>"'; do
  case "$vf" in *"$w"*) pass ;; *) fail "new-project Verify: open command missing: $w" ;; esac
done
# A taken name (preflight name-local / name-github FAIL) stops and asks for another name; it is never a resume.
nm="$(awk '/^\*\*2\. Name\.\*\*/{on=1} /^\*\*3\./{on=0} on' "$NP")"
PF="$PLUGIN/skills/new-project/scripts/preflight.sh"
for id in name-local name-github; do
  grep -qF "\"$id " "$PF" && pass || fail "preflight.sh no longer prints $id"
  case "$nm" in *"$id"*) pass ;; *) fail "new-project Name: does not say what to do on $id" ;; esac
done
st="$(awk '/^## /{on = ($0 == "## Stages")} on' "$NP" | tr '\n' ' ')"
case "$st" in *'already has a brief, read it and resume'*) fail "new-project Stages: resume must need the user's word or this run's project" ;; *) pass ;; esac

# Every file path a corecrew prompt names through a placeholder exists: <plugin>/..., <scripts>/..., the skill's own
# <skill>/... and references/... (placeholders inside the rest of the path are skipped).
chk_paths() { # <file> <skill dir or empty>
  local f="$1" sd="$2" t rel base
  LC_ALL=C grep -oE '<(plugin|scripts|skill)>/[A-Za-z0-9_./-]*[A-Za-z0-9_]|(^|[ `(])references/[A-Za-z0-9_.-]+\.md' "$f" | LC_ALL=C sed -E 's/^[ `(]//' | LC_ALL=C sort -u |
  while IFS= read -r t; do
    case "$t" in
      '<plugin>/'*) base="$PLUGIN"; rel="${t#<plugin>/}" ;;
      '<scripts>/'*) base="$PLUGIN/scripts"; rel="${t#<scripts>/}" ;;
      '<skill>/'*) [ -n "$sd" ] || continue; base="$sd"; rel="${t#<skill>/}" ;;
      references/*) [ -n "$sd" ] || continue; base="$sd"; rel="$t" ;;
    esac
    case "$rel" in ../../*) base="$PLUGIN"; rel="${rel#../../}" ;; esac
    [ -e "$base/$rel" ] || echo "$(basename "$f") names $t, which does not exist"
  done
}
miss=""
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"
  for f in "$sk" "$d"/references/*.md; do [ -f "$f" ] && miss="$miss$(chk_paths "$f" "$d")"; done
done
for f in "$PLUGIN"/reference/*.md "$PLUGIN"/agents/*.md; do miss="$miss$(chk_paths "$f" "")"; done
assert_eq "$miss" "" "every <plugin>/, <scripts>/, <skill>/ and references/ path in the prompts exists"
T="$(mktemp -d)"; printf 'Read `<plugin>/reference/gone.md` and `references/paths.md`.\n' > "$T/x.md"
assert_eq "$(chk_paths "$T/x.md" "$PLUGIN/skills/task")" "x.md names <plugin>/reference/gone.md, which does not exist" "the path check catches a made-up path"
rm -rf "$T"
finish
