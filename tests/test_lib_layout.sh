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

# --- projects_upsert <name> <purpose> <entry> <purpose_set>: a new name is appended silently; the name's line
# gets the new entry (and the purpose when purpose_set is 1) and "updated PROJECTS.md entry" is printed
pu() { ( source "$LIB"; load_settings; projects_upsert "$@" ); }
printf -- '- bar — Old — bar/code/\n- barn — Keep — barn/\n- dash — a — b — dash/code/\n' > "$CORE_DIR/PROJECTS.md"
assert_exit 0 pu foo "New" "Foo/" 0;        assert_eq "$OUT" "" "projects_upsert append is silent"
assert_exit 0 pu bar "Ignored" "bar/" 0;    assert_eq "$OUT" "updated PROJECTS.md entry" "projects_upsert update line"
assert_exit 0 pu dash "Ignored" "dash/" 0
assert_exit 0 pu barn "Fresh" "Barn/" 1
assert_eq "$(cat "$CORE_DIR/PROJECTS.md")" "$(printf -- '- bar — Old — bar/\n- barn — Fresh — Barn/\n- dash — a — b — dash/\n- foo — New — Foo/')" "projects_upsert lines"
before="$(cat "$CORE_DIR/PROJECTS.md")"
OUT="$(DRY=1 pu bar "X" "x/" 1)"; assert_eq "$OUT" "would update PROJECTS.md entry" "projects_upsert DRY=1"
assert_eq "$(cat "$CORE_DIR/PROJECTS.md")" "$before" "projects_upsert DRY=1 wrote PROJECTS.md"
# a failed write leaves PROJECTS.md as it was and no temp file (a read-only Core folder; root may write anyway)
before="$(snap_tree "$CORE_DIR")"; chmod 555 "$CORE_DIR"
if ( : > "$CORE_DIR/.w" ) 2>/dev/null; then rm -f "$CORE_DIR/.w"; chmod 755 "$CORE_DIR"; skip "projects_upsert write failure" "a read-only folder is writable here (root)"
else
  assert_exit 1 pu bar "X" "x/" 1; chmod 755 "$CORE_DIR"
  assert_eq "$(snap_tree "$CORE_DIR")" "$before" "a failed projects_upsert changed the Core"
fi

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

# --- no <core_project_dir>/CLAUDE.md: refuse with exit 1 and create nothing (no dangling link)
ll() { ( source "$LIB"; load_settings; link_local_claude "$@" ); }
new_sandbox; P="$SANDBOX/Projects"; mkdir -p "$CORE_DIR/nc" "$P/Nc"
for fn in la ll; do
  assert_exit 1 $fn "$P/Nc" "$CORE_DIR/nc"
  [ -e "$P/Nc/AGENTS.md" ] || [ -L "$P/Nc/AGENTS.md" ] || [ -e "$P/Nc/CLAUDE.local.md" ] || [ -L "$P/Nc/CLAUDE.local.md" ] \
    && fail "$fn made a dangling link" || pass
  OUT="$(DRY=1 $fn "$P/Nc" "$CORE_DIR/nc" 2>&1)"; [ $? -eq 1 ] && pass || fail "$fn DRY=1 without CLAUDE.md did not exit 1: $OUT"
  echo "$OUT" | grep -q "^would create" && fail "$fn DRY=1 announced a link: $OUT" || pass
done

# --- a new-layout project whose names hold non-ASCII letters: <Projects>/Uni проект beside <Core>/uni проект.
# lc lowers ASCII only, on both sides, so the names match; the project is found from its code folder too.
new_sandbox; P="$SANDBOX/Projects"; U="uni проект"
mkdir -p "$CORE_DIR/$U" "$P/Uni проект/src"; : > "$CORE_DIR/$U/CLAUDE.md"; git init -q "$P/Uni проект"
assert_exit 0 bash "$LIB" code-dir "$U";                      assert_eq "$OUT" "$P/Uni проект" "code-dir non-ASCII"
assert_exit 0 bash "$LIB" layout "$U";                        assert_eq "$OUT" "new" "layout non-ASCII"
assert_exit 0 bash "$LIB" project-of "$P/Uni проект";         assert_eq "$OUT" "$U" "project-of non-ASCII code folder"
assert_exit 0 bash "$LIB" project-of "$P/Uni проект/src/x.ts"; assert_eq "$OUT" "$U" "project-of a file in it"
assert_exit 0 bash "$LIB" code-root "$P/Uni проект/src";      assert_eq "$OUT" "$P/Uni проект" "code-root non-ASCII"
# still no project: a folder with no Core project of its name, a dot-folder, standards, knowledge
mkdir -p "$P/Другое" "$P/.hidden" "$P/Standards" "$P/knowledge" "$CORE_DIR/.hidden" "$CORE_DIR/standards" "$CORE_DIR/knowledge"
: > "$CORE_DIR/.hidden/CLAUDE.md"; : > "$CORE_DIR/standards/CLAUDE.md"; : > "$CORE_DIR/knowledge/CLAUDE.md"
for d in "$P/Другое" "$P/.hidden" "$P/Standards" "$P/knowledge/x"; do
  assert_exit 1 bash "$LIB" project-of "$d"; assert_eq "$OUT" "" "project-of $d prints nothing"
done

# --- save and undo-step with such names. A non-ASCII name is saved and undone as any other. A name with a space
# (or a tab) is refused before any commit, both repos left as they were: save and undo-step hand git the Core paths as
# one space-separated line (CORE_PATHS), so such a name would split and leave a step half-saved.
new_sandbox; setup_core; sync_tools; P="$SANDBOX/Projects"
mkproj() {  # mkproj <Core project folder> <code folder>: a new-layout project
  mkdir -p "$CORE_DIR/$1" "$P/$2"; echo "# $1" > "$CORE_DIR/$1/CLAUDE.md"
  git -C "$P/$2" init -q; ln -s "$CORE_DIR/$1/CLAUDE.md" "$P/$2/CLAUDE.local.md"
  printf 'CLAUDE.local.md\n' > "$P/$2/.gitignore"
}
mkproj "uni-проект" "Uni-проект"; N="$P/Uni-проект"
echo c1 > "$N/c.txt"; echo d1 > "$CORE_DIR/uni-проект/d.md"
OUT="$(cd "$N" && bash "$SCRIPTS/save" "first" 2>&1)" && pass || fail "save of a non-ASCII project failed: $OUT"
echo c2 > "$N/c.txt"; echo d2 > "$CORE_DIR/uni-проект/d.md"
OUT="$(cd "$N" && bash "$SCRIPTS/save" "second" 2>&1)" && pass || fail "second save of a non-ASCII project failed: $OUT"
assert_eq "$(git -C "$N" status --porcelain)" "" "non-ASCII project: code left unsaved"
assert_eq "$(git -C "$CORE_DIR" status --porcelain -- "uni-проект")" "" "non-ASCII project: docs left unsaved"
OUT="$(cd "$N" && bash "$SCRIPTS/undo-step" 2>&1)" && pass || fail "undo-step of a non-ASCII project failed: $OUT"
assert_eq "$(cat "$N/c.txt")" "c1" "undo-step: code of a non-ASCII project"
assert_eq "$(cat "$CORE_DIR/uni-проект/d.md")" "d1" "undo-step: docs of a non-ASCII project"
# a space: new layout (Uni проект beside <Core>/uni проект) and old layout (<Core>/my app/code)
mkproj "uni проект" "Uni проект"
mkdir -p "$CORE_DIR/my app/code"; echo "# my app" > "$CORE_DIR/my app/CLAUDE.md"; git -C "$CORE_DIR/my app/code" init -q
git -C "$CORE_DIR" add -A && git -C "$CORE_DIR" commit -qm "two projects"
for C in "$P/Uni проект" "$CORE_DIR/my app/code"; do
  d="$(dirname "$C")"; [ "$C" = "$P/Uni проект" ] && d="$CORE_DIR/uni проект"
  echo c1 > "$C/c.txt"; git -C "$C" add c.txt && git -C "$C" commit -qm "by hand"
  echo c2 > "$C/c.txt"; echo d1 > "$d/d.md"
  nc="$(commit_count "$C")"; nd="$(commit_count "$CORE_DIR")"; sc="$(git -C "$C" status --porcelain)"; sd="$(git -C "$CORE_DIR" status --porcelain)"
  OUT="$(cd "$C" && bash "$SCRIPTS/save" "spaced" 2>&1)" && fail "save of a name with a space did not refuse: $OUT" || pass
  echo "$OUT" | grep -q "saved code" && fail "save committed the code of a name with a space: $OUT" || pass
  OUT="$(cd "$C" && bash "$SCRIPTS/undo-step" 2>&1)" && fail "undo-step of a name with a space did not refuse: $OUT" || pass
  assert_eq "$(commit_count "$C")" "$nc" "code commits after a refused save/undo ($C)"
  assert_eq "$(commit_count "$CORE_DIR")" "$nd" "Core commits after a refused save/undo ($C)"
  assert_eq "$(git -C "$C" status --porcelain)" "$sc" "code tree after a refused save/undo ($C)"
  assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "$sd" "Core tree after a refused save/undo ($C)"
  assert_eq "$(cat "$C/c.txt")" "c2" "code file after a refused save/undo ($C)"
done
# the hooks' and skills' helpers still find the spaced project (only save and undo-step refuse it)
assert_exit 0 bash "$LIB" project-of "$P/Uni проект"; assert_eq "$OUT" "uni проект" "project-of a spaced name"

# --- lib.sh sources its parts (lib-*.sh and the awk files it names): every part is there, every helper is still defined
# through lib.sh, and lib.sh itself stays small. The shell-patch check is the guards' own file, not part of lib.sh.
parts="$(grep -oE '\$_LIB_DIR/[A-Za-z_][A-Za-z0-9._-]*' "$LIB" | sed 's|^\$_LIB_DIR/||' | LC_ALL=C sort -u)"
[ -n "$parts" ] && pass || fail "lib.sh names no parts in \$_LIB_DIR"
for f in $parts; do assert_file "$SCRIPTS/$f"; done
n="$(wc -l < "$LIB" | tr -d ' ')"
[ "$n" -le 250 ] && pass || fail "lib.sh is $n lines; its helpers belong in its parts"
HELPERS="expand_home canon_dir coredev_get core_ready coredev_set opt_value settings_file_path _sf_load _sf_get _setting_valid
  _resolve_setting _settings_file_check resolve_setting _core_raw load_settings json_str patch_paths
  _project_of_path worktree_of project_of wt_is_main_of code_root_of code_dir_of layout_of valid_project_name lc norm_path
  resolve_abs codex_home host tools_dir hooks_marker_path plugin_version rel_core esc render put mkdir_p git_init
  project_docs_manifest put_project_docs link_file_to_claude link_local_claude link_agents projects_entry projects_upsert"
# shellcheck disable=SC1090,SC2086
missing="$( ( . "$LIB"; for fn in $HELPERS; do type "$fn" >/dev/null 2>&1 || echo "$fn"; done ) 2>&1 )"
assert_eq "$missing" "" "helpers not defined after sourcing lib.sh"
# shellcheck disable=SC1090
assert_eq "$( ( . "$LIB"; type shell_patch_refused >/dev/null 2>&1 && echo defined ) )" "" "shell_patch_refused is in lib.sh"
# sourced through a relative path from another folder, then used after a cd: the parts are still found
OUT="$(cd "$PLUGIN" && . scripts/lib.sh && cd / && json_str '{"a":"b"}' a && echo && valid_project_name foo && echo ok)"
assert_eq "$OUT" "$(printf 'b\nok')" "lib.sh sourced by a relative path, used after a cd"
# the same with CDPATH exported and naming a folder that holds another scripts/: lib.sh still finds its own parts
mkdir -p "$SANDBOX/cdp/scripts"
OUT="$(cd "$PLUGIN" && export CDPATH="$SANDBOX/cdp" && . scripts/lib.sh && cd / && json_str '{"a":"b"}' a && echo && printf '%s\n' "$_LIB_DIR")"
assert_eq "$OUT" "$(printf 'b\n%s' "$SCRIPTS")" "lib.sh sourced by a relative path with CDPATH set"
# lib.sh copied alone: plugin-root needs no part and still answers; anything else names the missing part and fails
mkdir -p "$SANDBOX/alone/scripts"; cp "$LIB" "$SANDBOX/alone/scripts/"
assert_exit 1 bash "$SANDBOX/alone/scripts/lib.sh" plugin-root
assert_eq "$OUT" "corecrew: not a plugin folder: $SANDBOX/alone" "plugin-root of a lib.sh copied alone"
assert_exit 1 bash "$SANDBOX/alone/scripts/lib.sh" schema
echo "$OUT" | grep -qF "lib-paths.sh is missing or broken" && pass || fail "no missing-part line: $OUT"
# shellcheck disable=SC1091
( . "$SANDBOX/alone/scripts/lib.sh" ) 2>/dev/null && fail "sourcing a lib.sh without its parts succeeded" || pass
# codex_home: an absolute CODEX_HOME (no trailing slash), else HOME/.codex; nothing for a relative one
ch() { ( . "$LIB"; codex_home ); }
assert_eq "$(CODEX_HOME=/x/cx/ ch)" "/x/cx" "codex_home from CODEX_HOME"
assert_eq "$(CODEX_HOME= HOME=/h ch)" "/h/.codex" "codex_home from HOME"
assert_eq "$(CODEX_HOME=rel HOME=/h ch)" "" "codex_home: a relative CODEX_HOME is none"
assert_eq "$(CODEX_HOME= HOME=rel ch)" "" "codex_home: a relative HOME is none"

# case clash: only on a case-sensitive disk
new_sandbox; P="$SANDBOX/Projects"; mkdir -p "$P/Foo/src"
if mkdir "$P/foo" 2>/dev/null && [ "$(ls "$P" | grep -ci '^foo$')" -eq 2 ]; then
  assert_exit 3 bash "$LIB" code-dir foo
  echo "$OUT" | grep -q "two folders differ only in case" && pass || fail "no case-clash line: $OUT"
else
  skip "case clash" "case-insensitive disk"
fi
finish
