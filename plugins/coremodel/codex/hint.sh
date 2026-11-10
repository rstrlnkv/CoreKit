#!/usr/bin/env bash
# coremodel in Codex: Codex hooks cannot switch the model, so this UserPromptSubmit hook asks a small
# model (gpt-6-luna, one `codex exec` call) which model and effort the prompt needs and adds one line of
# context: "switch with /model". It stays silent when the current model is the one it would name or a
# stronger one. It never blocks the prompt: any failure is silent, exit 0.
# Off until turned on, since it sends every prompt to a model once more: `codex_hint: on` in
# ~/.config/coremodel/settings (COREMODEL_CONFIG names another file); without that key,
# `coremodel_mode: on` in the corecrew settings file. COREMODEL_HINT_TIMEOUT seconds (default 20).
[ -z "${COREMODEL_NESTED:-}" ] || exit 0
command -v codex >/dev/null 2>&1 || exit 0
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
ts="$here/../hooks/classifier.ts"
[ -f "$ts" ] || exit 0

# settings_file <ENV value> <folder> — the file the ENV value names (an absolute path), else <folder>/settings
# under XDG_CONFIG_HOME or ~/.config; empty when there is no absolute place
settings_file() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) case "${XDG_CONFIG_HOME:-}" in
         /*) printf '%s' "${XDG_CONFIG_HOME%/}/$2/settings" ;;
         *) case "${HOME:-}" in /*) printf '%s' "$HOME/.config/$2/settings" ;; esac ;;
       esac ;;
  esac
}
# read_key <file> <key> — the value of `key: value` in the file; empty when the file or the key is missing
read_key() {
  [ -n "$1" ] && [ -f "$1" ] && [ -r "$1" ] || return 0
  tr -d '\r' < "$1" | sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\$/\1/p" | head -1
}
on="$(read_key "$(settings_file "${COREMODEL_CONFIG:-}" coremodel)" codex_hint)"
# the corecrew file is the fallback, found the way corecrew's lib.sh does (coremodel does not need corecrew)
[ -n "$on" ] || on="$(read_key "$(settings_file "${CORECREW_CONFIG:-}" corecrew)" coremodel_mode)"
[ "$on" = on ] || exit 0

tmp="$(mktemp -d 2>/dev/null)" || exit 0
wd=""; cp=""
# kill_tree <pid> — the process and all its descendants
kill_tree() {
  local c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'); do kill_tree "$c"; done
  kill -TERM "$1" 2>/dev/null
  return 0
}
cleanup() { [ -z "$cp" ] || kill_tree "$cp"; [ -z "$wd" ] || kill_tree "$wd"; rm -rf "$tmp"; }
trap cleanup EXIT
trap 'exit 143' INT TERM HUP

head -c 262144 > "$tmp/in" 2>/dev/null || exit 0

# the prompt field of the event: a small JSON reader (top-level keys only; \" \\ \/ \b \f \n \r \t \uXXXX).
# Linear in the input: strings are read in chunks; of the prompt only the first and the last 4000 bytes are kept.
LC_ALL=C awk -v out="$tmp/prompt" -v mout="$tmp/model" '
function hexv(h,  k, c, n) { n = 0; h = tolower(h)
  for (k = 1; k <= length(h); k++) { c = index("0123456789abcdef", substr(h, k, 1)); if (!c) return -1; n = n * 16 + c - 1 }
  return n }
function utf8(n) {
  if (n < 128) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
  if (n < 65536) return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
  return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64) }
# emit(p): a decoded piece of the string being read goes to V (short keys and values) or, for the prompt, to F (first bytes) and T (last bytes)
function emit(p) {
  if (!cap) { if (length(V) < 512) V = V p; return }
  if (p ~ /[^ \t\r\n]/) nonblank = 1
  tl += length(p)
  if (length(F) < 4000) F = substr(F p, 1, 4000)
  T = T p; if (length(T) > 16000) T = substr(T, length(T) - 7999)
}
# str() reads the string whose opening quote is at i; sets V and i (after the closing quote); OK=0 when unterminated
function str(  chunk, k, c, e, n, lo) {
  V = ""; OK = 0; i++
  while (i <= L) {
    chunk = substr(s, i, 2048); k = match(chunk, /["\\]/)
    if (!k) { emit(chunk); i += length(chunk); continue }
    if (k > 1) emit(substr(chunk, 1, k - 1))
    i += k - 1
    c = substr(s, i, 1)
    if (c == "\"") { i++; OK = 1; return }
    e = substr(s, i + 1, 1); i += 2
    if (e == "n") emit("\n"); else if (e == "t") emit("\t"); else if (e == "r") emit("\r")
    else if (e == "b") emit("\b"); else if (e == "f") emit("\f")
    else if (e == "u") {
      n = hexv(substr(s, i, 4)); i += 4
      if (n >= 55296 && n < 56320 && substr(s, i, 2) == "\\u") {
        lo = hexv(substr(s, i + 2, 4))
        if (lo >= 56320 && lo < 57344) { n = 65536 + (n - 55296) * 1024 + (lo - 56320); i += 6 }
      }
      if (n > 0) emit(utf8(n))
    } else emit(e)
  }
}
BEGIN { RS = "\001" }
{ s = $0 }
END {
  L = length(s); i = 1; depth = 0; ev = ""; have = 0; cap = 0; nonblank = 0; tl = 0
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == "{" || c == "[") { depth++; i++ }
    else if (c == "}" || c == "]") { depth--; i++ }
    else if (c == "\"") {
      cap = 0; str(); if (!OK) break
      key = V; j = i
      while (substr(s, j, 1) ~ /[ \t\r\n]/) j++
      if (depth == 1 && substr(s, j, 1) == ":") {
        j++; while (substr(s, j, 1) ~ /[ \t\r\n]/) j++
        if ((key == "prompt" || key == "hook_event_name" || key == "model") && substr(s, j, 1) == "\"") {
          i = j; cap = (key == "prompt"); F = ""; T = ""; tl = 0; nonblank = 0
          str(); cap = 0; if (!OK) break
          if (key == "prompt") { have = 1; prompt_ok = nonblank; pF = F; pT = T; ptl = tl } else if (key == "model") mdl = V; else ev = V
        } else i = j
      }
    } else i++
  }
  if (!have || ev != "UserPromptSubmit" || !prompt_ok) exit 1
  if (ptl <= 4000) pr = pF
  else {
    h = substr(pF, 1, 2000); sub(/[\300-\377][\200-\277]*$/, "", h)
    t = substr(pT, length(pT) - 1999); sub(/^[\200-\277]+/, "", t)
    pr = h "\n[…]\n" t
  }
  printf "%s", pr > out
  printf "%s", mdl > mout
}' < "$tmp/in" 2>/dev/null || exit 0
[ -s "$tmp/prompt" ] || exit 0

# rank <codex model> — its place on the ladder the hint names; 0 for a model it does not name
rank() { case "$1" in gpt-6-luna) echo 1 ;; gpt-6.1-sol) echo 2 ;; gpt-6-astra) echo 3 ;; *) echo 0 ;; esac; }
now="$(rank "$(cat "$tmp/model" 2>/dev/null)")"
# on the strongest model there is nothing to suggest: no call
[ "$now" -lt 3 ] || exit 0

# the template between the markers of classifier.ts; {{NOW}} and {{REPLY}} first, the prompt last
tpl="$(sed -n '/^export const TEMPLATE = `/,/^\/\/ TEMPLATE-END/p' "$ts" | sed '1s/^export const TEMPLATE = `//' | sed '$d' | sed '$s/`$//')"
[ -n "$tpl" ] || exit 0
tpl="${tpl//\{\{NOW\}\}/unknown}"
tpl="${tpl//\{\{REPLY\}\}/(none, this is the first prompt)}"
case "$tpl" in *'{{PROMPT}}'*) ;; *) exit 0 ;; esac
pre="${tpl%%\{\{PROMPT\}\}*}"; post="${tpl#*\{\{PROMPT\}\}}"
{ printf '%s' "$pre"; cat "$tmp/prompt"; printf '%s' "$post"; } > "$tmp/full"

to="${COREMODEL_HINT_TIMEOUT:-20}"
case "$to" in ''|*[!0-9]*) to=20 ;; esac
[ "$to" -gt 20 ] && to=20
export COREMODEL_NESTED=1
# project_doc_max_bytes=0: the project's AGENTS.md is not added to the classifier prompt
codex exec --model gpt-6-luna --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config -c 'model_reasoning_effort="low"' -c 'project_doc_max_bytes=0' - < "$tmp/full" > "$tmp/ans" 2>/dev/null &
cp=$!
( sleep "$to"; kill_tree "$cp" ) > /dev/null 2>&1 &
wd=$!
wait "$cp" 2>/dev/null; cp=""
kill_tree "$wd"; wd=""

# the first {...} of the answer that holds a level and a model (the Claude parser's rule, on the flat object)
obj="$(tr '\n' ' ' < "$tmp/ans" 2>/dev/null | sed -n 's/^[^{]*\({[^{}]*}\).*$/\1/p')"
[ -n "$obj" ] || exit 0
lv="$(printf '%s' "$obj" | sed -n 's/.*"level"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr 'A-Z' 'a-z' | tr -d ' -')"
md="$(printf '%s' "$obj" | sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr 'A-Z' 'a-z' | tr -d ' ')"
[ "$lv" = extrahigh ] && lv=xhigh
case "$lv" in low|medium|high|xhigh|max) ;; *) exit 0 ;; esac
case "$md" in
  haiku) cm=gpt-6-luna ;;
  sonnet) cm=gpt-6.1-sol ;;
  opus|fable) cm=gpt-6-astra ;;
  *) exit 0 ;;
esac
# the current model fits already (it is the pick or a stronger one): nothing to say
[ "$now" -eq 0 ] || [ "$now" -lt "$(rank "$cm")" ] || exit 0
# additionalContext reaches only the model; systemMessage shows the same line to the user
msg="coremodel: this prompt needs $cm at $lv effort; switch with /model if the current one differs."
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"},"systemMessage":"%s"}\n' "$msg" "$msg"
exit 0
