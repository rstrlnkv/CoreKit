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

# An old-layout project plus an unrelated folder of the same name beside the Core: <Core>/<name>/code
# wins (only the old layout has one).
mkdir -p "$CORE_DIR/twin/code" "$P/Twin"; : > "$CORE_DIR/twin/CLAUDE.md"; git init -q "$P/Twin"
assert_exit 0 bash "$LIB" layout twin;                                   assert_eq "$OUT" "old" "layout twin (old + unrelated Twin)"
assert_exit 0 bash "$LIB" code-dir twin;                                 assert_eq "$OUT" "$CORE_DIR/twin/code" "code-dir twin"

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

# --- link_agents <code_dir> <core_project_dir>: <code_dir>/AGENTS.md -> <core_project_dir>/CLAUDE.md (M7)
la() { ( source "$LIB"; load_settings; link_agents "$@" ); }
new_sandbox; P="$SANDBOX/Projects"
mkdir -p "$CORE_DIR/ag" "$P/Ag"; : > "$CORE_DIR/ag/CLAUDE.md"
T="$CORE_DIR/ag/CLAUDE.md"
OUT="$(DRY=1 la "$P/Ag" "$CORE_DIR/ag" 2>&1)"; assert_eq "$OUT" "would create ../Ag/AGENTS.md" "link_agents dry-run line"
[ -e "$P/Ag/AGENTS.md" ] || [ -L "$P/Ag/AGENTS.md" ] && fail "DRY=1 wrote AGENTS.md" || pass
assert_exit 0 la "$P/Ag" "$CORE_DIR/ag"; assert_eq "$OUT" "created ../Ag/AGENTS.md" "link_agents created line"
[ -L "$P/Ag/AGENTS.md" ] && pass || fail "AGENTS.md is not a symlink"
assert_eq "$(readlink "$P/Ag/AGENTS.md")" "$T" "link_agents target"
assert_exit 0 la "$P/Ag" "$CORE_DIR/ag"; assert_eq "$OUT" "skipped ../Ag/AGENTS.md" "link_agents second run"
assert_eq "$(readlink "$P/Ag/AGENTS.md")" "$T" "link kept on second run"
# a real file is never touched: content and type stay, exit 1, a plain line
rm "$P/Ag/AGENTS.md"; printf 'mine\n' > "$P/Ag/AGENTS.md"
assert_exit 1 la "$P/Ag" "$CORE_DIR/ag"
echo "$OUT" | grep -qF "AGENTS.md exists and is not a link to $T; leave it or remove it yourself" && pass || fail "real-file message: $OUT"
assert_eq "$(cat "$P/Ag/AGENTS.md")" "mine" "real AGENTS.md content"
[ -L "$P/Ag/AGENTS.md" ] && fail "real AGENTS.md replaced by a link" || pass
# DRY=1 on a real file: still exit 1, still untouched
OUT="$(DRY=1 la "$P/Ag" "$CORE_DIR/ag" 2>&1)"; [ $? -eq 1 ] && pass || fail "DRY=1 real file did not exit 1"
assert_eq "$(cat "$P/Ag/AGENTS.md")" "mine" "real AGENTS.md content after DRY=1"
# a link to elsewhere (and a dangling one) stays as it is
for tgt in "$SANDBOX/elsewhere.md" "$SANDBOX/no/such.md"; do
  rm -f "$P/Ag/AGENTS.md"; ln -s "$tgt" "$P/Ag/AGENTS.md"
  assert_exit 1 la "$P/Ag" "$CORE_DIR/ag"
  echo "$OUT" | grep -qF "AGENTS.md exists and is not a link to $T; leave it or remove it yourself" && pass || fail "elsewhere message: $OUT"
  assert_eq "$(readlink "$P/Ag/AGENTS.md")" "$tgt" "link to elsewhere changed"
done
# a Core AGENTS.md blocks the link, stays as it is, and the line names it
rm -f "$P/Ag/AGENTS.md"; printf 'core rules\n' > "$CORE_DIR/ag/AGENTS.md"
assert_exit 1 la "$P/Ag" "$CORE_DIR/ag"
echo "$OUT" | grep -qF "fold $CORE_DIR/ag/AGENTS.md into CLAUDE.md, then remove it" && pass || fail "core AGENTS.md message: $OUT"
[ -e "$P/Ag/AGENTS.md" ] || [ -L "$P/Ag/AGENTS.md" ] && fail "link made despite Core AGENTS.md" || pass
assert_eq "$(cat "$CORE_DIR/ag/AGENTS.md")" "core rules" "Core AGENTS.md changed"
OUT="$(DRY=1 la "$P/Ag" "$CORE_DIR/ag" 2>&1)"; [ $? -eq 1 ] && pass || fail "DRY=1 with Core AGENTS.md did not exit 1"
echo "$OUT" | grep -q "^would create" && fail "DRY=1 announced a link: $OUT" || pass

# case clash: only on a case-sensitive disk
if mkdir "$P/foo" 2>/dev/null && [ -d "$P/Foo/src" ] && [ "$(ls "$P" | grep -ci '^foo$')" -eq 2 ]; then
  assert_exit 3 bash "$LIB" code-dir foo
  echo "$OUT" | grep -q "two folders differ only in case" && pass || fail "no case-clash line: $OUT"
else
  echo "  note: case-insensitive disk, case-clash check skipped"
fi
finish
