#!/usr/bin/env bash
# Manual check of the classifier on the real model (spec §7.2): nine prompts, each compared with the
# expected level. Needs the claude CLI and the network, so tests/run.sh does not call it.
# Usage: bash plugins/effort-picker/tests/quality.sh haiku|sonnet
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

# prompt|expected (several levels separated by /)
cases='почини опечатку в README|low
что делает git rebase --onto?|low
почини авторизацию, после логина кидает на 500|high
добавь кнопку экспорта в CSV на страницу отчётов|medium
отрефактори модуль платежей и мигрируй базу на новую схему|high/xhigh
сделай с нуля приложение-трекер привычек на SwiftUI, план утверждён, работай сам|xhigh
перепиши это письмо клиенту повежливее|low
проверь договор аренды на риски, 12 страниц|high
да, давай|keep'

ok=0; n=0
while IFS='|' read -r prompt want; do
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
  case "/$want/" in
    */"$got"/*) [ -n "$got" ] && { ok=$((ok + 1)); mark=OK; } || mark=MISS ;;
    *) mark=MISS ;;
  esac
  printf '%s → %s (expected %s) %s\n' "$prompt" "${got:-?}" "$want" "$mark"
done <<EOF2
$cases
EOF2
echo "$ok/$n OK ($1)"
