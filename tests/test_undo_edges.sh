#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
bash "$SKILL/scripts/scaffold.sh" --name edge-app >/dev/null
C="$CORE_DIR/edge-app/code"; SAVE="$CORE_DIR/bin/save"; UNDO="$CORE_DIR/bin/undo-step"
cd "$C" || exit 1
bash "$SAVE" "Scaffold" >/dev/null
# two saves within the same second get different Step-Ids
echo a > a.txt; bash "$SAVE" "Step A" >/dev/null
echo b > b.txt; bash "$SAVE" "Step B" >/dev/null
ids=$(git log --format=%B | sed -n 's/^Step-Id: //p' | sort -u | wc -l | tr -d ' ')
assert_eq "$ids" "3" "Step-Ids must be unique"
bash "$UNDO" >/dev/null
assert_file "$C/a.txt"; assert_no_file "$C/b.txt"
# the very first step (project creation) cannot be undone; shared Core files survive
bash "$UNDO" >/dev/null; assert_no_file "$C/a.txt"
assert_exit 1 bash "$UNDO"
echo "$OUT" | grep -qi 'first step' && pass || fail "no first-step message"
assert_file "$CORE_DIR/bin/save"; assert_file "$CORE_DIR/edge-app/CLAUDE.md"
finish
