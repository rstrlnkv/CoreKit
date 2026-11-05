#!/usr/bin/env bash
# Runs every tests/test_*.sh; exits non-zero if any fails.
cd "$(dirname "$0")" || exit 1
rc=0
skipped=""
for t in test_*.sh; do
  out="$(bash "$t" 2>&1)" || rc=1
  [ -n "$out" ] && printf '%s\n' "$out"
  # a whole file that skipped (a tool is missing) is named in the summary, not hidden behind PASSED
  s="$(printf '%s\n' "$out" | sed -n 's/^SKIP \([^:]*\):.*/\1/p' | head -1)"
  [ -n "$s" ] && skipped="${skipped:+$skipped, }$s"
done
if [ $rc -eq 0 ]; then
  if [ -n "$skipped" ]; then echo "ALL TESTS PASSED (skipped: $skipped)"; else echo "ALL TESTS PASSED"; fi
else
  echo "SOME TESTS FAILED"
fi
exit $rc
