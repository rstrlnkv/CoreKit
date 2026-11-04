#!/usr/bin/env bash
# The one table of every message the corecrew hooks show. Sourced by all five hooks.
#
#   msg <key> [arg ...]    prints the text of <key> in the language of the plugin setting ui_language
#                          ($CLAUDE_PLUGIN_OPTION_UI_LANGUAGE), without a final newline.
#   msg_has <key> <lang>   exit 0 when the table has a <lang> text for <key>.
#   MSG_KEYS               the list of keys (tests/test_hook_messages.sh checks both languages for each).
#
# Languages: en (default) and ru. An unset, empty, unknown or unsubstituted "${user_config." value is en.
# A key that lacks a text in the chosen language prints its en text.
# In a text, @1 @2 ... stand for the arguments. They are inserted as plain text (never as a printf
# format, never re-scanned), so a path with %, spaces, quotes or Cyrillic prints verbatim.
#
# To add a language, add one more branch with its texts to each key below (a "<lang>:<key>)" line next to the
# "en:" and "ru:" ones; a key without it falls back to en), and add the language to the ui_language
# options in .claude-plugin/plugin.json. Nothing else changes.
#
# Portable bash 3.2: no associative arrays, no case-change expansions.

MSG_KEYS="sync_failed hint_not_set_up hint_not_found project_header docs_index save_hint standards standards_none
session_rules schema_none run_starting layout_note old_hooks guard_code_blocked guard_code_public secrets_blocked secrets_ask
one_suite_wait dirty_code dirty_docs dirty_both stop_remind"

# _msg_text <lang> <key> — sets MSG_T to the text, or to nothing when there is none. Keep the keys and
# the en:/ru: branches in step with MSG_KEYS.
_msg_text() {
  MSG_T=""
  case "$1:$2" in
    en:sync_failed) MSG_T='corecrew: tools not refreshed: @1' ;;
    ru:sync_failed) MSG_T='corecrew: инструменты не обновлены: @1' ;;
    en:hint_not_set_up) MSG_T='corecrew: Core at @1 is not set up — /corecrew:new-project or /corecrew:task adopt <folder> will set it up' ;;
    ru:hint_not_set_up) MSG_T='corecrew: Core в @1 не настроен — /corecrew:new-project или /corecrew:task adopt <folder> настроят его' ;;
    en:hint_not_found) MSG_T='corecrew: Core not found at @1 — /corecrew:new-project or /corecrew:task adopt <folder> will set it up' ;;
    ru:hint_not_found) MSG_T='corecrew: Core не найден в @1 — /corecrew:new-project или /corecrew:task adopt <folder> создадут его' ;;
    en:project_header) MSG_T='corecrew: you are in the Core project "@1" (Core: @2)' ;;
    ru:project_header) MSG_T='corecrew: вы в проекте Core "@1" (Core: @2)' ;;
    en:docs_index) MSG_T='Project docs index: @1' ;;
    ru:docs_index) MSG_T='Индекс документации проекта: @1' ;;
    en:save_hint) MSG_T='Save a finished step: bash "@1" "<message>"@2; undo the last step: bash "@3"' ;;
    ru:save_hint) MSG_T='Сохранить завершённый шаг: bash "@1" "<message>"@2; отменить последний шаг: bash "@3"' ;;
    en:standards) MSG_T='Standards: @1' ;;
    ru:standards) MSG_T='Стандарты: @1' ;;
    en:standards_none) MSG_T='none' ;;
    ru:standards_none) MSG_T='нет' ;;
    en:session_rules) MSG_T='Session rules (@1):' ;;
    ru:session_rules) MSG_T='Правила сессии (@1):' ;;
    en:schema_none) MSG_T='none' ;;
    ru:schema_none) MSG_T='не указана' ;;
    en:run_starting) MSG_T='a run that is starting' ;;
    ru:run_starting) MSG_T='тест, который запускается' ;;
    en:layout_note) MSG_T='Layout note: this Core has layout schema @1, the plugin expects @2. Bring it up to date (adds only what is missing): bash "@3" "@4"' ;;
    ru:layout_note) MSG_T='Заметка о структуре: структура этого Core — версия @1, плагину нужна @2. Обновите её (добавится только недостающее): bash "@3" "@4"' ;;
    en:old_hooks) MSG_T='Old git hooks from an older version: @1. Replace them with: bash "@2" "@3"' ;;
    ru:old_hooks) MSG_T='Найдены старые git-хуки от прошлой версии: @1. Замените их командой: bash "@2" "@3"' ;;
    en:guard_code_blocked) MSG_T='corecrew: @1 is an internal file and must not live in code/. Write it to @2 instead.' ;;
    ru:guard_code_blocked) MSG_T='corecrew: @1 — внутренний файл, ему не место в code/. Запишите его в @2.' ;;
    en:guard_code_public) MSG_T='Docs meant to stay public in code/: list them on a "public-docs: <paths>" line in @1.' ;;
    ru:guard_code_public) MSG_T='Документы, которые должны остаться в code/ публичными, перечислите в строке "public-docs: <paths>" в @1.' ;;
    en:secrets_blocked) MSG_T='corecrew: reading secrets is blocked (@1)' ;;
    ru:secrets_blocked) MSG_T='corecrew: чтение секретов заблокировано (@1)' ;;
    en:secrets_ask) MSG_T='Ask the user to check the value themselves, or use .env.example.' ;;
    ru:secrets_ask) MSG_T='Попросите пользователя проверить значение самому или используйте .env.example.' ;;
    en:one_suite_wait) MSG_T='one-suite: a test run is still in progress after @1 s of waiting (@2) — run the same command again: this hook waits for it. If it is a watcher you started, stop it first.' ;;
    ru:one_suite_wait) MSG_T='one-suite: тесты всё ещё идут после ожидания @1 с (@2) — запустите ту же команду ещё раз: хук дождётся. Если это процесс, который сам перезапускает тесты при изменении файлов, сначала остановите его.' ;;
    en:dirty_code) MSG_T='code' ;;
    ru:dirty_code) MSG_T='код' ;;
    en:dirty_docs) MSG_T='docs' ;;
    ru:dirty_docs) MSG_T='документация' ;;
    en:dirty_both) MSG_T='code and docs' ;;
    ru:dirty_both) MSG_T='код и документация' ;;
    en:stop_remind) MSG_T='Uncommitted changes in @1. If this working step is finished, run: bash "@2" "<short English message>"@3. If you are waiting for the user'"'"'s answer or approval, do not save; just end your turn.' ;;
    ru:stop_remind) MSG_T='Есть несохранённые изменения: @1. Если этот рабочий шаг закончен, выполните: bash "@2" "<short English message>"@3. Если вы ждёте ответа или одобрения пользователя, не сохраняйте, просто закончите ответ.' ;;
  esac
}

# _msg_lang — the language to use: en or ru.
_msg_lang() {
  local l
  if type opt_value >/dev/null 2>&1; then l="$(opt_value "${CLAUDE_PLUGIN_OPTION_UI_LANGUAGE:-}")"
  else case "${CLAUDE_PLUGIN_OPTION_UI_LANGUAGE:-}" in *'${user_config.'*) l="" ;; *) l="${CLAUDE_PLUGIN_OPTION_UI_LANGUAGE:-}" ;; esac
  fi
  case "$l" in ru) printf 'ru' ;; *) printf 'en' ;; esac
}

msg_has() { _msg_text "$2" "$1"; [ -n "$MSG_T" ]; }

# msg <key> [arg ...]
msg() {
  local key="$1" lang tpl out="" d
  shift
  lang="$(_msg_lang)"
  _msg_text "$lang" "$key"
  [ -n "$MSG_T" ] || _msg_text en "$key"
  tpl="$MSG_T"
  while :; do
    case "$tpl" in *@*) ;; *) break ;; esac
    out="$out${tpl%%@*}"; tpl="${tpl#*@}"
    d="${tpl:0:1}"
    case "$d" in
      [1-9]) if [ "$d" -le "$#" ]; then out="$out${!d}"; fi; tpl="${tpl:1}" ;;
      *) out="$out@" ;;
    esac
  done
  printf '%s' "$out$tpl"
}
