#!/usr/bin/env bash
# Manual check of the classifier on the real model (coremodel spec §9.2): nine prompts, each compared
# with the expected level and model. Needs the claude CLI and the network, so tests/run.sh does not call it.
# Usage: bash plugins/coremodel/tests/quality.sh haiku|sonnet
case "$1" in
  haiku) model=claude-haiku-5-5 ;;
  sonnet) model=claude-sonnet-5-5 ;;
  *) echo "usage: $0 haiku|sonnet" >&2; exit 2 ;;
esac
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../hooks/classifier.ts"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ep-quality.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# The template between the marker lines, without the opening `export const TEMPLATE = \`` and the closing backtick.
sed -n '/^\/\/ TEMPLATE-START$/,/^\/\/ TEMPLATE-END$/p' "$src" | sed '1d;$d' |
  sed '1s/^export const TEMPLATE = `//;$s/`$//' > "$tmp/template"

# prompt|expected level|expected model (several separated by /; * = any)
cases='почини опечатку в README|low|haiku
что делает git rebase --onto?|low|haiku
почини авторизацию, после логина кидает на 500|high|opus
добавь кнопку экспорта в CSV на страницу отчётов|medium|sonnet
отрефактори модуль платежей и мигрируй базу на новую схему|high/xhigh|opus/fable
сделай с нуля приложение-трекер привычек на SwiftUI, план утверждён, работай сам|xhigh|fable
перепиши это письмо клиенту повежливее|low|haiku/sonnet
проверь договор аренды на риски, 12 страниц|high|opus
да, давай|keep|*'

ok=0; okm=0; n=0
while IFS='|' read -r prompt want wantm; do
  n=$((n + 1))
  # awk index/substr, not sub(): a prompt holding & or \ stays as written.
  awk -v p="$prompt" '
    { line = $0
      while ((i = index(line, "{{PROMPT}}")) > 0) line = substr(line, 1, i - 1) p substr(line, i + 10)
      while ((i = index(line, "{{REPLY}}")) > 0) line = substr(line, 1, i - 1) "(none, this is the first prompt)" substr(line, i + 9)
      while ((i = index(line, "{{NOW}}")) > 0) line = substr(line, 1, i - 1) "high" substr(line, i + 7)
      print line }' "$tmp/template" > "$tmp/prompt"
  answer="$(claude -p --model "$model" --effort low < "$tmp/prompt" 2>&1 | tr '\n' ' ')"
  got="$(printf '%s' "$answer" | sed -n 's/.*"level"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')"
  gotm="$(printf '%s' "$answer" | sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')"
  case "/$want/" in
    */"$got"/*) [ -n "$got" ] && { ok=$((ok + 1)); mark=OK; } || mark=MISS ;;
    *) mark=MISS ;;
  esac
  case "$wantm" in
    '*') okm=$((okm + 1)); markm=OK ;;
    *) case "/$wantm/" in
         */"$gotm"/*) [ -n "$gotm" ] && { okm=$((okm + 1)); markm=OK; } || markm=MISS ;;
         *) markm=MISS ;;
       esac ;;
  esac
  printf '%s → %s %s (expected %s %s) level %s, model %s\n' "$prompt" "${got:-?}" "${gotm:-?}" "$want" "$wantm" "$mark" "$markm"
done <<EOF2
$cases
EOF2
echo "level $ok/$n OK, model $okm/$n OK ($1)"
