#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core
bash "$SKILL/scripts/scaffold.sh" --name gen-app >/dev/null
C="$(dirname "$CORE_DIR")/gen-app"; G="$SANDBOX/gen"; mkdir -p "$G/src"
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

# the user's own .gitignore.add in the code folder is never written or removed (the temp file is elsewhere)
G2="$SANDBOX/gen2"; mkdir -p "$G2"; printf 'build/\n' > "$G2/.gitignore"
echo mine > "$C/.gitignore.add"
assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G2" "$C"
assert_eq "$(cat "$C/.gitignore.add" 2>/dev/null)" "mine" "the user's .gitignore.add changed"
assert_contains "$C/.gitignore" "build/"

# a code folder with no .gitignore: it is created with the generator's lines, no grep errors
D2="$SANDBOX/no-gi"; mkdir -p "$D2"
assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G" "$D2"
assert_contains "$D2/.gitignore" "node_modules/"; assert_contains "$D2/.gitignore" "dist/"
echo "$OUT" | grep -q 'No such file' && fail "error output for a missing .gitignore: $OUT" || pass

# failure path: a file that cannot be copied makes the run exit non-zero and names it; the rest is
# still copied and nothing of the user's is overwritten
if [ "$(id -u)" != 0 ]; then
  G3="$SANDBOX/gen3"; mkdir -p "$G3/ro"; echo x > "$G3/ro/x.txt"; echo ok > "$G3/ok.txt"
  D3="$SANDBOX/d3"; mkdir -p "$D3/ro"; echo keep > "$D3/ro/kept.txt"; chmod a-w "$D3/ro"
  assert_exit 1 bash "$SKILL/scripts/merge-generated.sh" "$G3" "$D3"
  chmod u+w "$D3/ro"
  echo "$OUT" | grep -q 'ro/x.txt' && pass || fail "the failed copy is not named: $OUT"
  echo "$OUT" | grep -q '^merged into' && fail "success claimed after a failed copy: $OUT" || pass
  assert_file "$D3/ok.txt"; assert_no_file "$D3/ro/x.txt"; assert_eq "$(cat "$D3/ro/kept.txt")" "keep" "user file changed"
fi
finish
