#!/usr/bin/env bash
# The effort-picker plugin: validate its manifest and module, run its own tests (claude plugin test).
# Skipped, not failed, where the claude CLI is missing: the suite needs no network or Claude Code.
source "$(dirname "$0")/lib.sh"
P="$ROOT/plugins/effort-picker"
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP effort-picker: claude not on PATH"
  exit 0
fi
assert_dir "$P"
assert_exit 0 claude plugin validate "$P"
assert_exit 0 claude plugin test "$P"
finish
