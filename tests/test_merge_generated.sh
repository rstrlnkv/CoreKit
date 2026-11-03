#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core
bash "$SKILL/scripts/scaffold.sh" --name gen-app >/dev/null
C="$CORE_DIR/gen-app/code"; G="$SANDBOX/gen"; mkdir -p "$G/src"
echo "main" > "$G/src/main.txt"; printf 'node_modules/\n.DS_Store\ndist/\n' > "$G/.gitignore"
echo "theirs" > "$G/.worktreeinclude"; mkdir -p "$G/.git"; echo junk > "$G/.git/HEAD"
before=$(cat "$C/.worktreeinclude")
assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G" "$C"
assert_file "$C/src/main.txt"
assert_eq "$(cat "$C/.worktreeinclude")" "$before" "existing file overwritten"
assert_contains "$C/.gitignore" "node_modules/"; assert_contains "$C/.gitignore" "dist/"
assert_contains "$C/.gitignore" "CLAUDE.md"
c=$(grep -cx '.DS_Store' "$C/.gitignore"); assert_eq "$c" "1" "duplicate .gitignore line"
[ "$(cat "$C/.git/HEAD")" = "junk" ] && fail "generator .git copied" || pass
finish
