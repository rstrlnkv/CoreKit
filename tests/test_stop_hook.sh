#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox
bash "$SKILL/scripts/scaffold.sh" --name stop-app >/dev/null
P="$CORE_DIR/stop-app"; C="$P/code"; H="$CORE_DIR/bin/stop-remind.sh"
assert_file "$H"
J="$C/.claude/settings.local.json"
python3 -m json.tool "$J" >/dev/null 2>&1 && pass || fail "settings.local.json is not valid JSON"
assert_contains "$J" "\"Stop\""; assert_contains "$J" "$CORE_DIR/bin/stop-remind.sh"
(cd "$C" && bash "$CORE_DIR/bin/save" "init") >/dev/null 2>&1

input() { printf '{"session_id":"x","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2"; }
# clean -> 0
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "clean repo should pass"
# dirty code -> 2 with message naming save
echo x > "$C/new.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "2" "dirty code should block"; echo "$OUT" | grep -q 'save' && pass || fail "message lacks save"
# already reminded -> 0
input "$C" true | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "stop_hook_active must not loop"
# dirty docs only -> 2
(cd "$C" && bash "$CORE_DIR/bin/save" "s") >/dev/null 2>&1; echo y >> "$P/docs/brief.md"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "dirty docs should block"
# outside a project -> 0 (never block unrelated sessions)
input "$SANDBOX" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "outside project should pass"
finish
