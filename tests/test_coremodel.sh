#!/usr/bin/env bash
# The coremodel plugin: validate its manifest and module, run its module tests (claude plugin test).
# The module tests live in tests/coremodel/, outside the plugin, so an install does not carry them. They import
# ../hooks/..., so they run on a copy of the plugin assembled in the sandbox with them as its tests/ folder.
# Skipped, not failed, where the claude CLI is missing: the suite needs no network or Claude Code.
# Runs in a sandbox: `claude plugin test` writes $HOME/.claude.json, which must not be the developer's.
source "$(dirname "$0")/lib.sh"
P="$ROOT/plugins/coremodel"
# the `language` setting offers auto and one value per locale file, nothing more or less
LANG_OPTS="$(awk '/"language": *\{/ { on = 1 } on && /"options"/ { opts = 1; next } opts && /\]/ { exit } opts { gsub(/[ ",]/, ""); if ($0 != "") print }' "$P/.claude-plugin/plugin.json" | LC_ALL=C sort | tr '\n' ' ')"
LOCALE_FILES="$( (echo auto; for f in "$P"/hooks/locales/*.ts; do basename "$f" .ts; done) | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "$LANG_OPTS" "$LOCALE_FILES" "plugin.json language options vs hooks/locales/*.ts"
if ! command -v claude >/dev/null 2>&1; then skip coremodel "claude not on PATH"; finish; fi
new_sandbox
assert_dir "$P"
assert_exit 0 claude plugin validate "$P"
# every gating hook has a .catch: a hook that throws must not stop the chat's own handling
V="$(claude plugin validate "$P" 2>&1)"
printf '%s' "$V" | grep -q "gating hook without .catch" && fail "gating hook without .catch: $(printf '%s' "$V" | grep "without .catch")" || pass
# validate reads the shipped tree; the module tests run on the assembled copy
cp -R "$P" "$SANDBOX/coremodel" && cp -R "$ROOT/tests/coremodel" "$SANDBOX/coremodel/tests" && pass || fail "cannot assemble the copy"
assert_exit 0 claude plugin test "$SANDBOX/coremodel"
# the plugin test wrote into the sandbox HOME, nowhere else
assert_file "$HOME/.claude.json"
finish
