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
new_sandbox
# Processes are found by the pids the stub writes, never by name: another suite running at the same time has
# stubs with the same command line. OURS holds the pids of a check in progress; they are stopped when the file exits
# (at_exit, before lib.sh removes the sandboxes).
OURS=""
# shellcheck disable=SC2086  # a list of pids
stop_ours() { [ -z "$OURS" ] || kill $OURS 2>/dev/null; OURS=""; }
at_exit stop_ours
# poll <tenths> <cmd...> — runs cmd every 0.1 s until it succeeds, at most <tenths> more times; 1 when it never did
poll() { local n="$1"; shift; while ! "$@"; do [ "$n" -gt 0 ] || return 1; n=$((n - 1)); sleep 0.1; done; }
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
assert_file "$HJSON"
if [ -f "$HJSON" ]; then
  json_ok "$HJSON" && pass || fail "$HJSON is not valid JSON"
  assert_eq "$(grep -c '"UserPromptSubmit"' "$HJSON")" "1" "one UserPromptSubmit entry"
  assert_eq "$(grep -c '"command"' "$HJSON")" "1" "one hook command"
  assert_eq "$(grep -cE '"(PreToolUse|PostToolUse|SessionStart|Stop|PermissionRequest)"' "$HJSON")" "0" "no other event"
  assert_contains "$HJSON" 'bash \"${CLAUDE_PLUGIN_ROOT}/codex/hint.sh\"'
  # Codex shows this while the hook runs, instead of a silent wait
  assert_contains "$HJSON" '"statusMessage": "coremodel: choosing a model"'
  t="$(sed -n 's/.*"timeout": *\([0-9][0-9]*\).*/\1/p' "$HJSON" | head -1)"
  if [ -n "$t" ] && [ "$t" -ge 1 ] && [ "$t" -le 30 ]; then pass; else fail "explicit timeout 1..30 s in hooks.json (got '${t:-none}')"; fi
  # the hook's own wait (default 20 s) fits inside the hook timeout
  if [ -n "$t" ] && [ "$t" -gt 20 ]; then pass; else fail "hook timeout ($t) must exceed hint.sh's own 20 s limit"; fi
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
  req="$SANDBOX/req.jsonl"
  printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"t","version":"1"}}}' '{"method":"initialized"}' \
    "{\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$SANDBOX/work\"]}}" > "$req"
  # stdin stays open until the answer to request 2 is written (polled, up to 10 s)
  answered() { grep -q '"id":2' "$SANDBOX/hooks-list.out" 2>/dev/null; }
  (cat "$req"; poll 100 answered) | codex --disable remote_plugin app-server --listen stdio:// > "$SANDBOX/hooks-list.out" 2> "$SANDBOX/hooks-list.err"
  grep '"id":2' "$SANDBOX/hooks-list.out" | sed 's/{"key":/\
&/g' | grep '^{"key":"coremodel@' > "$SANDBOX/hooks.lines"
  assert_eq "$(wc -l < "$SANDBOX/hooks.lines" | tr -d ' ')" "1" "Codex lists exactly one coremodel hook"
  assert_contains "$SANDBOX/hooks.lines" '"key":"coremodel@corekit:codex/hooks.json:user_prompt_submit:0:0"'
  assert_contains "$SANDBOX/hooks.lines" '"eventName":"userPromptSubmit"'
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
printf '%s\0' "$@" > "$STUB_DIR/argv"
cat > "$STUB_DIR/stdin"
echo "NESTED=${COREMODEL_NESTED:-}" > "$STUB_DIR/env"
echo $$ > "$STUB_DIR/pid"
case "${STUB_MODE:-ok}" in
  fail) echo "boom" >&2; exit 1 ;;
  empty) exit 0 ;;
  sleep) sleep 10.37 & echo $! > "$STUB_DIR/sleep.pid"; wait $!; exit 0 ;;
esac
# an answer file given as -o / --output-last-message is written too
prev=""; for a in "$@"; do
  case "$prev" in -o|--output-last-message) cat "$STUB_DIR/answer" > "$a" ;; esac
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
run_hint() {
  local p="$1" in="$2"; shift 2
  rm -f "$CALLS" "$ARGV" "$STDIN" "$ENVREC" "$SANDBOX/pid" "$SANDBOX/sleep.pid"
  { printf "%s" "$in"; } 2>/dev/null | env PATH="$p" COREMODEL_CONFIG="$ON_SF" "$@" /bin/bash "$HINT" > "$SANDBOX/out" 2> "$SANDBOX/err"; RC=$?
}
ncalls() { [ -f "$CALLS" ] && wc -l < "$CALLS" | tr -d ' ' || echo 0; }
# event <prompt> — the hook's stdin JSON for a prompt that needs no escaping
event() { printf '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp","prompt":"%s"}' "$1"; }
silent() { # silent <label> — exit 0, nothing on stdout
  assert_eq "$RC" "0" "$1: exit 0"
  assert_eq "$(cat "$SANDBOX/out")" "" "$1: no stdout"
}
answer() { printf '%s' "$1" > "$STUB_ANSWER"; }

# the classifier template, straight from the Claude module
TPL="$SANDBOX/template.txt"
sed -n '/^export const TEMPLATE = `/,/^\/\/ TEMPLATE-END/p' "$CM/hooks/classifier.ts" | sed '1s/^export const TEMPLATE = `//' | sed '$d' > "$TPL"
[ -s "$TPL" ] && pass || fail "could not extract the template from classifier.ts"
T_FIRST="$(head -1 "$TPL")"
T_LAST="$(tail -1 "$TPL" | sed 's/`$//')"

# main path: high, opus
answer '{"why":"flaky test, cause unknown","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
assert_eq "$RC" "0" "main: exit 0"
assert_eq "$(ncalls)" "1" "main: codex called once"
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
  assert_contains "$SANDBOX/sent.txt" 'First decide if it is keep.'
  assert_contains "$SANDBOX/sent.txt" 'fix the flaky login test'
  assert_not_contains "$SANDBOX/sent.txt" '{{PROMPT}}'
  assert_not_contains "$SANDBOX/sent.txt" '{{REPLY}}'
  assert_not_contains "$SANDBOX/sent.txt" '{{NOW}}'
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

# the map: model and effort
check_map() { # <level> <model word> <expected codex model> <other model names that must not appear>
  answer "{\"why\":\"x\",\"level\":\"$1\",\"model\":\"$2\"}"
  run_hint "$PATHSTUB" "$(event 'do the thing')"
  local o; o="$(cat "$SANDBOX/out")"
  assert_eq "$RC" "0" "map $1/$2: exit 0"
  case "$o" in *"$3"*) pass ;; *) fail "map $1/$2: context lacks $3: $o" ;; esac
  case "$o" in *"$1"*) pass ;; *) fail "map $1/$2: context lacks effort $1: $o" ;; esac
  case "$o" in */model*) pass ;; *) fail "map $1/$2: context lacks /model" ;; esac
  local m; for m in $4; do case "$o" in *"$m"*) fail "map $1/$2: context names $m too: $o" ;; *) pass ;; esac; done
}
check_map low haiku gpt-6-luna "gpt-6.1-sol gpt-6-astra"
check_map medium sonnet gpt-6.1-sol "gpt-6-luna gpt-6-astra"
check_map high opus gpt-6-astra "gpt-6-luna gpt-6.1-sol"
check_map xhigh fable gpt-6-astra "gpt-6-luna gpt-6.1-sol"
check_map max fable gpt-6-astra "gpt-6-luna gpt-6.1-sol"
check_map max opus gpt-6-astra "gpt-6-luna gpt-6.1-sol"
# the answer may come wrapped in prose or a fence, as the Claude parser also accepts
answer 'Sure! ```json
{"why":"x","level":"medium","model":"sonnet"}
```'
run_hint "$PATHSTUB" "$(event 'add a field')"
case "$(cat "$SANDBOX/out")" in *gpt-6.1-sol*) pass ;; *) fail "fenced answer is not read: $(cat "$SANDBOX/out")" ;; esac

# keep: nothing to add
answer '{"why":"approval","level":"keep","model":"sonnet"}'
run_hint "$PATHSTUB" "$(event 'yes')"
silent "keep"; assert_eq "$(ncalls)" "1" "keep: codex was asked"

# recursion guard
answer '{"why":"x","level":"high","model":"opus"}'
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
mevent() { printf '{"hook_event_name":"UserPromptSubmit","model":"%s","prompt":"%s"}' "$1" "$2"; }
answer '{"why":"x","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-astra 'fix the flaky login test')"
silent "on the strongest model"; assert_eq "$(ncalls)" "0" "on the strongest model: codex not called"
answer '{"why":"x","level":"medium","model":"sonnet"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'add a field')"
silent "current model is the pick"; assert_eq "$(ncalls)" "1" "current model is the pick: codex was asked"
answer '{"why":"x","level":"low","model":"haiku"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'rename x')"
silent "current model is stronger than the pick"
answer '{"why":"x","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(mevent gpt-6.1-sol 'fix the flaky login test')"
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "a weaker current model: no hint: $(cat "$SANDBOX/out")" ;; esac
answer '{"why":"x","level":"low","model":"haiku"}'
run_hint "$PATHSTUB" "$(mevent gpt-6-luna 'rename x')"
silent "luna for a haiku pick"
# a model it does not know, or a model key that is not the event's own: the hint as before
answer '{"why":"x","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(mevent some-other-model 'fix the flaky login test')"
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "unknown current model: no hint" ;; esac
run_hint "$PATHSTUB" '{"hook_event_name":"UserPromptSubmit","meta":{"model":"gpt-6-astra"},"prompt":"fix the flaky login test"}'
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "a nested model key was read as the current model" ;; esac

# failures are silent and never block the prompt
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" STUB_MODE=fail
silent "stub exits 1"; assert_eq "$(ncalls)" "1" "stub exits 1: it was called"
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" STUB_MODE=empty
silent "stub prints nothing"
for g in 'garbage, no json here' '{"level":"high"' '{"why":"x","level":"enormous","model":"opus"}' '{"why":"x","level":"high","model":"gpt-9"}' '[1,2,3]' ''; do
  answer "$g"
  run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
  silent "garbage answer '$g'"
done
answer '{"why":"x","level":"high","model":"opus"}'
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
answer '{"why":"x","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')" COREMODEL_HINT_TIMEOUT=abc
case "$(cat "$SANDBOX/out")" in *gpt-6-astra*) pass ;; *) fail "COREMODEL_HINT_TIMEOUT=abc: no hint (a bad value should mean the default)" ;; esac

# the prompt reaches codex unchanged: quotes, $(...), backticks, newlines, Cyrillic, backslashes
answer '{"why":"x","level":"high","model":"opus"}'
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
# nothing on stdout other than the one object, in every case above the prompt text stays out
# (stderr is free)

# ---- pass 2: stdin, ephemeral, big prompt, SIGTERM, clamp ----
echo "  -- C2. stdin, big prompt, signals"
answer '{"why":"x","level":"high","model":"opus"}'
run_hint "$PATHSTUB" "$(event 'fix the flaky login test')"
tr '\0' '\n' < "$ARGV" > "$SANDBOX/argv.txt"
assert_contains "$SANDBOX/argv.txt" '--ephemeral'
assert_contains "$SANDBOX/argv.txt" '--ignore-user-config'
assert_contains "$SANDBOX/argv.txt" 'model_reasoning_effort="low"'
assert_not_contains "$SANDBOX/argv.txt" 'fix the flaky login test'
assert_contains "$STDIN" 'fix the flaky login test'
assert_eq "$(tail -1 "$SANDBOX/argv.txt")" "-" "prompt read from stdin (last argument -)"
# a 1 MB prompt with many \n escapes
awk 'BEGIN{printf "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\""; for(i=0;i<100000;i++) printf "line%d\\n", i; printf "\"}"}' > "$SANDBOX/big.json"
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

# ---- D. portability scan covers the new script ----
echo "  -- D. portability"
assert_file "$CM/codex/hint.sh"
if [ -f "$CM/codex/hint.sh" ]; then
  head -1 "$CM/codex/hint.sh" | grep -qE '^#!.*bash' && pass || fail "hint.sh starts with a bash shebang"
  # test_portability.sh finds every .sh under plugins/ by find; its self-check lists the same way
  (cd "$ROOT" && find skills scripts hooks tests plugins -type f 2>/dev/null) | grep -qx 'plugins/coremodel/codex/hint.sh' && pass || fail "portability scan list misses hint.sh"
  grep -qE 'sed[[:space:]]+-i|mapfile|readarray|grep[[:space:]]+-P|declare[[:space:]]+-A|local[[:space:]]+-n|\$\{[A-Za-z_]+(,,|\^\^)|\|[&]|date[[:space:]]+-d|readlink[[:space:]]+-f|\bjq\b' "$CM/codex/hint.sh" && fail "hint.sh uses a non-portable construct or jq" || pass
fi
finish
