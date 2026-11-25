#!/usr/bin/env bash
# The native hook returns routing instructions; --recommend returns the decision to a standalone client.
[ -z "${COREMODEL_NESTED:-}" ] || exit 0
script="$0"
case "$script" in
  [A-Za-z]:[\\/]*|\\\\*) command -v cygpath >/dev/null 2>&1 && script="$(cygpath -u "$script")" ;;
esac
here="$(cd "$(dirname "$script")" 2>/dev/null && pwd)" || exit 0
[ -f "$here/classifier.txt" ] || exit 0
. "$here/paths.sh" || exit 0

# read_key <file> <key> — the value of `key: value` in the file; empty when the file or the key is missing
read_key() {
  [ -n "$1" ] && [ -f "$1" ] && [ -r "$1" ] || return 0
  tr -d '\r' < "$1" | sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\$/\1/p" | head -1
}
mode=hook
settings="$(settings_file "${COREMODEL_CONFIG:-}" coremodel)"
routing="$(read_key "$settings" codex_mode)"
pick_model=true
[ "$(read_key "$settings" codex_pick_model)" != off ] || pick_model=false
case "$routing" in ask|auto|off|'') ;; *) routing=off ;; esac
case "${1:-}" in
  --settings)
    printf '{"mode":"%s","pickModel":%s}\n' "${routing:-ask}" "$pick_model"
    exit 0 ;;
  --recommend) mode=client ;;
esac
command -v codex >/dev/null 2>&1 || exit 0
if [ "$mode" = hook ] && [ -z "$routing" ]; then
  # Both legacy enabled modes migrate to ask. An explicit legacy off wins.
  on="$(read_key "$settings" codex_hint)"
  [ -n "$on" ] || on="$(read_key "$(settings_file "${CORECREW_CONFIG:-}" corecrew)" coremodel_mode)"
  [ "$on" = on ] || exit 0
fi
routing="${routing:-ask}"

keep() {
  if [ "$mode" = client ]; then printf '%s\n' '{"keep":true}'; fi
  exit 0
}

[ "$routing" != off ] || keep

tmp="$(mktemp -d 2>/dev/null)" || exit 0
wd=""; cp=""
# Each background job has its own process group. Its children inherit that group.
kill_group() { kill -KILL -- "-$1" 2>/dev/null || :; }
cleanup() { [ -z "$cp" ] || kill_group "$cp"; [ -z "$wd" ] || kill_group "$wd"; rm -rf "$tmp"; }
trap cleanup EXIT
trap 'exit 143' INT TERM HUP

head -c 262144 > "$tmp/in" 2>/dev/null || exit 0

# Decode top-level JSON fields in chunks. Keep the ends of long prompts and the tail of the previous reply.
LC_ALL=C awk -v d="$tmp" -v mode="$mode" '
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
        if ((key == "prompt" || key == "last_assistant_message" || key == "hook_event_name" || key == "model" || key == "reasoning_effort" || key == "session_id") && substr(s, j, 1) == "\"") {
          i = j; cap = (key == "prompt" || key == "last_assistant_message"); F = ""; T = ""; tl = 0; nonblank = 0
          str(); cap = 0; if (!OK) break
          if (key == "prompt") {
            # Identify the whole prompt even when the classifier receives a shortened copy.
            if (mode == "hook") printf "%s", substr(s, j, i-j) > (d "/prompt-id")
            have = 1; prompt_ok = nonblank; pF = F; pT = T; ptl = tl }
          else if (key == "last_assistant_message") { rF = F; rT = T; rtl = tl }
          else if (key == "reasoning_effort") effort = V
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
  } else if (ev != "Stop") exit 1
  if (ev == "Stop" || mode == "client") {
    r = (rtl <= 4000) ? rF : rT
    gsub(/[ \t\r\n]+/, " ", r); sub(/^ /, "", r); sub(/ $/, "", r)
    if (length(r) > 600) { r = substr(r, length(r) - 599); sub(/^[\200-\277]+/, "", r) }
    printf "%s", r > (d ((mode == "client") ? "/ctx" : "/reply"))
  }
  printf "%s", ev > (d "/ev")
  printf "%s", mdl > (d "/model")
  printf "%s", effort > (d "/effort")
  printf "%s", sid > (d "/sid")
}' < "$tmp/in" 2>/dev/null || exit 0
ev="$(cat "$tmp/ev" 2>/dev/null)"
# the session id names a file: a plain name only
sid="$(cat "$tmp/sid" 2>/dev/null)"
case "$sid" in ''|.*|*[!A-Za-z0-9._-]*) sid="" ;; esac
[ "${#sid}" -le 128 ] || sid=""
# the saved replies: one private file per session, under XDG_STATE_HOME or ~/.local/state
state_root="$(base_dir "${XDG_STATE_HOME:-}" .local/state)"
sd="${state_root:+$state_root/coremodel/codex-replies}"
[ -n "$sid" ] && [ "$mode" = hook ] || sd=""

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
if [ -n "$sd" ] && [ -f "$sd/$sid" ]; then
  find "$sd/$sid" -type f ! -mtime +0 -exec cat {} \; > "$tmp/ctx" 2>/dev/null
  rm -f "$sd/$sid"
fi
[ -s "$tmp/prompt" ] || exit 0

# Claim the previous offer by rename. A retry in this session is allowed through once.
od=""; sum=""
if [ -n "$sd" ]; then
  od="${sd%/*}/codex-offered"
  sum="$(cksum < "$tmp/prompt-id" 2>/dev/null)"
  if [ -f "$od/$sid" ]; then
    # A numbered text-menu reply continues the dialog without consuming the task's retry.
    if [ "$routing" = ask ] && grep -Eq '^[[:space:]]*[0-9]+[[:space:]]*$' "$tmp/prompt" &&
       [ "$(wc -l < "$tmp/prompt")" -eq 0 ] &&
       [ -n "$(find "$od/$sid" -mmin -10 2>/dev/null)" ] && [ "$(cat "$od/$sid" 2>/dev/null)" != "$sum" ]; then
      if grep -Eq '^[[:space:]]*0[[:space:]]*$' "$tmp/prompt"; then rm -f "$od/$sid"; fi
      exit 0
    fi
    claim="$(mktemp "$od/.claim.XXXXXX" 2>/dev/null)"
    if [ -n "$claim" ]; then
      match=""
      if mv -f "$od/$sid" "$claim" 2>/dev/null && [ -n "$sum" ] &&
         [ -n "$(find "$claim" -mmin -10 2>/dev/null)" ] && [ "$(cat "$claim" 2>/dev/null)" = "$sum" ]; then match=1; fi
      rm -f "$claim"
      [ -z "$match" ] || exit 0
    fi
  fi
fi

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
}' "$here/replies.txt" 2>/dev/null && keep

# Keep the visibility of each catalog row so hidden models are distinct from a missing catalog.
catalog_root="$(base_dir "${CODEX_HOME:-}" .codex)"
catf="${catalog_root:+$catalog_root/models_cache.json}"
if [ "$mode" = client ]; then
  override="$(absolute_path "${COREMODEL_CATALOG:-}")" && catf="$override"
fi
: > "$tmp/cat"
have_catalog=""
if [ -f "$catf" ] && [ -r "$catf" ]; then
  # Tokenize complete quoted strings so braces and escaped quotes in descriptions are data.
  LC_ALL=C grep -oE '"([^"\\]|\\.)*"|[][{}:,]' "$catf" 2>/dev/null |
    awk -f "$here/catalog.awk" > "$tmp/cat"
  grep -qx '#catalog' "$tmp/cat" && have_catalog=1
fi
visible="$(awk '$2 == "list" { printf " %s ", $1 }' "$tmp/cat")"

ladder=(gpt-6-luna gpt-6.1-sol gpt-6.2-sol gpt-6-astra gpt-6.2-astra)
model_tier() {
  case "$1" in *-luna) printf 'Luna' ;; *-sol) printf 'Sol' ;; *-astra) printf 'Astra' ;; esac
}

# Later entries in the same tier take precedence when visible.
luna=""; sol=""; astra=""; classifier=""
for m in "${ladder[@]}"; do
  if [ -n "$have_catalog" ]; then
    case "$visible" in *" $m "*) ;; *) continue ;; esac
  else
    case "$m" in gpt-6.2-*) continue ;; esac
  fi
  case "$(model_tier "$m")" in Luna) luna="$m" ;; Sol) sol="$m" ;; Astra) astra="$m" ;; esac
  [ -n "$classifier" ] || classifier="$m"
done
current_model="$(cat "$tmp/model")"
case "$current_model" in -*|*[!A-Za-z0-9._-]*) current_model="" ;; esac
candidates=("$luna" "$sol" "$astra")
if [ "$pick_model" = false ]; then
  [ -n "$current_model" ] || keep
  candidates=("$current_model")
  # A non-ladder model can still classify its own effort when it is visible.
  if [ -z "$classifier" ]; then
    case "$visible" in *" $current_model "*) classifier="$current_model" ;; esac
  fi
fi
[ -n "$classifier" ] || exit 0

models=""; enum=""; choices=""
for m in "${candidates[@]}"; do
  [ -n "$m" ] || continue
  models="$models $m "; enum="$enum${enum:+,}\"$m\""
  choices="$choices${choices:+$'\n'}- $(model_tier "$m"): $m"
done
if [ "$pick_model" = false ]; then
  choices="$choices. The user locked this model. Judge effort specifically for this model."
fi
printf '{"type":"object","additionalProperties":false,"required":["keep","model","effort"],"properties":{"keep":{"type":"boolean"},"model":{"type":"string","enum":[%s]},"effort":{"type":"string","enum":["low","medium","high","xhigh","max"]}}}\n' "$enum" > "$tmp/schema.json"

# The last reply goes only with a short prompt, which may lean on it; a missing one is said to be unknown
if [ "$(wc -w < "$tmp/prompt" | tr -d ' ')" -gt 8 ]; then
  printf '%s' '(not included: the prompt is long enough to judge on its own)' > "$tmp/ctx"
elif [ ! -s "$tmp/ctx" ]; then
  printf '%s' '(unknown: Codex did not pass its previous reply)' > "$tmp/ctx"
fi

# The template with the offered models, reply and prompt spliced in.
tpl="$(cat "$here/classifier.txt" 2>/dev/null)"
case "$tpl" in *'{{MODELS}}'*'{{REPLY}}'*'{{PROMPT}}'*) ;; *) exit 0 ;; esac
tpl="${tpl/\{\{MODELS\}\}/$choices}"
pre="${tpl%%\{\{REPLY\}\}*}"; rest="${tpl#*\{\{REPLY\}\}}"
mid="${rest%%\{\{PROMPT\}\}*}"; post="${rest#*\{\{PROMPT\}\}}"
{ printf '%s' "$pre"; cat "$tmp/ctx"; printf '%s' "$mid"; cat "$tmp/prompt"; printf '%s\n' "$post"; } > "$tmp/full"

to="${COREMODEL_HINT_TIMEOUT:-20}"
case "$to" in ''|*[!0-9]*) to=20 ;; esac
[ "$to" -gt 20 ] && to=20
export COREMODEL_NESTED=1
# project_doc_max_bytes=0: the project's AGENTS.md is not added to the classifier prompt
classifier_effort=low
supported="$(awk -v m="$classifier" '$1 == m { $1 = $2 = ""; print $0 " " }' "$tmp/cat")"
if [ -n "${supported// /}" ]; then
  for level in low minimal none medium high xhigh max ultra; do
    case "$supported" in *" $level "*) classifier_effort="$level"; break ;; esac
  done
fi
mkdir "$tmp/work" || exit 0
schema="$(cd "$tmp" && pwd -P)/schema.json"
set -m
(
  cd "$tmp/work" || exit 1
  exec codex exec --model "$classifier" --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config -c "model_reasoning_effort=\"$classifier_effort\"" -c 'project_doc_max_bytes=0' --output-schema "$schema" -
) < "$tmp/full" > "$tmp/ans" 2>/dev/null &
cp=$!
( set +m; sleep "$to"; kill_group "$cp" ) > /dev/null 2>&1 &
wd=$!
wait "$cp" 2>/dev/null; classifier_rc=$?; cp=""
kill_group "$wd"; wait "$wd" 2>/dev/null; wd=""
set +m
[ "$classifier_rc" -eq 0 ] || exit 0

# the first flat {...} of the answer
obj="$(tr '\n' ' ' < "$tmp/ans" 2>/dev/null | sed -n 's/^[^{]*\({[^{}]*}\).*$/\1/p')"
[ -n "$obj" ] || exit 0
val() { printf '%s' "$obj" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([A-Za-z0-9._-]*\).*/\1/p" | tr 'A-Z' 'a-z'; }
case "$(val keep)" in true) keep ;; false) ;; *) exit 0 ;; esac
md="$(val model)"; ef="$(val effort)"
[ -n "$md" ] || exit 0
case "$models" in *" $md "*) ;; *) exit 0 ;; esac
case "$ef" in low|medium|high|xhigh|max) ;; *) exit 0 ;; esac
# an effort the catalog does not list for that model drops to the highest one it does list below it
effs="$(awk -v m="$md" '$1 == m && $2 == "list" && NF > 2 { $1 = $2 = ""; print $0 " " }' "$tmp/cat" 2>/dev/null)"
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
if [ "$mode" = client ]; then
  printf '{"model":"%s","effort":"%s"}\n' "$md" "$ef"
  exit 0
fi
current_effort="$(cat "$tmp/effort")"
case "$current_effort" in none|minimal|low|medium|high|xhigh|max|ultra) ;; *) current_effort="" ;; esac
[ "$current_model" != "$md" ] || [ "$current_effort" != "$ef" ] || exit 0
model_command="/model $md --reasoning=$ef"
if [ "$current_model" = "$md" ]; then model_command="/model --reasoning=$ef"; fi

# Mark the original request, so the manual /model fallback can run it once.
marked=""
if [ -n "$od" ] && [ -n "$sum" ] && mkdir -p "${od%/*}" 2>/dev/null &&
   { [ -d "$od" ] || mkdir -m 700 "$od" 2>/dev/null; }; then
  find "$od" -type f -mtime +0 -exec rm -f {} + 2>/dev/null
  f="$(mktemp "$od/.new.XXXXXX" 2>/dev/null)"
  if [ -n "$f" ] && printf '%s' "$sum" > "$f" && mv -f "$f" "$od/$sid" 2>/dev/null; then
    marked=1
  else
    [ -z "$f" ] || rm -f "$f"
  fi
fi

msg="coremodel: this prompt needs $md at $ef effort."
version="${md%-*}"
nm="$md"
case "$md" in gpt-*-luna|gpt-*-sol|gpt-*-astra) nm="GPT-${version#gpt-} $(model_tier "$md")" ;; esac
case "$ef" in low) el=Low ;; medium) el=Medium ;; high) el=High ;; xhigh) el=XHigh ;; *) el=Max ;; esac
ctx="CoreModel recommends $nm · $el for this prompt. Use the user's language. Current model: ${current_model:-unknown}. Current effort: ${current_effort:-unknown}."
if [ -z "$marked" ]; then
  ctx="$ctx If the chat shows this exact task was resent after the CoreModel command, proceed immediately with the user's settings."
fi
if [ "$routing" = ask ]; then
  # Only validated IDs and effort names from catalog.awk are interpolated into JSON.
  menu="$(awk '$2 == "list" { printf "%s", $1; for (i=3; i<=NF; i++) printf "%s%s", (i==3 ? ":" : ","), $i; printf "; " }' "$tmp/cat")"
  if [ -z "$menu" ]; then menu="$luna $sol $astra (fallback catalog; confirm available levels with /model)"; fi
  ctx="$ctx Before starting the task ask one question at a time using request_user_input_async or the available question tool. Wait for an explicit answer at each step. If buttons are unavailable or all choices do not fit, use a numbered text list with 0 to cancel. Request the option number for text replies. Catalog (model:efforts): $menu."
  if [ "$pick_model" = false ] || { [ "$current_model" = "$md" ] && [ -z "$current_effort" ]; }; then
    ctx="$ctx Ask only for effort for $current_model."
  else
    ctx="$ctx First ask for the model. Offer every available model, including the current one, and label current and recommended. After the answer ask for effort for that selected model."
  fi
  ctx="$ctx Offer supported efforts only. Mark current and recommended where applicable. If effort data is missing, ask the user to choose a level offered by /model. On dismissal or cancellation cancel the task, discard both selections and restore the original draft if the client supports it; otherwise give the original text back for editing. If the selected settings already match, proceed with the task."
else
  ctx="$ctx Use the recommendation without asking."
fi
ctx="$ctx When a change is needed this host requires a manual command. Show /model MODEL --reasoning=EFFORT for the final selection (omit MODEL when unchanged), then ask to resend the original task. For the recommended pair: $model_command. Wait instead of executing under the old settings. Manual /model can persist; tell the user to restore their previous settings after this task."
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"},"systemMessage":"%s"}\n' "$ctx" "$msg"
