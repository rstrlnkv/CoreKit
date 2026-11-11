#!/usr/bin/env bash
# coremodel in Codex: Codex hooks cannot switch the model, so this UserPromptSubmit hook asks a small
# model (gpt-6-luna, one `codex exec` call) which model and effort the prompt needs and adds one line of
# context: "switch with /model". It stays silent when the current model is the one it would name or a
# stronger one. It never blocks the prompt: any failure is silent, exit 0.
# - A whole greeting, thanks, approval or "go on" (codex/replies.txt) gets no call at all.
# - The same script on Stop keeps the last 600 bytes of Codex's reply, per session, until the next
#   prompt; a short prompt (at most 8 words) sends it along, a longer one stands on its own.
# - The classifier prompt is codex/classifier.txt; the answer comes in a JSON Schema shape, with the
#   models offered cut to those the client's catalog lists ($CODEX_HOME/models_cache.json, when readable).
# Off until turned on, since it sends every prompt to a model once more: `codex_hint: on` in
# ~/.config/coremodel/settings (COREMODEL_CONFIG names another file); without that key,
# `coremodel_mode: on` in the corecrew settings file. COREMODEL_HINT_TIMEOUT seconds (default 20).
[ -z "${COREMODEL_NESTED:-}" ] || exit 0
command -v codex >/dev/null 2>&1 || exit 0
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
[ -f "$here/classifier.txt" ] || exit 0

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

# the fields of the event: a small JSON reader (top-level keys only; \" \\ \/ \b \f \n \r \t \uXXXX).
# Linear in the input: strings are read in chunks; of the prompt and the reply only the first and the last
# bytes are kept. Writes the prompt (cut in the middle past 4000 bytes) on UserPromptSubmit and the last
# 600 bytes of the reply, blanks folded, on Stop; the event name, the model and the session id on both.
LC_ALL=C awk -v d="$tmp" '
function hexv(h,  k, c, n) { n = 0; h = tolower(h)
  for (k = 1; k <= length(h); k++) { c = index("0123456789abcdef", substr(h, k, 1)); if (!c) return -1; n = n * 16 + c - 1 }
  return n }
function utf8(n) {
  if (n < 128) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
  if (n < 65536) return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
  return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64) }
# emit(p): a decoded piece of the string being read goes to V (short keys and values) or, for a long text, to F (first bytes) and T (last bytes)
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
  L = length(s); i = 1; depth = 0; ev = ""; have = 0; cap = 0; nonblank = 0; tl = 0; rtl = 0
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
        if ((key == "prompt" || key == "last_assistant_message" || key == "hook_event_name" || key == "model" || key == "session_id") && substr(s, j, 1) == "\"") {
          i = j; cap = (key == "prompt" || key == "last_assistant_message"); F = ""; T = ""; tl = 0; nonblank = 0
          str(); cap = 0; if (!OK) break
          if (key == "prompt") { have = 1; prompt_ok = nonblank; pF = F; pT = T; ptl = tl }
          else if (key == "last_assistant_message") { rF = F; rT = T; rtl = tl }
          else if (key == "model") mdl = V; else if (key == "session_id") sid = V; else ev = V
        } else i = j
      }
    } else i++
  }
  if (ev == "UserPromptSubmit") {
    if (!have || !prompt_ok) exit 1
    if (ptl <= 4000) pr = pF
    else {
      h = substr(pF, 1, 2000); sub(/[\300-\377][\200-\277]*$/, "", h)
      t = substr(pT, length(pT) - 1999); sub(/^[\200-\277]+/, "", t)
      pr = h "\n[…]\n" t
    }
    printf "%s", pr > (d "/prompt")
  } else if (ev == "Stop") {
    r = (rtl <= 4000) ? rF : rT
    gsub(/[ \t\r\n]+/, " ", r); sub(/^ /, "", r); sub(/ $/, "", r)
    if (length(r) > 600) { r = substr(r, length(r) - 599); sub(/^[\200-\277]+/, "", r) }
    printf "%s", r > (d "/reply")
  } else exit 1
  printf "%s", ev > (d "/ev")
  printf "%s", mdl > (d "/model")
  printf "%s", sid > (d "/sid")
}' < "$tmp/in" 2>/dev/null || exit 0
ev="$(cat "$tmp/ev" 2>/dev/null)"
# the session id names a file: a plain name only
sid="$(cat "$tmp/sid" 2>/dev/null)"
case "$sid" in ''|.*|*[!A-Za-z0-9._-]*) sid="" ;; esac
[ "${#sid}" -le 128 ] || sid=""
# the saved replies: one private file per session, under XDG_STATE_HOME or ~/.local/state
case "${XDG_STATE_HOME:-}" in
  /*) sd="${XDG_STATE_HOME%/}/coremodel/codex-replies" ;;
  *) case "${HOME:-}" in /*) sd="$HOME/.local/state/coremodel/codex-replies" ;; *) sd="" ;; esac ;;
esac
[ -n "$sid" ] || sd=""

# Stop: keep the end of the reply for the next prompt of this session; replies older than a day go
if [ "$ev" = Stop ]; then
  [ -n "$sd" ] || exit 0
  mkdir -p "${sd%/*}" 2>/dev/null && { [ -d "$sd" ] || mkdir -m 700 "$sd" 2>/dev/null; } || exit 0
  find "$sd" -type f -mtime +0 -exec rm -f {} + 2>/dev/null
  if [ -s "$tmp/reply" ]; then
    f="$(mktemp "$sd/.new.XXXXXX" 2>/dev/null)" || exit 0
    if cat "$tmp/reply" > "$f" 2>/dev/null; then mv -f "$f" "$sd/$sid" 2>/dev/null || rm -f "$f"; else rm -f "$f"; fi
  else
    rm -f "$sd/$sid"
  fi
  exit 0
fi

# UserPromptSubmit: the saved reply is used once, whatever happens next
if [ -n "$sd" ] && [ -f "$sd/$sid" ]; then cat "$sd/$sid" > "$tmp/ctx" 2>/dev/null; rm -f "$sd/$sid"; fi
[ -s "$tmp/prompt" ] || exit 0

# rank <codex model> — its place on the ladder the hint names; 0 for a model it does not name
rank() { case "$1" in gpt-6-luna) echo 1 ;; gpt-6.1-sol) echo 2 ;; gpt-6-astra) echo 3 ;; *) echo 0 ;; esac; }
now="$(rank "$(cat "$tmp/model" 2>/dev/null)")"
# on the strongest model there is nothing to suggest: no call
[ "$now" -lt 3 ] || exit 0

# A whole prompt of at most 8 words made only of replies.txt phrases (case, punctuation and ё/е ignored,
# phrases in any order) brings no new work: no call.
LC_ALL=C awk -v pf="$tmp/prompt" '
function norm(s,  k) {
  s = tolower(s); for (k in UP) gsub(k, UP[k], s)
  gsub(/[.,!?;:()"\047*-]/, " ", s); for (k in PU) gsub(k, " ", s)
  gsub(/[ \t\r\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
BEGIN {
  for (c = 144; c <= 159; c++) UP[sprintf("%c%c", 208, c)] = sprintf("%c%c", 208, c + 32)
  for (c = 160; c <= 175; c++) UP[sprintf("%c%c", 208, c)] = sprintf("%c%c", 209, c - 32)
  UP[sprintf("%c%c", 208, 129)] = sprintf("%c%c", 208, 181); UP[sprintf("%c%c", 209, 145)] = sprintf("%c%c", 208, 181)
  # the ellipsis, the em and en dashes, the guillemets and the curly quotes read as blanks
  PU[sprintf("%c%c%c", 226, 128, 166)]; PU[sprintf("%c%c%c", 226, 128, 148)]; PU[sprintf("%c%c%c", 226, 128, 147)]
  PU[sprintf("%c%c", 194, 171)]; PU[sprintf("%c%c", 194, 187)]
  PU[sprintf("%c%c%c", 226, 128, 152)]; PU[sprintf("%c%c%c", 226, 128, 153)]
  PU[sprintf("%c%c%c", 226, 128, 156)]; PU[sprintf("%c%c%c", 226, 128, 157)]
}
/^[ \t]*(#|$)/ { next }
{ p = norm($0); if (p != "") P[++np] = p }
END {
  while ((getline line < pf) > 0) s = s " " line
  s = norm(s)
  if (s == "" || split(s, w, " ") > 8) exit 1
  while (s != "") {
    best = 0
    for (k = 1; k <= np; k++) { p = P[k]; n = length(p); if ((s == p || substr(s, 1, n + 1) == p " ") && n > best) best = n }
    if (!best) exit 1
    s = substr(s, best + 2)
  }
}' "$here/replies.txt" 2>/dev/null && exit 0

# The client's catalog, when readable: "slug effort effort ..." for each model it lists (visibility "list")
catf="${CODEX_HOME:-${HOME:-}/.codex}/models_cache.json"
: > "$tmp/cat"
[ -f "$catf" ] && grep -oE '"(slug|visibility|effort)"[[:space:]]*:[[:space:]]*"[^"]*"' "$catf" 2>/dev/null |
  awk -F'"' '$2 == "slug" { m = $4; S[m] = 1; next } $2 == "visibility" { V[m] = $4; next } $2 == "effort" { E[m] = E[m] " " $4 }
    END { for (m in S) if (V[m] == "list") print m E[m] }' > "$tmp/cat" 2>/dev/null
# the models offered: the ladder, cut to the catalog when there is one
models=""; enum=""
for m in gpt-6-luna gpt-6.1-sol gpt-6-astra; do
  if [ -s "$tmp/cat" ]; then awk -v m="$m" '$1 == m { f = 1 } END { exit !f }' "$tmp/cat" || continue; fi
  models="$models $m "; enum="$enum${enum:+,}\"$m\""
done
[ -n "$models" ] || exit 0
printf '{"type":"object","additionalProperties":false,"required":["why","keep","model","effort"],"properties":{"why":{"type":"string"},"keep":{"type":"boolean"},"model":{"type":"string","enum":[%s]},"effort":{"type":"string","enum":["low","medium","high","xhigh","max"]}}}\n' "$enum" > "$tmp/schema.json"

# The last reply goes only with a short prompt, which may lean on it; a missing one is said to be unknown
if [ "$(wc -w < "$tmp/prompt" | tr -d ' ')" -gt 8 ]; then
  printf '%s' '(not included: the prompt is long enough to judge on its own)' > "$tmp/ctx"
elif [ ! -s "$tmp/ctx" ]; then
  printf '%s' '(unknown: Codex did not pass its previous reply)' > "$tmp/ctx"
fi

# the template with the reply and the prompt spliced in, never read as patterns
tpl="$(cat "$here/classifier.txt" 2>/dev/null)"
case "$tpl" in *'{{REPLY}}'*'{{PROMPT}}'*) ;; *) exit 0 ;; esac
pre="${tpl%%\{\{REPLY\}\}*}"; rest="${tpl#*\{\{REPLY\}\}}"
mid="${rest%%\{\{PROMPT\}\}*}"; post="${rest#*\{\{PROMPT\}\}}"
{ printf '%s' "$pre"; cat "$tmp/ctx"; printf '%s' "$mid"; cat "$tmp/prompt"; printf '%s\n' "$post"; } > "$tmp/full"

to="${COREMODEL_HINT_TIMEOUT:-20}"
case "$to" in ''|*[!0-9]*) to=20 ;; esac
[ "$to" -gt 20 ] && to=20
export COREMODEL_NESTED=1
# project_doc_max_bytes=0: the project's AGENTS.md is not added to the classifier prompt
codex exec --model gpt-6-luna --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config -c 'model_reasoning_effort="low"' -c 'project_doc_max_bytes=0' --output-schema "$tmp/schema.json" - < "$tmp/full" > "$tmp/ans" 2>/dev/null &
cp=$!
( sleep "$to"; kill_tree "$cp" ) > /dev/null 2>&1 &
wd=$!
wait "$cp" 2>/dev/null; cp=""
kill_tree "$wd"; wd=""

# the first flat {...} of the answer
obj="$(tr '\n' ' ' < "$tmp/ans" 2>/dev/null | sed -n 's/^[^{]*\({[^{}]*}\).*$/\1/p')"
[ -n "$obj" ] || exit 0
val() { printf '%s' "$obj" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([A-Za-z0-9.-]*\).*/\1/p" | tr 'A-Z' 'a-z'; }
[ "$(val keep)" = true ] && exit 0
md="$(val model)"; ef="$(val effort)"
case "$models" in *" $md "*) ;; *) exit 0 ;; esac
case "$ef" in low|medium|high|xhigh|max) ;; *) exit 0 ;; esac
# an effort the catalog does not list for that model drops to the highest one it does list below it
effs="$(awk -v m="$md" '$1 == m { $1 = ""; print $0 " " }' "$tmp/cat" 2>/dev/null)"
if [ -n "$effs" ]; then
  case "$effs" in
    *" $ef "*) ;;
    *) lv=""
       for l in low medium high xhigh max; do
         case "$effs" in *" $l "*) lv="$l" ;; esac
         [ "$l" = "$ef" ] && break
       done
       [ -n "$lv" ] || exit 0
       ef="$lv" ;;
  esac
fi
# the current model fits already (it is the pick or a stronger one): nothing to say. Codex does not tell
# the hook the current effort, so the effort is named, never compared.
[ "$now" -eq 0 ] || [ "$now" -lt "$(rank "$md")" ] || exit 0
# additionalContext reaches only the model; systemMessage shows the same line to the user
msg="coremodel: this prompt needs $md at $ef effort; switch with /model if the current one differs."
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"},"systemMessage":"%s"}\n' "$msg" "$msg"
exit 0
