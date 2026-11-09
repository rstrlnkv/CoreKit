#!/usr/bin/env bash
# json_str (hook JSON without jq) and project_of (path -> project in the Core).
source "$(dirname "$0")/lib.sh"
new_sandbox
. "$SCRIPTS/lib.sh"

# --- json_str
# Every document a json_str case below reads is kept (NUL-separated), so that json_fields is compared with json_str on all
# of them at the end of this section.
JCORPUS="$TEST_TMP/json-corpus"; : > "$JCORPUS"
eval "_json_str_lib() $(declare -f json_str | tail -n +2)"
json_str() { printf '%s\0' "${1:-}" >> "$JCORPUS"; _json_str_lib "$@"; }
assert_eq "$(json_str '{"cwd":"/a/b"}' cwd)" "/a/b" "plain value"
assert_eq "$(json_str '{"cwd":"/a/\"q\"/b"}' cwd)" '/a/"q"/b' "escaped quote"
assert_eq "$(json_str '{"cwd":"C:\\x\\y"}' cwd)" 'C:\x\y' "escaped backslash"
assert_eq "$(json_str '{"cwd":"\/a\/b"}' cwd)" "/a/b" "escaped slash"
assert_eq "$(json_str '{"cwd":"a\tb"}' cwd)" "$(printf 'a\tb')" "tab"
assert_eq "$(json_str '{"cwd":"a\nb"}' cwd)" "$(printf 'a\nb')" "newline"
assert_eq "$(json_str '{"cwd":"\u0430\u0431"}' cwd)" "аб" "BMP escape (Cyrillic)"
assert_eq "$(json_str '{"cwd":"\u00e9\u00C9"}' cwd)" "éÉ" "two-byte escape, hex case"
assert_eq "$(json_str '{"cwd":"\u20ac"}' cwd)" "€" "three-byte escape"
assert_eq "$(json_str '{"cwd":"\ud83d\ude00"}' cwd)" "😀" "surrogate pair"
assert_eq "$(json_str '{"cwd":"x\ud83dy"}' cwd)" "x�y" "lone surrogate becomes U+FFFD"
assert_eq "$(json_str '{"cwd":"/x/Ядро/проект"}' cwd)" "/x/Ядро/проект" "raw UTF-8 passes through"
assert_eq "$(json_str '{"cwd" : "/a b"}' cwd)" "/a b" "spaces around colon"
assert_eq "$(json_str "$(printf '{\n  "session_id": "s",\n  "cwd"\n  :\n  "/multi/line",\n  "x": 1\n}\n')" cwd)" "/multi/line" "several lines"
assert_eq "$(json_str "$(printf '{\r\n\t"cwd":\t"/crlf"\r\n}')" cwd)" "/crlf" "tabs and CRLF"
assert_eq "$(json_str '{"session_id":"s"}' cwd)" "" "missing key"
assert_eq "$(json_str '{"cwd":5}' cwd)" "" "number value"
assert_eq "$(json_str '{"cwd":null}' cwd)" "" "null value"
assert_eq "$(json_str '{"cwd":true}' cwd)" "" "boolean value"
assert_eq "$(json_str '{"cwd":{"a":"b"}}' cwd)" "" "object value"
assert_eq "$(json_str '{"cwd":""}' cwd)" "" "empty string"
assert_eq "$(json_str '{"cwdx":"no","xcwd":"no","cwd":"yes"}' cwd)" "yes" "whole key only"
assert_eq "$(json_str '{"a":"first","cwd":"one","cwd":"two"}' cwd)" "one" "first value wins"
assert_eq "$(json_str '{"tool_input":{"cwd":"/nested"}}' cwd)" "/nested" "nested key found"
assert_eq "$(json_str '{"note":"say \"cwd\": \"/fake\"","cwd":"/real"}' cwd)" "/real" "key text inside a value is not a key"
assert_eq "$(json_str '{"a":"cwd","b":"/x"}' cwd)" "" "key name as a value"
assert_eq "$(json_str '{"cwd":"/a\qb"}' cwd)" "/aqb" "unknown escape keeps the character"
assert_eq "$(json_str '{"cwd":"/a\u12"}' cwd)" "/a" "short \\u escape dropped"
assert_eq "$(json_str '{"cwd":"/a\uZZZZb"}' cwd)" "/ab" "non-hex \\u escape dropped"
assert_eq "$(json_str '{"cwd":"a\u0000b"}' cwd)" "ab" "NUL dropped"
# malformed input: nothing printed, exit 0, no crash
for bad in '' 'garbage' '{' '{"cwd"' '{"cwd":' '{"cwd":"unterminated' '{"cwd":"ends with backslash\' '"' '\' '{"cwd":"x"' '[1,2' ; do
  OUT="$(json_str "$bad" cwd 2>&1)"; rc=$?
  [ "$rc" = 0 ] && pass || fail "json_str exit $rc on: $bad"
  case "$bad" in '{"cwd":"x"') assert_eq "$OUT" "x" "unclosed object still yields the value" ;;
    *) assert_eq "$OUT" "" "malformed input prints nothing: $bad" ;; esac
done
json_str '{"cwd":"x"}' >/dev/null 2>&1; assert_eq "$?" "0" "no key argument"
# a large payload (a Write of a big file) with escapes is scanned quickly
big="$(awk 'BEGIN{for(i=0;i<3000;i++) printf "line %d with \\\"quotes\\\" and \\n escapes padding padding\\n", i}')"
doc="{\"content\":\"$big\",\"cwd\":\"/after/big\"}"
cpu_run json_str "$doc" cwd > "$TEST_TMP/got"
assert_eq "$(<"$TEST_TMP/got")" "/after/big" "key after a large value"
[ "$CPU_MS" -le 5000 ] && pass || fail "json_str too slow on a large payload: $CPU_MS ms of CPU"

# Linear time: decoding a 600 KB value with many escapes and scanning past a 1 MB payload. The limits are on CPU time
# (cpu_run, tests/lib.sh), which load on the machine does not raise.
chunk='abc \"q\" \\ \u0430 \n padding padding'
exp_chunk="$(printf 'abc "q" \\ а \n padding padding')"
big="$chunk"; want="$exp_chunk"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do big="$big$big"; want="$want$want"; done
doc="{\"content\":\"$big\",\"cwd\":\"/after/600k\"}"
cpu_run json_str "$doc" content > "$TEST_TMP/got"; got="$(<"$TEST_TMP/got")"
[ "$got" = "$want" ] && pass || fail "decoded 600 KB value differs (${#got} bytes vs ${#want})"
echo "  timing: decode of $((${#big} / 1000)) KB value: $CPU_MS ms of CPU"
[ "$CPU_MS" -le 2000 ] && pass || fail "decode of a 600 KB value took $CPU_MS ms of CPU"
big="$big$big"; doc="{\"content\":\"$big\",\"x\":1,\"cwd\":\"/after/1m\"}"
cpu_run json_str "$doc" cwd > "$TEST_TMP/got"; got="$(<"$TEST_TMP/got")"
assert_eq "$got" "/after/1m" "key after a 1 MB value"
echo "  timing: scan past $((${#big} / 1000)) KB: $CPU_MS ms of CPU"
[ "$CPU_MS" -le 2000 ] && pass || fail "scan past 1 MB took $CPU_MS ms of CPU"
# many small tokens (a long pretty-printed document) are scanned in linear time too
many="$(awk 'BEGIN{printf "{\n"; for(i=0;i<40000;i++) printf "  \"k%d\": \"v%d\",\n", i, i; printf "  \"cwd\": \"/after/many\"\n}\n"}')"
cpu_run json_str "$many" cwd > "$TEST_TMP/got"; got="$(<"$TEST_TMP/got")"
assert_eq "$got" "/after/many" "key after 80000 tokens"
[ "$CPU_MS" -le 2000 ] && pass || fail "scan past 80000 tokens took $CPU_MS ms of CPU"
# growth: decoding four times the value costs about four times the CPU (a quadratic decoder would cost 16 times)
big="$chunk"; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13; do big="$big$big"; done   # about 300 KB
# shellcheck disable=SC2034  # read by the command lines assert_linear evals
J1="{\"content\":\"$big\",\"cwd\":\"/x\"}"
# shellcheck disable=SC2034  # (as above)
J4="{\"content\":\"$big$big$big$big\",\"cwd\":\"/x\"}"
assert_linear "json_str: a 300 KB value against a 1.2 MB one" 6 'json_str "$J1" content > /dev/null' 'json_str "$J4" content > /dev/null'
# adversarial: a value that is all escaped quotes / all escaped backslashes
adv="$(awk 'BEGIN{for(i=0;i<50000;i++) printf "%s", "\\" "\""}')"
doc="{\"a\":\"$adv\",\"cwd\":\"/ok\"}"
assert_eq "$(json_str "$doc" cwd)" "/ok" "scan past escaped quotes"
adv="$(awk 'BEGIN{for(i=0;i<50000;i++) printf "%s", "\\\\"}')"
doc="{\"a\":\"$adv\",\"cwd\":\"/ok2\"}"
assert_eq "$(json_str "$doc" cwd)" "/ok2" "scan past escaped backslashes"
assert_eq "$(json_str '{"a":"x\"y\\","cwd":"/ok3"}' cwd)" "/ok3" "quote parity"
assert_eq "$(json_str '{"a":"x\\\"y","cwd":"/ok4"}' cwd)" "/ok4" "quote parity, odd run"
assert_eq "$(json_str '{"a":"x\\\"y\\\\"}' a)" 'x\"y\\' "decode: escaped backslash then escaped quote"

# --- json_fields: one pass, the value json_str gives for each key, in the order of the keys, NUL-terminated, trailing
# newlines dropped as $(...) drops them. Compared with json_str on every document above, plus hook inputs of both hosts.
eval "json_str() $(declare -f _json_str_lib | tail -n +2)"
nl='
'
for d in '{"session_id":"s","transcript_path":"/t.jsonl","cwd":"/p","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"},"tool_use_id":"toolu_1"}' \
  '{"session_id":"s","turn_id":"turn-1","transcript_path":null,"cwd":"/p","hook_event_name":"PreToolUse","model":"gpt-5","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: docs/a.md\n+x\n*** End Patch\n"},"tool_use_id":"call_1"}' \
  '{"cwd":"/p","agent_type":"corecrew:verifier","tool_name":"Bash","tool_input":{"command":"cat <<EOF\nx\n\nEOF\n\n\n"}}' \
  '{"cwd":"/p","tool_name":"Write","tool_input":{"file_path":"/p/src/x.py","content":"\"cwd\": \"/fake\"\n"}}' \
  '{"cwd":5,"tool_name":"Read","tool_input":{"file_path":null,"cwd":"/later","file_path":"/p/.env"}}' \
  "{\"cwd\":\"/p\",${nl}\"tool_name\" :${nl} \"Glob\",\"tool_input\":{\"pattern\":\"**/.env\",\"path\":\"~\"}}" \
  '{"tool_name":"Bash","tool_input":{"command":"\n\n"},"cwd":"\u000a/p\u000a"}' '{"command":"a\\nb\\"}' '{"command":"x\"' '{"a":"b"'; do
  printf '%s\0' "$d" >> "$JCORPUS"
done
keys="cwd tool_name command file_path path turn_id agent_type a b content"
n=0; diffs=""
while IFS= read -r -d '' doc; do
  n=$((n + 1))
  # shellcheck disable=SC2086  # the keys are words
  { for k in $keys cwd; do IFS= read -r -d '' "jf_$k"; done; } < <(json_fields "$doc" $keys cwd)
  ks="$keys"; [ "${#doc}" -le 65536 ] || ks="cwd content command"   # a large document: the keys it has (time)
  for k in $ks; do
    v="jf_$k"; [ "${!v}" = "$(json_str "$doc" "$k")" ] || diffs="$diffs doc$n:$k"
  done
done < "$JCORPUS"
[ "$n" -ge 60 ] && pass || fail "json_fields corpus has only $n documents"
assert_eq "$diffs" "" "json_fields differs from json_str ($n documents)"
assert_eq "$(json_fields '{"a":"x"}' a b c | tr -cd '\000' | wc -c | tr -d ' ')" "3" "one NUL per key"
assert_eq "$(json_fields 'garbage' a b | tr -cd '\000' | wc -c | tr -d ' ')" "2" "one NUL per key, malformed input"
assert_eq "$(json_fields '{"a":"x\n\n"}' a | od -An -c | tr -d ' \n')" 'x\0' "trailing newlines dropped"
assert_eq "$(json_fields '{"a":"x\n\ny"}' a | od -An -c | tr -d ' \n')" 'x\n\ny\0' "inner newlines kept"
json_fields '{"a":"x"}' >/dev/null 2>&1; assert_eq "$?" "0" "no key argument"
# one pass: a 1 MB command is read once for all the keys, in linear time
# shellcheck disable=SC2034  # read by the command lines assert_linear evals
F1="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$big\"},\"cwd\":\"/x\"}"
# shellcheck disable=SC2034  # (as above)
F4="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$big$big$big$big\"},\"cwd\":\"/x\"}"
assert_linear "json_fields: a 300 KB command against a 1.2 MB one" 6 'json_fields "$F1" tool_name cwd command turn_id > /dev/null' 'json_fields "$F4" tool_name cwd command turn_id > /dev/null'

# --- project_of
unset CORE_DIR
mkdir -p "$SANDBOX/real/My Проекты/Ядро"
export CORE_DIR="$SANDBOX/real/My Проекты/Ядро/"   # trailing slash
load_settings
assert_eq "$CORE_DIR" "$SANDBOX/real/My Проекты/Ядро" "CORE_DIR canonical"
mkdir -p "$CORE_DIR/p1/code/.claude/worktrees/w1/src" "$CORE_DIR/p1/docs" "$CORE_DIR/p2/code" "$CORE_DIR/standards" \
  "$CORE_DIR/knowledge" "$CORE_DIR/.git" "$CORE_DIR/misc/sub" "$CORE_DIR/bin" "$CORE_DIR/пр оект"
echo "# p1" > "$CORE_DIR/p1/CLAUDE.md"; echo "# n" > "$CORE_DIR/пр оект/CLAUDE.md"
assert_eq "$(project_of "$CORE_DIR/p1")" "p1" "project root"
assert_eq "$(project_of "$CORE_DIR/p1/")" "p1" "trailing slash"
assert_eq "$(project_of "$CORE_DIR/p1/code")" "p1" "code folder"
assert_eq "$(project_of "$CORE_DIR/p1/docs/INDEX.md")" "p1" "file that does not exist yet"
assert_eq "$(project_of "$CORE_DIR/p1/code/.claude/worktrees/w1")" "p1" "worktree"
assert_eq "$(project_of "$CORE_DIR/p1/code/.claude/worktrees/w1/src")" "p1" "inside a worktree"
assert_eq "$(project_of "$CORE_DIR/p1/code/.claude/worktrees/w1/src/../../w1")" "p1" "dot-dot resolved"
assert_eq "$(project_of "$CORE_DIR/p2/code")" "p2" "project with code/ only"
assert_eq "$(project_of "$CORE_DIR/пр оект/x")" "пр оект" "project name with a space and Cyrillic"
assert_eq "$(project_of "$CORE_DIR/p1/../p2/code")" "p2" "dot-dot between projects"
for np in "$CORE_DIR" "$CORE_DIR/" "$CORE_DIR/standards" "$CORE_DIR/standards/x.md" "$CORE_DIR/knowledge" \
          "$CORE_DIR/.git" "$CORE_DIR/.git/hooks" "$CORE_DIR/misc" "$CORE_DIR/misc/sub" "$CORE_DIR/bin" \
          "$CORE_DIR/PROJECTS.md" "$CORE_DIR/nothing-here" "$CORE_DIR-other/p1" "${CORE_DIR}x/p1" \
          "$SANDBOX" "$SANDBOX/real" "/" "/tmp" ""; do
  OUT="$(project_of "$np")"; rc=$?
  [ "$rc" = 1 ] && pass || fail "project_of '$np': exit $rc, expected 1"
  assert_eq "$OUT" "" "project_of '$np' printed"
done
# core_dir given through a symlink and with ~
ln -s "$SANDBOX/real/My Проекты" "$SANDBOX/link"
export CORE_DIR="$SANDBOX/link/Ядро"; load_settings
assert_eq "$CORE_DIR" "$SANDBOX/real/My Проекты/Ядро" "symlinked CORE_DIR resolved"
assert_eq "$(project_of "$SANDBOX/link/Ядро/p1/code")" "p1" "path through the symlink"
assert_eq "$(project_of "$SANDBOX/real/My Проекты/Ядро/p1/code")" "p1" "path through the real folder"
ln -s "$SANDBOX/real/My Проекты/Ядро/p1/code" "$SANDBOX/codelink"
assert_eq "$(project_of "$SANDBOX/codelink")" "p1" "symlink to a project folder"
ln -s "$SANDBOX/real/My Проекты/Ядро/standards" "$SANDBOX/stdlink"
project_of "$SANDBOX/stdlink" >/dev/null; assert_eq "$?" "1" "symlink to standards"
ln -s "$SANDBOX/real/My Проекты/Ядро" "$HOME/Core"
export CORE_DIR="~/Core"; load_settings
assert_eq "$CORE_DIR" "$SANDBOX/real/My Проекты/Ядро" "~ CORE_DIR resolved"
assert_eq "$(project_of "~/Core/p2/code")" "p2" "path with ~"

# --- letter case: the spelling on disk wins (macOS volumes are case-insensitive, `cd -P` keeps what was typed)
mkdir -p "$SANDBOX/cs/a"
if [ -d "$SANDBOX/cs/A" ]; then
  mkdir -p "$SANDBOX/CaseCore/Ядро/MyApp/code"; echo "# app" > "$SANDBOX/CaseCore/Ядро/MyApp/CLAUDE.md"
  export CORE_DIR="$SANDBOX/casecore/ядро"; load_settings
  assert_eq "$CORE_DIR" "$SANDBOX/CaseCore/Ядро" "CORE_DIR takes the case on disk"
  assert_eq "$(canon_dir "$SANDBOX/CASECORE/ядро/myapp/new/file")" "$SANDBOX/CaseCore/Ядро/MyApp/new/file" "canon_dir: existing part on-disk case, missing part as typed"
  assert_eq "$(project_of "$SANDBOX/CaseCore/Ядро/MyApp/code")" "MyApp" "cwd as on disk"
  assert_eq "$(project_of "$SANDBOX/CASECORE/ЯДРО/myapp/code")" "MyApp" "cwd in other case"
else
  skip "letter case" "case-sensitive volume"; pass
fi
# a long run of escaped backslashes is scanned in linear time
bs="$(awk 'BEGIN{for(i=0;i<50000;i++) printf "\\\\"}')"
doc="{\"content\":\"${bs}a\\\"b\",\"cwd\":\"/after/bs\"}"
cpu_run json_str "$doc" cwd > "$TEST_TMP/got"
assert_eq "$(<"$TEST_TMP/got")" "/after/bs" "key after a long backslash run"
[ "$CPU_MS" -le 2000 ] && pass || fail "json_str quadratic on a backslash run: $CPU_MS ms of CPU"
# a raw newline in a value (invalid JSON) survives and does not start an escape
assert_eq "$(json_str "$(printf '{"cwd":"a\nb"}')" cwd)" "$(printf 'a\nb')" "raw newline kept"

# --- json_str needs no awk file: with every scripts/*.awk gone (the guards' documented case: the Bash path fails open,
# file tools are still judged), json_str still reads hook JSON, and guard-code still refuses a Write of an internal file.
new_sandbox; PL="$SANDBOX/plugin-noawk"; mkdir -p "$PL/hooks" "$PL/scripts"
cp "$HOOKS/guard-code.sh" "$HOOKS/messages.sh" "$PL/hooks/"
for f in "$SCRIPTS"/*; do case "$f" in *.awk) ;; *) [ -f "$f" ] && cp "$f" "$PL/scripts/" ;; esac; done
find "$PL/scripts" -name '*.awk' | grep -q . && fail "the no-awk copy holds an awk file" || pass
# shellcheck disable=SC1091
assert_eq "$( (. "$PL/scripts/lib.sh"; json_str '{"cwd":"/a/а"}' cwd) )" "/a/а" "json_str without awk files"
N="$SANDBOX/Projects/Foo"; mkdir -p "$CORE_DIR/foo" "$N"; echo '# foo' > "$CORE_DIR/foo/CLAUDE.md"
ln -s "$CORE_DIR/foo/CLAUDE.md" "$N/CLAUDE.local.md"
printf '%s' '{"cwd":"'"$N"'","tool_name":"Write","tool_input":{"file_path":"'"$N"'/CLAUDE.md"}}' | bash "$PL/hooks/guard-code.sh" >/dev/null 2>&1
assert_eq "$?" "2" "no awk files: guard-code still judges a file tool"
finish
