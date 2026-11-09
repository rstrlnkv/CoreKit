#!/usr/bin/env bash
# json_str (hook JSON without jq) and project_of (path -> project in the Core).
source "$(dirname "$0")/lib.sh"
new_sandbox
. "$SCRIPTS/lib.sh"

# --- json_str
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
start=$SECONDS
doc="{\"content\":\"$big\",\"cwd\":\"/after/big\"}"
assert_eq "$(json_str "$doc" cwd)" "/after/big" "key after a large value"
[ $((SECONDS - start)) -le 5 ] && pass || fail "json_str too slow on a large payload"

# Linear time: decoding a 600 KB value with many escapes and scanning past a 1 MB payload.
chunk='abc \"q\" \\ \u0430 \n padding padding'
exp_chunk="$(printf 'abc "q" \\ а \n padding padding')"
big="$chunk"; want="$exp_chunk"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do big="$big$big"; want="$want$want"; done
doc="{\"content\":\"$big\",\"cwd\":\"/after/600k\"}"
t0=$(date +%s); got="$(json_str "$doc" content)"; t1=$(date +%s)
[ "$got" = "$want" ] && pass || fail "decoded 600 KB value differs (${#got} bytes vs ${#want})"
echo "  timing: decode of $((${#big} / 1000)) KB value: $((t1 - t0)) s"
[ $((t1 - t0)) -le 2 ] && pass || fail "decode of a 600 KB value took $((t1 - t0)) s"
big="$big$big"; doc="{\"content\":\"$big\",\"x\":1,\"cwd\":\"/after/1m\"}"
t0=$(date +%s); got="$(json_str "$doc" cwd)"; t1=$(date +%s)
assert_eq "$got" "/after/1m" "key after a 1 MB value"
echo "  timing: scan past $((${#big} / 1000)) KB: $((t1 - t0)) s"
[ $((t1 - t0)) -le 2 ] && pass || fail "scan past 1 MB took $((t1 - t0)) s"
# many small tokens (a long pretty-printed document) are scanned in linear time too
many="$(awk 'BEGIN{printf "{\n"; for(i=0;i<40000;i++) printf "  \"k%d\": \"v%d\",\n", i, i; printf "  \"cwd\": \"/after/many\"\n}\n"}')"
t0=$(date +%s); got="$(json_str "$many" cwd)"; t1=$(date +%s)
assert_eq "$got" "/after/many" "key after 80000 tokens"
[ $((t1 - t0)) -le 2 ] && pass || fail "scan past 80000 tokens took $((t1 - t0)) s"
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
start=$SECONDS
doc="{\"content\":\"${bs}a\\\"b\",\"cwd\":\"/after/bs\"}"
assert_eq "$(json_str "$doc" cwd)" "/after/bs" "key after a long backslash run"
[ $((SECONDS - start)) -le 2 ] && pass || fail "json_str quadratic on a backslash run"
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
