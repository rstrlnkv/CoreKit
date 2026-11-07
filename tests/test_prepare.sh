#!/usr/bin/env bash
# scripts/prepare.sh: what session-start does for hosts whose hooks may not run yet (Codex): tools copy, the
# CLAUDE.local.md / AGENTS.md links (also in a worktree outside the project), layout and git hook notes, the trust note.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR COREKIT_HOST
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
PREP="$SCRIPTS/prepare.sh"
assert_file "$PREP"
setup_core
bash "$SKILL/scripts/scaffold.sh" --name prep >/dev/null
P="$CORE_DIR/prep"; PR="$(dirname "$CORE_DIR")"; C="$PR/prep"
git -C "$C" commit -q --allow-empty -m init
mkdir -p "$SANDBOX/elsewhere"
VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json" | head -1)"
MARK="$XDG_CONFIG_HOME/corecrew/state/hooks-seen-codex"
# run <host> [args] — stdout+stderr in OUT, exit code in RC
run() { local h="$1"; shift; OUT="$(COREKIT_HOST="$h" bash "$PREP" "$@" 2>&1)"; RC=$?; }

# --- first run (claude host): tools copy, both links; second run silent
rm -rf "$COREDEV_TOOLS" "$C/CLAUDE.local.md" "$C/AGENTS.md"
run claude --cwd "$C"
assert_eq "$RC" "0" "exit"
assert_file "$COREDEV_TOOLS/VERSION"; assert_file "$COREDEV_TOOLS/save"
assert_eq "$(readlink "$C/CLAUDE.local.md")" "$P/CLAUDE.md" "CLAUDE.local.md link"
assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "AGENTS.md link"
echo "$OUT" | grep -qF "linked CLAUDE.local.md to $P/CLAUDE.md" && pass || fail "link note missing: $OUT"
echo "$OUT" | grep -qF "Codex" && fail "trust note on the claude host: $OUT" || pass
run claude --cwd "$C"; assert_eq "$OUT" "" "second run is silent"
run claude --cwd "$SANDBOX/elsewhere"; assert_eq "$OUT" "" "outside a project: silent"
run claude; assert_eq "$RC" "0" "default cwd: exit"

# --- the trust note (codex host): no marker, older marker, current marker
run codex --cwd "$C"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "trust note missing: $OUT"
mkdir -p "$(dirname "$MARK")"; echo "0.0.1" > "$MARK"
run codex --cwd "$C"; echo "$OUT" | grep -qF "open /hooks" && pass || fail "older marker: trust note expected: $OUT"
echo "$VER" > "$MARK"
run codex --cwd "$C"; assert_eq "$OUT" "" "current marker: silent"
run codex --cwd "$SANDBOX/elsewhere"; assert_eq "$OUT" "" "current marker, outside a project: silent"
rm -f "$MARK"; run codex --cwd "$SANDBOX/elsewhere"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "trust note outside a project: $OUT"
assert_no_file "$MARK"   # prepare never writes the marker: only the hook can prove it ran
OUT="$(COREKIT_HOST=codex bash "$PREP" --part host --cwd "$C" 2>&1)"
echo "$OUT" | grep -qF "/hooks" && pass || fail "--part host: $OUT"
OUT="$(COREKIT_HOST=codex CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "Защита corecrew" && pass || fail "ru trust note: $OUT"

# --- a worktree outside the project gets both links; the main folder is left as it is
W="$SANDBOX/codex-home/worktrees/ab12/prep"
git -C "$C" worktree add -q "$W" -b b1 || fail "worktree add"
assert_no_file "$W/AGENTS.md"
run claude --cwd "$W/src-none"
assert_eq "$(readlink "$W/AGENTS.md")" "$P/CLAUDE.md" "worktree AGENTS.md link"
assert_eq "$(readlink "$W/CLAUDE.local.md")" "$P/CLAUDE.md" "worktree CLAUDE.local.md link"
run claude --cwd "$W"; assert_eq "$OUT" "" "worktree: second run silent"
# a Claude worktree under the main folder gets no links of its own (the main folder's are found above it)
CW="$C/.claude/worktrees/w1"; git -C "$C" worktree add -q "$CW" -b b2
run claude --cwd "$CW"; assert_no_file "$CW/AGENTS.md"; assert_no_file "$CW/CLAUDE.local.md"
# the same from the Core project folder: links belong to the main folder
rm -f "$C/AGENTS.md"; run claude --cwd "$P"; assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "link made from the Core project folder"

# --- failure path: a real file where a link should go is reported (CLAUDE.local.md) or left silent (AGENTS.md), never replaced
W2="$SANDBOX/codex-home/worktrees/cd34/prep"
git -C "$C" worktree add -q "$W2" -b b3
printf 'mine\n' > "$W2/CLAUDE.local.md"; printf 'mine too\n' > "$W2/AGENTS.md"
run claude --cwd "$W2"
assert_eq "$RC" "0" "refused link: exit 0"
echo "$OUT" | grep -qF "$W2/CLAUDE.local.md exists and is not a link" && pass || fail "refused link not reported: $OUT"
assert_eq "$(cat "$W2/CLAUDE.local.md")" "mine" "real CLAUDE.local.md kept"
assert_eq "$(cat "$W2/AGENTS.md")" "mine too" "real AGENTS.md kept"
[ ! -L "$W2/CLAUDE.local.md" ] && [ ! -L "$W2/AGENTS.md" ] && pass || fail "a real file was replaced by a link"
rm -f "$C/CLAUDE.local.md"; printf 'main mine\n' > "$C/CLAUDE.local.md"
run claude --cwd "$C"
echo "$OUT" | grep -qF "$C/CLAUDE.local.md exists and is not a link" && pass || fail "main: refused link not reported: $OUT"
assert_eq "$(cat "$C/CLAUDE.local.md")" "main mine" "real CLAUDE.local.md in the main folder kept"
rm -f "$C/CLAUDE.local.md"; ln -s "$P/CLAUDE.md" "$C/CLAUDE.local.md"

# --- layout note and old git hooks (same texts as session-start)
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
run claude --cwd "$C"; echo "$OUT" | grep -qF "Layout note" && pass || fail "layout note: $OUT"
printf 'schema: 2\n' > "$CORE_DIR/.coredev"
mkdir -p "$C/.git/hooks"; printf '#!/bin/sh\n# new-project hook\n' > "$C/.git/hooks/pre-commit"
run claude --cwd "$C"; echo "$OUT" | grep -qF "Old git hooks" && pass || fail "stale hook note: $OUT"
rm -f "$C/.git/hooks/pre-commit"

# --- a failing sync is reported and the exit stays 0; the rest still runs
mkdir -p "$SANDBOX/foreign-tools"; : > "$SANDBOX/foreign-tools/mine.txt"
rm -f "$C/AGENTS.md"
OUT="$(COREKIT_HOST=claude COREDEV_TOOLS="$SANDBOX/foreign-tools" bash "$PREP" --cwd "$C" 2>&1)"; RC=$?
assert_eq "$RC" "0" "sync failure: exit 0"
echo "$OUT" | grep -qF "corecrew: tools not refreshed:" && pass || fail "sync_failed missing: $OUT"
assert_eq "$(ls "$SANDBOX/foreign-tools")" "mine.txt" "foreign tools folder untouched"
assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "links still made after a failed sync"

# --- no usable HOME: no data folder, nothing written in the cwd or at /
rm -rf "$COREDEV_TOOLS"
mkdir -p "$SANDBOX/cwdempty"
for H in "" "relhome"; do
  OUT="$(cd "$SANDBOX/cwdempty" && env -u COREDEV_TOOLS -u CLAUDE_PLUGIN_DATA -u XDG_CONFIG_HOME -u CODEX_HOME -u CORECREW_CONFIG HOME="$H" CORE_DIR="$CORE_DIR" COREKIT_HOST=codex bash "$PREP" --cwd "$SANDBOX/elsewhere" 2>&1)"; RC=$?
  assert_eq "$RC" "0" "HOME='$H': exit 0"
  assert_eq "$(ls -A "$SANDBOX/cwdempty")" "" "HOME='$H': nothing written in the cwd"
  [ ! -e "/.claude" ] && [ ! -e "/.codex" ] && [ ! -e "/.config" ] && pass || fail "HOME='$H': wrote at /"
  assert_no_file "$COREDEV_TOOLS"
done

# --- host, tools_dir, hooks_marker_path; session-start writes the marker on Codex only
CP="$CODEX_HOME/plugins/cache/corekit/corecrew/$VER"; mkdir -p "$(dirname "$CP")"; cp -R "$PLUGIN" "$CP"
assert_eq "$(. "$CP/scripts/lib.sh"; host)" "codex" "host: plugin under CODEX_HOME"
assert_eq "$(. "$SCRIPTS/lib.sh"; host)" "claude" "host: plugin elsewhere"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex host)" "codex" "host: COREKIT_HOST"
assert_eq "$(. "$CP/scripts/lib.sh"; COREKIT_HOST=claude host)" "claude" "host: COREKIT_HOST wins"
assert_eq "$(. "$SCRIPTS/lib.sh"; tools_dir)" "$COREDEV_TOOLS" "tools_dir: COREDEV_TOOLS"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS; tools_dir)" "$CLAUDE_PLUGIN_DATA/tools" "tools_dir: CLAUDE_PLUGIN_DATA"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; tools_dir)" "$HOME/.claude/plugins/data/corecrew-corekit/tools" "tools_dir: claude default"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; COREKIT_HOST=codex tools_dir)" "$CODEX_HOME/plugins/data/corecrew-corekit/tools" "tools_dir: codex default"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; HOME=rel; tools_dir)" "" "tools_dir: relative HOME"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex hooks_marker_path)" "$MARK" "hooks_marker_path"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset XDG_CONFIG_HOME; HOME=""; COREKIT_HOST=codex hooks_marker_path)" "" "hooks_marker_path: no settings folder"
SS="{\"session_id\":\"s\",\"cwd\":\"$C\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
rm -f "$MARK"
printf '%s' "$SS" | COREKIT_HOST=claude CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_no_file "$MARK"
printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "$VER" "session-start writes the version on Codex"
touch -t 200001010000 "$MARK"; printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
[ -n "$(find "$MARK" -newermt 2001-01-01 2>/dev/null)" ] && fail "marker rewritten although current" || pass
echo "0.0.1" > "$MARK"; printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "$VER" "an older marker is replaced"
run codex --cwd "$C"; assert_eq "$OUT" "" "after session-start: no trust note"
finish
