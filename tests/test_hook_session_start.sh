#!/usr/bin/env bash
# hooks/session-start.sh: tools sync, one-time Core hint, project context.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/session-start.sh"
export CLAUDE_PLUGIN_ROOT="$ROOT"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR

input() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }
# run_rc <cwd> — stdout and stderr in OUT, exit code in RC
run_rc() { OUT="$(input "$1" | bash "$H" 2>&1)"; RC=$?; }

# --- no Core yet: the hint comes once per machine; tools are synced either way
mkdir -p "$SANDBOX/elsewhere"
run_rc "$SANDBOX/elsewhere"
assert_eq "$RC" "0" "exit code without Core"
assert_eq "$OUT" "corecrew: Core not found at $CORE_DIR — /corecrew:new-project or /corecrew:task adopt <folder> will set it up" "hint text"
assert_file "$CLAUDE_PLUGIN_DATA/state/core-hint-shown"
assert_file "$CLAUDE_PLUGIN_DATA/tools/VERSION"
assert_file "$CLAUDE_PLUGIN_DATA/tools/save"
run_rc "$SANDBOX/elsewhere"
assert_eq "$RC" "0" "exit code on the second run"; assert_eq "$OUT" "" "hint is shown only once"
# stdin without a cwd falls back to $PWD; empty and broken stdin never fail
rm -f "$CLAUDE_PLUGIN_DATA/state/core-hint-shown"
OUT="$(cd "$SANDBOX/elsewhere" && echo '{"session_id":"s"}' | bash "$H" 2>&1)"; assert_eq "$?" "0" "no cwd: exit"
case "$OUT" in "corecrew: Core not found at "*) pass ;; *) fail "no cwd: hint expected, got: $OUT" ;; esac
rm -f "$CLAUDE_PLUGIN_DATA/state/core-hint-shown"
OUT="$(cd "$SANDBOX/elsewhere" && bash "$H" </dev/null 2>&1)"; assert_eq "$?" "0" "empty stdin: exit"
OUT="$(printf '{"cwd":"unterminated' | bash "$H" 2>&1)"; assert_eq "$?" "0" "broken JSON: exit"

# --- Core set up, session elsewhere: silent (tools still synced)
setup_core
scaffold_old sess-app
P="$CORE_DIR/sess-app"; C="$P/code"
rm -rf "$CLAUDE_PLUGIN_DATA/tools" "$CLAUDE_PLUGIN_DATA/state"
run_rc "$SANDBOX/elsewhere"
assert_eq "$RC" "0" "exit outside Core"; assert_eq "$OUT" "" "silent outside Core"
assert_file "$CLAUDE_PLUGIN_DATA/tools/VERSION"
assert_no_file "$CLAUDE_PLUGIN_DATA/state/core-hint-shown"
run_rc "$CORE_DIR/standards"; assert_eq "$OUT" "" "standards is not a project"
run_rc "$CORE_DIR"; assert_eq "$OUT" "" "the Core root is not a project"

# --- inside a project
T="$CLAUDE_PLUGIN_DATA/tools"
run_rc "$C"
assert_eq "$RC" "0" "exit in project"
echo "$OUT" | grep -qF "sess-app" && pass || fail "project name missing: $OUT"
echo "$OUT" | grep -qF "$P/docs/INDEX.md" && pass || fail "INDEX path missing: $OUT"
echo "$OUT" | grep -qF "$T/save" && pass || fail "save path missing: $OUT"
echo "$OUT" | grep -qF "$T/undo-step" && pass || fail "undo-step path missing: $OUT"
echo "$OUT" | grep -qF "Standards: none" && pass || fail "standards 'none' missing: $OUT"
echo "$OUT" | grep -qiE "layout|schema|install-hooks|session rules" && fail "unexpected note on a fresh Core: $OUT" || pass
echo "$OUT" | grep -qF "Core not found" && fail "hint inside a project" || pass
# attribution=forbid: the save command it prints carries --no-attribution; allow (default) does not
echo "$OUT" | grep -qF -- "--no-attribution" && fail "--no-attribution without forbid: $OUT" || pass
OUT="$(input "$C" | CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid bash "$H" 2>&1)"
echo "$OUT" | grep -qF "bash \"$T/save\" \"<message>\" --no-attribution" && pass || fail "forbid: save line lacks --no-attribution: $OUT"
# standards: names on one line, README.md left out
printf -- '---\nname: alpha\n---\n' > "$CORE_DIR/standards/alpha.md"; : > "$CORE_DIR/standards/beta.md"
run_rc "$C"
echo "$OUT" | grep -qxF "Standards: alpha, beta" && pass || fail "standards line: $OUT"
echo "$OUT" | grep -qF "README" && fail "README listed among standards: $OUT" || pass
# worktree and project root, the docs folder, a file path that does not exist: same project
mkdir -p "$C/.claude/worktrees/w1/src"
for d in "$C/.claude/worktrees/w1" "$C/.claude/worktrees/w1/src" "$P" "$P/docs" "$P/docs/not-yet"; do
  run_rc "$d"; echo "$OUT" | grep -qF "$P/docs/INDEX.md" && pass || fail "cwd $d: $OUT"
done
# session rules: full content
printf 'Rule one: be kind.\nRule two: "quote" and \\ backslash.\n' > "$CORE_DIR/session-rules.md"
run_rc "$C"
echo "$OUT" | grep -qxF 'Rule one: be kind.' && pass || fail "session rule 1 missing: $OUT"
echo "$OUT" | grep -qxF 'Rule two: "quote" and \ backslash.' && pass || fail "session rule 2 missing: $OUT"
printf 'Last rule, no newline' > "$CORE_DIR/session-rules.md"; printf 'schema: 0\n' > "$CORE_DIR/.coredev"
run_rc "$C"; echo "$OUT" | grep -qxF 'Last rule, no newline' && pass || fail "rules without final newline run into the next line: $OUT"
echo "$OUT" | grep -q '^Layout note' && pass || fail "layout note missing after rules: $OUT"
printf 'schema: 2\n' > "$CORE_DIR/.coredev"
rm "$CORE_DIR/session-rules.md"
run_rc "$C"; echo "$OUT" | grep -qF "Rule one" && fail "rules shown without file" || pass

# --- layout note when .coredev is older
cp "$CORE_DIR/.coredev" "$SANDBOX/corecrew.bak"
FIX="bash \"$ROOT/scripts/setup-core.sh\" \"$CORE_DIR\""
printf 'app-id-prefix: com.example\n' > "$CORE_DIR/.coredev"          # no schema line
run_rc "$C"; echo "$OUT" | grep -qF "$FIX" && pass || fail "no schema: fix command missing: $OUT"
printf 'schema: 0\n' > "$CORE_DIR/.coredev"                           # lower schema
run_rc "$C"; echo "$OUT" | grep -qF "$FIX" && pass || fail "schema 0: fix command missing: $OUT"
printf 'schema: 1\n' > "$CORE_DIR/.coredev"                           # schema 1: layout note
run_rc "$C"; echo "$OUT" | grep -qF "$FIX" && pass || fail "schema 1: fix command missing: $OUT"
printf 'schema: 2\n' > "$CORE_DIR/.coredev"
run_rc "$C"; echo "$OUT" | grep -qF "setup-core.sh" && fail "note at the current schema: $OUT" || pass
printf 'schema: 3\n' > "$CORE_DIR/.coredev"                           # newer Core than the plugin: no note
run_rc "$C"; echo "$OUT" | grep -qF "setup-core.sh" && fail "note for a newer schema: $OUT" || pass
# a 0.1.x Core (no .coredev at all): Core counts as not set up, but a session in a project gets context + note
rm "$CORE_DIR/.coredev"
run_rc "$C"
echo "$OUT" | grep -qF "$P/docs/INDEX.md" && pass || fail "old Core: project context missing: $OUT"
echo "$OUT" | grep -qF "$FIX" && pass || fail "old Core: fix command missing: $OUT"
echo "$OUT" | grep -qF "Core not found" && fail "old Core in project: hint shown" || pass
run_rc "$SANDBOX/elsewhere"
assert_eq "$OUT" "corecrew: Core at $CORE_DIR is not set up — /corecrew:new-project or /corecrew:task adopt <folder> will set it up" "old Core elsewhere: hint says not set up"
cp "$SANDBOX/corecrew.bak" "$CORE_DIR/.coredev"

# --- git hooks: only an old "new-project hook" is named; shims and a user's own hook are left alone
INST="bash \"$ROOT/scripts/install-hooks.sh\" \"$P\""
mkdir -p "$C/.git/hooks" "$CORE_DIR/.git/hooks"
run_rc "$C"; echo "$OUT" | grep -qF "install-hooks.sh" && fail "hook note without hooks: $OUT" || pass
printf '#!/bin/sh\n# new-project hook\nexit 0\n' > "$C/.git/hooks/pre-commit"
run_rc "$C"; echo "$OUT" | grep -qF "$INST" && pass || fail "old pre-commit: install command missing: $OUT"
echo "$OUT" | grep -qF "pre-commit" && pass || fail "old pre-commit not named: $OUT"
rm "$C/.git/hooks/pre-commit"
printf '#!/bin/sh\n# new-project hook\nexit 0\n' > "$C/.git/hooks/pre-push"
run_rc "$C"; echo "$OUT" | grep -qF "$INST" && pass || fail "old pre-push: install command missing: $OUT"
rm "$C/.git/hooks/pre-push"
printf '#!/bin/sh\n# new-project hook\nexit 0\n' > "$CORE_DIR/.git/hooks/pre-push"
run_rc "$C"; echo "$OUT" | grep -qF "$INST" && pass || fail "old Core pre-push: install command missing: $OUT"
echo "$OUT" | grep -qF "$CORE_DIR/.git/hooks/pre-push" && pass || fail "old Core pre-push not named: $OUT"
rm "$CORE_DIR/.git/hooks/pre-push"
printf '#!/bin/sh\n# coredev hook shim\nexec true\n' > "$C/.git/hooks/pre-commit"
run_rc "$C"; echo "$OUT" | grep -qF "$INST" && pass || fail "0.2.x shim: install command missing: $OUT"
rm "$C/.git/hooks/pre-commit"
printf '#!/bin/sh\n# corecrew hook shim\nexec true\n' > "$C/.git/hooks/pre-commit"
printf '#!/bin/sh\n# my own hook\nexit 0\n' > "$C/.git/hooks/pre-push"
printf '#!/bin/sh\n# new-project hook\n# corecrew hook shim\n' > "$CORE_DIR/.git/hooks/pre-push"
run_rc "$C"; echo "$OUT" | grep -qF "install-hooks.sh" && fail "shim or user hook reported: $OUT" || pass
rm -f "$C/.git/hooks/pre-commit" "$C/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"
# real installer output is a shim: nothing to report
bash "$SCRIPTS/install-hooks.sh" "$P" >/dev/null 2>&1
run_rc "$C"; echo "$OUT" | grep -qF "install-hooks.sh" && fail "fresh shims reported: $OUT" || pass

# --- new layout: the CLAUDE.local.md link, created once, never overwritten; old layout is named
PR="$(dirname "$CORE_DIR")"
bash "$SKILL/scripts/scaffold.sh" --name newapp >/dev/null
NP="$CORE_DIR/newapp"; NC="$PR/newapp"
rm -f "$NC/CLAUDE.local.md"
run_rc "$NC"; assert_eq "$RC" "0" "new layout: exit"
echo "$OUT" | grep -qF "corecrew: linked CLAUDE.local.md to $NP/CLAUDE.md; restart the session to load it" && pass || fail "link created line missing: $OUT"
[ -L "$NC/CLAUDE.local.md" ] && pass || fail "symlink not created"
assert_eq "$(readlink "$NC/CLAUDE.local.md")" "$NP/CLAUDE.md" "link target"
echo "$OUT" | grep -qF "$NP/docs/INDEX.md" && pass || fail "new layout: project context missing: $OUT"
echo "$OUT" | grep -qF "still lives in" && fail "old-layout line in a new layout: $OUT" || pass
run_rc "$NC"; echo "$OUT" | grep -qF "linked CLAUDE.local.md" && fail "second run links again: $OUT" || pass
echo "$OUT" | grep -qF "created " && fail "link_local_claude line leaked: $OUT" || pass
echo "$OUT" | grep -qF "skipped " && fail "link_local_claude line leaked: $OUT" || pass
# from a worktree under the code folder and from the Core project folder: the link is in the main folder
rm "$NC/CLAUDE.local.md"; mkdir -p "$NC/.claude/worktrees/w1"
run_rc "$NC/.claude/worktrees/w1"; [ -L "$NC/CLAUDE.local.md" ] && pass || fail "worktree session: link not made in the main folder"
[ -e "$NC/.claude/worktrees/w1/CLAUDE.local.md" ] && fail "link made in the worktree" || pass
rm "$NC/CLAUDE.local.md"; run_rc "$NP"; [ -L "$NC/CLAUDE.local.md" ] && pass || fail "Core-folder session: link not made"
# a real file: left alone, one line names the fix
rm "$NC/CLAUDE.local.md"; printf 'mine\n' > "$NC/CLAUDE.local.md"
run_rc "$NC"; assert_eq "$RC" "0" "real file: exit"
assert_eq "$(cat "$NC/CLAUDE.local.md")" "mine" "real file untouched"; [ -L "$NC/CLAUDE.local.md" ] && fail "real file replaced" || pass
echo "$OUT" | grep -qF "ln -s \"$NP/CLAUDE.md\" \"$NC/CLAUDE.local.md\"" && pass || fail "real file: fix missing: $OUT"
echo "$OUT" | grep -qF "linked CLAUDE.local.md" && fail "real file: claims a link: $OUT" || pass
# a dangling link to an old Core path: left alone, same line
rm "$NC/CLAUDE.local.md"; ln -s "$CORE_DIR/gone/CLAUDE.md" "$NC/CLAUDE.local.md"
run_rc "$NC"; assert_eq "$(readlink "$NC/CLAUDE.local.md")" "$CORE_DIR/gone/CLAUDE.md" "dangling link untouched"
echo "$OUT" | grep -qF "ln -s \"$NP/CLAUDE.md\"" && pass || fail "dangling link: fix missing: $OUT"
rm "$NC/CLAUDE.local.md"
# the old layout: its line, no link
run_rc "$C"
echo "$OUT" | grep -qF "corecrew: this project still lives in $C; run /corecrew:task adopt $C to move it to $PR/sess-app" && pass || fail "old layout line missing: $OUT"
[ -e "$C/CLAUDE.local.md" ] && fail "link made in an old-layout code folder" || pass
# a folder of Projects that is not a project: nothing at all
mkdir -p "$PR/Brain"; run_rc "$PR/Brain"; assert_eq "$OUT" "" "Projects/Brain: silent"

# --- cwd given with JSON escapes (\u Cyrillic, \/ and \") in a Core whose path has a space
E="$SANDBOX/Мой проект \"q\""; mkdir -p "$E"
export CORE_DIR="$E/Ядро"
setup_core; scaffold_old esc-app
EP="$CORE_DIR/esc-app"
# JSON-escape the sandbox path: \u for Мой, \" for quotes, \/ for slashes
json_path="$(printf '%s' "$EP/code" | sed -e 's/"/\\"/g' -e 's|/|\\/|g' -e 's/Мой/\\u041c\\u043e\\u0439/')"
OUT="$(printf '{"cwd":"%s","source":"resume"}' "$json_path" | bash "$H" 2>&1)"; RC=$?
assert_eq "$RC" "0" "escaped cwd: exit"
echo "$OUT" | grep -qF "$EP/docs/INDEX.md" && pass || fail "escaped cwd not resolved: $OUT"
# core_dir through a symlink: cwd via the link resolves to the same project
ln -s "$E" "$SANDBOX/sym"; export CORE_DIR="$SANDBOX/sym/Ядро"
run_rc "$SANDBOX/sym/Ядро/esc-app/code"
echo "$OUT" | grep -qF "$EP/docs/INDEX.md" && pass || fail "symlinked core_dir: $OUT"

# --- a failing tools sync never blocks; one short line. Outside a project it goes to stderr, in a project to stdout.
export CORE_DIR="$P/.."; mkdir -p "$SANDBOX/emptyroot/scripts"
sync_fail() {  # sync_fail <cwd> — stdout in OUT, stderr in ERR, exit code in RC
  OUT="$(input "$1" | CLAUDE_PLUGIN_ROOT="$SANDBOX/emptyroot" bash "$H" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"
}
sync_fail "$SANDBOX/elsewhere"
assert_eq "$RC" "0" "sync failure: exit"
assert_eq "$OUT" "" "sync failure outside a project: nothing on stdout"
case "$ERR" in "corecrew: tools not refreshed"*) pass ;; *) fail "sync failure outside a project: stderr line expected, got: $ERR" ;; esac
assert_eq "$(echo "$ERR" | wc -l | tr -d ' ')" "1" "sync failure: one line"
sync_fail "$C"
assert_eq "$RC" "0" "sync failure in a project: exit"
echo "$OUT" | grep -q "^corecrew: tools not refreshed" && pass || fail "sync failure in a project: stdout line expected, got: $OUT"
assert_eq "$ERR" "" "sync failure in a project: nothing on stderr"

# --- letter case: Core path typed in another case than on disk (macOS volumes are case-insensitive)
mkdir -p "$SANDBOX/cs/a"
if [ -d "$SANDBOX/cs/A" ]; then
  export CORE_DIR="$SANDBOX/CaseCore/Ядро"; setup_core
  CP="$CORE_DIR/MyApp"; mkdir -p "$CP/code" "$CP/docs"; echo "# MyApp" > "$CP/CLAUDE.md"
  export CORE_DIR="$SANDBOX/casecore/ядро"
  run_rc "$CP/code"; echo "$OUT" | grep -qF "$CP/docs/INDEX.md" && pass || fail "CORE_DIR in other case, cwd as on disk: $OUT"
  run_rc "$SANDBOX/CASECORE/ЯДРО/myapp/code"; echo "$OUT" | grep -qF "$CP/docs/INDEX.md" && pass || fail "cwd in other case: $OUT"
else
  echo "  note: case-sensitive volume, letter-case test skipped"; pass
fi
finish
