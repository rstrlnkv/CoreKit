#!/usr/bin/env bash
# Inputs nobody fed to the Paths mechanism: plugin-root through a symlink, a path with spaces, a
# foreign cwd; a placeholder left in a command; every <skill>/<plugin>/<scripts> path in the
# SKILL.md files exists; the two manifests agree; the Codex install check is offline.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR
phys="$(cd -P "$PLUGIN" && pwd)"

# plugin-root: spaces, symlinked folder, symlinked lib.sh, foreign cwd, run through zsh/sh-less paths
mkdir -p "$SANDBOX/with space"; cp -R "$PLUGIN" "$SANDBOX/with space/corecrew"
want="$SANDBOX/with space/corecrew"
assert_eq "$(cd / && bash "$want/scripts/lib.sh" plugin-root 2>&1)" "$want" "plugin-root in a path with spaces"
ln -s "$want" "$SANDBOX/link"
assert_eq "$(cd / && bash "$SANDBOX/link/scripts/lib.sh" plugin-root 2>&1)" "$want" "plugin-root through a symlinked plugin folder prints the physical path"
assert_eq "$(cd / && bash "$SANDBOX/link/skills/task/../../scripts/lib.sh" plugin-root 2>&1)" "$want" "plugin-root via <skill>/../../ through a symlink"
ln -s "$want/scripts/lib.sh" "$SANDBOX/lib-link.sh"
out="$(cd / && bash "$SANDBOX/lib-link.sh" plugin-root 2>&1)"; rc=$?
# lib.sh behind a symlink in a foreign folder is not a plugin: must be loud, not a wrong success
[ "$rc" -ne 0 ] && pass || fail "symlinked lib.sh outside a plugin must fail loudly, got: $out"
assert_eq "$(cd "$SANDBOX" && bash "$phys/scripts/lib.sh" plugin-root 2>&1)" "$phys" "plugin-root from a cwd that is not the plugin"
assert_eq "$(cd "$SANDBOX/with space" && bash "../with space/corecrew/scripts/lib.sh" plugin-root 2>&1)" "$want" "plugin-root through a relative path"

# plugin-root needs BOTH skills/ and a manifest; either one alone is not a plugin; the Codex manifest alone is enough
mk() { rm -rf "$SANDBOX/pr"; mkdir -p "$SANDBOX/pr/scripts"; cp "$PLUGIN/scripts/lib.sh" "$SANDBOX/pr/scripts/lib.sh"; }
mk; mkdir -p "$SANDBOX/pr/.claude-plugin"; echo '{ "name": "corecrew" }' > "$SANDBOX/pr/.claude-plugin/plugin.json"
assert_exit 1 bash "$SANDBOX/pr/scripts/lib.sh" plugin-root   # manifest, no skills/
mk; mkdir -p "$SANDBOX/pr/skills"
assert_exit 1 bash "$SANDBOX/pr/scripts/lib.sh" plugin-root   # skills/, no manifest
mk; mkdir -p "$SANDBOX/pr/skills" "$SANDBOX/pr/.codex-plugin"; echo '{ "name": "corecrew" }' > "$SANDBOX/pr/.codex-plugin/plugin.json"
assert_exit 0 bash "$SANDBOX/pr/scripts/lib.sh" plugin-root   # skills/ + Codex manifest only
# identity: a lookalike folder with another plugin name is refused (a mix-up catch, not a boundary)
mk; mkdir -p "$SANDBOX/pr/skills" "$SANDBOX/pr/.codex-plugin"; echo '{ "name": "other" }' > "$SANDBOX/pr/.codex-plugin/plugin.json"
assert_exit 1 bash "$SANDBOX/pr/scripts/lib.sh" plugin-root
err="$(bash "$SANDBOX/pr/scripts/lib.sh" plugin-root 2>&1 >/dev/null)"
assert_eq "$err" "corecrew: not a corecrew plugin folder: $(cd -P "$SANDBOX/pr" && pwd)" "lookalike message"
# the winning manifest decides: Codex manifest named other, Claude manifest named corecrew -> refused
mkdir -p "$SANDBOX/pr/.claude-plugin"; echo '{ "name": "corecrew" }' > "$SANDBOX/pr/.claude-plugin/plugin.json"
assert_exit 1 bash "$SANDBOX/pr/scripts/lib.sh" plugin-root

# an unreplaced placeholder, or an empty substitution, never resolves: non-zero and a message on stderr
n=0
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  while IFS= read -r span; do
    [ -n "$span" ] || continue
    for variant in raw empty; do
      cmd="$span"
      [ "$variant" = empty ] && cmd="$(printf '%s' "$span" | sed -e 's|<scripts>||g' -e 's|<plugin>||g' -e 's|<skill>||g')"
      n=$((n + 1))
      err="$(cd "$SANDBOX" && bash -c "$cmd" 2>&1 >/dev/null)"; rc=$?
      [ "$rc" -ne 0 ] && [ -n "$err" ] && pass || fail "$(basename "$(dirname "$sk")") $variant: rc=$rc err='$err' :: $cmd"
    done
  done <<< "$(grep -oE '`(CORE_DIR=[^`]* )?bash "<(scripts|plugin|skill)>[^`]*`' "$sk" | tr -d '`')"
done
[ "$n" -ge 20 ] && pass || fail "expected many command spans with placeholders, found $n"

# every named <skill>/<plugin>/<scripts> path exists after substitution
n=0
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"
  for ph in scripts plugin skill; do
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case "$tok" in *'<'[a-z]*'>'*) rest="${tok#*>}"; case "$rest" in *'<'*) continue ;; esac ;; esac
      tok="${tok%[.,;:]}"
      p="$(printf '%s' "$tok" | sed -e "s|^<scripts>|$PLUGIN/scripts|" -e "s|^<plugin>|$PLUGIN|" -e "s|^<skill>|$d|")"
      n=$((n + 1))
      [ -e "$p" ] && pass || fail "$(basename "$d"): $tok does not exist ($p)"
    done <<< "$(grep -ohE "<$ph>/[^ \`\"')]*" "$sk" | sort -u)"
  done
done
[ "$n" -ge 25 ] && pass || fail "expected many named paths, found $n"

# the two manifests agree
f() { sed -n "s/^ *\"$1\": *\(.*[^,]\),\{0,1\}$/\1/p" "$2" | head -1; }
C="$PLUGIN/.claude-plugin/plugin.json"; X="$PLUGIN/.codex-plugin/plugin.json"
for k in name version description license keywords; do
  [ -n "$(f $k "$C")" ] && assert_eq "$(f $k "$X")" "$(f $k "$C")" "manifest key $k equal" || fail "key $k missing in the Claude manifest"
done

# every skill that hides itself from Codex has the policy, and nobody else has the file
for y in "$PLUGIN"/skills/*/agents/openai.yaml; do assert_contains "$y" 'allow_implicit_invocation: false'; done

# the Codex install test needs no network (a dead proxy must not break it); twice in one sandbox
if command -v codex >/dev/null 2>&1; then
  for i in 1 2; do
    out="$(HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 bash "$ROOT/tests/test_codex_install.sh" 2>&1)"
    case "$out" in *", 0 failed"*) pass ;; *) fail "codex install test, dead proxy, run $i: $(printf '%s' "$out" | tail -3)" ;; esac
  done
else echo "  SKIP codex part: codex not on PATH"; fi
finish
