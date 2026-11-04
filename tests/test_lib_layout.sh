#!/usr/bin/env bash
# Detection helpers in scripts/lib.sh: project_of beside the Core, code_dir_of, layout_of.
source "$(dirname "$0")/lib.sh"
LIB="$SCRIPTS/lib.sh"

new_sandbox
P="$SANDBOX/Projects"
mkdir -p "$CORE_DIR/foo" "$CORE_DIR/old/code" "$P/Foo/src" "$P/Foo/.claude/worktrees/w" "$P/Brain" "$P/Claude outputs"
: > "$CORE_DIR/foo/CLAUDE.md"; : > "$CORE_DIR/old/CLAUDE.md"
git init -q "$P/Foo"

assert_exit 0 bash "$LIB" project-of "$P/Foo";                           assert_eq "$OUT" "foo" "project-of Foo"
assert_exit 0 bash "$LIB" project-of "$P/Foo/src";                       assert_eq "$OUT" "foo" "project-of Foo/src"
assert_exit 0 bash "$LIB" project-of "$P/Foo/.claude/worktrees/w";       assert_eq "$OUT" "foo" "project-of worktree"
assert_exit 1 bash "$LIB" project-of "$P/Brain";                         assert_eq "$OUT" "" "Brain silent"
assert_exit 1 bash "$LIB" project-of "$P/Claude outputs"
assert_exit 1 bash "$LIB" project-of "$CORE_DIR"
assert_exit 1 bash "$LIB" project-of "$P"
assert_exit 0 bash "$LIB" project-of "$CORE_DIR/old/code";               assert_eq "$OUT" "old" "project-of old code"

assert_exit 0 bash "$LIB" code-dir foo;                                  assert_eq "$OUT" "$P/Foo" "code-dir foo"
assert_exit 0 bash "$LIB" layout foo;                                    assert_eq "$OUT" "new" "layout foo"
assert_exit 0 bash "$LIB" layout old;                                    assert_eq "$OUT" "old" "layout old"
assert_exit 0 bash "$LIB" code-dir old;                                  assert_eq "$OUT" "$CORE_DIR/old/code" "code-dir old"
assert_exit 1 bash "$LIB" code-dir none
assert_exit 1 bash "$LIB" layout none

# shellcheck disable=SC1090
( source "$LIB"; load_settings
  for n in core standards knowledge; do valid_project_name "$n" && echo "accepted $n"; done
  valid_project_name foo || echo "refused foo"
  [ "$PROJECTS_DIR" = "$P" ] || echo "PROJECTS_DIR=$PROJECTS_DIR"
  [ "$(rel_core "$P/Foo")" = "../Foo" ] || echo "rel_core outside: $(rel_core "$P/Foo")"
  [ "$(rel_core "$CORE_DIR/foo/x")" = "foo/x" ] || echo "rel_core inside"
  [ "$(rel_core "$SANDBOX/elsewhere")" = "$SANDBOX/elsewhere" ] || echo "rel_core far"
  : > "$CORE_DIR/PROJECTS.md"
  projects_entry foo "x" "Foo/" >/dev/null
  cat "$CORE_DIR/PROJECTS.md" ) > "$SANDBOX/out" 2>&1
assert_eq "$(cat "$SANDBOX/out")" "- foo — x — Foo/" "valid_project_name / rel_core / projects_entry"

# case clash: only on a case-sensitive disk
if mkdir "$P/foo" 2>/dev/null && [ -d "$P/Foo/src" ] && [ "$(ls "$P" | grep -ci '^foo$')" -eq 2 ]; then
  assert_exit 3 bash "$LIB" code-dir foo
  echo "$OUT" | grep -q "two folders differ only in case" && pass || fail "no case-clash line: $OUT"
else
  echo "  note: case-insensitive disk, case-clash check skipped"
fi
finish
