#!/usr/bin/env bash
# The one table of every message the corecrew hooks show. Sourced by all five hooks, by prepare.sh and by the
# lib.sh CLI (core-dir and settings print their settings warnings in English with msg_settings_warning).
#
#   msg <key> [arg ...]    prints the text of <key> in the language of the setting ui_language
#                          (lib.sh resolve_setting: plugin option, then settings file), without a final newline.
#   msg_has <key> <lang>   exit 0 when the table has a <lang> text for <key>.
#   MSG_LANGS              the one list of languages; en is the default.
#   MSG_KEYS               the list of keys (tests/test_hook_messages.sh checks every language for each).
#   MSG_EN_ONLY            the keys that have only an en text, each with its reason beside the list.
#
# Source lib.sh first (every hook does). The language is UI_LANGUAGE (load_settings sets it), else lib.sh's
# resolve_setting ui_language; an empty value, or one not in MSG_LANGS, is en.
# A key that lacks a text in the chosen language prints its en text: only the keys of MSG_EN_ONLY lack one.
# In a text, @1 @2 ... stand for the arguments. They are inserted as plain text (never as a printf
# format, never re-scanned), so a path with %, spaces, quotes or Cyrillic prints verbatim. Every language of a
# key has the placeholders of its en text.
#
# To add a language, add it to MSG_LANGS and give each key below, but those of MSG_EN_ONLY, one more branch: a
# "<lang>:<key>)" line beside the key's other branches (a key's branches stand together). Then add the language to
# the ui_language options in .claude-plugin/plugin.json and to _setting_valid in scripts/lib-settings.sh.
# tests/test_hook_messages.sh checks each of these.
#
# Portable bash 3.2: no associative arrays, no case-change expansions.

MSG_LANGS="en ru"
# shellcheck disable=SC2034  # MSG_KEYS is read by tests/test_hook_messages.sh (every language for every key)
MSG_KEYS="sync_failed sync_not_ours agents_in_core hint_not_set_up hint_not_found project_header docs_index save_hint standards standards_none
session_rules schema_none run_starting layout_note hooks_path hooks_path_empty guard_code_blocked guard_code_public guard_code_too_many patch_too_many patch_unjudgeable patch_no_reader patch_shell secrets_blocked secrets_ask
local_link_created agents_link_created agents_link_wrong agents_link_failed local_link_wrong local_link_failed old_layout one_suite_wait dirty_code dirty_docs dirty_both stop_remind
readonly_agent settings_invalid_path settings_invalid_value settings_unreadable settings_no_home allowed_attribution allowed_model_profile
src_env src_option src_file fix_env fix_option fix_file codex_trust codex_profile"
# readonly_agent: the read-only checker's refusal is read only by a subagent (designer, localizer, security,
# verifier) told to work in English, never by the person, so it stays English, as do the reasons in its @2.
# shellcheck disable=SC2034  # read by tests/test_hook_messages.sh
MSG_EN_ONLY="readonly_agent"

# _msg_text <lang> <key> — sets MSG_T to the text, or to nothing when there is none. Keep the keys and
# their <lang>: branches in step with MSG_KEYS and MSG_LANGS.
_msg_text() {
  MSG_T=""
  case "$1:$2" in
    en:sync_failed) MSG_T='corecrew: tools not refreshed: could not update @1' ;;
    ru:sync_failed) MSG_T='corecrew: инструменты не обновлены: не удалось обновить @1' ;;
    en:sync_not_ours) MSG_T='corecrew: tools not refreshed: @1 is not a corecrew tools folder; move it away and start a new session' ;;
    ru:sync_not_ours) MSG_T='corecrew: инструменты не обновлены: @1 — не папка инструментов corecrew; уберите её и начните новую сессию' ;;
    en:agents_in_core) MSG_T='corecrew: AGENTS.md exists in the Core at @1; fold it into CLAUDE.md and remove it, then the AGENTS.md link can be made' ;;
    ru:agents_in_core) MSG_T='corecrew: AGENTS.md есть в Core в @1; перенесите его в CLAUDE.md и удалите, тогда можно будет создать ссылку AGENTS.md' ;;
    en:codex_trust) MSG_T="corecrew's guards (project docs in code, secrets) and the save reminder are not active in Codex until you trust the corecrew hooks: open /hooks, review them, trust them, then start a new session (or restart if you just did)." ;;
    ru:codex_trust) MSG_T='Защита corecrew (внутренние документы в коде, секреты) и напоминание сохранить изменения не работают в Codex, пока вы не доверите хуки corecrew: откройте /hooks, просмотрите хуки и доверьте их, затем начните новую сессию (или перезапустите Codex, если только что это сделали).' ;;
    en:codex_profile) MSG_T="corecrew's sandbox profile is not the default in Codex, so secrets (.env files, keys) are protected only partly, by corecrew's hooks. To protect them better, run this in a terminal (it only prints text): bash \"@1\" codex-profile    then copy what it prints and paste it into @2. The profile applies to every Codex session, and afterwards Codex asks for approval before each git commit. It is a default only: command-line sandbox flags or a trusted project's settings can switch it off (the comments in the pasted text say how). corecrew never writes that file." ;;
    ru:codex_profile) MSG_T='Профиль песочницы corecrew в Codex не выбран по умолчанию, поэтому секреты (файлы .env, ключи) защищены лишь частично — только хуками corecrew. Чтобы защита стала надёжнее, выполните в терминале (команда только печатает текст): bash "@1" codex-profile    затем скопируйте напечатанное и вставьте в @2. Профиль действует на все сессии Codex, а после этого Codex будет спрашивать подтверждение перед каждым git commit. Это лишь значение по умолчанию: флаги песочницы в командной строке или настройки доверенного проекта могут его отключить (подробности — в комментариях вставленного текста). corecrew этот файл никогда не меняет.' ;;
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
    en:hooks_path) MSG_T='corecrew git hooks do not run in @1: core.hooksPath sends git to @2. To chain them from your own hooks, run: bash "@3" "@4" (it prints the lines to add).' ;;
    ru:hooks_path) MSG_T='Git-хуки corecrew не работают в @1: core.hooksPath направляет git в @2. Чтобы подключить их к вашим хукам, выполните: bash "@3" "@4" (команда напечатает строки для добавления).' ;;
    en:hooks_path_empty) MSG_T='corecrew git hooks do not run in @1: core.hooksPath is set to an empty value, so git runs no hooks there. To install them, first remove the setting: git -C "@1" config --unset core.hooksPath    then run: bash "@2" "@3"' ;;
    ru:hooks_path_empty) MSG_T='Git-хуки corecrew не работают в @1: core.hooksPath задан пустым, поэтому git не запускает там никаких хуков. Чтобы установить их, сначала удалите эту настройку: git -C "@1" config --unset core.hooksPath    затем выполните: bash "@2" "@3"' ;;
    en:readonly_agent) MSG_T='corecrew: @1 is a read-only checker and must not change anything (@2). Write logs and scratch files under @3; report a needed change for engineer to make.' ;;
    en:guard_code_blocked) MSG_T='corecrew: @1 is an internal file and must not live in the code folder. Write it to @2 instead.' ;;
    ru:guard_code_blocked) MSG_T='corecrew: @1 — внутренний файл, ему не место в папке кода. Запишите его в @2.' ;;
    en:guard_code_public) MSG_T='Docs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in @1.' ;;
    ru:guard_code_public) MSG_T='Документы, которые должны остаться публичными в папке кода, перечислите в строке "public-docs: <paths>" в @1.' ;;
    en:guard_code_too_many) MSG_T='corecrew: this command writes too many files to check. Split it into smaller commands.' ;;
    ru:guard_code_too_many) MSG_T='corecrew: команда записывает слишком много файлов, проверить её нельзя. Разбейте её на команды поменьше.' ;;
    en:patch_too_many) MSG_T='corecrew: this patch names more than @1 files and cannot be checked. Split it into patches of at most @1 files.' ;;
    ru:patch_too_many) MSG_T='corecrew: патч затрагивает больше @1 файлов, проверить его нельзя. Разбейте его на патчи не более чем по @1 файлов.' ;;
    en:patch_unjudgeable) MSG_T='corecrew: the patch cannot be judged: its text cannot be read, and the line "@1" names an internal path. Use the apply_patch tool and lines like "*** Add File: <full path>".' ;;
    ru:patch_unjudgeable) MSG_T='corecrew: патч нельзя проверить: не удаётся прочитать текст патча, а строка "@1" называет внутренний путь. Используйте инструмент apply_patch и строки вида "*** Add File: <полный путь>".' ;;
    en:patch_no_reader) MSG_T='corecrew: the patch cannot be judged: patch-paths.awk is missing or failed, so no file of the patch can be checked. Reinstall the corecrew plugin.' ;;
    ru:patch_no_reader) MSG_T='corecrew: патч нельзя проверить: patch-paths.awk отсутствует или не сработал, поэтому ни один файл патча не проверить. Переустановите плагин corecrew.' ;;
    en:patch_shell) MSG_T='corecrew: run patches with the apply_patch tool, not through the Bash command line; that form cannot be checked (matched: @1). If this is not a patch, rewrite the command without it: run a reader such as grep or cat on its own, or name the files instead of using a wildcard.' ;;
    ru:patch_shell) MSG_T='corecrew: применяйте патчи инструментом apply_patch, а не через командную строку (Bash); в такой форме патч проверить нельзя (сработало на: @1). Если это не патч, перепишите команду без этого: запустите чтение (grep, cat) отдельной командой или перечислите файлы вместо шаблона.' ;;
    en:secrets_blocked) MSG_T='corecrew: reading secrets is blocked (@1)' ;;
    ru:secrets_blocked) MSG_T='corecrew: чтение секретов заблокировано (@1)' ;;
    en:secrets_ask) MSG_T='Ask the user to check the value themselves, or use .env.example.' ;;
    ru:secrets_ask) MSG_T='Попросите пользователя проверить значение самому или используйте .env.example.' ;;
    en:local_link_created) MSG_T='corecrew: linked CLAUDE.local.md to @1; restart the session to load it' ;;
    ru:local_link_created) MSG_T='corecrew: CLAUDE.local.md связан с @1; перезапустите сессию, чтобы он загрузился' ;;
    en:agents_link_created) MSG_T='corecrew: linked AGENTS.md to @1 for tools that read AGENTS.md' ;;
    ru:agents_link_created) MSG_T='corecrew: AGENTS.md связан с @1 для инструментов, читающих AGENTS.md' ;;
    en:agents_link_wrong) MSG_T='corecrew: @1 is a link to somewhere other than @2, so tools that read AGENTS.md do not get the private CLAUDE.md. Remove that link, then run: ln -s "@2" "@1"' ;;
    ru:agents_link_wrong) MSG_T='corecrew: @1 — ссылка не на @2, поэтому инструменты, читающие AGENTS.md, не получают приватный CLAUDE.md. Удалите эту ссылку и выполните: ln -s "@2" "@1"' ;;
    en:agents_link_failed) MSG_T='corecrew: could not create @1, so tools that read AGENTS.md do not get the private CLAUDE.md. Run: ln -s "@2" "@1"' ;;
    ru:agents_link_failed) MSG_T='corecrew: не удалось создать @1, поэтому инструменты, читающие AGENTS.md, не получают приватный CLAUDE.md. Выполните: ln -s "@2" "@1"' ;;
    en:local_link_wrong) MSG_T='corecrew: @1 exists and is not a link to @2, so the private CLAUDE.md is not loaded. Move that file away, then run: ln -s "@2" "@1"' ;;
    ru:local_link_wrong) MSG_T='corecrew: @1 уже существует и не ведёт на @2, поэтому приватный CLAUDE.md не загружается. Уберите этот файл и выполните: ln -s "@2" "@1"' ;;
    en:local_link_failed) MSG_T='corecrew: could not create @1, so the private CLAUDE.md is not loaded. Run: ln -s "@2" "@1"' ;;
    ru:local_link_failed) MSG_T='corecrew: не удалось создать @1, поэтому приватный CLAUDE.md не загружается. Выполните: ln -s "@2" "@1"' ;;
    en:old_layout) MSG_T='corecrew: this project still lives in @1; run /corecrew:task adopt @2 to move it to @3' ;;
    ru:old_layout) MSG_T='corecrew: этот проект всё ещё лежит в @1; выполните /corecrew:task adopt @2, чтобы перенести его в @3' ;;
    en:one_suite_wait) MSG_T='one-suite: a test run is still in progress after @1 s of waiting (@2) — run the same command again: this hook waits for it. If it is a watcher you started, stop it first.' ;;
    ru:one_suite_wait) MSG_T='one-suite: тесты всё ещё идут после ожидания @1 с (@2) — запустите ту же команду ещё раз: хук дождётся. Если это процесс, который сам перезапускает тесты при изменении файлов, сначала остановите его.' ;;
    en:dirty_code) MSG_T='code' ;;
    ru:dirty_code) MSG_T='код' ;;
    en:dirty_docs) MSG_T='docs' ;;
    ru:dirty_docs) MSG_T='документация' ;;
    en:dirty_both) MSG_T='code and docs' ;;
    ru:dirty_both) MSG_T='код и документация' ;;
    en:settings_invalid_path) MSG_T='corecrew: core_dir "@1" (@2) is not valid: it must be an absolute path or start with ~/. @3 Using @4 instead.' ;;
    ru:settings_invalid_path) MSG_T='corecrew: core_dir "@1" (@2) недопустим: нужен абсолютный путь или путь, начинающийся с ~/. @3 Вместо него используется @4.' ;;
    en:settings_invalid_value) MSG_T='corecrew: @1 "@2" (@3) is not valid: use @4. @5 Using "@6" instead.' ;;
    ru:settings_invalid_value) MSG_T='corecrew: @1 "@2" (@3) недопустимо: допустимы @4. @5 Вместо него используется "@6".' ;;
    en:settings_no_home) MSG_T='corecrew: HOME is empty or not an absolute path, so ~ (the default core_dir ~/Projects/Core) has no meaning and there is no Core. Set HOME or give core_dir as an absolute path.' ;;
    ru:settings_no_home) MSG_T='corecrew: HOME пуст или не абсолютный путь, поэтому ~ (core_dir по умолчанию ~/Projects/Core) ничего не значит и Core нет. Задайте HOME или укажите core_dir абсолютным путём.' ;;
    en:settings_unreadable) MSG_T='corecrew: the settings file @1 cannot be read (or is over 64 KB); its values are ignored and the defaults are used.' ;;
    ru:settings_unreadable) MSG_T='corecrew: файл настроек @1 не читается (или больше 64 КБ); его значения игнорируются, используются значения по умолчанию.' ;;
    en:allowed_attribution) MSG_T='allow or forbid' ;;
    ru:allowed_attribution) MSG_T='allow или forbid' ;;
    en:allowed_model_profile) MSG_T='economy, balanced or strong' ;;
    ru:allowed_model_profile) MSG_T='economy, balanced или strong' ;;
    en:src_env) MSG_T='environment variable CORE_DIR' ;;
    ru:src_env) MSG_T='переменная окружения CORE_DIR' ;;
    en:src_option) MSG_T='plugin option' ;;
    ru:src_option) MSG_T='параметр плагина' ;;
    en:src_file) MSG_T='settings file' ;;
    ru:src_file) MSG_T='файл настроек' ;;
    en:fix_env) MSG_T='Unset or correct the CORE_DIR variable.' ;;
    ru:fix_env) MSG_T='Удалите переменную CORE_DIR или исправьте её.' ;;
    en:fix_option) MSG_T='Correct it in the plugin'"'"'s options in Claude Code.' ;;
    ru:fix_option) MSG_T='Исправьте значение в параметрах плагина в Claude Code.' ;;
    en:fix_file) MSG_T='Correct it in @1.' ;;
    ru:fix_file) MSG_T='Исправьте значение в файле @1.' ;;
    en:stop_remind) MSG_T='Uncommitted changes in @1. If this working step is finished, run: bash "@2" "<short English subject>"@3 (at most 72 characters, details after a blank line; a commit standard of the project wins). If you are waiting for the user'"'"'s answer or approval, do not save; just end your turn.' ;;
    ru:stop_remind) MSG_T='Есть несохранённые изменения: @1. Если этот рабочий шаг закончен, выполните: bash "@2" "<short English subject>"@3 (не длиннее 72 символов, подробности после пустой строки; стандарт коммитов проекта важнее). Если вы ждёте ответа или одобрения пользователя, не сохраняйте, просто закончите ответ.' ;;
  esac
}

# _msg_lang — the language to use: one of MSG_LANGS, else en.
_msg_lang() {
  local l
  if [ -n "${UI_LANGUAGE:-}" ]; then l="$UI_LANGUAGE"
  else l="$(resolve_setting ui_language)"
  fi
  [ -n "$l" ] || { printf en; return 0; }
  case " $MSG_LANGS " in *" $l "*) printf '%s' "$l" ;; *) printf en ;; esac
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
  # The texts name skills as Claude Code calls them (/corecrew:<skill>); Codex calls them $corecrew:<skill>
  # (lib.sh host). Only the text changes, before the arguments go in.
  # shellcheck disable=SC2016  # $corecrew is literal text
  case "$tpl" in
    */corecrew:*) if [ "$(host)" = codex ]; then tpl="$(printf '%s' "$tpl" | sed 's|/corecrew:|$corecrew:|g')"; fi ;;
  esac
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

# msg_settings_warning <key> <value> <source> <value in effect> <settings file> — one SETTINGS_WARN record
# (lib.sh) as a sentence in the person's language: what is wrong, where to fix it, what is used instead.
msg_settings_warning() {
  local sl fx
  if [ "$1" = settings_file ]; then msg settings_unreadable "$2"; return; fi
  if [ "$1" = home ]; then msg settings_no_home; return; fi
  case "$3" in
    env) sl="$(msg src_env)"; fx="$(msg fix_env)" ;;
    option) sl="$(msg src_option)"; fx="$(msg fix_option)" ;;
    *) sl="$(msg src_file)"; fx="$(msg fix_file "$5")" ;;
  esac
  case "$1" in
    core_dir) msg settings_invalid_path "$2" "$sl" "$fx" "$4" ;;
    attribution) msg settings_invalid_value "$1" "$2" "$sl" "$(msg allowed_attribution)" "$fx" "$4" ;;
    *) msg settings_invalid_value "$1" "$2" "$sl" "$(msg allowed_model_profile)" "$fx" "$4" ;;
  esac
}
