#!/usr/bin/env bash
# The coremodel plugin: validate its manifest and module, run its own tests (claude plugin test).
# Skipped, not failed, where the claude CLI is missing: the suite needs no network or Claude Code.
# Runs in a sandbox: `claude plugin test` writes $HOME/.claude.json, which must not be the developer's.
source "$(dirname "$0")/lib.sh"
P="$ROOT/plugins/coremodel"
if ! command -v claude >/dev/null 2>&1; then skip coremodel "claude not on PATH"; finish; fi
new_sandbox
assert_dir "$P"
assert_exit 0 claude plugin validate "$P"
# every gating hook has a .catch: a hook that throws must not stop the chat's own handling
V="$(claude plugin validate "$P" 2>&1)"
printf '%s' "$V" | grep -q "gating hook without .catch" && fail "gating hook without .catch: $(printf '%s' "$V" | grep "without .catch")" || pass
assert_exit 0 claude plugin test "$P"
# the plugin test wrote into the sandbox HOME, nowhere else
assert_file "$HOME/.claude.json"
finish
