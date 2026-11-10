#!/usr/bin/env bash
# The public docs' claims about what CI runs. The suite matrix in .github/workflows/tests.yml is the
# source: a doc that calls one of its systems untested, or "expected to work", has drifted, and the
# README's "tested on" badge must name each of them. Nothing here reads a literal list of systems.
source "$(dirname "$0")/lib.sh"
WF="$ROOT/.github/workflows/tests.yml"
assert_file "$WF"

# The documents, one glob a line; "optional" marks a glob that may match nothing (the translations).
# run.sh runs this file from tests/, so every glob expands under the root it is given, never the cwd.
CLAIM_GLOBS='README.md
README.*.md optional
SECURITY.md
ARCHITECTURE.md
CONTRIBUTING.md
plugins/*/README.md
plugins/*/README.*.md optional
docs/*.md'
# claim_docs <root> <glob> — the files of <glob> under <root>, relative to it
claim_docs() {
  local f
  # shellcheck disable=SC2086 # $2 is a glob on purpose; the root is quoted, so its own characters stay literal
  for f in "$1"/$2; do [ -f "$f" ] && printf '%s\n' "${f#"$1"/}"; done
}
docs=""
while read -r g opt; do
  got="$(claim_docs "$ROOT" "$g")"
  # a required glob that finds nothing has stopped expanding (or its files moved): nothing of it would be checked
  [ -n "$got" ] || [ "$opt" = optional ] && pass || fail "the document glob $g finds no file under the repo root"
  docs="$docs $got"
done <<< "$CLAIM_GLOBS"

# ci_oses <workflow> — the systems of the suite matrix (one line `os: [a, b]`), named as the docs name
# them: macos-* -> macOS, ubuntu-* -> Linux, windows-* -> Windows; anything else as written
ci_oses() {
  sed -n 's/^[[:space:]]*os:[[:space:]]*\[\(.*\)\].*/\1/p' "$1" | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r r; do
        case "$r" in '') ;; macos-*) echo macOS ;; ubuntu-*) echo Linux ;; windows-*) echo Windows ;; *) echo "$r" ;; esac
      done | LC_ALL=C sort -u
}
# untested_claims <file> <os> — the lines that name <os> as a word and call it untested
untested_claims() {
  grep -nw -- "$2" "$1" | grep -iE 'untested|no test run|expected to work|not tested'
}

oses="$(ci_oses "$WF")"
[ -n "$oses" ] && pass || fail "no os matrix found in $WF (did the matrix line move or split?)"
for os in $oses; do
  for doc in $docs; do
    hits="$(untested_claims "$ROOT/$doc" "$os")"
    [ -z "$hits" ] && pass || fail "$doc calls $os untested, but CI runs the suite on it: $hits"
  done
  grep -q "tested%20on-[^)]*$os" "$ROOT/README.md" && pass || fail "README.md: the 'tested on' badge does not name $os"
done

# self-check: the matrix is read as the docs name the systems; a claim is caught for its own system only
new_sandbox
printf 'jobs:\n  suite:\n    strategy:\n      matrix:\n        os: [macos-latest, ubuntu-latest, windows-2022]\n' > "$SANDBOX/wf.yml"
assert_eq "$(ci_oses "$SANDBOX/wf.yml" | tr '\n' ' ')" "Linux Windows macOS " "ci_oses from the matrix line"
printf 'jobs:\n  suite:\n    runs-on: ubuntu-latest\n' > "$SANDBOX/nomatrix.yml"
assert_eq "$(ci_oses "$SANDBOX/nomatrix.yml")" "" "ci_oses without a matrix"
printf '%s\n' '- macOS is tested. Linux is expected to work.' '  Windows is untested.' 'The suite runs on Linux.' > "$SANDBOX/doc.md"
assert_eq "$(untested_claims "$SANDBOX/doc.md" Linux | cut -d: -f1)" "1" "an 'expected to work' claim is caught for Linux"
assert_eq "$(untested_claims "$SANDBOX/doc.md" Windows | cut -d: -f1)" "2" "an 'untested' claim is caught for Windows"
assert_eq "$(untested_claims "$SANDBOX/doc.md" Linux | wc -l | tr -d ' ')" "1" "a plain mention of Linux is not a claim"
# every document glob expands under the root it is given and not under the cwd (run.sh runs from tests/)
DR="$SANDBOX/doc root"
mkdir -p "$DR/plugins/p" "$DR/docs"
for f in README.md README.de.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/p/README.md plugins/p/README.de.md docs/a.md; do
  : > "$DR/$f"
done
got="$(cd "$SANDBOX" && while read -r g _; do claim_docs "$DR" "$g" | tr '\n' ' '; done <<< "$CLAIM_GLOBS")"
assert_eq "$got" "README.md README.de.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/p/README.md plugins/p/README.de.md docs/a.md " \
  "each document glob expands under the given root"

# --- CONTRIBUTING names every knob of tests/run.sh. The header of run.sh is the source: a line "#   <knob> ..."
# whose knob is an option (-j N) or a variable (VERBOSE=1, KEEP_SANDBOX=1). Nothing here reads a literal list of knobs.
run_knobs() { sed -n -E 's/^#   (-[a-z]|[A-Z][A-Z_]*)[= ].*/\1/p' "$1" | LC_ALL=C sort -u; }
# names_knob <file> <knob> — the knob as its own word (not inside another word or a longer option)
names_knob() { grep -qE -- "(^|[^[:alnum:]_-])$2([^[:alnum:]_]|$)" "$1"; }
knobs="$(run_knobs "$ROOT/tests/run.sh")"
[ -n "$knobs" ] && pass || fail "no knob lines in the header of tests/run.sh (did the header change its form?)"
for k in $knobs; do
  names_knob "$ROOT/CONTRIBUTING.md" "$k" && pass || fail "CONTRIBUTING.md does not name the run.sh knob $k"
done
# self-check: knobs are read from the header's form only; a knob must be its own word
printf '%s\n' '#!/usr/bin/env bash' '# Runs the tests.' '#   bash tests/run.sh [-j N] [word ...]' '#   word ...        a filter' \
  '#   -j N            N files at a time' '#   VERBOSE=1       every file' '#   KEEP_SANDBOX=1  keep the folder' 'cd x' > "$SANDBOX/run.sh"
assert_eq "$(run_knobs "$SANDBOX/run.sh" | tr '\n' ' ')" "-j KEEP_SANDBOX VERBOSE " "run_knobs from the header"
printf 'Use `-j 4` and `KEEP_SANDBOX=1`; -jx and XVERBOSE are other words.\n' > "$SANDBOX/c.md"
names_knob "$SANDBOX/c.md" -j && pass || fail "names_knob: -j in backticks"
names_knob "$SANDBOX/c.md" KEEP_SANDBOX && pass || fail "names_knob: KEEP_SANDBOX=1"
names_knob "$SANDBOX/c.md" VERBOSE && fail "names_knob: XVERBOSE counted as VERBOSE" || pass

# --- the Codex CLI version the docs say they were tested with (R4-132) is the one CI installs: CODEX_VERSION in the
# workflow is the source, cut to major.minor. A bump there with the docs left behind fails here.
# codex_tested <workflow> — major.minor of its CODEX_VERSION line (comment lines are not read); empty if there is none
codex_tested() {
  grep -v '^[[:space:]]*#' "$1" | sed -n -E 's/^[[:space:]]*CODEX_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+)\.[0-9]+.*/\1/p' | head -1
}
cxv="$(codex_tested "$WF")"
[ -n "$cxv" ] && pass || fail "no CODEX_VERSION: <major.minor.patch> line in $WF"
for doc in README.md plugins/corecrew/README.md; do
  grep -qF "(tested with $cxv)" "$ROOT/$doc" && pass || fail "$doc does not say '(tested with $cxv)', the Codex CLI that CI installs"
done
# self-check: the version is read from the env line, not from a comment, and cut to major.minor
printf '%s\n' 'jobs:' '  suite:' '    env:' '      # CODEX_VERSION: 9.9.9 was the old one' '      CODEX_VERSION: 0.167.2    # bump on purpose' > "$SANDBOX/cx.yml"
assert_eq "$(codex_tested "$SANDBOX/cx.yml")" "0.167" "codex_tested: major.minor of the env line"
printf '%s\n' '      CODEX_VERSION: "12.3.0"' > "$SANDBOX/cx.yml"
assert_eq "$(codex_tested "$SANDBOX/cx.yml")" "12.3" "codex_tested: a quoted version"
assert_eq "$(codex_tested "$SANDBOX/nomatrix.yml")" "" "codex_tested without the line"
finish
