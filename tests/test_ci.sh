#!/usr/bin/env bash
# The CI workflow (.github/workflows/tests.yml), read with awk and grep: what it runs on and what its jobs do.
source "$(dirname "$0")/lib.sh"
new_sandbox
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
# when the log holds a SKIP line that names claude.
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
# the claude check is the step's if-block whose grep names claude; like the codex one it greps run.sh's SKIP lines
# for claude anywhere in them, not for one chosen skip text, and it is not gated on the OS: both runners install claude
cl="$(printf '%s\n' "$run" | awk '/^ *if grep .*claude/{f=1} f; f && /^ *fi$/{exit}')"
case "$cl" in *"grep -E '^SKIP .*claude' "*) pass ;; *) fail "the suite step fails on every claude skip (grep -E '^SKIP .*claude')" ;; esac
case "$cl" in *'not on PATH'*) fail "the claude skip check still names a chosen skip text" ;; *) pass ;; esac
case "$cl" in *'RUNNER_OS'*) fail "the claude skip check is gated on an OS" ;; *) pass ;; esac
case "$cl" in *'exit 1'*) pass ;; *) fail "the claude skip check exits 1" ;; esac
clstep="$(printf '%s\n' "$suite" | awk '/- name: Install the claude CLI/{f=1; print; next} f && /- name:/{f=0} f')"
[ -n "$clstep" ] && pass || fail "the claude install step (Install the claude CLI)"
printf '%s\n' "$clstep" | grep -qE '^ *if:' && fail "the claude install step runs on both runners (no if:)" || pass
# The suite runs one file per core (run.sh starts the largest files first), its output still teed for the skip greps.
case "$run" in *'bash tests/run.sh -j "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" 2>&1 | tee'*) pass ;;
  *) fail "the suite step runs tests/run.sh -j <cores> and tees its output" ;; esac
# The pipe to tee needs `shell: bash`: GitHub runs an explicit `shell: bash` with -eo pipefail; the default shell is
# `bash -e`, where the pipeline's status is tee's and a red suite would pass.
rstep="$(printf '%s\n' "$suite" | awk '/- name: Run the suite/{f=1; print; next} f && /- name:/{f=0} f')"
printf '%s\n' "$rstep" | grep -qE '^ *shell: bash$' && pass || fail "the 'Run the suite' step holds shell: bash (pipefail for the pipe to tee)"

# The suite job installs the codex CLI on macos-latest only (Decision 20 (b): the sandbox tests expect the macOS
# seatbelt text), pinned, before the bash 3.2 step; on macOS its suite step fails on every skip that names codex
# (R3-35): a missing CLI, a failed catalog, a nested sandbox or a root user all leave codex parts unchecked.
ci="$(printf '%s\n' "$suite" | grep -nE 'npm install -g "?@openai/codex@' | head -1 | cut -d: -f1)"
[ -n "$ci" ] && pass || fail "the suite job installs @openai/codex with npm"
[ -n "$ci" ] && [ -n "$nb" ] && [ "$ci" -lt "$nb" ] && pass || fail "the codex install step comes before the bash 3.2 step (lines $ci $nb)"
cstep="$(printf '%s\n' "$suite" | awk '/- name: Install the codex CLI/{f=1; print; next} f && /- name:/{f=0} f')"
case "$cstep" in *"if: runner.os == 'macOS'"*) pass ;; *) fail "the codex install step runs on macOS only" ;; esac
case "$suite" in *'CODEX_VERSION:'*) pass ;; *) fail "the codex version is pinned in env (CODEX_VERSION)" ;; esac
case "$suite" in *'@openai/codex@${CODEX_VERSION}'*) pass ;; *) fail "the codex install uses CODEX_VERSION" ;; esac
# the macOS check is the step's if-block that names RUNNER_OS; it greps run.sh's SKIP lines for codex anywhere in
# them (a file name such as test_codex_chain.sh counts), not for chosen skip texts
mac="$(printf '%s\n' "$run" | awk '/^ *if .*RUNNER_OS/{f=1} f; f && /^ *fi$/{exit}')"
case "$mac" in *'macOS'*) pass ;; *) fail "the codex skip check is gated on macOS (RUNNER_OS)" ;; esac
case "$mac" in *"grep -E '^SKIP .*codex' "*) pass ;; *) fail "on macOS the suite step fails on every codex skip (grep -E '^SKIP .*codex')" ;; esac
case "$mac" in *'not on PATH'*|*'--bundled failed'*) fail "the macOS codex check still names chosen skip texts" ;; *) pass ;; esac
case "$mac" in *'exit 1'*) pass ;; *) fail "the macOS codex check exits 1" ;; esac

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
# "Quote paths" in the shipped scripts: a second ShellCheck call, fed from the plugins/ entries of the same list,
# reports every unquoted expansion (SC2086, an info-level note the first call leaves out)
sc="$(job "$WF" shellcheck)"
printf '%s\n' "$sc" | grep -F -- '--include=SC2086' | grep -E "^ *grep '\\^plugins/' " | grep -qF -- '--severity=info' \
  && pass || fail "the shellcheck job runs --severity=info --include=SC2086 over the plugins/ entries of the file list"
case "$sc" in *"xargs -0 shellcheck --severity=warning"*) pass ;; *) fail "the shellcheck job still runs --severity=warning over every shell file" ;; esac

finish
