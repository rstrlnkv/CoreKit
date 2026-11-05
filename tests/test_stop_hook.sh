#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
bash "$SKILL/scripts/scaffold.sh" --name stop-app >/dev/null
P="$CORE_DIR/stop-app"; C="$(dirname "$CORE_DIR")/stop-app"; H="$HOOKS/stop-remind.sh"
assert_file "$H"
J="$C/.claude/settings.local.json"
python3 -m json.tool "$J" >/dev/null 2>&1 && pass || fail "settings.local.json is not valid JSON"
# the Stop hook ships with the plugin; the project settings carry no hooks and no Core/bin path
assert_not_contains "$J" "\"Stop\""; assert_not_contains "$J" "\"hooks\""
assert_not_contains "$J" "stop-remind"; assert_contains "$J" "\"$P\""
assert_not_contains "$SKILL/templates/code/settings.local.json.tmpl" "\"hooks\""
HJ="$PLUGIN/hooks/hooks.json"
python3 -m json.tool "$HJ" >/dev/null 2>&1 && pass || fail "hooks.json is not valid JSON"
assert_contains "$HJ" "\"Stop\""
assert_contains "$HJ" 'bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-remind.sh\"'
assert_contains "$HJ" "\"timeout\": 10"
(cd "$C" && bash "$SCRIPTS/save" "init") >/dev/null 2>&1

input() { printf '{"session_id":"x","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2"; }
# clean -> 0
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "clean repo should pass"
# dirty code -> 2 with message naming save
echo x > "$C/new.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "2" "dirty code should block"; echo "$OUT" | grep -q 'save' && pass || fail "message lacks save"
echo "$OUT" | grep -qF "bash \"$SCRIPTS/save\"" && pass || fail "message does not name the plugin's save ($SCRIPTS/save): $OUT"
echo "$OUT" | grep -qF "/bin/save" && fail "message names a Core/bin copy: $OUT" || pass
echo "$OUT" | grep -q 'waiting for the user' && pass || fail "message lacks the waiting-for-approval case"
# already reminded -> 0
input "$C" true | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "stop_hook_active must not loop"
# same changes at the next stop (e.g. waiting for approval) -> no repeat
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "repeated reminder for unchanged state"
# new edits, also to an already untracked file -> remind again
echo more >> "$C/new.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no reminder after new edits"
assert_eq "$(git -C "$C" status --porcelain)" "?? new.txt" "hook left files in the worktree"
# dirty docs only -> 2
(cd "$C" && bash "$SCRIPTS/save" "s") >/dev/null 2>&1; echo y >> "$P/docs/brief.md"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "dirty docs should block"
# a session in <Core>/<name>/ of a new-layout project: the reminder covers the code folder beside the Core
(cd "$C" && bash "$SCRIPTS/save" "s-core") >/dev/null 2>&1; echo z > "$C/from-core.txt"
OUT=$(input "$P" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "2" "dirty code, session in <Core>/<name>/: $OUT"
echo "$OUT" | grep -q 'save' && pass || fail "reminder from <Core>/<name>/ lacks save: $OUT"
(cd "$C" && bash "$SCRIPTS/save" "s-core2") >/dev/null 2>&1
# outside a project -> 0 (never block unrelated sessions)
OUT=$(input "$SANDBOX" false | bash "$H" 2>&1); assert_eq "$?" "0" "outside project should pass"
assert_eq "$OUT" "" "hook must stay silent outside a Core project"

# untracked file with a non-ASCII name: edits are noticed, no cksum errors reach Claude
(cd "$C" && bash "$SCRIPTS/save" "s2") >/dev/null 2>&1
echo a > "$C/заметки.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); assert_eq "$?" "2" "non-ASCII file: first reminder"
assert_eq "$(echo "$OUT" | grep -c 'No such file')" "0" "cksum error in reminder: $OUT"
echo b >> "$C/заметки.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "edit of non-ASCII untracked file missed"

# repo with no commits yet (right after scaffold): edits to a staged file are noticed
bash "$SKILL/scripts/scaffold.sh" --name fresh-app >/dev/null; F="$(dirname "$CORE_DIR")/fresh-app"
echo 1 > "$F/a.txt"; git -C "$F" add a.txt; echo 2 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: first reminder"
echo 3 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: edit of staged file missed"
# cwd with JSON escapes: a Core whose path has a space, quotes and Cyrillic (written as \u, \/ and \")
OLD_CORE="$CORE_DIR"; EC="$SANDBOX/Мой проекты \"q\"/Ядро"; export CORE_DIR="$EC"; setup_core
bash "$SKILL/scripts/scaffold.sh" --name esc-app >/dev/null; X="$(dirname "$EC")/esc-app"
echo x > "$X/new.txt"
esc_json() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's|/|\\/|g' -e 's/Мой/\\u041c\\u043e\\u0439/'; }
printf '{"session_id":"x",\n "cwd" :\n "%s", "hook_event_name":"Stop","stop_hook_active":false}' "$(esc_json "$X")" | bash "$H" >/dev/null 2>&1
assert_eq "$?" "2" "escaped cwd (quote, space, \\u) must still find the project"
export CORE_DIR="$OLD_CORE"
# a cwd that is not valid JSON-wise parseable lets the stop through
printf '{"cwd":"/no/such/\\' | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "broken JSON passes"
# a nested repo with the Core shape but outside the Core (other/proj/code): the hook stays inert
O="$SANDBOX/other"; mkdir -p "$O/proj/code"
git init -q "$O"; echo r > "$O/readme.txt"; git -C "$O" add -A; git -C "$O" commit -q -m o
git init -q "$O/proj/code"; echo a > "$O/proj/code/a.txt"; git -C "$O/proj/code" add -A; git -C "$O/proj/code" commit -q -m a
echo dirty > "$O/proj/code/new.txt"; echo dirty >> "$O/proj/notes.md"
OUT=$(input "$O/proj/code" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "0" "non-Core other/proj/code must pass"
assert_eq "$OUT" "" "hook must stay silent in a non-Core other/proj/code"
assert_no_file "$O/proj/code/.git/new-project-stop-remind"
# attribution=forbid: the reminder's save command carries --no-attribution
echo more >> "$C/new.txt"
OUT=$(input "$C" false | CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid bash "$H" 2>&1)
echo "$OUT" | grep -qF "bash \"$SCRIPTS/save\" \"<short English message>\" --no-attribution" && pass || fail "forbid: reminder lacks --no-attribution: $OUT"
echo more >> "$C/new.txt"
OUT=$(input "$C" false | bash "$H" 2>&1)
echo "$OUT" | grep -qF -- "--no-attribution" && fail "allow: reminder has --no-attribution: $OUT" || pass

finish
