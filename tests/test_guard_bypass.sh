#!/usr/bin/env bash
# Bypasses of hooks/guard-secrets.sh, hooks/guard-code.sh and hooks/one-suite.sh found in the 0.5.0 audit:
# quoting inside a secret name, globs, wrapper options (timeout 5, nice -n 5, sudo -u x), zip -x, HOME unset,
# a core_dir that is a symlink, a file directly under .claude/worktrees/, and << used as a shift.
# The tests only ever create FAKE files inside the sandbox.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; [ -z "${dummy:-}" ] || kill "$dummy" 2>/dev/null' EXIT
mkdir -p "$CORE_DIR/p/code/src" "$HOME/.ssh"
: > "$CORE_DIR/p/CLAUDE.md"
C="$CORE_DIR/p/code"
echo "FAKE=1" > "$C/.env"

jesc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }
bash_json() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" "$(jesc "$1")"; }
# sec <command> [cwd] — guard-secrets exit code in RC, stderr in ERR
sec() { bash_json "$1" "${2-$C}" | bash "$HOOKS/guard-secrets.sh" >/dev/null 2>"$SANDBOX/err"; RC=$?; ERR="$(<"$SANDBOX/err")"; }
code() { bash_json "$1" "${2-$C}" | bash "$HOOKS/guard-code.sh" >/dev/null 2>"$SANDBOX/err"; RC=$?; ERR="$(<"$SANDBOX/err")"; }
sec_blocked() { sec "$1"; assert_eq "$RC" "2" "secrets blocked: $1"; }
sec_ok() { sec "$1"; assert_eq "$RC" "0" "secrets pass: $1"; }

# 1. quotes and backslashes inside the name
sec_blocked "cat .e'n'v"
sec_blocked 'cat .e""nv'
sec_blocked 'cat .\env'
sec_blocked 'cat ~/.s""sh/id_rsa'
sec_blocked 'cat ".e"nv'
# 2. globs that can match a secret name
sec_blocked 'cat .e*'
sec_blocked 'cat .en?'
sec_blocked 'cat .[e]nv'
sec_blocked 'cat .{e,x}nv'
sec_blocked 'cat ~/.s*/id_rsa'
sec_blocked 'cat ~/.[s]sh/id_rsa'
sec_blocked 'head -n 3 .e*'
sec_ok 'cat *'
sec_ok 'cat .*'
sec_ok 'cat *.env'
sec_ok 'cat .e*.md'
sec_ok 'cat .git*'
sec_ok 'cat README.md'
sec_ok 'cat .env.example'
# 3. wrapper options take their values
sec_blocked 'timeout 5 cat .env'
sec_blocked 'timeout -s KILL 5 cat .env'
sec_blocked 'nice -n 5 cat .env'
sec_blocked 'sudo -u root cat .env'
sec_blocked 'env -u X cat .env'
sec_blocked 'stdbuf -o0 cat .env'
sec_blocked 'stdbuf -o 0 cat .env'
sec_blocked 'sudo nice -n 5 timeout 5 cat .env'
sec_blocked 'sudo -E -u root cat .env'
sec_ok 'timeout 5 cat README.md'
sec_ok 'nice -n 5 cat README.md'
# 4. zip -x takes patterns
sec_ok 'zip a.zip src -x .env'
sec_ok 'zip -r a.zip . -x .env .env.local'
sec_blocked 'zip a.zip .env'
# 5. HOME unset
printf '%s' "$(bash_json 'cat ~/.ssh/id_rsa' "$C")" | env -u HOME bash "$HOOKS/guard-secrets.sh" >/dev/null 2>"$SANDBOX/err"; RC=$?
assert_eq "$RC" "2" "HOME unset: ~/.ssh/id_rsa is blocked"

# guard-code: wrapper options
code 'timeout 5 tee docs/a'; assert_eq "$RC" "2" "timeout 5 tee docs/a"
code 'sudo -u x touch CLAUDE.md'; assert_eq "$RC" "2" "sudo -u x touch CLAUDE.md"
code 'nice -n 5 tee docs/a'; assert_eq "$RC" "2" "nice -n 5 tee docs/a"
code 'timeout 5 tee src/a'; assert_eq "$RC" "0" "timeout 5 tee src/a passes"
# 7. a file directly under .claude/worktrees
wt() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$C" "$1" | bash "$HOOKS/guard-code.sh" >/dev/null 2>&1; RC=$?; }
wt "$C/.claude/worktrees/notes.md"; assert_eq "$RC" "2" "file directly under .claude/worktrees is blocked"
mkdir -p "$C/.claude/worktrees/w"
wt "$C/.claude/worktrees/w"; assert_eq "$RC" "0" "an existing worktree dir passes"
wt "$C/.claude/worktrees/w/src/a.sh"; assert_eq "$RC" "0" "code inside a worktree passes"

# 6. core_dir that is a symlink
S2="$SANDBOX/sl"; mkdir -p "$S2/Projects/Proj" "$S2/elsewhere/Core/proj"
ln -s "$S2/elsewhere/Core" "$S2/Projects/Core"
: > "$S2/elsewhere/Core/proj/CLAUDE.md"; echo "F=1" > "$S2/Projects/Proj/.env"
( export CORE_DIR="$S2/Projects/Core"
  bash_json 'cat .env' "$S2/Projects/Proj" | bash "$HOOKS/guard-secrets.sh" >/dev/null 2>&1; RC=$?
  assert_eq "$RC" "2" "symlinked core_dir: guard-secrets sees the code folder"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$S2/Projects/Proj" "$S2/Projects/Proj/CLAUDE.md" | bash "$HOOKS/guard-code.sh" >/dev/null 2>&1; RC=$?
  assert_eq "$RC" "2" "symlinked core_dir: guard-code sees the code folder"
  echo "$PASSES $FAILS" > "$S2/count" )
read -r p f < "$S2/count"; PASSES=$((PASSES + p)); FAILS=$((FAILS + f))

# 9. a command line handed to another shell is judged too: bash -c, sh -c, zsh -c, eval
sec_blocked 'bash -c "cat .env"'
sec_blocked "sh -c 'cat .env'"
sec_blocked 'zsh -c "head -n 2 .env"'
sec_blocked 'bash -lc "cat .env"'
sec_blocked 'sudo bash -c "cat ~/.ssh/id_rsa"'
sec_blocked 'bash -c "echo hi; cat .env"'
sec_blocked 'eval "cat .env"'
sec_blocked 'eval cat .env'
sec_ok 'bash -c "echo hello"'
sec_ok 'bash -c "cat .env.example"'
sec_ok 'bash scripts/run.sh .env'
sec_ok 'bash -c "grep .env README.md"'
sec_ok 'eval "$(ssh-agent -s)"'
code 'bash -c "echo hi > CLAUDE.md"'; assert_eq "$RC" "2" "bash -c writes CLAUDE.md"
code "sh -c 'touch docs/a.md'"; assert_eq "$RC" "2" "sh -c touches docs/a.md"
code 'eval "tee AGENTS.md"'; assert_eq "$RC" "2" "eval tee AGENTS.md"
code 'bash -c "echo hi > src/a.ts"'; assert_eq "$RC" "0" "bash -c writes src/a.ts passes"
code 'bash -c "ls docs"'; assert_eq "$RC" "0" "bash -c ls docs passes"

# 8. << as a shift is not a heredoc
export ONE_SUITE_PROCS="onesuite-fake-run-$$" ONE_SUITE_WAIT=0 ONE_SUITE_GRACE=0 ONE_SUITE_TURN="$SANDBOX/turn"
(cd "$C" && exec bash -c "exec -a onesuite-fake-run-$$ sleep 120") >/dev/null 2>&1 & dummy=$!; disown "$dummy" 2>/dev/null
sleep 1
for c in 'echo $((1<<3)); swift test' 'x=$(( 1 << 3 )) && pytest' 'echo $(( (1<<3)+1 )); swift test'; do
  bash_json "$c" "$C" | bash "$HOOKS/one-suite.sh" >/dev/null 2>&1; RC=$?
  assert_eq "$RC" "2" "a shift is not a heredoc: $c"
done
bash_json "cat <<EOF
swift test
EOF" "$C" | bash "$HOOKS/one-suite.sh" >/dev/null 2>&1; RC=$?
assert_eq "$RC" "0" "heredoc body still skipped"

finish
