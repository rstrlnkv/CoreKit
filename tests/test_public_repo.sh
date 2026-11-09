#!/usr/bin/env bash
# The public-repository standard (<Core>/standards/public-repository.md), checks 1 to 4, which run offline:
# the root files, no loose code at the root, nothing rule 2 keeps out, no CHANGELOG translation and the
# order of the required README.md headings, all read from the tracked files. Rule 4 binds the plugin READMEs too (one shape for all three): `# <Name>`, a one-line description,
# one line of shields.io badges (platform, release, licence), then ## Install, ## Features (opening
# with a `| Feature | What it does |` table), ## Requirements, ## Development, ## Licence, in that order.
# Nothing in a plugin is built, so a plugin README says Development, never Build from source.
# The repo description against README.md line 3 is checked in tests/test_manifest.sh.
source "$(dirname "$0")/lib.sh"

# outside_fences <file> — its lines outside ``` fences (a fence may be indented, inside a list)
outside_fences() { LC_ALL=C awk '/^[[:space:]]*```/ { inb = !inb; next } !inb' "$1"; }

# req_headings <file> — the required ## headings of rule 4 the file has, in its order, joined by |
req_headings() {
  outside_fences "$1" | LC_ALL=C grep -E '^## (Install|Features|Requirements|Build from source|Development|Licence)$' \
    | LC_ALL=C tr '\n' '|' | LC_ALL=C sed 's/|$//'
}

# section_of <file> <heading> — the lines under the heading, up to the next heading of its level or higher
section_of() {
  LC_ALL=C awk -v h="$2" '
    $0 == h { s = 1; lv = index(h, " "); next }
    s && /^#+ / { if (index($0, " ") <= lv) exit }
    s' "$1"
}

# badge <line> <alt> — the URL of the ![alt](...) image on the line
badge() { printf '%s\n' "$1" | LC_ALL=C grep -oE "!\[$2\]\([^)]*\)" | LC_ALL=C sed -E 's/^[^(]*\(//; s/\)$//'; }

# plugin_readme_problems <README> — one line per way the plugin README breaks the shape; nothing when it fits.
# The plugin is the folder that holds the README.
plugin_readme_problems() {
  local f="$1" pl got line3 bl b ver
  pl="$(basename "$(dirname "$f")")"
  got="$(req_headings "$f")"
  [ "$got" = '## Install|## Features|## Requirements|## Development|## Licence' ] \
    || echo "required headings out of shape: $got"
  sed -n 1p "$f" | LC_ALL=C grep -qE '^# [^ ]' || echo "line 1 is not # <Name>"
  [ -z "$(sed -n 2p "$f")" ] || echo "line 2 is not blank"
  line3="$(sed -n 3p "$f")"
  case "$line3" in ''|'#'*|'!['*|'|'*) echo "line 3 is not a one-line description" ;; esac
  bl="$(LC_ALL=C awk 'NR > 3 && NF { print; exit }' "$f")"
  printf '%s\n' "$bl" | LC_ALL=C grep -qE '^(!\[[^]]*\]\(https://img\.shields\.io/[^)[:space:]]*\) ?)+$' \
    || echo "the first line after the description is not a line of shields.io badges"
  for b in platform release licence; do
    [ -n "$(badge "$bl" "$b")" ] || echo "no $b badge"
  done
  badge "$bl" release | LC_ALL=C grep -qF "plugins%2F$pl%2F.claude-plugin%2Fplugin.json" \
    || echo "the release badge does not read plugins/$pl/.claude-plugin/plugin.json"
  # the platform badge names the Claude Code version that Requirements asks for
  ver="$(badge "$bl" platform | LC_ALL=C grep -oE 'Claude%20Code%20[0-9]+\.[0-9]+\.[0-9]+' | LC_ALL=C sed 's/.*%20//')"
  if [ -z "$ver" ]; then echo "the platform badge names no Claude Code version"
  else section_of "$f" '## Requirements' | LC_ALL=C grep -qF -- "$ver" \
    || echo "the platform badge names Claude Code $ver, Requirements does not"
  fi
  [ "$(section_of "$f" '## Features' | LC_ALL=C awk 'NF { print; exit }')" = '| Feature | What it does |' ] \
    || echo "## Features does not open with a | Feature | What it does | table"
}

# repo_problems <repo> — one line per way the tracked files break checks 1 to 4 of the standard; nothing when
# they fit: the root files (1), no loose code at the root (1), nothing rule 2 keeps out (2), no CHANGELOG
# translation, a plugin's included (3), the required headings of README.md in order (4)
repo_problems() {
  local files f got
  files="$(git -C "$1" ls-files)"
  for f in README.md LICENSE CHANGELOG.md SECURITY.md ARCHITECTURE.md; do
    printf '%s\n' "$files" | LC_ALL=C grep -qxF "$f" || echo "missing $f"
  done
  printf '%s\n' "$files" | LC_ALL=C grep -v / | LC_ALL=C grep -E '\.(swift|cs|py|js|ts|go|rs|c|cpp|h|m|sh|cmd)$' \
    | LC_ALL=C grep -vx 'Package.swift' | LC_ALL=C sed 's/^/loose code at the root: /'
  printf '%s\n' "$files" | LC_ALL=C grep -iE '^(Architecture|design|\.superpowers)/|^release-[^/]*\.md$' \
    | LC_ALL=C sed 's/^/tracked, rule 2 keeps it out: /'
  printf '%s\n' "$files" | LC_ALL=C grep -E '(^|/)CHANGELOG\.[^/]+\.md$' | LC_ALL=C sed 's/^/a CHANGELOG translation: /'
  got="$(req_headings "$1/README.md")"
  printf '%s\n' "$got" | LC_ALL=C grep -qxE '## Install\|## Features\|## Requirements\|## (Build from source|Development)\|## Licence' \
    || echo "README.md required headings out of order: $got"
}

out="$(repo_problems "$ROOT")"
[ -z "$out" ] && pass || fail "$out"

for f in "$ROOT"/plugins/*/README.md; do
  out="$(plugin_readme_problems "$f")"
  [ -z "$out" ] && pass || fail "${f#"$ROOT"/}: $out"
done

# --- self-check: a README in shape passes; each kind of error is caught
new_sandbox
mkdir -p "$SANDBOX/plugins/x"
X="$SANDBOX/plugins/x/README.md"
REL='https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fexample.org%2Fplugins%2Fx%2F.claude-plugin%2Fplugin.json&query=%24.version&label=release'
good() {
  printf '%s\n' '# X' '' 'Does one thing.' '' \
    "![platform](https://img.shields.io/badge/platform-Claude%20Code%202.1.271%2B-lightgrey) ![release]($REL) ![licence](https://img.shields.io/github/license/o/r)" \
    '' 'More words.' '' '## Install' '' '```' '## Licence' '```' '' '## Features' '' '| Feature | What it does |' '|---|---|' \
    '| a | b |' '' '### More' '' '## Requirements' '' '- **Claude Code** 2.1.271 or newer' '' '### Detail' '' \
    '## Uninstall' '' '## Development' '' '## Licence' '' 'MIT'
}
caught() {   # caught <what> <sed script> — the planted error is reported
  good | LC_ALL=C sed -e "$2" > "$X"
  [ -n "$(plugin_readme_problems "$X")" ] && pass || fail "self-check: $1 passes"
}
good > "$X"
assert_eq "$(plugin_readme_problems "$X")" "" "self-check: a README in shape"
caught "a two-line description" '4s/^$/and a second line./'
caught "no badge line" '5d'
caught "a badge off shields.io" '5s|img\.shields\.io/github|example.org/github|'
caught "no licence badge" '5s| !\[licence\].*||'
caught "a release badge of another plugin" '5s|%2Fx%2F|%2Fy%2F|'
caught "a platform version Requirements lacks" '5s|2\.1\.271|2.1.300|'
caught "Build from source" 's/^## Development$/## Build from source/'
caught "a swapped heading order" 's/^## Requirements$/## TMP/; s/^## Features$/## Requirements/; s/^## TMP$/## Features/'
caught "Features without the table" 's/^| Feature | What it does |$/| Word | Meaning |/'
caught "no Licence heading" 's/^## Licence$/## License/'

# the repo checks: a repo in shape passes; each planted error is reported (plant <what> <command>, run in a fresh repo)
make_repo() {
  rm -rf "$SANDBOX/r"; mkdir -p "$SANDBOX/r/scripts" && git -C "$SANDBOX/r" init -q
  printf '%s\n' '# R' '' 'Does one thing.' '' '## Install' '## Features' '## Requirements' '## Uninstall' \
    '## Build from source' '## Licence' > "$SANDBOX/r/README.md"
  for f in LICENSE CHANGELOG.md SECURITY.md ARCHITECTURE.md Package.swift scripts/run.sh; do
    printf 'x\n' > "$SANDBOX/r/$f"
  done
  printf '.DS_Store\n' > "$SANDBOX/r/.gitignore"; git -C "$SANDBOX/r" add -A
}
plant() {
  make_repo
  ( cd "$SANDBOX/r" && eval "$2" && git add -A )
  [ -n "$(repo_problems "$SANDBOX/r")" ] && pass || fail "self-check: $1 passes"
}
make_repo
assert_eq "$(repo_problems "$SANDBOX/r")" "" "self-check: a repo in shape"
plant "a missing LICENSE" 'git rm -q --cached LICENSE && rm LICENSE'
plant "loose code at the root" 'printf x > tool.sh'
plant "a tracked design/x" 'mkdir design && printf x > design/x'
plant "a tracked Architecture/ page" 'mkdir Architecture && printf x > Architecture/a.md'
plant "a tracked .superpowers/ file" 'mkdir .superpowers && printf x > .superpowers/a'
plant "a release-note draft" 'printf x > release-1.0.md'
plant "a CHANGELOG translation" 'printf x > CHANGELOG.ru.md'
plant "a plugin CHANGELOG translation" 'mkdir -p plugins/p && printf x > plugins/p/CHANGELOG.ru.md'
plant "a swapped heading order" "sed -e 's/^## Features\$/## T/; s/^## Requirements\$/## Features/; s/^## T\$/## Requirements/' README.md > R && mv R README.md"
finish
