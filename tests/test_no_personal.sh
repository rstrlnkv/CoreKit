#!/usr/bin/env bash
# Guards this public repo against personal data: absolute home paths, the owner's handle outside
# the places that must carry it, the owner's own standard files, archive project names, and any
# project name listed in the owner's private PROJECTS.md (the list itself never enters the repo).
# Scans tracked files only (git ls-files -z); binary files are skipped.
# This file names the forbidden strings on purpose, so it is the one file the scan skips.
source "$(dirname "$0")/lib.sh"
# The real Core must be found before new_sandbox swaps HOME and CORE_DIR. It is only read.
REAL_CORE="${CORE_DIR:-$HOME/Projects/Core}"
new_sandbox

SELF="tests/test_no_personal.sh"
# Words that are also part of this repo's own vocabulary: never a "personal" project name.
GENERIC='core corekit coredev test-coredev demo test tests example examples sample project projects code docs todo hello world'

# project_names <PROJECTS.md> — one name per line, from list items "- <name> — <purpose> — <path>".
# Drops names under 4 characters and generic words. Names are only ever written to a file.
project_names() {
  [ -f "$1" ] || return 0
  sed -n 's/^[-*][[:space:]][[:space:]]*//p' "$1" | sed 's/[[:space:]]*—.*$//; s/[[:space:]]*$//' |
    while IFS= read -r n; do
      [ "${#n}" -ge 4 ] || continue
      low="$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')"
      case " $GENERIC " in *" $low "*) continue ;; esac
      printf '%s\n' "$n"
    done
}

# is_binary <file> — true when the file holds a NUL byte
is_binary() { [ "$(LC_ALL=C tr -d '\000' < "$1" | wc -c)" != "$(wc -c < "$1")" ]; }

# lines <label> <rel> <grep args...> — "<rel>:<line>: <label>" per matching line (never the text)
lines() {
  local label="$1" rel="$2"; shift 2
  grep -n "$@" 2>/dev/null | sed "s|:.*||" | while IFS= read -r ln; do
    echo "$rel:$ln: $label"
  done
}

# scan_repo <root> <names-file> — checks every tracked text file of the repo at <root>.
# <names-file> may be empty or missing: then the PROJECTS.md check is skipped.
scan_repo() {
  local root="$1" names="$2"
  git -C "$root" ls-files -z | while IFS= read -r -d '' rel; do
    local f="$root/$rel"
    [ "$rel" = "$SELF" ] && continue
    [ -f "$f" ] || continue
    is_binary "$f" && continue
    case "$rel" in
      docs/specs/*|docs/plans/*|CHANGELOG.md) ;;
      *) lines "absolute home path (/Users/ or /home/)" "$rel" -E '/Users/|/home/' "$f" ;;
    esac
    case "$rel" in
      .claude-plugin/*.json|README.md|LICENSE|CHANGELOG.md|docs/*) ;;
      plugins/*/.claude-plugin/*.json|plugins/*/README.md|plugins/*/CHANGELOG.md) ;;
      *) lines "owner handle outside manifests, README, LICENSE, CHANGELOG, docs" "$rel" -iF 'rstrlnkv' "$f" ;;
    esac
    case "$rel" in
      skills/*|agents/*|reference/*)
        lines "owner standard file name" "$rel" -E 'versioning\.md|about-screen\.md' "$f" ;;
    esac
    case "$rel" in
      docs/specs/*|docs/plans/*) ;;
      *) lines "archive project name" "$rel" -wE 'Helm|Mafia' "$f" ;;
    esac
    case "$rel" in
      docs/*) ;;
      *) [ -s "$names" ] && lines "a project name from PROJECTS.md" "$rel" -iwF -f "$names" "$f" ;;
    esac
  done
}

# --- Self-check: plant every kind of leak in a throwaway repo; each must be caught once. -------
R="$SANDBOX/repo"
mkdir -p "$R/docs/specs" "$R/docs/plans" "$R/skills/s" "$R/tests" "$R/.claude-plugin"
git -C "$R" init -q
H=/Users; U="$H/someone/x"; V="/ho""me/someone"          # built here so this file stays clean
printf 'path %s\n' "$U" > "$R/tests/leak-path.sh"          # hit: home path
printf 'path %s\n' "$V" > "$R/skills/s/leak-home.md"       # hit: home path
printf 'path %s\n' "$U" > "$R/docs/specs/ok.md"            # allowed: specs
printf 'path %s\n' "$U" > "$R/docs/plans/ok.md"            # allowed: plans
printf 'path %s\n' "$U" > "$R/CHANGELOG.md"                # allowed: changelog
printf 'owner rstrlnkv\n' > "$R/skills/s/handle.md"        # hit: handle
printf 'owner rstrlnkv\n' > "$R/README.md"                 # allowed
printf '{"owner":"rstrlnkv"}\n' > "$R/.claude-plugin/plugin.json"   # allowed
printf 'owner rstrlnkv\n' > "$R/LICENSE"                   # allowed
mkdir -p "$R/plugins/p/.claude-plugin" "$R/plugins/p/hooks"
printf '{"owner":"rstrlnkv"}\n' > "$R/plugins/p/.claude-plugin/plugin.json"   # allowed: a plugin's manifest
printf 'owner rstrlnkv\n' > "$R/plugins/p/README.md"       # allowed: a plugin's README
printf 'owner rstrlnkv\n' > "$R/plugins/p/CHANGELOG.md"    # allowed: a plugin's CHANGELOG
printf 'owner rstrlnkv\n' > "$R/plugins/p/hooks/h.ts"      # hit: a plugin's code
printf 'see versioning.md\n' > "$R/skills/s/std.md"         # hit: owner standard
printf 'see about-screen.md\n' > "$R/docs/ok2.md"          # allowed: outside skills/agents/reference
printf 'a Helm chart\n' > "$R/skills/s/old.md"             # hit: archive name
printf 'a helmet\n' > "$R/skills/s/fine.md"                # fine: not a whole word
printf 'Mafia notes\n' > "$R/docs/plans/old.md"            # allowed: plans
printf 'Mafia game\n' > "$R/docs/ok3.md"                   # hit: docs/ is not specs/plans
printf 'x\000%s\n' "$U" > "$R/skills/s/blob.bin"           # skipped: binary
printf 'path %s\n' "$U" > "$R/tests/a b.sh"                # hit: name with a space
git -C "$R" add -A >/dev/null
printf 'path %s\n' "$U" > "$R/untracked.sh"                # not tracked: not scanned
hits="$(scan_repo "$R" "" | LC_ALL=C sort | tr '\n' ';')"
assert_eq "$hits" "docs/ok3.md:1: archive project name;plugins/p/hooks/h.ts:1: owner handle outside manifests, README, LICENSE, CHANGELOG, docs;skills/s/handle.md:1: owner handle outside manifests, README, LICENSE, CHANGELOG, docs;skills/s/leak-home.md:1: absolute home path (/Users/ or /home/);skills/s/old.md:1: archive project name;skills/s/std.md:1: owner standard file name;tests/a b.sh:1: absolute home path (/Users/ or /home/);tests/leak-path.sh:1: absolute home path (/Users/ or /home/);" "planted leaks"

# PROJECTS.md self-check: fake list, fake names; a name never shows up in the output.
FAKE="$SANDBOX/fake-PROJECTS.md"
cat > "$FAKE" <<'EOF'
# Projects

One line per project: name — purpose — path to code.

- Zorblax Quill — fake purpose — Zorblax Quill/code/
- app — too short — app/code/
- Demo — generic word — Demo/code/
- coredev — generic word — coredev/code/
- Frumbly — fake purpose — Frumbly/code/
EOF
project_names "$FAKE" > "$SANDBOX/names"
assert_eq "$(tr '\n' ';' < "$SANDBOX/names")" "Zorblax Quill;Frumbly;" "extracted names"
P="$SANDBOX/repo2"; mkdir -p "$P/skills" "$P/docs"; git -C "$P" init -q
printf 'Uses the zorblax quill library\n' > "$P/skills/leak.md"      # hit: case-insensitive phrase
printf 'a frumbly day\nfrumblyish\n' > "$P/skills/word.md"           # hit line 1 only (whole word)
printf 'app demo coredev test\n' > "$P/skills/generic.md"            # fine: short / generic names
printf 'Frumbly lives here\n' > "$P/docs/ok.md"                      # fine: docs/
git -C "$P" add -A >/dev/null
out="$(scan_repo "$P" "$SANDBOX/names" | LC_ALL=C sort)"
assert_eq "$(echo "$out" | tr '\n' ';')" "skills/leak.md:1: a project name from PROJECTS.md;skills/word.md:1: a project name from PROJECTS.md;" "fake project names"
printf '%s' "$out" | grep -qiE 'zorblax|frumbly' && fail "output leaked a project name" || pass
assert_eq "$(project_names "$SANDBOX/missing.md")" "" "missing PROJECTS.md gives no names"

# --- The real repo ----------------------------------------------------------------------------
if [ -f "$REAL_CORE/PROJECTS.md" ]; then
  # a real check: the names come from the list items (never more names than items)
  project_names "$REAL_CORE/PROJECTS.md" > "$SANDBOX/real-names" \
    && [ "$(wc -l < "$SANDBOX/real-names")" -le "$(grep -c '^[-*][[:space:]]' "$REAL_CORE/PROJECTS.md")" ] \
    && pass || fail "could not read project names from the Core's PROJECTS.md"
else
  : > "$SANDBOX/real-names"
  echo "  note: no PROJECTS.md in the Core; project-name check skipped"
fi
scan_repo "$ROOT" "$SANDBOX/real-names" > "$SANDBOX/real-hits"
[ -s "$SANDBOX/real-hits" ] && fail "personal data in tracked files: $(cat "$SANDBOX/real-hits" | tr '\n' ' ')" || pass
finish
