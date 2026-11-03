#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core
bash "$SKILL/scripts/scaffold.sh" --name stop-app >/dev/null
P="$CORE_DIR/stop-app"; C="$P/code"; H="$HOOKS/stop-remind.sh"
assert_file "$H"
J="$C/.claude/settings.local.json"
python3 -m json.tool "$J" >/dev/null 2>&1 && pass || fail "settings.local.json is not valid JSON"
assert_contains "$J" "\"Stop\""; assert_contains "$J" "$CORE_DIR/bin/stop-remind.sh"
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
# outside a project -> 0 (never block unrelated sessions)
input "$SANDBOX" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "outside project should pass"

# untracked file with a non-ASCII name: edits are noticed, no cksum errors reach Claude
(cd "$C" && bash "$SCRIPTS/save" "s2") >/dev/null 2>&1
echo a > "$C/заметки.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); assert_eq "$?" "2" "non-ASCII file: first reminder"
assert_eq "$(echo "$OUT" | grep -c 'No such file')" "0" "cksum error in reminder: $OUT"
echo b >> "$C/заметки.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "edit of non-ASCII untracked file missed"

# repo with no commits yet (right after scaffold): edits to a staged file are noticed
bash "$SKILL/scripts/scaffold.sh" --name fresh-app >/dev/null; F="$CORE_DIR/fresh-app/code"
echo 1 > "$F/a.txt"; git -C "$F" add a.txt; echo 2 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: first reminder"
echo 3 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: edit of staged file missed"
finish
