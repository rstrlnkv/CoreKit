#!/usr/bin/env bash
# coremodel in Codex: Codex hooks cannot change the model, so a UserPromptSubmit hook
# (plugins/coremodel/codex/hint.sh) asks a small model which model and effort the prompt needs and adds
# that as context ("switch with /model"). The hint is off until the person turns it on, and it stays
# silent when the current model already fits. Checks: the Codex manifest and hooks file (and, offline, that
# Codex 0.166.0 lists exactly that hook and not the Claude module hooks/hooks.json), then hint.sh against
# a FAKE `codex` on PATH. No network; CODEX_HOME and HOME are the test sandbox. The manifest key was found by
# experiment on codex 0.166.0: "hooks" in .codex-plugin/plugin.json (a string or an array of paths, relative
# to the plugin root), seen through the app-server request `hooks/list` (sourcePath, key, eventName).
# HINT_SH=<path> runs the behaviour checks against another copy of hint.sh (used to mutate copies).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
# Processes are found by the pids the stub writes, never by name: another suite running at the same time has
# stubs with the same command line. OURS holds the pids of a check in progress; they are stopped when the file exits
# (at_exit, before lib.sh removes the sandboxes).
OURS=""
# shellcheck disable=SC2086  # a list of pids
stop_ours() { [ -z "$OURS" ] || kill $OURS 2>/dev/null; OURS=""; }
at_exit stop_ours
# gone <pid> — the process is not running (not a child of this shell: a child stays a zombie until waited for)
gone() { ! kill -0 "$1" 2>/dev/null; }
# DECOY is another suite's stub sleep: the same command line, started by this file. decoy_kept <label> — it was not
# killed here: it is still running (ended now with USR1, which nothing else sends) or ended by itself (exit 0).
decoy_kept() {
  local rc; kill -USR1 "$DECOY" 2>/dev/null; wait "$DECOY" 2>/dev/null; rc=$?; OURS=""
  { [ "$rc" = 0 ] || [ "$(kill -l "$rc" 2>/dev/null)" = USR1 ]; } && pass || fail "$1: another run's sleep was killed (exit $rc)"
}
CM="$ROOT/plugins/coremodel"
HINT="${HINT_SH:-$CM/codex/hint.sh}"
CX_MAN="$CM/.codex-plugin/plugin.json"; CL_MAN="$CM/.claude-plugin/plugin.json"
HJSON="$CM/codex/hooks.json"

json_ok() { # json_ok <file> — valid JSON (node or python3; without either, only a brace check)
  if command -v node >/dev/null 2>&1; then node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null
  else head -c1 "$1" | grep -q '{'; fi
}
field() { sed -n "s/^ *\"$2\": *\"\(.*\)\",\{0,1\}\$/\1/p" "$1" | head -1; }

# ---- A. manifest ----
echo "  -- A. manifest and hooks file"
assert_file "$CX_MAN"
if [ -f "$CX_MAN" ]; then
  json_ok "$CX_MAN" && pass || fail "$CX_MAN is not valid JSON"
  # description: the Codex one differs by design (a hint only); tests/test_manifest.sh checks the rest
  for k in name version; do
    v="$(field "$CX_MAN" $k)"
    [ -n "$v" ] && pass || fail "codex manifest has no $k"
    assert_eq "$v" "$(field "$CL_MAN" $k)" "codex manifest $k = claude manifest $k"
  done
  # Codex gets a hint, not a switch: its description promises nothing only the Claude module does
  d="$(field "$CX_MAN" description)"
  [ -n "$d" ] && pass || fail "codex manifest has no description"
  [ "$d" != "$(field "$CL_MAN" description)" ] && pass || fail "codex manifest description is the Claude one"
  for word in Fable Opus Sonnet Haiku xhigh 'asks before' 'token cost' Picks 'switches'; do
    case "$d" in *"$word"*) fail "codex description names Claude-only behaviour: $word" ;; *) pass ;; esac
  done
  case "$d" in */model*) pass ;; *) fail "codex description does not say the person switches with /model" ;; esac
  grep -qE '"hooks": *("\./codex/hooks\.json"|\[ *"\./codex/hooks\.json" *\])' "$CX_MAN" && pass || fail "codex manifest does not point \"hooks\" at ./codex/hooks.json"
fi
# the Claude module file stays as it is and is not what Codex reads
assert_contains "$CM/hooks/hooks.json" '"modules"'
# and it wires no command hook: the Codex-only hint must not run in Claude Code
assert_not_contains "$CM/hooks/hooks.json" '"hooks"'
assert_file "$HJSON"
if [ -f "$HJSON" ]; then
  json_ok "$HJSON" && pass || fail "$HJSON is not valid JSON"
  assert_eq "$(grep -c '"UserPromptSubmit"' "$HJSON")" "1" "one UserPromptSubmit entry"
  # Stop keeps the end of Codex's reply for the next prompt (the same script)
  assert_eq "$(grep -c '"Stop"' "$HJSON")" "1" "one Stop entry"
  assert_eq "$(grep -c '"command"' "$HJSON")" "2" "two hook commands"
  assert_eq "$(grep -cE '"(PreToolUse|PostToolUse|SessionStart|PermissionRequest|SubagentStop)"' "$HJSON")" "0" "no other event"
  assert_eq "$(grep -c 'bash \\"${CLAUDE_PLUGIN_ROOT}/codex/hint.sh\\"' "$HJSON")" "2" "both events run hint.sh"
  # Codex shows this while the hook runs, instead of a silent wait
  assert_contains "$HJSON" '"statusMessage": "coremodel: choosing a model"'
  assert_eq "$(grep -c '"statusMessage"' "$HJSON")" "1" "only the prompt hook shows a status"
  t="$(grep '"statusMessage"' "$HJSON" | sed -n 's/.*"timeout": *\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [ -n "$t" ] && [ "$t" -ge 1 ] && [ "$t" -le 30 ]; then pass; else fail "explicit timeout 1..30 s in hooks.json (got '${t:-none}')"; fi
  # the hook's own wait (default 20 s) fits inside the hook timeout
  if [ -n "$t" ] && [ "$t" -gt 20 ]; then pass; else fail "hook timeout ($t) must exceed hint.sh's own 20 s limit"; fi
  # the Stop hook only writes a file: a short limit
  ts="$(sed -n '/"Stop"/,$p' "$HJSON" | sed -n 's/.*"timeout": *\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [ -n "$ts" ] && [ "$ts" -ge 1 ] && [ "$ts" -le 10 ]; then pass; else fail "Stop timeout 1..10 s (got '${ts:-none}')"; fi
fi

# offline install into the sandbox CODEX_HOME and ask Codex which hooks it sees
if command -v codex >/dev/null 2>&1; then
  mkdir -p "$CODEX_HOME" "$SANDBOX/work"
  cx() { codex --disable remote_plugin --disable plugin_discovery_prefetch "$@"; }
  assert_exit 0 cx plugin marketplace add "$ROOT"
  assert_exit 0 cx plugin add coremodel@corekit
  ver="$(field "$CL_MAN" version)"
  inst="$CODEX_HOME/plugins/cache/corekit/coremodel/$ver"
  assert_file "$inst/codex/hint.sh"
  assert_file "$inst/.codex-plugin/plugin.json"
  codex_hooks_list "$SANDBOX/work" "$SANDBOX/hooks-list.out" && pass || fail "hooks/list: no answer in 10 s: $(head -3 "$SANDBOX/hooks-list.out.err")"
  grep '^{"key":"coremodel@' "$SANDBOX/hooks-list.out" > "$SANDBOX/hooks.lines"
  assert_eq "$(wc -l < "$SANDBOX/hooks.lines" | tr -d ' ')" "2" "Codex lists exactly two coremodel hooks"
  assert_contains "$SANDBOX/hooks.lines" '"key":"coremodel@corekit:codex/hooks.json:user_prompt_submit:0:0"'
  assert_contains "$SANDBOX/hooks.lines" '"eventName":"userPromptSubmit"'
  assert_contains "$SANDBOX/hooks.lines" '"key":"coremodel@corekit:codex/hooks.json:stop:0:0"'
  assert_contains "$SANDBOX/hooks.lines" '"eventName":"stop"'
  assert_contains "$SANDBOX/hooks.lines" "\"sourcePath\":\"$inst/codex/hooks.json\""
  assert_contains "$SANDBOX/hooks.lines" "$inst/codex/hint.sh"
  assert_not_contains "$SANDBOX/hooks.lines" 'hooks/hooks.json'
  assert_not_contains "$SANDBOX/hooks.lines" 'CLAUDE_PLUGIN_ROOT'
else
  skip codex-install "codex not on PATH; the offline install and hooks/list checks are not run"
fi

# ---- C. hint.sh against a fake codex ----
echo "  -- C. hint.sh"
assert_file "$HINT"
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
STUB_ANSWER="$SANDBOX/answer"; CALLS="$SANDBOX/calls"; ARGV="$SANDBOX/argv"; STDIN="$SANDBOX/stdin"; ENVREC="$SANDBOX/env"
cat > "$BIN/codex" <<'STUB'
#!/bin/bash
# fake codex: records argv (NUL-separated), stdin, COREMODEL_NESTED; answers with $STUB_ANSWER (or fails as $STUB_MODE says)
echo x >> "$STUB_DIR/calls"
pwd -P > "$STUB_DIR/classifier-cwd"
find . ! -name . -prune -print > "$STUB_DIR/classifier-files"
printf '%s\0' "$@" > "$STUB_DIR/argv"
cat > "$STUB_DIR/stdin"
echo "NESTED=${COREMODEL_NESTED:-}" > "$STUB_DIR/env"
echo $$ > "$STUB_DIR/pid"
case "${STUB_MODE:-ok}" in
  partial) cat "$STUB_DIR/answer"; exit 1 ;;
  fail) echo "boom" >&2; exit 1 ;;
  empty) exit 0 ;;
  sleep) sleep 10.37 & echo $! > "$STUB_DIR/sleep.pid"; wait $!; exit 0 ;;
esac
# an answer file given as -o / --output-last-message is written too; the --output-schema file is kept
prev=""; for a in "$@"; do
  case "$prev" in -o|--output-last-message) cat "$STUB_DIR/answer" > "$a" ;; --output-schema) cat "$a" > "$STUB_DIR/schema" ;; esac
  prev="$a"
done
cat "$STUB_DIR/answer"
STUB
chmod +x "$BIN/codex"
export STUB_DIR="$SANDBOX"
PATHSTUB="$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
PATHNONE="$SANDBOX/nobin:/usr/bin:/bin:/usr/sbin:/sbin"; mkdir -p "$SANDBOX/nobin"

# The hint is off until turned on; ON_SF turns it on for the behaviour checks.
ON_SF="$SANDBOX/coremodel-on"; printf 'codex_hint: on\n' > "$ON_SF"
# run_hint <path> <stdin-text> [VAR=value ...] — stdout in $SANDBOX/out, stderr in $SANDBOX/err, exit code in $RC.
# The hint is on (COREMODEL_CONFIG=$ON_SF) unless a VAR=value names COREMODEL_CONFIG itself.
# The saved replies go under $STATE (XDG_STATE_HOME), never the developer's own state folder.
STATE="$SANDBOX/state"; REPLIES="$STATE/coremodel/codex-replies"
run_hint() {
  local p="$1" in="$2"; shift 2
  rm -f "$CALLS" "$ARGV" "$STDIN" "$ENVREC" "$SANDBOX/pid" "$SANDBOX/sleep.pid" "$SANDBOX/schema"
  { printf "%s" "$in"; } 2>/dev/null | env PATH="$p" COREMODEL_CONFIG="$ON_SF" XDG_STATE_HOME="$STATE" "$@" /bin/bash "$HINT" > "$SANDBOX/out" 2> "$SANDBOX/err"; RC=$?
}
ncalls() { [ -f "$CALLS" ] && wc -l < "$CALLS" | tr -d ' ' || echo 0; }
# event <prompt> — the hook's stdin JSON for a prompt (Codex's shape, tests/lib-hook.sh)
event() { hook_event codex UserPromptSubmit /tmp prompt="$1"; }
silent() { # silent <label> — exit 0, nothing on stdout
  assert_eq "$RC" "0" "$1: exit 0"
  assert_eq "$(cat "$SANDBOX/out")" "" "$1: no stdout"
}
answer() { printf '%s' "$1" > "$STUB_ANSWER"; }
reps() { awk -v n="$1" -v c="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", c }'; }   # reps <n> <char>

# the Codex classifier template: its own file, with Codex's model names (the Claude one stays in classifier.ts)
TPL="$CM/codex/classifier.txt"
assert_file "$TPL"
T_FIRST="$(head -1 "$TPL" 2>/dev/null)"
T_LAST="$(tail -1 "$TPL" 2>/dev/null)"
for ph in '{{REPLY}}' '{{PROMPT}}'; do assert_eq "$(grep -cF "$ph" "$TPL" 2>/dev/null)" "1" "classifier.txt has $ph once"; done
assert_not_contains "$TPL" '{{NOW}}'   # Codex does not tell the hook the current effort
for w in Claude haiku sonnet opus fable; do assert_not_contains "$TPL" "$w"; done
# {{PROMPT}} after {{REPLY}}: the person's text is spliced in last
if [ "$(grep -nF '{{REPLY}}' "$TPL" | cut -d: -f1)" -lt "$(grep -nF '{{PROMPT}}' "$TPL" | cut -d: -f1)" ] 2>/dev/null; then pass; else fail "{{PROMPT}} must come after {{REPLY}}"; fi
# the Claude Code template and its parser are not touched by the Codex work
assert_contains "$CM/hooks/classifier.ts" 'Pick the effort level and the model for one prompt sent to Claude Code.'

# main path: high, astra
answer '{"keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
assert_eq "$RC" "0" "main: exit 0"
assert_eq "$(ncalls)" "1" "main: codex called once"
assert_eq "$(cat "$SANDBOX/classifier-files")" "" "classifier starts in an empty folder"
assert_no_file "$(cat "$SANDBOX/classifier-cwd")"
if [ -f "$ARGV" ]; then
  tr '\0' '\n' < "$ARGV" > "$SANDBOX/argv.txt"
  assert_eq "$(sed -n 1p "$SANDBOX/argv.txt")" "exec" "main: first argument is exec"
  # --model gpt-6-luna (or -m, or --model=...)
  if grep -qxF -- 'gpt-6-luna' "$SANDBOX/argv.txt" && { grep -qxE -- '--model|-m' "$SANDBOX/argv.txt" || grep -qxF -- '--model=gpt-6-luna' "$SANDBOX/argv.txt"; }; then pass; else fail "main: argv lacks --model gpt-6-luna"; fi
  if grep -A1 -xE -- '--sandbox|-s' "$SANDBOX/argv.txt" | grep -qxF read-only || grep -qxF -- '--sandbox=read-only' "$SANDBOX/argv.txt"; then pass; else fail "main: argv lacks a read-only sandbox"; fi
  grep -qE 'danger|full-auto|workspace-write|bypass' "$SANDBOX/argv.txt" && fail "main: argv widens the sandbox" || pass
  cat "$SANDBOX/argv.txt" "$STDIN" > "$SANDBOX/sent.txt"   # the prompt may go as an argument or on stdin
  assert_contains "$SANDBOX/sent.txt" "$T_FIRST"
  assert_contains "$SANDBOX/sent.txt" "$T_LAST"
  assert_contains "$SANDBOX/sent.txt" 'fix the flaky login test'
  assert_not_contains "$SANDBOX/sent.txt" '{{PROMPT}}'
  assert_not_contains "$SANDBOX/sent.txt" '{{REPLY}}'
  for m in gpt-6-luna gpt-6.1-sol gpt-6-astra; do assert_contains "$SANDBOX/sent.txt" "$m"; done
  if grep -iE 'JSON (shape|schema)|keep, model and effort' "$SANDBOX/sent.txt" | grep -iqw why; then fail "main: classifier prompt requests a why field"; else pass; fi
  # the hook never claims a first prompt: it cannot know that
  assert_not_contains "$STDIN" 'first prompt'
  # the answer shape goes as a JSON Schema file: keep, model and effort, each on its own
  grep -A1 -xF -- '--output-schema' "$SANDBOX/argv.txt" | sed -n 2p | grep -q . && pass || fail "main: argv lacks --output-schema <file>"
  for k in '"keep"' '"model"' '"effort"' '"additionalProperties":false' '"required":["keep","model","effort"]' \
    '"gpt-6-luna"' '"gpt-6.1-sol"' '"gpt-6-astra"' '"low"' '"medium"' '"high"' '"xhigh"' '"max"'; do
    assert_contains "$SANDBOX/schema" "$k"
  done
  assert_not_contains "$SANDBOX/schema" '"why"'
  assert_not_contains "$SANDBOX/schema" '"ultra"'   # a delegation mode, not a depth: never recommended
  json_ok "$SANDBOX/schema" && pass || fail "main: the schema is not valid JSON"
fi
assert_contains "$ENVREC" 'NESTED=1'
out="$(cat "$SANDBOX/out")"
case "$out" in
  '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"'*'"},"systemMessage":"'*'"}') pass ;;
  *) fail "main: stdout is not the hookSpecificOutput object: $out" ;;
esac
assert_eq "$(printf '%s' "$out" | wc -l | tr -d ' ')" "0" "main: stdout is one line"
json_ok "$SANDBOX/out" && pass || fail "main: stdout is not valid JSON"
case "$out" in *'"systemMessage":"coremodel: this prompt needs gpt-6-astra'*) pass ;; *) fail "main: no systemMessage: $out" ;; esac
case "$out" in *gpt-6-astra*) pass ;; *) fail "main: context lacks gpt-6-astra: $out" ;; esac
case "$out" in *high*) pass ;; *) fail "main: context lacks the effort 'high'" ;; esac
case "$out" in *xhigh*) fail "main: effort high reported as xhigh" ;; *) pass ;; esac
case "$out" in */model*) pass ;; *) fail "main: context lacks /model" ;; esac
case "$out" in *'fix the flaky login test'*) fail "main: the prompt is printed back" ;; *) pass ;; esac
# Codex Desktop does not show systemMessage in the chat: additionalContext asks the model to name the pick in its first
# visible message, in the person's language, and to carry on. systemMessage stays for clients that show it.
ctx="$(printf '%s' "$out" | sed -n 's/.*"additionalContext":"\([^"]*\)".*/\1/p')"
sysm="$(printf '%s' "$out" | sed -n 's/.*"systemMessage":"\([^"]*\)".*/\1/p')"
assert_eq "$sysm" "coremodel: this prompt needs gpt-6-astra at high effort; switch with /model if the current one differs." "main: systemMessage as before"
for w in 'CoreModel recommends GPT-6 Astra · High' 'first visible message' "user's language" 'Then continue' '/model'; do
  case "$ctx" in *"$w"*) pass ;; *) fail "main: additionalContext lacks '$w': $ctx" ;; esac
done
[ "$ctx" != "$sysm" ] && pass || fail "main: additionalContext is the systemMessage line"
# the label for each model and effort
label() { # label <model> <effort> <expected label>
  answer "{\"why\":\"x\",\"keep\":false,\"model\":\"$1\",\"effort\":\"$2\"}"
  run_hint "$PATHSTUB" "$(event 'do the thing in the code')"
  json_ok "$SANDBOX/out" && pass || fail "label $1/$2: stdout is not valid JSON"
  assert_contains "$SANDBOX/out" "\"additionalContext\":\"CoreModel recommends $3 "
}
label gpt-6-luna low 'GPT-6 Luna · Low'
label gpt-6.1-sol medium 'GPT-6.1 Sol · Medium'
label gpt-6-astra xhigh 'GPT-6 Astra · XHigh'
label gpt-6-astra max 'GPT-6 Astra · Max'

# model and effort are read on their own: a strong model at low effort stays low, a light one at high stays high
check_pair() { # <model> <effort> <other names that must not appear>
  answer "{\"why\":\"x\",\"keep\":false,\"model\":\"$1\",\"effort\":\"$2\"}"
  run_hint "$PATHSTUB" "$(event 'do the thing in the code')"
  local o; o="$(cat "$SANDBOX/out")"
  assert_eq "$RC" "0" "pair $1/$2: exit 0"
  case "$o" in *"needs $1 at $2 effort"*) pass ;; *) fail "pair $1/$2: context lacks '$1 at $2 effort': $o" ;; esac
  case "$o" in */model*) pass ;; *) fail "pair $1/$2: context lacks /model" ;; esac
  local m; for m in $3; do case "$o" in *"$m"*) fail "pair $1/$2: context names $m too: $o" ;; *) pass ;; esac; done
}
check_pair gpt-6-luna low "gpt-6.1-sol gpt-6-astra"
check_pair gpt-6-luna high "gpt-6.1-sol gpt-6-astra"
check_pair gpt-6.1-sol medium "gpt-6-luna gpt-6-astra"
check_pair gpt-6-astra low "gpt-6-luna gpt-6.1-sol"
check_pair gpt-6-astra xhigh "gpt-6-luna gpt-6.1-sol"
check_pair gpt-6-astra max "gpt-6-luna gpt-6.1-sol"
# the answer may come wrapped in prose or a fence
answer 'Sure! ```json
{"why":"x","keep":false,"model":"gpt-6.1-sol","effort":"medium"}
```'
run_hint "$PATHSTUB" "$(event 'add a field')"
case "$(cat "$SANDBOX/out")" in *'needs gpt-6.1-sol at medium effort'*) pass ;; *) fail "fenced answer is not read: $(cat "$SANDBOX/out")" ;; esac

# keep: nothing to add
answer '{"why":"picks an offered option","keep":true,"model":"gpt-6.1-sol","effort":"medium"}'
run_hint "$PATHSTUB" "$(event 'option 2')"
silent "keep"; assert_eq "$(ncalls)" "1" "keep: codex was asked"

# ---- C1. local skip: a whole greeting, approval or "go on" never reaches Luna ----
echo "  -- C1. local skip"
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
for p in 'привет' 'Привет!' 'Добрый день' 'да' 'ДА' 'да, давай' 'Да, давай.' 'ок' 'Окей, спасибо!' 'да, продолжай' 'давай дальше' \
  'спасибо большое' 'хорошо, делай' 'Ну давай' 'hi' 'Hello!' 'thanks' 'Thank you!' 'yes' 'Yes please' 'ok, go ahead' 'OK' 'sounds good' \
  'continue' 'keep going' 'lgtm' 'yep, do it' '👍'; do
  run_hint "$PATHSTUB" "$(event "$p")"
  silent "local skip '$p'"; assert_eq "$(ncalls)" "0" "local skip '$p': Luna not called"
done
# new work after an approval, or a reply that may lean on the last answer: Luna is asked
for p in 'Да, и ещё выясни, почему сумма заказа иногда расходится на копейку' 'Да, и ещё проверь расчёты' 'почини' 'Почини' \
  'второй вариант' 'да, но без тестов' 'нет' 'no' 'yes, and also fix the login' 'hi, why does the build fail?' 'привет, как дела с релизом?' \
  'go ahead and deploy to prod' 'ok then rename it' 'continue the migration' 'thanks, now add tests'; do
  run_hint "$PATHSTUB" "$(event "$p")"
  assert_eq "$(ncalls)" "1" "'$p': Luna is asked"
done
# the new work after "да, и ещё" is judged: the hint names it
run_hint "$PATHSTUB" "$(event 'Да, и ещё выясни, почему сумма заказа иногда расходится на копейку')"
assert_contains "$STDIN" 'Да, и ещё выясни, почему сумма заказа иногда расходится на копейку'
case "$(cat "$SANDBOX/out")" in *'needs gpt-6-astra at high effort'*) pass ;; *) fail "'да, и ещё…': no astra/high hint: $(cat "$SANDBOX/out")" ;; esac
# the phrase list is data next to the script, and a list entry with spaces or a comment line does not break it
assert_file "$CM/codex/replies.txt"
for w in 'привет' 'да' 'давай' 'продолжай' 'hi' 'yes' 'go ahead' 'continue'; do
  grep -qxF -- "$w" "$CM/codex/replies.txt" && pass || fail "replies.txt lacks '$w'"
done
for w in 'почини' 'нет' 'no' 'fix it'; do
  grep -qxF -- "$w" "$CM/codex/replies.txt" && fail "replies.txt holds '$w', which names work or turns it down" || pass
done
# a long prompt is never skipped, whatever it is made of
run_hint "$PATHSTUB" "$(event "$(awk 'BEGIN { for (i = 0; i < 60; i++) printf "да " }')")"
assert_eq "$(ncalls)" "1" "a long run of approvals goes to Luna"

# ---- C2. the last reply: kept by Stop, sent only for a short prompt, never claimed when missing ----
echo "  -- C2. context from Stop"
# sevent <session> <last reply, JSON-escaped> — Codex's Stop event
sevent() { printf '{"session_id":"%s","turn_id":"t","cwd":"/tmp","hook_event_name":"Stop","model":"gpt-6.1-sol","permission_mode":"default","stop_hook_active":false,"transcript_path":null,"last_assistant_message":%s}' "$1" "$2"; }
# pevent <session> <prompt> — a prompt in that session
pevent() { printf '{"session_id":"%s","turn_id":"t","cwd":"/tmp","hook_event_name":"UserPromptSubmit","model":"gpt-6.1-sol","permission_mode":"default","transcript_path":null,"prompt":"%s"}' "$1" "$(json_esc "$2")"; }
REPLY1='I found the cause: each line is rounded before the sum. Should I fix the rounding in cart.ts?'
rm -rf "$STATE"
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")"
silent "Stop"; assert_eq "$(ncalls)" "0" "Stop: Luna not called"
assert_file "$REPLIES/s1"
assert_contains "$REPLIES/s1" 'Should I fix the rounding in cart.ts?'
# only the person can read it
case "$(ls -ld "$REPLIES" | cut -c1-10)" in drwx------) pass ;; *) fail "the replies folder is not private: $(ls -ld "$REPLIES")" ;; esac
case "$(ls -l "$REPLIES/s1" | cut -c1-10)" in -rw-------) pass ;; *) fail "the saved reply is not private: $(ls -l "$REPLIES/s1")" ;; esac
# a short follow-up gets the reply, and the reply is used once
answer '{"why":"fix the named rounding","keep":false,"model":"gpt-6.1-sol","effort":"medium"}'
run_hint "$PATHSTUB" "$(pevent s1 'почини')"
assert_eq "$(ncalls)" "1" "почини with context: Luna asked"
assert_contains "$STDIN" 'Should I fix the rounding in cart.ts?'
assert_not_contains "$STDIN" '(unknown'
assert_no_file "$REPLIES/s1"
# without a saved reply: said to be unknown, never "first prompt"
run_hint "$PATHSTUB" "$(pevent s1 'почини')"
assert_contains "$STDIN" '(unknown'
assert_not_contains "$STDIN" 'first prompt'
assert_not_contains "$STDIN" 'cart.ts'
# another session's reply is not used
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")"
run_hint "$PATHSTUB" "$(pevent s2 'второй вариант')"
assert_contains "$STDIN" '(unknown'
assert_not_contains "$STDIN" 'cart.ts'
assert_file "$REPLIES/s1"
# a long prompt stands on its own: the reply is not sent, and it is dropped all the same
LONGP='Add a CSV export to the orders page with the same columns as the table, and a test for an empty list'
run_hint "$PATHSTUB" "$(pevent s1 "$LONGP")"
assert_contains "$STDIN" "$LONGP"
assert_not_contains "$STDIN" 'cart.ts'
assert_contains "$STDIN" '(not included'
assert_no_file "$REPLIES/s1"
# a skipped approval drops the saved reply too: the next prompt follows a newer turn
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")"
run_hint "$PATHSTUB" "$(pevent s1 'да')"
assert_eq "$(ncalls)" "0" "да after a reply: Luna not called"
assert_no_file "$REPLIES/s1"
# only the end of a long reply is kept (the question sits there), cut on a character boundary
LONGR="$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "ёжик " }')THE QUESTION?"
run_hint "$PATHSTUB" "$(sevent s1 "\"$LONGR\"")"
sz="$(wc -c < "$REPLIES/s1" | tr -d ' ')"
if [ "$sz" -gt 300 ] && [ "$sz" -le 600 ]; then pass; else fail "saved reply is $sz bytes, want 301..600"; fi
assert_contains "$REPLIES/s1" 'THE QUESTION?'
LC_ALL=C grep -q "^[$(printf '\200-\277')]" "$REPLIES/s1" && fail "saved reply starts inside a character" || pass
# a null or empty reply removes the saved one
run_hint "$PATHSTUB" "$(sevent s1 null)"
assert_no_file "$REPLIES/s1"
# hint off: Stop writes nothing
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")" COREMODEL_CONFIG="$SANDBOX/nothing"
assert_no_file "$REPLIES/s1"
# nested (the classifier's own run): nothing either
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")" COREMODEL_NESTED=1
assert_no_file "$REPLIES/s1"
# a session id that is not a plain name writes nothing and reads nothing
for sid in '../escape' 'a/b' '.hidden' '' "$(reps 200 a)"; do
  rm -rf "$STATE"
  run_hint "$PATHSTUB" "$(sevent "$sid" "\"$REPLY1\"")"
  silent "Stop with session '$sid'"
  assert_eq "$(find "$STATE" -type f 2>/dev/null)" "" "Stop with session '$sid': no file written"
done
# a stale reply (older than a day) is removed by the next Stop
mkdir -p "$REPLIES"; printf 'old' > "$REPLIES/old-session"; touch -t 202001010000 "$REPLIES/old-session"
run_hint "$PATHSTUB" "$(sevent s1 "\"$REPLY1\"")"
assert_no_file "$REPLIES/old-session"
assert_file "$REPLIES/s1"
rm -rf "$STATE"

run_hint "$PATHSTUB" "$(sevent resumed '"expired reply"')"
touch -t 202001010000 "$REPLIES/resumed"
run_hint "$PATHSTUB" "$(pevent resumed 'fix it')"
assert_not_contains "$STDIN" 'expired reply'
assert_contains "$STDIN" '(unknown'
assert_no_file "$REPLIES/resumed"

# ---- C3. the client's model catalog ----
echo "  -- C3. catalog"
CAT="$SANDBOX/cat-home"; mkdir -p "$CAT"
# catalog <models...> — each "slug:visibility:effort,effort,..."; written as Codex's models_cache.json is
catalog() {
  local first=1 m slug vis effs e
  { printf '{\n  "fetched_at": "2026-11-11T00:00:00Z",\n  "models": [\n'
    for m in "$@"; do
      slug="${m%%:*}"; vis="${m#*:}"; vis="${vis%%:*}"; effs="${m##*:}"
      [ "$first" = 1 ] || printf ',\n'; first=0
      printf '    {\n      "slug": "%s",\n      "description": "a \\"slug\\": \\"fake\\" text",\n      "supported_reasoning_levels": [\n' "$slug"
      local f2=1; for e in $(printf '%s' "$effs" | tr ',' ' '); do
        [ "$f2" = 1 ] || printf ',\n'; f2=0; printf '        { "effort": "%s", "description": "d" }' "$e"
      done
      printf '\n      ],\n      "visibility": "%s",\n      "multi_agent_reasoning_effort": "max"\n    }' "$vis"
    done
    printf '\n  ]\n}\n'; } > "$CAT/models_cache.json"
}
printf '%s\n' '{"models":[{"visibility":"list","supported_reasoning_levels":[{"effort":"medium"}],"slug":"gpt-6.1-sol"},{"visibility":"list","slug":"gpt-6-astra"}]}' > "$CAT/models_cache.json"
answer '{"keep":false,"model":"gpt-6.1-sol","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'rename the field everywhere')" CODEX_HOME="$CAT"
assert_contains "$SANDBOX/out" 'needs gpt-6.1-sol at medium effort'
tr '\0' '\n' < "$ARGV" > "$SANDBOX/argv.txt"
assert_eq "$(awk '/^--model$/ { getline; print }' "$SANDBOX/argv.txt")" 'gpt-6.1-sol' "lightest available classifier"
assert_contains "$SANDBOX/argv.txt" 'model_reasoning_effort="medium"'
# luna offers no max here: a max pick on luna is lowered to its highest level
catalog 'gpt-6-luna:list:low,medium,high' 'gpt-6.1-sol:list:low,medium,high,xhigh,max,ultra' 'gpt-6-astra:list:low,medium,high,xhigh,max,ultra'
json_ok "$CAT/models_cache.json" && pass || fail "the test catalog is not valid JSON"
answer '{"why":"x","keep":false,"model":"gpt-6-luna","effort":"max"}'
run_hint "$PATHSTUB" "$(event 'rename the field everywhere')" CODEX_HOME="$CAT"
case "$(cat "$SANDBOX/out")" in *'needs gpt-6-luna at high effort'*) pass ;; *) fail "catalog: luna/max is not lowered to high: $(cat "$SANDBOX/out")" ;; esac
# a model the catalog hides or lacks is not offered to Luna, and not named if Luna names it anyway
catalog 'gpt-6-luna:list:low,medium,high,xhigh,max' 'gpt-6.1-sol:list:low,medium,high,xhigh,max' 'gpt-6-astra:hide:low,medium,high'
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$CAT"
assert_eq "$(ncalls)" "1" "catalog without astra: Luna asked"
assert_not_contains "$SANDBOX/schema" 'gpt-6-astra'
assert_contains "$SANDBOX/schema" '"gpt-6.1-sol"'
silent "catalog without astra: astra not named"
# none of the three models in the catalog: nothing to offer, no call
catalog 'gpt-7-x:list:low,high'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$CAT"
silent "catalog without the ladder"; assert_eq "$(ncalls)" "0" "catalog without the ladder: Luna not called"
# A readable catalog may list no visible models, or contain no models at all.
catalog 'gpt-6-luna:hide:low,high' 'gpt-6.1-sol:hide:low,high' 'gpt-6-astra:hide:low,high'
json_ok "$CAT/models_cache.json" && pass || fail "all-hidden catalog is not valid JSON"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$CAT"
silent "all-hidden catalog"; assert_eq "$(ncalls)" "0" "all-hidden catalog: Luna not called"
catalog
json_ok "$CAT/models_cache.json" && pass || fail "empty catalog is not valid JSON"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$CAT"
silent "empty catalog"; assert_eq "$(ncalls)" "0" "empty catalog: Luna not called"
# an unreadable catalog is no catalog: all three are offered
printf 'not json' > "$CAT/models_cache.json"
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$CAT"
assert_contains "$SANDBOX/schema" '"gpt-6-astra"'
case "$(cat "$SANDBOX/out")" in *'needs gpt-6-astra at high effort'*) pass ;; *) fail "unreadable catalog: no hint" ;; esac
# no catalog at all: the same
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" CODEX_HOME="$SANDBOX/no-such-home"
case "$(cat "$SANDBOX/out")" in *'needs gpt-6-astra at high effort'*) pass ;; *) fail "no catalog: no hint" ;; esac

# A visible 6.2 model takes its tier's place in the schema, prompt, and hint.
mevent() { hook_event codex UserPromptSubmit /tmp model="$1" prompt="$2"; }   # mevent <model> <prompt>
catalog 'gpt-6-luna:list:low,medium,high' 'gpt-6.1-sol:list:low,medium,high' 'gpt-6.2-sol:list:low,medium,high' \
  'gpt-6-astra:list:low,medium,high' 'gpt-6.2-astra:list:low,medium,high'
answer '{"keep":false,"model":"gpt-6.2-sol","effort":"medium"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'add a field')" CODEX_HOME="$CAT"
assert_eq "$(ncalls)" "1" "visible 6.2 models: codex was asked"
for m in gpt-6-luna gpt-6.2-sol gpt-6.2-astra; do
  assert_contains "$SANDBOX/schema" "\"$m\""
  assert_contains "$STDIN" "$m"
done
for m in gpt-6.1-sol gpt-6-astra; do
  assert_not_contains "$SANDBOX/schema" "\"$m\""
  assert_not_contains "$STDIN" "$m"
done
assert_contains "$SANDBOX/out" 'needs gpt-6.2-sol at medium effort'
assert_contains "$SANDBOX/out" 'CoreModel recommends GPT-6.2 Sol · Medium'

answer '{"keep":false,"model":"gpt-6.2-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-astra 'fix the flaky login test')" CODEX_HOME="$CAT"
assert_eq "$(ncalls)" "1" "legacy Astra with visible 6.2 Astra: codex was asked"
assert_contains "$SANDBOX/out" 'needs gpt-6.2-astra at high effort'
assert_contains "$SANDBOX/out" 'CoreModel recommends GPT-6.2 Astra · High'
run_hint "$PATHSTUB" "$(mevent gpt-6.2-astra 'fix the flaky login test')" CODEX_HOME="$CAT"
silent "on the strongest 6.2 model"; assert_eq "$(ncalls)" "0" "on the strongest 6.2 model: codex not called"

# Fallback is independent for the two tiers, and hidden entries are unavailable.
catalog 'gpt-6-luna:list:low,medium,high' 'gpt-6.1-sol:list:low,medium,high' 'gpt-6.2-sol:hide:low,medium,high' \
  'gpt-6-astra:list:low,medium,high' 'gpt-6.2-astra:list:low,medium,high'
answer '{"keep":false,"model":"gpt-6.1-sol","effort":"medium"}'
run_hint "$PATHSTUB" "$(event 'add a field')" CODEX_HOME="$CAT"
assert_contains "$SANDBOX/schema" '"gpt-6.1-sol"'
assert_contains "$SANDBOX/schema" '"gpt-6.2-astra"'
assert_not_contains "$SANDBOX/schema" '"gpt-6.2-sol"'
assert_contains "$STDIN" 'gpt-6.1-sol'
assert_not_contains "$STDIN" 'gpt-6.2-sol'
assert_contains "$SANDBOX/out" 'needs gpt-6.1-sol at medium effort'
run_hint "$PATHSTUB" "$(mevent gpt-6.2-sol 'add a field')" CODEX_HOME="$CAT"
assert_eq "$(ncalls)" "1" "6.2 Sol with legacy Sol offered: codex was asked"
silent "6.2 Sol is stronger than legacy Sol"

catalog 'gpt-6-luna:list:low,medium,high' 'gpt-6.1-sol:list:low,medium,high' 'gpt-6.2-sol:list:low,medium,high' 'gpt-6-astra:list:low,medium,high'
answer '{"keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.2-sol 'fix the flaky login test')" CODEX_HOME="$CAT"
assert_contains "$SANDBOX/schema" '"gpt-6.2-sol"'
assert_contains "$SANDBOX/schema" '"gpt-6-astra"'
assert_not_contains "$SANDBOX/schema" '"gpt-6.2-astra"'
assert_contains "$STDIN" 'gpt-6-astra'
assert_not_contains "$STDIN" 'gpt-6.2-astra'
assert_contains "$SANDBOX/out" 'needs gpt-6-astra at high effort'
run_hint "$PATHSTUB" "$(mevent gpt-6.2-astra 'fix the flaky login test')" CODEX_HOME="$CAT"
silent "6.2 Astra is stronger than legacy Astra"

# recursion guard
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_NESTED=1
silent "nested"; assert_eq "$(ncalls)" "0" "nested: codex not called"

# settings: off by default; on in the coremodel settings file, or (the fallback) in the corecrew one
CM_SF="$XDG_CONFIG_HOME/coremodel/settings"; mkdir -p "$(dirname "$CM_SF")"
SF="$(bash "$SCRIPTS/lib.sh" setting-path)"; mkdir -p "$(dirname "$SF")"
rm -f "$CM_SF" "$SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
silent "no settings file: off"; assert_eq "$(ncalls)" "0" "no settings file: codex not called"
printf 'codex_hint: on\n' > "$CM_SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
assert_eq "$(ncalls)" "1" "codex_hint: on in ~/.config/coremodel/settings: codex called"
printf 'other: 1\n  codex_hint :   on  \r\n' > "$CM_SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
assert_eq "$(ncalls)" "1" "codex_hint: on (spaces, CRLF): codex called"
printf 'codex_hint: off\n' > "$CM_SF"; printf 'coremodel_mode: on\n' > "$SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
silent "coremodel off wins over corecrew on"; assert_eq "$(ncalls)" "0" "coremodel off wins: codex not called"
printf 'other: 1\n' > "$CM_SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
assert_eq "$(ncalls)" "1" "no codex_hint key: the corecrew coremodel_mode: on is the fallback"
rm -f "$CM_SF"
printf 'ui_language: en\n  coremodel_mode :   off  \r\n' > "$SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
silent "corecrew off (spaces, CRLF)"; assert_eq "$(ncalls)" "0" "corecrew off: codex not called"
printf 'ui_language: en\n' > "$SF"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
silent "corecrew without coremodel_mode: off"; assert_eq "$(ncalls)" "0" "corecrew other keys only: off by default"
for v in suggest auto yes; do
  printf 'coremodel_mode: %s\n' "$v" > "$SF"
  run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG=
  assert_eq "$(ncalls)" "0" "corecrew coremodel_mode: $v is not on"
done
rm -f "$SF"
# COREMODEL_CONFIG and CORECREW_CONFIG point the files elsewhere
printf 'codex_hint: on\n' > "$SANDBOX/alt-cm"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG="$SANDBOX/alt-cm"
assert_eq "$(ncalls)" "1" "on via COREMODEL_CONFIG: codex called"
printf 'coremodel_mode: on\n' > "$SANDBOX/alt-settings"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG= CORECREW_CONFIG="$SANDBOX/alt-settings"
assert_eq "$(ncalls)" "1" "on via CORECREW_CONFIG: codex called"
printf 'coremodel_mode: off\n' > "$SANDBOX/alt-settings"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_CONFIG= CORECREW_CONFIG="$SANDBOX/alt-settings"
silent "off via CORECREW_CONFIG"; assert_eq "$(ncalls)" "0" "off via CORECREW_CONFIG: codex not called"

# the current model: silent when it is the pick or a stronger one
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-astra 'fix the flaky login test')"
silent "on the strongest model"; assert_eq "$(ncalls)" "0" "on the strongest model: codex not called"
answer '{"why":"x","keep":false,"model":"gpt-6.1-sol","effort":"medium"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'add a field')"
silent "current model is the pick"; assert_eq "$(ncalls)" "1" "current model is the pick: codex was asked"
answer '{"why":"x","keep":false,"model":"gpt-6-luna","effort":"low"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'rename x')"
silent "current model is stronger than the pick"
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'fix the flaky login test')"
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "a weaker current model: no hint: $(cat "$SANDBOX/out")" ;; esac
answer '{"why":"x","keep":false,"model":"gpt-6-luna","effort":"low"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-luna 'rename x')"
silent "luna for a haiku pick"
# a model it does not know, or a model key that is not the event's own: the hint as before
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(mevent some-other-model 'fix the flaky login test')"
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "unknown current model: no hint" ;; esac
# a Codex model the hint does not rank (README: "it cannot compare"): the pick is named, even the lightest one
answer '{"why":"x","keep":false,"model":"gpt-6-luna","effort":"low"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-sol 'rename x')"
case "$(cat "$SANDBOX/out")" in *'needs gpt-6-luna at low effort'*) pass ;; *) fail "an unranked current model (gpt-6-sol): the pick is not named: $(cat "$SANDBOX/out")" ;; esac
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" '{"hook_event_name":"UserPromptSubmit","meta":{"model":"gpt-6-astra"},"prompt":"fix the flaky login test"}'
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "a nested model key was read as the current model" ;; esac

# failures are silent and never block the prompt
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" STUB_MODE=fail
silent "stub exits 1"; assert_eq "$(ncalls)" "1" "stub exits 1: it was called"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" STUB_MODE=empty
silent "stub prints nothing"
for g in 'garbage, no json here' '{"effort":"high"' '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"enormous"}' \
  '{"why":"x","keep":false,"model":"gpt-9","effort":"high"}' '{"why":"x","keep":false,"model":"opus","effort":"high"}' \
  '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"ultra"}' '{"why":"x","level":"high","model":"opus"}' '[1,2,3]' ''; do
  answer "$g"
  run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
  silent "garbage answer '$g'"
done
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHNONE" "$(event 'fix the flaky login test')"
silent "no codex on PATH"
for bad in '' '   ' 'not json at all' '{"hook_event_name":"UserPromptSubmit"' '{"hook_event_name":"UserPromptSubmit"}' '{"hook_event_name":"UserPromptSubmit","prompt":""}' '{"hook_event_name":"UserPromptSubmit","prompt":"   "}' '{"hook_event_name":"UserPromptSubmit","prompt":42}' '{"prompt":'; do
  run_hint "$PATHSTUB" "$bad"
  silent "stdin '$bad'"
  assert_eq "$(ncalls)" "0" "stdin '$bad': codex not called"
done
# a hook event that is not a prompt: no call
run_hint "$PATHSTUB" '{"hook_event_name":"SessionStart","prompt":"fix the flaky login test"}'
silent "other event"

# Process enumeration can be denied by the host sandbox.
printf '#!/bin/sh\nexit 1\n' > "$BIN/ps"
chmod +x "$BIN/ps"
# timeout: the stub sleeps 10 s, the limit is 2 s. Wall time on purpose: this times a real wait, not work.
t0="$(date +%s)"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" STUB_MODE=sleep COREMODEL_HINT_TIMEOUT=2
t1="$(date +%s)"
silent "timeout"
if [ $((t1 - t0)) -lt 6 ]; then pass; else fail "timeout: hint.sh took $((t1 - t0)) s with COREMODEL_HINT_TIMEOUT=2"; fi
assert_eq "$(ncalls)" "1" "timeout: stub was started"
sleep 10.37 & DECOY=$!
spid="$(cat "$SANDBOX/pid" 2>/dev/null)"; slp="$(cat "$SANDBOX/sleep.pid" 2>/dev/null)"
OURS="$spid $slp $DECOY"
assert_eq "${spid:+y}${slp:+y}" "yy" "timeout: the stub wrote its pid and its sleep's"
# hint.sh has returned; its stub and the stub's sleep are gone within 5 s (polled)
if [ -n "$spid" ] && ! poll 50 gone "$spid"; then fail "timeout: the stub (pid $spid) is still running"; kill "$spid" 2>/dev/null; else pass; fi
if [ -n "$slp" ] && ! poll 50 gone "$slp"; then fail "timeout: the stub's sleep (pid $slp) is still running"; kill "$slp" 2>/dev/null; else pass; fi
decoy_kept timeout   # the others are gone or were killed above
# a bad limit value does not break the hook
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_HINT_TIMEOUT=abc
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "COREMODEL_HINT_TIMEOUT=abc: no hint (a bad value should mean the default)" ;; esac

# the prompt reaches codex unchanged: quotes, $(...), backticks, newlines, Cyrillic, backslashes
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
P='say "hi" and '"'"'bye'"'"' $(touch '"$SANDBOX"'/pwned) `touch '"$SANDBOX"'/pwned2` ${HOME} $HOME \n literal
вторая строка: почини авторизацию, "ёжик" \\ end *'
esc="$(printf '%s' "$P" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {print}')"
run_hint "$PATHSTUB" "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$esc\"}"
assert_eq "$RC" "0" "odd prompt: exit 0"
assert_no_file "$SANDBOX/pwned"; assert_no_file "$SANDBOX/pwned2"
if [ -f "$ARGV" ]; then
  tr '\0' '\n' < "$ARGV" > "$SANDBOX/argv.txt"; cat "$SANDBOX/argv.txt" "$STDIN" > "$SANDBOX/sent.txt"
  sent="$(cat "$SANDBOX/sent.txt")"
  case "$sent" in *"$P"*) pass ;; *) fail "odd prompt: the text did not reach codex unchanged" ;; esac
else fail "odd prompt: codex was not called"; fi
case "$(cat "$SANDBOX/out")" in *почини*|*pwned*|*literal*) fail "odd prompt: printed back" ;; *) pass ;; esac
# a very long prompt still gets an answer and does not break the call
long="$(awk 'BEGIN{for(i=0;i<20000;i++) printf "word%d ", i}')"
run_hint "$PATHSTUB" "$(event "$long")"
assert_eq "$RC" "0" "long prompt: exit 0"
assert_eq "$(ncalls)" "1" "long prompt: one call"
# over 4000 bytes it is cut as classifier.ts cutMiddle does: the first 2000 bytes, the marker, the last 2000
H="A$(reps 1999 h)"; TL="$(reps 1999 t)Z"
run_hint "$PATHSTUB" "$(event "${H}X$(reps 5000 m)Y${TL}")"
sent="$(cat "$STDIN" 2>/dev/null)"
case "$sent" in *"<prompt>
$H
[…]
$TL
</prompt>"*) pass ;; *) fail "a long prompt is not sent as its first 2000 bytes, [...] and its last 2000" ;; esac
# 4001 bytes is the shortest prompt that is cut; 4000 bytes go whole, with no marker
run_hint "$PATHSTUB" "$(event "${H}X${TL}")"
assert_contains "$STDIN" '[…]'
run_hint "$PATHSTUB" "$(event "${H}${TL}")"
assert_not_contains "$STDIN" '[…]'
assert_contains "$STDIN" "${H}${TL}"
# nothing on stdout other than the one object, in every case above the prompt text stays out
# (stderr is free)

# ---- pass 2: stdin, ephemeral, big prompt, SIGTERM, clamp ----
echo "  -- C4. stdin, big prompt, signals"
answer '{"why":"x","keep":false,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
tr '\0' '\n' < "$ARGV" > "$SANDBOX/argv.txt"
assert_contains "$SANDBOX/argv.txt" '--ephemeral'
assert_contains "$SANDBOX/argv.txt" '--ignore-user-config'
# the project's AGENTS.md does not ride along with the classifier prompt
assert_contains "$SANDBOX/argv.txt" 'project_doc_max_bytes=0'
# a change the user can see is in the release notes
assert_contains "$CM/CHANGELOG.md" 'project_doc_max_bytes=0'
assert_contains "$SANDBOX/argv.txt" 'model_reasoning_effort="low"'
assert_not_contains "$SANDBOX/argv.txt" 'fix the flaky login test'
assert_contains "$STDIN" 'fix the flaky login test'
assert_eq "$(tail -1 "$SANDBOX/argv.txt")" "-" "prompt read from stdin (last argument -)"
# a 1 MB prompt with many \n escapes
hook_event codex UserPromptSubmit /tmp rawprompt="$(awk 'BEGIN { for (i = 0; i < 100000; i++) printf "line%d\\n", i }')" > "$SANDBOX/big.json"
rm -f "$CALLS"; cpu_run env PATH="$PATHSTUB" COREMODEL_CONFIG="$ON_SF" /bin/bash "$HINT" < "$SANDBOX/big.json" > "$SANDBOX/out" 2>/dev/null; RC=$?
assert_eq "$RC" "0" "1 MB prompt: exit 0"
# CPU time (cpu_run, tests/lib.sh), which load on the machine does not raise
if [ "$CPU_MS" -lt 5000 ]; then pass; else fail "1 MB prompt took $CPU_MS ms of CPU"; fi
assert_eq "$(ncalls)" "0" "1 MB prompt: cut at 256 KB, so it ends unterminated and gets no call"
# SIGTERM to hint.sh while the stub sleeps: nothing is left running. hint.sh is this shell's child ($! is its
# pid: env execs bash); it is stopped once the stub has started its sleep (polled, up to 10 s).
rm -f "$SANDBOX/pid" "$SANDBOX/sleep.pid"
event 'fix the flaky login test' > "$SANDBOX/ev.json"
env PATH="$PATHSTUB" COREMODEL_CONFIG="$ON_SF" STUB_MODE=sleep /bin/bash "$HINT" < "$SANDBOX/ev.json" > /dev/null 2>&1 &
hp=$!; OURS="$hp"
poll 100 test -s "$SANDBOX/sleep.pid" && pass || fail "SIGTERM: the stub did not start its sleep in 10 s"
spid="$(cat "$SANDBOX/pid" 2>/dev/null)"; slp="$(cat "$SANDBOX/sleep.pid" 2>/dev/null)"
sleep 10.37 & DECOY=$!
OURS="$hp $spid $slp $DECOY"
kill -TERM "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
if [ -n "$spid" ] && ! poll 50 gone "$spid"; then fail "SIGTERM: the stub (pid $spid) is still running"; kill "$spid" 2>/dev/null; else pass; fi
if [ -n "$slp" ] && ! poll 50 gone "$slp"; then fail "SIGTERM: the stub's sleep (pid $slp) is still running"; kill "$slp" 2>/dev/null; else pass; fi
decoy_kept SIGTERM   # the others are gone or were killed above
# the limit is clamped to 20 s
if grep -qE 'to=20' "$HINT" && grep -q -- '-gt 20' "$HINT"; then pass; else fail "COREMODEL_HINT_TIMEOUT is not clamped to 20"; fi

# ---- C5. confirm: block the prompt once, the person switches, the same prompt goes through ----
# Codex hooks have no field that switches the model or asks a question (checked on codex 0.166.0 and 0.167.0-alpha.3.2:
# the UserPromptSubmit output schema holds continue, decision "block", reason, stopReason, suppressOutput, systemMessage,
# hookSpecificOutput.additionalContext). So "confirm" is: block once with a reason, remember the prompt, let the same
# prompt through when it comes again. Off until `codex_confirm: on` (and the hint itself is on). A block that cannot be
# remembered would trap the person: then it falls back to the plain hint.
echo "  -- C5. confirm"
CONF_SF="$SANDBOX/coremodel-confirm"; printf 'codex_hint: on\ncodex_confirm: on\n' > "$CONF_SF"
CONF_ONLY_SF="$SANDBOX/coremodel-confirm-only"; printf 'codex_confirm: on\n' > "$CONF_ONLY_SF"
MARKS="$STATE/coremodel/codex-offered"
# cevent <session> <prompt> [model] — a prompt in that session, from the current model (default gpt-6.1-sol)
cevent() { printf '{"session_id":"%s","turn_id":"t","cwd":"/tmp","hook_event_name":"UserPromptSubmit","model":"%s","permission_mode":"default","transcript_path":null,"prompt":"%s"}' "$1" "${3:-gpt-6.1-sol}" "$(json_esc "$2")"; }
blocked() { # blocked <label> <model> <effort> — one-line block object that names the pick, and nothing else on stdout
  local o; o="$(cat "$SANDBOX/out")"
  assert_eq "$RC" "0" "$1: exit 0"
  case "$o" in
    '{"decision":"block","reason":"coremodel: this prompt needs '"$2"' at '"$3"' effort'*'"}') pass ;;
    *) fail "$1: stdout is not the block object for $2/$3: $o" ;;
  esac
  assert_eq "$(printf '%s' "$o" | wc -l | tr -d ' ')" "0" "$1: stdout is one line"
  json_ok "$SANDBOX/out" && pass || fail "$1: stdout is not valid JSON"
  case "$o" in *'/model'*) pass ;; *) fail "$1: the reason does not say how to switch (/model)" ;; esac
  case "$o" in *'send'*'again'*) pass ;; *) fail "$1: the reason does not say to send the prompt again" ;; esac
  assert_not_contains "$SANDBOX/out" 'hookSpecificOutput'   # a block carries no additionalContext: the prompt does not run
  assert_not_contains "$SANDBOX/out" 'fix the flaky login test'   # the prompt is not printed back
}
plain_hint() { # plain_hint <label> — the old output: additionalContext, never a block
  assert_eq "$RC" "0" "$1: exit 0"
  assert_contains "$SANDBOX/out" '"hookSpecificOutput"'
  assert_not_contains "$SANDBOX/out" '"decision"'
}
answer '{"why":"flaky test, cause unknown","keep":false,"model":"gpt-6-astra","effort":"high"}'

# off by default: with codex_hint alone the output is the plain hint (the main check above), never a block
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test')"
plain_hint "confirm off"
# the confirm key alone does nothing: the hint (the classifier) is off
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_ONLY_SF"
silent "confirm without codex_hint"; assert_eq "$(ncalls)" "0" "confirm without codex_hint: Luna not called"
assert_no_file "$MARKS/c1"

# first send: blocked, and the prompt is remembered (as a hash, in a private file)
rm -rf "$STATE"
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
blocked "first send" gpt-6-astra high
assert_eq "$(ncalls)" "1" "first send: Luna asked once"
assert_file "$MARKS/c1"
assert_not_contains "$MARKS/c1" 'fix the flaky login test'
case "$(ls -ld "$MARKS" | cut -c1-10)" in drwx------) pass ;; *) fail "the offered folder is not private: $(ls -ld "$MARKS")" ;; esac
case "$(ls -l "$MARKS/c1" | cut -c1-10)" in -rw-------) pass ;; *) fail "the offered mark is not private: $(ls -l "$MARKS/c1")" ;; esac

# the same prompt again, same session: it goes through, with no classifier call and no output; the mark is used once
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
silent "resend"; assert_eq "$(ncalls)" "0" "resend: Luna not called"
assert_no_file "$MARKS/c1"
# a third time is a new offer
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
blocked "third send" gpt-6-astra high
assert_eq "$(ncalls)" "1" "third send: Luna asked again"

# a different prompt after an offer is judged on its own (and offered again), not waved through
run_hint "$PATHSTUB" "$(cevent c1 'fix the flaky login test, then the signup test')" COREMODEL_CONFIG="$CONF_SF"
blocked "other prompt" gpt-6-astra high
assert_eq "$(ncalls)" "1" "other prompt: Luna asked"
# another session's offer does not let this prompt through
run_hint "$PATHSTUB" "$(cevent c2 'fix the flaky login test, then the signup test')" COREMODEL_CONFIG="$CONF_SF"
blocked "other session" gpt-6-astra high
assert_eq "$(ncalls)" "1" "other session: Luna asked"
assert_file "$MARKS/c1"; assert_file "$MARKS/c2"

# The middle of a long prompt can change even when its classifier excerpt stays the same.
long_edge="$(reps 2100 a)"
for middle in first second; do
  run_hint "$PATHSTUB" "$(cevent long "$long_edge $middle $long_edge")" COREMODEL_CONFIG="$CONF_SF"
  blocked "long prompt with $middle middle" gpt-6-astra high
done

# a stale offer is ignored: the prompt is judged and offered again
run_hint "$PATHSTUB" "$(cevent c3 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
blocked "stale: offer" gpt-6-astra high
touch -t 200001010000 "$MARKS/c3"
run_hint "$PATHSTUB" "$(cevent c3 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
blocked "stale: after the limit" gpt-6-astra high
assert_eq "$(ncalls)" "1" "stale: Luna asked again"

# A known matching pair passes. Older clients omit effort, so a single confirmation lets the person check it.
pair_event() { printf '%s' "$(cevent c4 'test the queue' gpt-6-astra)" | sed "s/^{/{\"reasoning_effort\":\"$1\",/"; }
run_hint "$PATHSTUB" "$(pair_event high)" COREMODEL_CONFIG="$CONF_SF"
silent "matching model and effort"
run_hint "$PATHSTUB" "$(pair_event low)" COREMODEL_CONFIG="$CONF_SF"
blocked "different effort on the same model" gpt-6-astra high
run_hint "$PATHSTUB" "$(cevent c7 'test the queue' gpt-6-astra)" COREMODEL_CONFIG="$CONF_SF"
blocked "unknown effort on highest model" gpt-6-astra high
assert_contains "$SANDBOX/out" 'does not report the current effort'
answer '{"keep":false,"model":"gpt-6-luna","effort":"low"}'
run_hint "$PATHSTUB" "$(cevent c8 'rename the variable')" COREMODEL_CONFIG="$CONF_SF"
blocked "different lighter model" gpt-6-luna low
# keep: nothing to say and nothing remembered
answer '{"why":"picks an offered option","keep":true,"model":"gpt-6-astra","effort":"high"}'
run_hint "$PATHSTUB" "$(cevent c4 'option 2')" COREMODEL_CONFIG="$CONF_SF"
silent "keep"; assert_no_file "$MARKS/c4"
answer '{"why":"flaky test, cause unknown","keep":false,"model":"gpt-6-astra","effort":"high"}'

# a legitimate prompt always passes: a whole approval is never blocked (no call, no mark), nested calls stay silent
run_hint "$PATHSTUB" "$(cevent c4 'да, давай')" COREMODEL_CONFIG="$CONF_SF"
silent "approval"; assert_eq "$(ncalls)" "0" "approval: Luna not called"; assert_no_file "$MARKS/c4"
run_hint "$PATHSTUB" "$(cevent c4 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF" COREMODEL_NESTED=1
silent "nested"; assert_eq "$(ncalls)" "0" "nested: Luna not called"; assert_no_file "$MARKS/c4"

# the classifier fails or says nothing: the prompt goes through, nothing is remembered
for mode in fail empty partial; do
  run_hint "$PATHSTUB" "$(cevent c5 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF" STUB_MODE=$mode
  silent "classifier $mode"; assert_no_file "$MARKS/c5"
done

# a block that cannot be remembered would trap the person (the resend would be blocked again): fall back to the plain hint
# - the state folder cannot be made
: > "$SANDBOX/not-a-folder"
run_hint "$PATHSTUB" "$(cevent c6 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF" XDG_STATE_HOME="$SANDBOX/not-a-folder"
plain_hint "state folder unusable"
# - the event has no usable session id
run_hint "$PATHSTUB" "$(hook_event codex UserPromptSubmit /tmp prompt='fix the flaky login test' | sed 's/"session_id":"[^"]*",\{0,1\}//')" COREMODEL_CONFIG="$CONF_SF"
plain_hint "no session id"
run_hint "$PATHSTUB" "$(cevent '../up' 'fix the flaky login test')" COREMODEL_CONFIG="$CONF_SF"
plain_hint "unsafe session id"
assert_no_file "$STATE/coremodel/up"

# ---- D. hint.sh is a bash script (tests/test_portability.sh scans it) ----
echo "  -- D. hint.sh is a bash script"
assert_file "$CM/codex/hint.sh"
if [ -f "$CM/codex/hint.sh" ]; then
  head -1 "$CM/codex/hint.sh" | grep -qE '^#!.*bash' && pass || fail "hint.sh starts with a bash shebang"
fi
finish
