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

# a same-named skill that CoreKit did not install is left untouched
new_sandbox; export CLAUDE_SKILLS_DIR="$SANDBOX/skills"; D="$CLAUDE_SKILLS_DIR/new-project"
mkdir -p "$D"; echo mine > "$D/SKILL.md"
assert_exit 1 bash "$ROOT/install.sh"
assert_eq "$(cat "$D/SKILL.md")" "mine" "foreign skill overwritten"
echo "$OUT" | grep -q -- "--force" && pass || fail "no hint about --force: $OUT"
# --force replaces it
assert_exit 0 bash "$ROOT/install.sh" --force
assert_file "$D/scripts/scaffold.sh"; assert_file "$D/.corekit"

# a 0.1.0 copy (no marker, same layout) is upgraded
new_sandbox; export CLAUDE_SKILLS_DIR="$SANDBOX/skills"; D="$CLAUDE_SKILLS_DIR/new-project"
mkdir -p "$CLAUDE_SKILLS_DIR"; cp -R "$SKILL" "$D"; rm -f "$D/.corekit"; echo old > "$D/stale.md"
assert_exit 0 bash "$ROOT/install.sh"
assert_no_file "$D/stale.md"; assert_file "$D/.corekit"

# a symlinked skill folder (e.g. to a dev checkout) is not CoreKit's: left as is
new_sandbox; export CLAUDE_SKILLS_DIR="$SANDBOX/skills"; D="$CLAUDE_SKILLS_DIR/new-project"
mkdir -p "$CLAUDE_SKILLS_DIR"; cp -R "$SKILL" "$SANDBOX/dev-skill"; ln -s "$SANDBOX/dev-skill" "$D"
assert_exit 1 bash "$ROOT/install.sh"
[ -L "$D" ] && pass || fail "symlinked skill folder was replaced"
rm "$D"; ln -s "$SANDBOX/missing" "$D"
assert_exit 1 bash "$ROOT/install.sh"
[ -L "$D" ] && pass || fail "dangling symlink was replaced"

# installing into the repo's own skills folder must not delete the source
new_sandbox; mkdir -p "$SANDBOX/repo"; cp -R "$ROOT/install.sh" "$ROOT/skills" "$SANDBOX/repo/"
CLAUDE_SKILLS_DIR="$SANDBOX/repo/skills" assert_exit 1 bash "$SANDBOX/repo/install.sh" --force
assert_file "$SANDBOX/repo/skills/new-project/SKILL.md"
ln -s "$SANDBOX/repo/skills" "$SANDBOX/link"
CLAUDE_SKILLS_DIR="$SANDBOX/link" assert_exit 1 bash "$SANDBOX/repo/install.sh" --force
assert_file "$SANDBOX/repo/skills/new-project/SKILL.md"
finish
