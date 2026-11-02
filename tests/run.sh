#!/usr/bin/env bash
# Runs every tests/test_*.sh; exits non-zero if any fails.
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do bash "$t" || rc=1; done
[ $rc -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $rc
