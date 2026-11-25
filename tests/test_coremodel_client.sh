#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
assert_exit 0 python3 "$ROOT/tests/coremodel_client.py" "$SANDBOX"
finish
