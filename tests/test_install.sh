#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
export CLAUDE_SKILLS_DIR="$SANDBOX/skills"
mkdir -p "$CLAUDE_SKILLS_DIR/other-skill"; echo keep > "$CLAUDE_SKILLS_DIR/other-skill/SKILL.md"
assert_exit 0 bash "$ROOT/install.sh"
assert_file "$CLAUDE_SKILLS_DIR/new-project/SKILL.md"
assert_file "$CLAUDE_SKILLS_DIR/new-project/scripts/scaffold.sh"
echo "$OUT" | grep -q "$CLAUDE_SKILLS_DIR/new-project" && pass || fail "path not printed"
# stale file from an old version is removed on reinstall; other skills untouched
echo old > "$CLAUDE_SKILLS_DIR/new-project/stale.md"
assert_exit 0 bash "$ROOT/install.sh"
assert_no_file "$CLAUDE_SKILLS_DIR/new-project/stale.md"
assert_eq "$(cat "$CLAUDE_SKILLS_DIR/other-skill/SKILL.md")" "keep"
finish
