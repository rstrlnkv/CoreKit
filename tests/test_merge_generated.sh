#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core
bash "$SKILL/scripts/scaffold.sh" --name gen-app >/dev/null
C="$(dirname "$CORE_DIR")/gen-app"; G="$SANDBOX/gen"; mkdir -p "$G/src"
echo "main" > "$G/src/main.txt"; printf 'node_modules/\n.DS_Store\ndist/\n' > "$G/.gitignore"
echo "theirs" > "$G/.worktreeinclude"; mkdir -p "$G/.git"; echo junk > "$G/.git/HEAD"
mkdir -p "$G/.git/hooks"; echo hook > "$G/.git/hooks/x"
# links of the generated project: to a file beside it, to a folder, and one that points nowhere
mkdir -p "$G/bin"; echo tool > "$G/bin/tool-1.0"; ln -s tool-1.0 "$G/bin/tool"
ln -s src "$G/source"; ln -s no/such/target "$G/dangling"
# a dangling link of the user's at a path the generator also has: left alone, nothing written through it
echo theirs > "$G/src/taken.txt"; mkdir -p "$C/src"; ln -s "$SANDBOX/not-made" "$C/src/taken.txt"
before=$(cat "$C/.worktreeinclude")
assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G" "$C"
echo "$OUT" | grep -qxF "merged into $C" && pass || fail "no merged line: $OUT"
assert_eq "$(readlink "$C/bin/tool")" "tool-1.0" "the link to a file was not copied as a link"
assert_eq "$(cat "$C/bin/tool" 2>/dev/null)" "tool" "the copied link does not reach its file"
assert_eq "$(readlink "$C/source")" "src" "the link to a folder was not copied as a link"
[ -L "$C/dangling" ] && pass || fail "the dangling link was not copied as a link"
assert_eq "$(readlink "$C/dangling")" "no/such/target" "the dangling link's target text changed"
assert_no_file "$C/.git/hooks/x"   # generator .git/hooks/x copied
[ -L "$C/src/taken.txt" ] && pass || fail "the user's dangling link was replaced"
assert_eq "$(readlink "$C/src/taken.txt")" "$SANDBOX/not-made" "the user's dangling link points elsewhere"
[ -e "$SANDBOX/not-made" ] && fail "the dangling link's target was created" || pass
echo "$OUT" | grep -qxF 'skipped src/taken.txt' && pass || fail "no skipped line for the user's dangling link: $OUT"
echo "$OUT" | grep -q '^skipped \.git/' && fail "a .git file of the generator was looked at: $OUT" || pass
assert_file "$C/src/main.txt"
assert_eq "$(cat "$C/.worktreeinclude")" "$before" "existing file overwritten"
assert_contains "$C/.gitignore" "node_modules/"; assert_contains "$C/.gitignore" "dist/"
assert_contains "$C/.gitignore" "CLAUDE.md"
c=$(grep -cx '.DS_Store' "$C/.gitignore"); assert_eq "$c" "1" "duplicate .gitignore line"
[ "$(cat "$C/.git/HEAD")" = "junk" ] && fail "generator .git copied" || pass

# a second run copies no link again: each is reported as skipped, the links stay as they are
assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G" "$C"
for l in bin/tool source dangling; do
  echo "$OUT" | grep -qxF "skipped $l" && pass || fail "second run: no skipped line for $l: $OUT"
done
assert_eq "$(readlink "$C/bin/tool") $(readlink "$C/source") $(readlink "$C/dangling")" "tool-1.0 src no/such/target" "second run changed a link"
[ -e "$C/src/src" ] || [ -L "$C/src/src" ] && fail "second run copied a link into the folder it points to" || pass

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

# a .gitignore in the code folder that is not a regular file (here a link that points nowhere) is left alone:
# exit 1, the missing lines are named, the link stays and nothing is written through it
D4="$SANDBOX/gi-link"; mkdir -p "$D4"; ln -s "$SANDBOX/gi-not-made" "$D4/.gitignore"
assert_exit 1 bash "$SKILL/scripts/merge-generated.sh" "$G2" "$D4"
echo "$OUT" | grep -qF ".gitignore (the generator's lines were not added)" && pass || fail "the .gitignore that was left alone is not named: $OUT"
echo "$OUT" | grep -q '^merged into' && fail "success claimed with .gitignore left alone: $OUT" || pass
assert_eq "$(readlink "$D4/.gitignore")" "$SANDBOX/gi-not-made" "the .gitignore link was changed"
[ -e "$SANDBOX/gi-not-made" ] && fail "the .gitignore link's target was created" || pass

# failure path: a file that cannot be copied makes the run exit non-zero and names it; the rest is
# still copied and nothing of the user's is overwritten
if [ "$(id -u)" != 0 ]; then
  G3="$SANDBOX/gen3"; mkdir -p "$G3/ro"; echo x > "$G3/ro/x.txt"; echo ok > "$G3/ok.txt"
  printf 'build/\n' > "$G3/.gitignore"
  D3="$SANDBOX/d3"; mkdir -p "$D3/ro"; echo keep > "$D3/ro/kept.txt"; chmod a-w "$D3/ro"
  assert_exit 1 bash "$SKILL/scripts/merge-generated.sh" "$G3" "$D3"
  chmod u+w "$D3/ro"
  echo "$OUT" | grep -q 'ro/x.txt' && pass || fail "the failed copy is not named: $OUT"
  echo "$OUT" | grep -q '^merged into' && fail "success claimed after a failed copy: $OUT" || pass
  assert_file "$D3/ok.txt"; assert_no_file "$D3/ro/x.txt"; assert_eq "$(cat "$D3/ro/kept.txt")" "keep" "user file changed"
  # after the folder is fixed, a rerun copies what was missed; a third run changes nothing
  assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G3" "$D3"
  assert_eq "$(cat "$D3/ro/x.txt" 2>/dev/null)" "x" "the rerun did not copy ro/x.txt"
  before=$(tree_sum "$D3")
  assert_exit 0 bash "$SKILL/scripts/merge-generated.sh" "$G3" "$D3"
  echo "$OUT" | grep -v '^skipped ' | grep -vxF "merged into $D3" | grep -q . && fail "third run printed more than skipped and merged lines: $OUT" || pass
  assert_eq "$(tree_sum "$D3")" "$before" "the third run changed the code folder"
  assert_eq "$(grep -cxF '# From the stack generator' "$D3/.gitignore")" "1" "the generator block was added again"
  assert_eq "$(grep -cxF 'build/' "$D3/.gitignore")" "1" "a generator line was added again"
else
  skip "a file that cannot be copied" "running as root"
fi
# nested .gitignore files are kept, and what they ignore stays ignored
new_sandbox; setup_core; bash "$SKILL/scripts/scaffold.sh" --name mg-app >/dev/null; G="$SANDBOX/g"; mkdir -p "$G/android"
printf 'key.properties\n' > "$G/android/.gitignore"; echo k > "$G/android/key.properties"
bash "$SKILL/scripts/merge-generated.sh" "$G" "$SANDBOX/Projects/mg-app" >/dev/null
assert_file "$SANDBOX/Projects/mg-app/android/.gitignore"
git -C "$SANDBOX/Projects/mg-app" status --porcelain | grep -q key.properties && fail "key.properties not ignored" || pass
finish
