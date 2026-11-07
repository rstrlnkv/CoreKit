#!/usr/bin/env bash
# Untried inputs for worktree_of / project_of / guard-code / prepare.sh / host: a relative or padded gitdir line,
# nested worktrees, a worktree inside the Core, a renamed main folder, concurrent prepare runs, paths with spaces,
# symlinked paths, a CODEX_HOME that is a symlink.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR COREKIT_HOST
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
setup_core
bash "$SKILL/scripts/scaffold.sh" --name edge >/dev/null
PR="$(dirname "$CORE_DIR")"; C="$PR/edge"; P="$CORE_DIR/edge"
git -C "$C" commit -q --allow-empty -m init
proj() { bash "$SCRIPTS/lib.sh" project-of "$1" 2>/dev/null; }
wt_of() { ( . "$SCRIPTS/lib.sh"; WT_ROOT=""; WT_MAIN=""; worktree_of "$1"; rc=$?; echo "$rc $WT_ROOT $WT_MAIN" ); }
guard() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$3" "$1" "$2" | bash "$HOOKS/guard-code.sh" >/dev/null 2>"$SANDBOX/err"; RC=$?; }

# --- the .git file of a worktree, rewritten: relative gitdir, trailing blanks, CRLF
W="$SANDBOX/ext/w1"; git -C "$C" worktree add -q "$W" -b e1 || fail "worktree add"
GD="$(sed -n 's/^gitdir: //p' "$W/.git")"
printf 'gitdir: %s\n' "$(python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$GD" "$W")" > "$W/.git"
assert_eq "$(wt_of "$W/src")" "0 $W $C" "relative gitdir"
guard Write "$W/docs/a.md" "$W"; assert_eq "$RC" "2" "guard blocks docs/ with a relative gitdir"
printf 'gitdir: %s   \n' "$GD" > "$W/.git"
assert_eq "$(wt_of "$W")" "0 $W $C" "gitdir with trailing blanks"
printf 'gitdir: %s\r\n' "$GD" > "$W/.git"
assert_eq "$(wt_of "$W")" "0 $W $C" "gitdir with CRLF"
printf 'gitdir: %s' "$GD" > "$W/.git"
assert_eq "$(wt_of "$W")" "0 $W $C" "gitdir without a newline"
printf 'gitdir: %s\n' "$GD" > "$W/.git"

# --- nested worktree: a worktree made from a worktree, and one placed inside another worktree
W2="$SANDBOX/ext/w2"; git -C "$W" worktree add -q "$W2" -b e2 || fail "nested add"
assert_eq "$(wt_of "$W2")" "0 $W2 $C" "worktree of a worktree: main is the main folder"
W3="$W/inner/w3"; git -C "$W" worktree add -q "$W3" -b e3 || fail "inner add"
assert_eq "$(wt_of "$W3/x")" "0 $W3 $C" "worktree inside a worktree: the inner root wins"
guard Write "$W3/docs/a.md" "$W3"; assert_eq "$RC" "2" "docs/ of the inner worktree"
guard Write "$W3/src/a.md" "$W3"; assert_eq "$RC" "0" "source of the inner worktree"
git -C "$W" worktree remove --force "$W3" 2>/dev/null

# --- a worktree inside the Core folder (the Core is a repo; its own .git is a folder above)
WC="$CORE_DIR/wt-in-core"; git -C "$C" worktree add -q "$WC" -b e4 || fail "add in core"
assert_eq "$(proj "$WC")" "edge" "worktree inside the Core: project_of"
guard Write "$WC/docs/a.md" "$WC"; assert_eq "$RC" "2" "docs/ in a worktree inside the Core"
guard Write "$WC/src/a.md" "$WC"; assert_eq "$RC" "0" "source in a worktree inside the Core"
git -C "$C" worktree remove --force "$WC" 2>/dev/null

# --- a symlink to the worktree
ln -s "$W" "$SANDBOX/linkw"
assert_eq "$(wt_of "$SANDBOX/linkw/src")" "0 $W $C" "symlinked worktree path"
guard Write "$SANDBOX/linkw/docs/a.md" "$SANDBOX/linkw"; assert_eq "$RC" "2" "guard blocks docs/ through a symlinked worktree"
guard Write "$SANDBOX/linkw/CLAUDE.md" "$SANDBOX/linkw"; assert_eq "$RC" "2" "guard blocks CLAUDE.md through a symlink"

# --- a path with spaces: worktree and prepare --cwd
WS="$SANDBOX/my work/wt sp"; git -C "$C" worktree add -q "$WS" -b e5 || fail "add spaces"
assert_eq "$(wt_of "$WS")" "0 $WS $C" "worktree path with spaces"
guard Write "$WS/docs/a.md" "$WS"; assert_eq "$RC" "2" "guard blocks docs/ in a worktree with spaces"
rm -f "$WS/CLAUDE.local.md" "$WS/AGENTS.md"
OUT="$(bash "$SCRIPTS/prepare.sh" --cwd "$WS" 2>&1)"; assert_eq "$?" "0" "prepare with spaces: exit"
[ -L "$WS/CLAUDE.local.md" ] && [ -L "$WS/AGENTS.md" ] && pass || fail "links in a worktree path with spaces: $OUT"
OUT="$(bash "$SCRIPTS/prepare.sh" --cwd "$WS" 2>&1)"; assert_eq "$OUT" "" "prepare with spaces: second run silent"

# --- prepare twice at once: no error output, no stray files, links right
rm -f "$W/CLAUDE.local.md" "$W/AGENTS.md"; rm -rf "$COREDEV_TOOLS"
for i in 1 2 3 4 5 6; do bash "$SCRIPTS/prepare.sh" --cwd "$W" > "$SANDBOX/conc$i" 2>&1 & done; wait
assert_eq "$(readlink "$W/CLAUDE.local.md")" "$P/CLAUDE.md" "concurrent: CLAUDE.local.md"
assert_eq "$(readlink "$W/AGENTS.md")" "$P/CLAUDE.md" "concurrent: AGENTS.md"
bad="$(cat "$SANDBOX"/conc* | grep 'is a link to somewhere other\|exists and is not a link' | head -1)"; assert_eq "$bad" "" "concurrent: no false 'link to somewhere other' warning (link_file_to_claude ln race)"
bad="$(cat "$SANDBOX"/conc* | grep 'tools not refreshed' | head -1)"; assert_eq "$bad" "" "concurrent: no false 'tools not refreshed' (sync-tools.sh mv race)"
assert_file "$COREDEV_TOOLS/VERSION"; assert_file "$COREDEV_TOOLS/save"
assert_eq "$(ls -A "$COREDEV_TOOLS" | grep -c 'tmp\|\.new\|\.part')" "0" "concurrent: no temp leftovers in tools"

# --- the main folder renamed after worktree add: the worktree's .git points to a path that is gone.
# LIMIT (ADR 005): git itself is broken there; the worktree is not trusted, so the guards do not judge it.
mv "$C" "$PR/edge-moved"
guard Write "$W2/docs/a.md" "$W2"; assert_eq "$RC" "0" "LIMIT renamed main: a worktree whose main is gone is not judged"
mv "$PR/edge-moved" "$C"

# --- a forged .git file: a gitdir that is not <main>/.git/worktrees/<name> is not a worktree (mutation: the shape check dropped)
mkdir -p "$SANDBOX/fake1" "$SANDBOX/fake2" "$SANDBOX/fake3"
printf 'gitdir: %s\n' "$C" > "$SANDBOX/fake1/.git"                       # points at a folder that has .git inside
printf 'gitdir: %s/.git/worktrees\n' "$C" > "$SANDBOX/fake2/.git"        # no worktree name
printf 'gitdir: %s/.git/modules/m\n' "$C" > "$SANDBOX/fake3/.git"        # a submodule-style path
for f in fake1 fake2 fake3; do assert_eq "$(wt_of "$SANDBOX/$f/src" | cut -c1-1)" "1" "forged $f/.git is not a worktree"; done

# --- a linked worktree inside the main folder but not under .claude/worktrees is its own root too
WI="$C/other/wt"; git -C "$C" worktree add -q "$WI" -b e6 || fail "add inside main"
assert_eq "$(wt_of "$WI")" "0 $WI $C" "worktree inside the main folder: detected"
guard Write "$WI/docs/a.md" "$WI"; assert_eq "$RC" "2" "docs/ of a worktree placed inside the main folder (guard-code WT_MAIN exclusion)"
guard Write "$WI/src/a.md" "$WI"; assert_eq "$RC" "0" "source of a worktree placed inside the main folder"
git -C "$C" worktree remove --force "$WI" 2>/dev/null

# --- the marker file is per host (mutation: the host ignored)
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=claude hooks_marker_path | sed 's|.*/||')" "hooks-seen-claude" "marker name on claude"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex hooks_marker_path | sed 's|.*/||')" "hooks-seen-codex" "marker name on codex"

# --- Codex host: the plugin under a CODEX_HOME that is itself (or contains) a symlink
REAL="$SANDBOX/realcodex"; mkdir -p "$REAL/plugins/cache/corekit"; ln -s "$REAL" "$SANDBOX/linkcodex"
cp -R "$PLUGIN" "$REAL/plugins/cache/corekit/corecrew"
assert_eq "$(CODEX_HOME="$SANDBOX/linkcodex" bash -c '. "$1"; host' _ "$REAL/plugins/cache/corekit/corecrew/scripts/lib.sh")" "codex" "host: CODEX_HOME is a symlink, plugin reached by the real path"
assert_eq "$(CODEX_HOME="$SANDBOX/linkcodex" bash -c '. "$1"; host' _ "$SANDBOX/linkcodex/plugins/cache/corekit/corecrew/scripts/lib.sh")" "codex" "host: plugin reached through the link"
assert_eq "$(CODEX_HOME="$REAL" bash -c '. "$1"; host' _ "$SANDBOX/linkcodex/plugins/cache/corekit/corecrew/scripts/lib.sh")" "codex" "host: CODEX_HOME real, plugin through the link"
mkdir -p "$REAL/inner"; ln -s "$REAL/plugins" "$REAL/inner/pl"
assert_eq "$(CODEX_HOME="$REAL/inner" bash -c '. "$1"; host' _ "$REAL/plugins/cache/corekit/corecrew/scripts/lib.sh")" "claude" "host: a plugin outside CODEX_HOME stays claude"

# --- ln never makes a link inside a directory that appeared at the link's path (mutation: plain ln -s)
LD="$SANDBOX/lnd"; mkdir -p "$LD"; STUB2="$SANDBOX/lnstub"; mkdir -p "$STUB2"
REALLN="$(command -v ln)"
# the stub makes the directory just before the real ln runs: the race between the -e test and ln
printf '#!/bin/sh\nmkdir -p "%s/CLAUDE.local.md"\nexec "%s" "$@"\n' "$LD" "$REALLN" > "$STUB2/ln"; chmod +x "$STUB2/ln"
OUT="$(PATH="$STUB2:$PATH" bash -c '. "$1"; link_file_to_claude "$2" "$3" CLAUDE.local.md' _ "$SCRIPTS/lib.sh" "$LD" "$P" 2>&1)"; RCLN=$?
assert_eq "$RCLN" "1" "ln into a new directory: exit 1"
assert_eq "$(ls -A "$LD/CLAUDE.local.md" | wc -l | tr -d ' ')" "0" "ln into a new directory: no link created inside it"
finish
