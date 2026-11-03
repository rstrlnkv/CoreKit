#!/usr/bin/env bash
# hooks/messages.sh and the language of every message the five hooks show. The plugin setting
# ui_language (CLAUDE_PLUGIN_OPTION_UI_LANGUAGE) is en (default) or ru; an unset, empty, unknown or
# unsubstituted "${user_config.ui_language}" value means en. Arguments print verbatim. Every key in the
# table has both an en and a ru text. Exit codes and stdout/stderr channels stay as they were.
source "$(dirname "$0")/lib.sh"
new_sandbox
M="$HOOKS/messages.sh"
export CLAUDE_PLUGIN_ROOT="$ROOT"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
assert_file "$M"

# --- The table: both languages for every key; the key list matches the branches; every key used by a hook exists.
(
  . "$M" 2>/dev/null || exit 3
  [ -n "${MSG_KEYS:-}" ] || exit 4
  for k in $MSG_KEYS; do
    msg_has "$k" en || { echo "key $k lacks en"; exit 1; }
    msg_has "$k" ru || { echo "key $k lacks ru"; exit 1; }
  done
  exit 0
) >"$SANDBOX/tbl.out" 2>&1; assert_eq "$?" "0" "every key has en and ru: $(cat "$SANDBOX/tbl.out")"
branches="$(grep -oE '^[[:space:]]*(en|ru):[a-z_]+\)' "$M" | sed -E 's/^[[:space:]]*//; s/\)$//' | LC_ALL=C sort)"
wanted="$(. "$M" 2>/dev/null; for k in $MSG_KEYS; do echo "en:$k"; echo "ru:$k"; done | LC_ALL=C sort)"
assert_eq "$branches" "$wanted" "MSG_KEYS and the en:/ru: branches agree"
used="$(grep -ohE '\bmsg[[:space:]]+[a-z_]+' "$HOOKS"/session-start.sh "$HOOKS"/guard-code.sh "$HOOKS"/guard-secrets.sh \
  "$HOOKS"/one-suite.sh "$HOOKS"/stop-remind.sh | awk '{print $2}' | LC_ALL=C sort -u)"
[ -n "$used" ] && pass || fail "no hook calls msg"
for k in $used; do (. "$M"; msg_has "$k" en) && pass || fail "hook uses key $k that is not in the table"; done
for k in $(. "$M" 2>/dev/null; echo $MSG_KEYS); do
  printf '%s\n' "$used" | grep -qx "$k" && pass || fail "key $k is not used by any hook"
done
assert_contains "$M" "add one more branch with its texts to each key below"   # the header says how to add a language

# --- msg: language choice and verbatim arguments.
text() { # text <lang-variant> <key> [args]
  local v="$1"; shift
  case "$v" in
    unset) ( unset CLAUDE_PLUGIN_OPTION_UI_LANGUAGE; . "$M"; msg "$@" ) ;;
    *) ( export CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="$v"; . "$M"; msg "$@" ) ;;
  esac
}
PLACEHOLDER='${user_config.ui_language}'
for v in unset en "" xx EN "$PLACEHOLDER"; do
  assert_eq "$(text "$v" docs_index /p)" "Project docs index: /p" "language '$v' is English"
done
assert_eq "$(text ru docs_index /p)" "Индекс документации проекта: /p" "ru text"
# a hostile argument: spaces, %s %d %%, quotes, backslash, ampersand, @1 @2, Cyrillic, a trailing newline is kept out
NASTY='/tmp/a b %s %d %% "q" '"'"'s'"'"' \n \\ & @2 @1 \1 $HOME `x` проект'
assert_eq "$(text en docs_index "$NASTY")" "Project docs index: $NASTY" "verbatim argument (en)"
assert_eq "$(text ru docs_index "$NASTY")" "Индекс документации проекта: $NASTY" "verbatim argument (ru)"
# two arguments: the second is not re-read as a placeholder, order is by placeholder number
assert_eq "$(text en project_header '@2' '@1')" 'corecrew: you are in the Core project "@2" (Core: @1)' "args are not re-substituted"
assert_eq "$(text ru project_header 'p q' '/c d')" 'corecrew: вы в проекте Core "p q" (Core: /c d)' "ru two args"
# a missing argument prints nothing for its placeholder; an unknown key prints nothing and succeeds
assert_eq "$(text en docs_index)" "Project docs index: " "missing arg"
assert_eq "$(text en no_such_key a)" "" "unknown key"

# --- helpers for the hook runs
# vrun <variant> <cmd...> — runs with the language variant in the environment
vrun() {
  local v="$1"; shift
  case "$v" in
    unset) env -u CLAUDE_PLUGIN_OPTION_UI_LANGUAGE "$@" ;;
    *) env CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="$v" "$@" ;;
  esac
}
# check <variant> <label> <text> <en fragments> <ru fragments> — fragments one per line; the text has all of the
# fragments of its language and none of the other language's
check() {
  local v="$1" label="$2" got="$3" en="$4" ru="$5" want other f
  if [ "$v" = ru ]; then want="$ru"; other="$en"; else want="$en"; other="$ru"; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$got" in *"$f"*) pass ;; *) fail "$label [$v]: lacks '$f' in: $got" ;; esac
  done <<EOF
$want
EOF
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$got" in *"$f"*) fail "$label [$v]: has the other language's '$f'" ;; *) pass ;; esac
  done <<EOF
$other
EOF
}
VARIANTS=(unset en ru xx "$PLACEHOLDER")

# --- session-start: stdout and exit 0 in every case
H="$HOOKS/session-start.sh"
input() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }
mkdir -p "$SANDBOX/elsewhere"
for v in "${VARIANTS[@]}"; do
  rm -rf "$CLAUDE_PLUGIN_DATA/state"
  OUT="$(input "$SANDBOX/elsewhere" | vrun "$v" bash "$H" 2>"$SANDBOX/err")"; RC=$?
  assert_eq "$RC" "0" "session-start hint exit [$v]"; assert_eq "$(cat "$SANDBOX/err")" "" "session-start hint: stderr empty [$v]"
  check "$v" "core not found" "$OUT" "corecrew: Core not found at $CORE_DIR — /corecrew:new-project or /corecrew:task adopt <folder> will set it up" \
    "corecrew: Core не найден в $CORE_DIR — /corecrew:new-project или /corecrew:task adopt <folder> создадут его"
done
mkdir -p "$CORE_DIR"
for v in en ru; do
  rm -rf "$CLAUDE_PLUGIN_DATA/state"
  OUT="$(input "$SANDBOX/elsewhere" | vrun "$v" bash "$H" 2>&1)"
  check "$v" "core not set up" "$OUT" "corecrew: Core at $CORE_DIR is not set up — /corecrew:new-project or /corecrew:task adopt <folder> will set it up" \
    "corecrew: Core в $CORE_DIR не настроен — /corecrew:new-project или /corecrew:task adopt <folder> настроят его"
done
# inside a project with spaces, %s, quotes and Cyrillic in the names; no schema; an old hook; session rules; two standards
PN="my app %s 'q' проект"
P="$CORE_DIR/$PN"; mkdir -p "$P/code/.git/hooks" "$CORE_DIR/standards" "$CORE_DIR/.git/hooks"
: > "$P/CLAUDE.md"; : > "$CORE_DIR/standards/a.md"; : > "$CORE_DIR/standards/b.md"
echo "# new-project hook" > "$P/code/.git/hooks/pre-commit"
printf 'rule one\nrule two' > "$CORE_DIR/session-rules.md"
for v in "${VARIANTS[@]}"; do
  OUT="$(input "$P/code" | vrun "$v" bash "$H" 2>"$SANDBOX/err")"; RC=$?
  assert_eq "$RC" "0" "session-start project exit [$v]"; assert_eq "$(cat "$SANDBOX/err")" "" "session-start project: stderr empty [$v]"
  check "$v" "project" "$OUT" "corecrew: you are in the Core project \"$PN\" (Core: $CORE_DIR)
Project docs index: $P/docs/INDEX.md
Save a finished step: bash \"$COREDEV_TOOLS/save\" \"<message>\"; undo the last step: bash \"$COREDEV_TOOLS/undo-step\"
Standards: a, b
Session rules ($CORE_DIR/session-rules.md):
Layout note: this Core has layout schema none, the plugin expects 1. Bring it up to date (adds only what is missing): bash \"$ROOT/scripts/setup-core.sh\" \"$CORE_DIR\"
Old git hooks from an older version: $P/code/.git/hooks/pre-commit. Replace them with: bash \"$ROOT/scripts/install-hooks.sh\" \"$P\"" \
"corecrew: вы в проекте Core \"$PN\" (Core: $CORE_DIR)
Индекс документации проекта: $P/docs/INDEX.md
Сохранить завершённый шаг: bash \"$COREDEV_TOOLS/save\" \"<message>\"; отменить последний шаг: bash \"$COREDEV_TOOLS/undo-step\"
Стандарты: a, b
Правила сессии ($CORE_DIR/session-rules.md):
Заметка о структуре: структура этого Core — версия не указана, плагину нужна 1. Обновите её (добавится только недостающее): bash \"$ROOT/scripts/setup-core.sh\" \"$CORE_DIR\"
Найдены старые git-хуки от прошлой версии: $P/code/.git/hooks/pre-commit. Замените их командой: bash \"$ROOT/scripts/install-hooks.sh\" \"$P\""
  case "$OUT" in *"):"$'\n'"rule one"$'\n'"rule two"$'\n'*) pass ;; *) fail "session rules text not printed verbatim [$v]: $OUT" ;; esac
done
rm -f "$CORE_DIR/standards/a.md" "$CORE_DIR/standards/b.md"
for v in en ru; do
  OUT="$(input "$P/code" | vrun "$v" bash "$H" 2>&1)"
  check "$v" "no standards" "$OUT" "Standards: none" "Стандарты: нет"
done
# attribution=forbid adds the flag in both languages
OUT="$(input "$P/code" | CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid vrun ru bash "$H" 2>&1)"
check ru "forbid flag" "$OUT" "" "\"<message>\" --no-attribution; отменить"
# a failing tools refresh: on stdout inside a project, on stderr elsewhere
mkdir -p "$SANDBOX/emptyroot"
OUT="$(input "$P/code" | CLAUDE_PLUGIN_ROOT="$SANDBOX/emptyroot" vrun ru bash "$H" 2>/dev/null)"
check ru "sync failed (project, stdout)" "$OUT" "" "corecrew: инструменты не обновлены: "
OUT="$(input "$P/code" | CLAUDE_PLUGIN_ROOT="$SANDBOX/emptyroot" vrun en bash "$H" 2>/dev/null)"
check en "sync failed (project, stdout)" "$OUT" "corecrew: tools not refreshed: " ""
OUT="$(input "$SANDBOX/elsewhere" | CLAUDE_PLUGIN_ROOT="$SANDBOX/emptyroot" vrun ru bash "$H" 2>&1 >/dev/null)"
check ru "sync failed (elsewhere, stderr)" "$OUT" "" "corecrew: инструменты не обновлены: "
rm -rf "$CORE_DIR" "$CLAUDE_PLUGIN_DATA/state"

# --- a project for the remaining hooks
PN2="app %s 'q' проект"
mkdir -p "$CORE_DIR/$PN2/code/src" "$CORE_DIR/$PN2/docs"; : > "$CORE_DIR/$PN2/CLAUDE.md"
C="$CORE_DIR/$PN2/code"

# --- guard-code: two lines on stderr, nothing on stdout, exit 2
H="$HOOKS/guard-code.sh"
pl() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$C" "$1"; }
for v in "${VARIANTS[@]}"; do
  pl "$C/docs/plan.md" | vrun "$v" bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
  assert_eq "$RC" "2" "guard-code exit [$v]"; assert_eq "$(cat "$SANDBOX/out")" "" "guard-code: stdout empty [$v]"
  check "$v" "guard-code" "$(cat "$SANDBOX/err")" \
"corecrew: $C/docs/plan.md is an internal file and must not live in code/. Write it to $CORE_DIR/$PN2/docs/plan.md instead.
Docs meant to stay public in code/: list them on a \"public-docs: <paths>\" line in $CORE_DIR/$PN2/CLAUDE.md." \
"corecrew: $C/docs/plan.md — внутренний файл, ему не место в code/. Запишите его в $CORE_DIR/$PN2/docs/plan.md.
Документы, которые должны остаться в code/ публичными, перечислите в строке \"public-docs: <paths>\" в $CORE_DIR/$PN2/CLAUDE.md."
done

# --- guard-secrets
H="$HOOKS/guard-secrets.sh"
echo "FAKE=1" > "$C/.env"
pl() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$C" "$1"; }
for v in "${VARIANTS[@]}"; do
  pl "$C/.env" | vrun "$v" bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
  assert_eq "$RC" "2" "guard-secrets exit [$v]"; assert_eq "$(cat "$SANDBOX/out")" "" "guard-secrets: stdout empty [$v]"
  check "$v" "guard-secrets" "$(cat "$SANDBOX/err")" \
"corecrew: reading secrets is blocked ($C/.env)
Ask the user to check the value themselves, or use .env.example." \
"corecrew: чтение секретов заблокировано ($C/.env)
Попросите пользователя проверить значение самому или используйте .env.example."
done

# --- one-suite: the refusal on stderr, exit 2
H="$HOOKS/one-suite.sh"
FAKE="onesuite-fake-run-$$"
export ONE_SUITE_PROCS="$FAKE" ONE_SUITE_WAIT=0 ONE_SUITE_GRACE=0 ONE_SUITE_TURN="$SANDBOX/turn"
dummy=""; trap '[ -z "$dummy" ] || kill "$dummy" 2>/dev/null; chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
bash -c "exec -a $FAKE sleep 120" >/dev/null 2>&1 & dummy=$!; disown "$dummy" 2>/dev/null
sleep 1
for v in "${VARIANTS[@]}"; do
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test","description":"run"}}' "$C" \
    | vrun "$v" bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
  assert_eq "$RC" "2" "one-suite exit [$v]"; assert_eq "$(cat "$SANDBOX/out")" "" "one-suite: stdout empty [$v]"
  check "$v" "one-suite" "$(cat "$SANDBOX/err")" \
"one-suite: a test run is still in progress after 0 s of waiting (" \
"one-suite: тесты всё ещё идут после ожидания 0 с ("
  case "$(cat "$SANDBOX/err")" in *"$FAKE"*) pass ;; *) fail "one-suite [$v]: the running command is not named" ;; esac
  case "$v" in ru) check "$v" "one-suite tail" "$(cat "$SANDBOX/err")" "" "запустите ту же команду ещё раз: хук дождётся. Если это процесс, который сам перезапускает тесты при изменении файлов, сначала остановите его." ;;
    *) check "$v" "one-suite tail" "$(cat "$SANDBOX/err")" "run the same command again: this hook waits for it." "" ;; esac
done
kill "$dummy" 2>/dev/null; dummy=""
# nothing is running but another call holds a fresh turn: the refusal names "a run that is starting"
mkdir -p "$SANDBOX/turn2"; date +%s > "$SANDBOX/turn2/at"
for v in en ru; do
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test","description":"run"}}' "$C" \
    | ONE_SUITE_TURN="$SANDBOX/turn2" ONE_SUITE_GRACE=1000 vrun "$v" bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"
  assert_eq "$?" "2" "one-suite starting-run exit [$v]"
  check "$v" "one-suite starting" "$(cat "$SANDBOX/err")" "(a run that is starting)" "(тест, который запускается)"
done

# --- stop-remind: the reminder on stderr, exit 2; the dirty-part words follow the language
H="$HOOKS/stop-remind.sh"
setup_core; sync_tools
bash "$SKILL/scripts/scaffold.sh" --name stop-app >/dev/null
SP="$CORE_DIR/stop-app"; SC="$SP/code"
(cd "$SC" && bash "$SCRIPTS/save" "init") >/dev/null 2>&1
sinput() { printf '{"session_id":"x","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$SC"; }
n=0
for v in "${VARIANTS[@]}"; do
  n=$((n + 1)); echo "change $n" > "$SC/new.txt"      # a new change each time: the reminder is once per set of changes
  sinput | vrun "$v" bash "$H" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
  assert_eq "$RC" "2" "stop-remind exit [$v]"; assert_eq "$(cat "$SANDBOX/out")" "" "stop-remind: stdout empty [$v]"
  check "$v" "stop-remind" "$(cat "$SANDBOX/err")" \
"Uncommitted changes in code. If this working step is finished, run: bash \"$SCRIPTS/save\" \"<short English message>\". If you are waiting for the user's answer or approval, do not save; just end your turn." \
"Есть несохранённые изменения: код. Если этот рабочий шаг закончен, выполните: bash \"$SCRIPTS/save\" \"<short English message>\". Если вы ждёте ответа или одобрения пользователя, не сохраняйте, просто закончите ответ."
done
(cd "$SC" && bash "$SCRIPTS/save" "s") >/dev/null 2>&1
echo y >> "$SP/docs/brief.md"
sinput | vrun ru bash "$H" 2>&1 >/dev/null | grep -qF "изменения: документация." && pass || fail "stop-remind ru: docs only"
echo z > "$SC/n2.txt"
sinput | vrun ru bash "$H" 2>&1 >/dev/null | grep -qF "изменения: код и документация." && pass || fail "stop-remind ru: code and docs"
echo w > "$SC/n3.txt"
sinput | vrun en bash "$H" 2>&1 >/dev/null | grep -qF "changes in code and docs." && pass || fail "stop-remind en: code and docs"

finish
