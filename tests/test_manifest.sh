#!/usr/bin/env bash
# Plugin and marketplace manifests: name, version, settings, dependency, rename; docs follow.
source "$(dirname "$0")/lib.sh"
P="$PLUGIN/.claude-plugin/plugin.json"
M="$ROOT/.claude-plugin/marketplace.json"

# plugin.json
assert_contains "$P" '"name": "corecrew"'
assert_contains "$P" '"userConfig"'
for key in core_dir attribution model_profile ui_language; do assert_contains "$P" "\"$key\""; done
assert_contains "$P" '"type": "directory"'
assert_contains "$P" '"default": "~/Projects/Core"'
assert_contains "$P" '"options": ["allow", "forbid"]'
assert_contains "$P" '"default": "allow"'
assert_contains "$P" '"options": ["economy", "balanced", "strong"]'
assert_contains "$P" '"default": "balanced"'
assert_contains "$P" '"title": "Hook messages language"'
assert_contains "$P" '"description": "Language of the messages corecrew hooks show: en (English) or ru (Russian)."'
assert_contains "$P" '"options": ["en", "ru"]'
assert_contains "$P" '"default": "en"'
assert_contains "$ROOT/README.md" '`ui_language`'
assert_contains "$ROOT/README.md" 'claude plugin install corecrew@corekit --config ui_language=ru'
assert_not_contains "$P" '"dependencies"'   # a hard dependency stops corecrew loading when feature-dev is synced from claude.ai
assert_not_contains "$P" '"marketplace": "claude-plugins-official"'

# marketplace.json
assert_contains "$M" '"name": "corekit"'
assert_contains "$M" '"name": "corecrew"'
assert_contains "$M" '"displayName": "CoreCrew"'
assert_contains "$M" '"displayName": "CoreModel"'
assert_contains "$P" '"displayName": "CoreCrew"'
assert_contains "$ROOT/plugins/coremodel/.claude-plugin/plugin.json" '"displayName": "CoreModel"'
assert_contains "$M" '"renames"'
assert_contains "$M" '"corekit": "corecrew"'
assert_contains "$M" '"coredev": "corecrew"'
assert_contains "$M" '"effort-picker": "coremodel"'
assert_contains "$M" '"coreeffort": "coremodel"'
assert_not_contains "$M" 'allowCrossMarketplaceDependenciesOn'
assert_contains "$M" '"name": "coremodel"'
assert_contains "$M" '"source": "./plugins/corecrew"'
assert_contains "$M" '"source": "./plugins/coremodel"'

# README and CHANGELOG
assert_contains "$ROOT/README.md" '<Projects>/<name>'
assert_not_contains "$ROOT/README.md" 'my-app/code/'
assert_contains "$ROOT/README.md" '/plugin install corecrew@corekit'
assert_not_contains "$ROOT/README.md" '/corekit:'
assert_not_contains "$ROOT/README.md" 'corekit@corekit'

# Versions, CHANGELOGs, descriptions and icons of every plugin: they must agree with each other,
# never with a literal, so a release edits no test.
jf() { sed -n "s/^ *\"$2\": *\"\(.*\)\",\{0,1\}\$/\1/p" "$1" | head -1; }
# changelog_of <plugin> — corecrew's CHANGELOG is the root one; the others sit next to the plugin
changelog_of() { [ "$1" = corecrew ] && echo "$ROOT/CHANGELOG.md" || echo "$ROOT/plugins/$1/CHANGELOG.md"; }
# check_changelog <file> — Keep a Changelog 1.1.0: "## [Unreleased]" first, then
# "## [X.Y.Z] - YYYY-MM-DD" with dates never rising, groups only Added..Security, no old badges.
# Prints one line per problem; prints nothing for a good file.
check_changelog() {
  LC_ALL=C awk '
    /^## / {
      n++
      if (n == 1) { if ($0 != "## [Unreleased]") print "first heading is not ## [Unreleased]: " $0; next }
      if ($0 !~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { print "bad release heading: " $0; next }
      d = substr($0, length($0) - 9); mo = substr(d, 6, 2) + 0; dy = substr(d, 9, 2) + 0
      if (mo < 1 || mo > 12 || dy < 1 || dy > 31) print "bad date: " $0
      if (last != "" && d > last) print "date rises: " $0
      last = d; next
    }
    /^### / { if ($0 !~ /^### (Added|Changed|Deprecated|Removed|Fixed|Security)$/) print "bad group: " $0; next }
    /\*\*(NEW|FIX|UPD)\*\*/ { print "old badge at line " NR }
    END { if (n < 2) print "no released version" }
  ' "$1"
}
# top_version <file> — the version of the first released heading
top_version() { sed -n 's/^## \[\([0-9][0-9.]*\)\] - .*/\1/p' "$1" | head -1; }
# market_desc <plugin> — the description of the plugin's entry in marketplace.json (one key per line)
market_desc() {
  awk -v p="$1" '
    /"name": / { n = $0; sub(/.*"name": "/, "", n); sub(/".*/, "", n) }
    /"description": / && n == p { d = $0; sub(/.*"description": "/, "", d); sub(/",?[[:space:]]*$/, "", d); print d; exit }
  ' "$M"
}

plugins=""
for d in "$ROOT"/plugins/*/; do plugins="$plugins $(basename "$d")"; done
for pl in $plugins; do
  CJ="$ROOT/plugins/$pl/.claude-plugin/plugin.json"; XJ="$ROOT/plugins/$pl/.codex-plugin/plugin.json"
  CL="$(changelog_of "$pl")"
  assert_file "$CL"
  assert_eq "$(check_changelog "$CL")" "" "$pl CHANGELOG format"
  top="$(top_version "$CL")"
  assert_eq "$(jf "$CJ" version)" "$top" "$pl .claude-plugin version vs CHANGELOG"
  [ -f "$XJ" ] && assert_eq "$(jf "$XJ" version)" "$top" "$pl .codex-plugin version vs CHANGELOG"
  # every plugin is listed, with the same one-sentence description as its manifests
  desc="$(jf "$CJ" description)"
  assert_contains "$M" "\"source\": \"./plugins/$pl\""
  assert_eq "$(market_desc "$pl")" "$desc" "$pl description differs between marketplace.json and plugin.json"
  [ -f "$XJ" ] && assert_eq "$(jf "$XJ" description)" "$desc" "$pl description differs between the Claude and Codex manifests"
  # the icon: ./assets/icon.png, named in every manifest, a square PNG of 512 to 2048 px, under 256 KiB
  ic="$ROOT/plugins/$pl/assets/icon.png"
  assert_eq "$(jf "$CJ" icon)" "./assets/icon.png" "$pl icon field"
  if [ -f "$XJ" ]; then
    for k in composerIcon logo; do assert_eq "$(jf "$XJ" $k)" "./assets/icon.png" "$pl Codex $k"; done
  fi
  assert_file "$ic"
  assert_no_file "$ROOT/plugins/$pl/.claude-plugin/icon.png"
  assert_file "$ROOT/docs/icons/$pl.svg"
  if command -v sips >/dev/null 2>&1; then
    w="$(sips -g pixelWidth "$ic" 2>/dev/null | sed -n 's/.*pixelWidth: //p')"; h="$(sips -g pixelHeight "$ic" 2>/dev/null | sed -n 's/.*pixelHeight: //p')"
    assert_eq "$w" "$h" "$pl icon is square"
    [ "${w:-0}" -ge 512 ] && [ "${w:-0}" -le 2048 ] && pass || fail "$pl icon is $w px, want 512 to 2048"
  fi
  [ "$(wc -c < "$ic" | tr -d ' ')" -lt 262144 ] && pass || fail "$pl icon is 256 KiB or more"
  case "$(head -c 4 "$ic" | od -An -c | tr -d ' ')" in *PNG*) pass ;; *) fail "$pl icon is not a PNG" ;; esac
  # SECURITY.md: a line that names this plugin and a version names the current one
  bad="$(grep -wF "$pl" "$ROOT/SECURITY.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | grep -vxF "$top")"
  assert_eq "$bad" "" "SECURITY.md names an old $pl version"
done
# the descriptions this repo owns are one sentence of at most 120 characters, benefit first
for pl in corecrew; do
  desc="$(jf "$ROOT/plugins/$pl/.claude-plugin/plugin.json" description)"
  [ "${#desc}" -le 120 ] && pass || fail "$pl description is ${#desc} characters, want 120 at most"
  case "$desc" in *.*.*) fail "$pl description is more than one sentence" ;; *.) pass ;; *) fail "$pl description does not end with a full stop" ;; esac
done

# self-check of the CHANGELOG rule: a good file passes, each kind of mistake is caught
new_sandbox; T="$SANDBOX/changelogs"; mkdir -p "$T"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] - 2026-11-08\n\n### Added\n\n- x\n\n## [1.0.0] - 2026-11-01\n\n### Fixed\n\n- y\n' > "$T/good.md"
assert_eq "$(check_changelog "$T/good.md")" "" "a good CHANGELOG passes"
assert_eq "$(top_version "$T/good.md")" "1.1.0" "top released version"
printf '## [1.0.0] - 2026-11-01\n' > "$T/nounrel.md"
case "$(check_changelog "$T/nounrel.md")" in *"not ## [Unreleased]"*) pass ;; *) fail "missing [Unreleased] not caught" ;; esac
printf '## [Unreleased]\n## 1.0.0 — 2026-11-01\n' > "$T/old.md"
case "$(check_changelog "$T/old.md")" in *"bad release heading"*) pass ;; *) fail "old heading not caught" ;; esac
printf '## [Unreleased]\n## [1.0.0] - 2026-11-01\n### New\n- **NEW** x\n' > "$T/group.md"
case "$(check_changelog "$T/group.md")" in *"bad group"*"old badge"*) pass ;; *) fail "bad group or badge not caught" ;; esac
printf '## [Unreleased]\n## [1.0.1] - 2026-10-01\n## [1.0.0] - 2026-11-01\n## [0.9.0] - 2026-13-01\n' > "$T/date.md"
case "$(check_changelog "$T/date.md")" in *"date rises"*"bad date"*) pass ;; *) fail "rising or bad date not caught" ;; esac
rm -rf "$T"

# hooks.json: plugin Stop hook; no install.sh any more
assert_file "$PLUGIN/hooks/hooks.json"
H="$PLUGIN/hooks/hooks.json"
assert_contains "$H" '"Stop"'
assert_contains "$H" '"timeout"'
# hooks.json wires all five hooks. One key per line, so awk can pair each event and
# matcher with its command and timeout: "Event|matcher|script|timeout".
WIRED="$(awk '
  /^    "[A-Za-z]+": \[/ { ev = $1; gsub(/[":]/, "", ev); m = "" }
  /"matcher":/ { m = $0; sub(/.*"matcher": "/, "", m); sub(/".*/, "", m) }
  /"command":/ { c = $0; sub(/.*\/hooks\//, "", c); sub(/\\".*/, "", c) }
  /"timeout":/ { t = $0; gsub(/[^0-9]/, "", t); print ev "|" m "|" c "|" t }
' "$H")"
want_wired="SessionStart|startup|resume|clear|compact|fork|session-start.sh|30
PreToolUse|Bash|one-suite.sh|150
PreToolUse|Write|Edit|MultiEdit|NotebookEdit|apply_patch|Bash|guard-code.sh|15
PreToolUse|Read|Grep|Glob|Edit|MultiEdit|Write|NotebookEdit|apply_patch|Bash|guard-secrets.sh|15
Stop||stop-remind.sh|10"
assert_eq "$WIRED" "$want_wired" "hooks.json events, matchers, scripts, timeouts"
# Codex edits files with apply_patch: both guards must be matched on that name (Codex lists it explicitly)
for g in guard-code guard-secrets; do
  m="$(printf '%s\n' "$WIRED" | awk -F'|' -v g="$g.sh" '$(NF-1) == g { print }')"
  case "|$m|" in *"|apply_patch|"*) pass ;; *) fail "hooks.json: the $g matcher lacks apply_patch" ;; esac
done
for s in session-start one-suite guard-code guard-secrets stop-remind; do
  assert_contains "$H" "/hooks/$s.sh"
  assert_file "$PLUGIN/hooks/$s.sh"
done
# every command runs through bash (the scripts are not executable) and via the plugin root
n_cmd="$(grep -c '"command":' "$H")"; n_to="$(grep -c '"timeout":' "$H")"
assert_eq "$n_cmd" "5" "hook commands in hooks.json"
assert_eq "$n_to" "$n_cmd" "every hook command has a timeout"
n_ok="$(grep -c '"command": "bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/[a-z-]*\.sh\\""' "$H")"
assert_eq "$n_ok" "$n_cmd" "every command is bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/<script>\""
# one-suite waits up to ONE_SUITE_WAIT (default) seconds; its timeout must be larger
wait_default="$(sed -n 's/.*limit="${ONE_SUITE_WAIT:-\([0-9]*\)}".*/\1/p' "$HOOKS/one-suite.sh" | head -1)"
suite_to="$(printf '%s\n' "$WIRED" | awk -F'|' '$(NF-1) == "one-suite.sh" { print $NF }')"
case "$wait_default" in ''|*[!0-9]*) fail "cannot read the ONE_SUITE_WAIT default from one-suite.sh" ;; *) pass ;; esac
case "$suite_to" in ''|*[!0-9]*) fail "one-suite has no timeout in hooks.json" ;; *)
  [ "$suite_to" -gt "${wait_default:-0}" ] && pass || fail "one-suite timeout $suite_to <= default wait $wait_default" ;; esac
# well-formed JSON (test-only use of python3; plugin code never uses it)
if command -v python3 >/dev/null 2>&1; then
  assert_exit 0 python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$H"
else
  echo "  note: python3 not found, JSON well-formedness of hooks.json not checked"
fi
assert_no_file "$ROOT/install.sh"; assert_no_file "$ROOT/tests/test_install.sh"
assert_not_contains "$ROOT/README.md" 'install.sh'
assert_contains "$ROOT/README.md" '2.1.271'
assert_contains "$ROOT/README.md" '/plugin install feature-dev@claude-plugins-official'
T="$PLUGIN/skills/new-project/templates"
assert_not_contains "$T/code/settings.local.json.tmpl" '"hooks"'
assert_contains "$T/code/settings.local.json.tmpl" '"additionalDirectories"'
assert_not_contains "$T/CLAUDE.md.tmpl" '/bin/'
assert_contains "$T/CLAUDE.md.tmpl" 'undo-step'
assert_contains "$T/CLAUDE.md.tmpl" 'printed at session start'

# migration note: the seven upgrade steps from 0.1
MG="$ROOT/docs/migration-0.2.md"
assert_file "$MG"
assert_contains "$MG" '/plugin install coredev@corekit'
assert_contains "$MG" 'claude plugin disable corekit@synced'
assert_not_contains "$MG" 'see below'
assert_not_contains "$MG" 'TODO'
assert_contains "$MG" 'install-hooks.sh'
assert_contains "$MG" 'session-rules.md'
for n in 1 2 3 4 5 6 7; do assert_contains "$MG" "### Step $n"; done

# migration note 0.3: the rename coredev -> corecrew, effort-picker -> coreeffort
M3="$ROOT/docs/migration-0.3.md"
assert_file "$M3"
assert_contains "$M3" '/plugin install corecrew@corekit'
assert_contains "$M3" '/plugin install coremodel@corekit'
assert_not_contains "$M3" '/coreeffort'
assert_contains "$M3" 'install-hooks.sh'
assert_contains "$M3" 'corecrew-corekit'
assert_contains "$ROOT/README.md" 'docs/migration-0.3.md'

# trigger evals (claude plugin eval): every case has a prompt and a grader; the frontmatter
# description is quoted (a bare ": " breaks the YAML); results stay out of git
for pl in corecrew coreopinion; do
  n=0
  for c in "$ROOT/plugins/$pl/evals"/*/; do
    [ -f "$c/prompt.md" ] || continue
    n=$((n + 1))
    ls "$c"graders/*.md >/dev/null 2>&1 && pass || fail "$c: no grader"
    d="$(sed -n 's/^description: //p' "$c/prompt.md" | head -1)"
    case "$d" in '"'*'"') pass ;; *) fail "$c/prompt.md: description not quoted" ;; esac
  done
  [ "$n" -ge 3 ] && pass || fail "$pl: fewer than 3 trigger eval cases ($n)"
  assert_contains "$ROOT/plugins/$pl/evals/.gitignore" 'results/'
done
# Codex manifest: Codex reads .codex-plugin/plugin.json instead of .claude-plugin/plugin.json, so the
# shared fields must not drift. No root plugin.json: Codex treats it as an AgentPlugin manifest and
# skips the plugin's hooks.
CX="$PLUGIN/.codex-plugin/plugin.json"
assert_file "$CX"
assert_no_file "$PLUGIN/plugin.json"
for k in name version description license; do
  [ -n "$(jf "$P" $k)" ] && assert_eq "$(jf "$CX" $k)" "$(jf "$P" $k)" "$k differs between the Claude and Codex manifests" || fail "no $k in the Claude manifest"
done
assert_eq "$(jf "$CX" displayName)" "$(jf "$P" displayName)" "displayName differs"
for k in hooks skills userConfig extensions mcpServers; do assert_not_contains "$CX" "\"$k\""; done
bc="$(jf "$CX" brandColor)"
case "$bc" in '#'??????) printf '%s' "${bc#\#}" | grep -qE '^[0-9A-Fa-f]{6}$' && pass || fail "brandColor not #RRGGBB: $bc" ;; *) fail "brandColor not #RRGGBB: $bc" ;; esac
for k in composerIcon logo; do
  v="$(jf "$CX" $k)"
  case "$v" in ./*) pass ;; *) fail "$k must start with ./: $v" ;; esac
  case "$v" in *..*) fail "$k must not hold ..: $v" ;; *) pass ;; esac
  assert_file "$PLUGIN/${v#./}"
done
if command -v python3 >/dev/null 2>&1; then
  assert_exit 0 python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CX"
fi
# Codex ignores disable-model-invocation; agents/openai.yaml is its equivalent. Both or neither.
for sk in "$PLUGIN"/skills/*/SKILL.md; do
  d="$(dirname "$sk")"; nm="$(basename "$d")"
  if grep -qx 'disable-model-invocation: true' "$sk"; then
    assert_contains "$d/agents/openai.yaml" 'allow_implicit_invocation: false'
  else
    assert_no_file "$d/agents/openai.yaml"
  fi
done

finish
