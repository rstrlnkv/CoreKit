#!/usr/bin/env bash
# The CI workflow (.github/workflows/tests.yml), read with awk and grep: what it runs on and what its jobs do.
source "$(dirname "$0")/lib.sh"
WF="$ROOT/.github/workflows/tests.yml"
assert_file "$WF"

# block <file> <key> — a top-level block: from the line `<key>:` to the next line that does not start with a space
block() { awk -v k="$2" '$0 == k ":" {f=1; next} f && /^[^ ]/ {f=0} f' "$1"; }
# job <file> <name> — one job under `jobs:`: from `  <name>:` to the next job key (two spaces, a letter)
job() { awk -v n="$2" '$0 == "  " n ":" {f=1; next} f && /^  [a-z]/ {f=0} f' "$1"; }

# Runs on a push of any branch (not a tag-only push: ship pushes tags after the run) and on a pull request,
# so a red run is seen before the branch lands on the default branch.
on="$(block "$WF" on)"
case "$on" in *'branches: [main]'*) fail "on: still limited to main" ;; *) pass ;; esac
case "$on" in *'push:'*"branches: ['**']"*) pass ;; *) fail "on: push of every branch (branches: ['**'])" ;; esac
case "$on" in *'pull_request:'*) pass ;; *) fail "on: pull_request" ;; esac
# A newer push to a branch cancels its stale run; runs on the default branch always finish.
grep -q '^concurrency:' "$WF" && pass || fail "a top-level concurrency block"
cc="$(block "$WF" concurrency)"
case "$cc" in *'cancel-in-progress:'*"!= 'refs/heads/main'"*) pass ;; *) fail "concurrency cancels a branch run, never one on main" ;; esac
# The matrix line stays on one line: a docs check parses it.
grep -qF 'os: [macos-latest, ubuntu-latest]' "$WF" && pass || fail "the os matrix on one line"

finish
