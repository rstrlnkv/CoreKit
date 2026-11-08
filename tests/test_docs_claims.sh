#!/usr/bin/env bash
# The public docs' claims about what CI runs. The suite matrix in .github/workflows/tests.yml is the
# source: a doc that calls one of its systems untested, or "expected to work", has drifted, and the
# README's "tested on" badge must name each of them. Nothing here reads a literal list of systems.
source "$(dirname "$0")/lib.sh"
WF="$ROOT/.github/workflows/tests.yml"
assert_file "$WF"

docs=""
for d in README.md README.*.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/*/README.md plugins/*/README.*.md docs/*.md; do
  [ -f "$ROOT/$d" ] && docs="$docs $d"
done

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
finish
