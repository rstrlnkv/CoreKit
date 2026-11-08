#!/usr/bin/env bash
# `claude plugin validate` for the marketplace and each plugin. Skipped where the claude CLI is missing;
# CI installs it, and its suite step fails when this skip line shows up there.
source "$(dirname "$0")/lib.sh"
if ! command -v claude >/dev/null 2>&1; then skip plugin-validate "claude not on PATH"; finish; fi
new_sandbox   # validate writes $HOME/.claude.json: never the developer's
assert_exit 0 claude plugin validate "$ROOT"
for p in corecrew coremodel coreopinion; do
  assert_exit 0 claude plugin validate "$ROOT/plugins/$p"
done
finish
