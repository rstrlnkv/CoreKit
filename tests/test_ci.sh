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

# The suite job installs the claude CLI (pinned, through npm: node is on both runners) before the macOS step
# that puts bash 3.2 first, so the tests that need claude run in CI instead of skipping. Its suite step fails
# when the log still says the tests skipped for lack of claude.
suite="$(job "$WF" suite)"
ni="$(printf '%s\n' "$suite" | grep -nE 'npm install -g "?@anthropic-ai/claude-code@' | head -1 | cut -d: -f1)"
nb="$(printf '%s\n' "$suite" | grep -nF 'Use the system bash 3.2' | head -1 | cut -d: -f1)"
nr="$(printf '%s\n' "$suite" | grep -nF 'Run the suite' | head -1 | cut -d: -f1)"
[ -n "$ni" ] && pass || fail "the suite job installs @anthropic-ai/claude-code with npm"
[ -n "$ni" ] && [ -n "$nb" ] && [ "$ni" -lt "$nb" ] && pass || fail "the install step comes before the bash 3.2 step (lines $ni $nb)"
[ -n "$ni" ] && [ -n "$nr" ] && [ "$ni" -lt "$nr" ] && pass || fail "the install step comes before the suite run (lines $ni $nr)"
case "$suite" in *'CLAUDE_VERSION:'*) pass ;; *) fail "the claude version is pinned in env (CLAUDE_VERSION)" ;; esac
for v in DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do case "$suite" in *"$v: 1"*) pass ;; *) fail "$v: 1 in the suite env" ;; esac; done
run="$(printf '%s\n' "$suite" | awk '/Run the suite/{f=1} f')"
case "$run" in *'claude not on PATH'*) pass ;; *) fail "the suite step fails on a claude skip (grep for: claude not on PATH)" ;; esac
# The suite runs one file per core (run.sh starts the largest files first), its output still teed for the skip greps.
case "$run" in *'bash tests/run.sh -j "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" 2>&1 | tee'*) pass ;;
  *) fail "the suite step runs tests/run.sh -j <cores> and tees its output" ;; esac

# The suite job installs the codex CLI on macos-latest only (Decision 20 (b): the sandbox tests expect the macOS
# seatbelt text), pinned, before the bash 3.2 step; on macOS its suite step fails on a codex skip, including
# test_codex_chain.sh's own skip texts.
ci="$(printf '%s\n' "$suite" | grep -nE 'npm install -g "?@openai/codex@' | head -1 | cut -d: -f1)"
[ -n "$ci" ] && pass || fail "the suite job installs @openai/codex with npm"
[ -n "$ci" ] && [ -n "$nb" ] && [ "$ci" -lt "$nb" ] && pass || fail "the codex install step comes before the bash 3.2 step (lines $ci $nb)"
cstep="$(printf '%s\n' "$suite" | awk '/- name: Install the codex CLI/{f=1; print; next} f && /- name:/{f=0} f')"
case "$cstep" in *"if: runner.os == 'macOS'"*) pass ;; *) fail "the codex install step runs on macOS only" ;; esac
case "$suite" in *'CODEX_VERSION:'*) pass ;; *) fail "the codex version is pinned in env (CODEX_VERSION)" ;; esac
case "$suite" in *'@openai/codex@${CODEX_VERSION}'*) pass ;; *) fail "the codex install uses CODEX_VERSION" ;; esac
case "$run" in *'codex (or python3 )?not on PATH|codex debug models --bundled failed'*) pass ;;
  *) fail "the suite step fails on a codex skip (grep -E for: codex (or python3 )?not on PATH|codex debug models --bundled failed)" ;; esac
case "$run" in *'RUNNER_OS'*'macOS'*) pass ;; *) fail "the codex skip check is gated on macOS (RUNNER_OS)" ;; esac

# The commit-subjects job: the whole history is fetched, the range is passed through env (never ${{ }} inside run:),
# and only the new commits are checked.
cs="$(job "$WF" commit-subjects)"
[ -n "$cs" ] && pass || fail "a commit-subjects job"
case "$cs" in *'fetch-depth: 0'*) pass ;; *) fail "commit-subjects: fetch-depth: 0" ;; esac
case "$cs" in *'scripts/commit-subjects.sh --range'*) pass ;; *) fail "commit-subjects: runs scripts/commit-subjects.sh --range" ;; esac
runs="$(printf '%s\n' "$cs" | awk '/^        run: \|/{f=1; next} f && /^        [a-z-]+:/{f=0} f')"
[ -n "$runs" ] && pass || fail "commit-subjects: a run block"
case "$runs" in *'${{'*) fail "commit-subjects: an expression inside run: (pass inputs through env:)" ;; *) pass ;; esac
for v in EVENT BEFORE PR_BASE PR_HEAD DEFAULT_BRANCH; do case "$cs" in *"$v: "*) pass ;; *) fail "commit-subjects: env $v" ;; esac; done
# The ShellCheck job also covers the repo-level scripts/
grep -qE '^ *find plugins tests scripts |^ *find .*\bscripts\b.*-prune' "$WF" && pass || fail "the shellcheck find roots name scripts"

finish
