#!/usr/bin/env bash
# hooks/guard-secrets.sh, second file: one case per single rule of the hook, of scripts/guard-lib.sh, of the shared
# tokenizer (scripts/bash-lex.awk) and of the reader (scripts/bashlex-guard-secrets.awk) that
# tests/test_hook_guard_secrets.sh leaves open. Each refused case has a twin that passes, and each case pins what the
# hook does today. The word lists below are written here on purpose (not read from the awk file): a word deleted from
# the product must make a case fail. The tests only ever create FAKE .env files and a fake $HOME/.ssh in the sandbox.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
H="$HOOKS/guard-secrets.sh"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR

mkdir -p "$CORE_DIR/p/code/src" "$SANDBOX/elsewhere" "$HOME/.ssh"
: > "$CORE_DIR/p/CLAUDE.md"
C="$CORE_DIR/p/code"
echo "FAKE=1" > "$C/.env"; echo "x" > "$HOME/.ssh/config"; echo "x" > "$SANDBOX/elsewhere/plain"
ln -s "$C/.env" "$C/notes.txt"                         # an innocent name that points at a .env
ln -s "$SANDBOX/elsewhere/plain" "$HOME/.ssh/out"      # a file in ~/.ssh that is a link leaving it
ln -s "$HOME" "$SANDBOX/hlink"                         # a second spelling of HOME (a link to it)
NL=$'\n'; CR=$'\r'; TABC=$'\t'

# run_tool <tool> <json of tool_input> — a tool call with the given tool_input, cwd in the project
run_tool() { run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$C" "$1" "$2")"; }
run_read() { run_tool Read "$(printf '{"file_path":"%s"}' "$(json_esc "$1")")"; }
run_bash() { run_tool Bash "$(printf '{"command":"%s"}' "$(json_esc "$1")")"; }
msg() { printf 'corecrew: reading secrets is blocked (%s)\nAsk the user to check the value themselves, or use .env.example.' "$1"; }
# blocked <label> <path shown> — exit 2, the exact message, nothing on stdout
blocked() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "$(msg "$2")" "$1: message"; }
# b <command> <word shown> — the command is refused; p <command> — it passes
b() { run_bash "$1"; blocked "Bash: $1" "$2"; }
p() { run_bash "$1"; hook_ok "Bash passes: $1"; }

# --- the hook: ~/.ssh as typed and as resolved, the cd rule, the raw scan, path and glob joined
sec_hook() {
  # HOME is reached through a link, so the folder as typed ($HOME/.ssh) and the resolved one differ
  rh="$HOME/.ssh/config"; HOME="$SANDBOX/hlink" run_read "$rh"; blocked "HOME is a link: the resolved ~/.ssh" "$rh"
  HOME="$SANDBOX/hlink" run_read "$SANDBOX/hlink/.ssh/out";   blocked "HOME is a link: a link in ~/.ssh that leaves it, as typed" "$SANDBOX/hlink/.ssh/out"
  HOME="$SANDBOX/hlink" run_read "$SANDBOX/hlink/notes.txt";  hook_ok "HOME is a link: a home file passes"
  run_read "$HOME/.ssh/out";                    blocked "a link in ~/.ssh that leaves it" "$HOME/.ssh/out"
  run_read "$SANDBOX/elsewhere/plain";          hook_ok "the file that link points at, by its own path"
  # HOME=/ names no ~/.ssh
  HOME=/ run_read "/.ssh/config";               hook_ok "HOME=/: /.ssh/config is not under a home"
  HOME=/ run_read "$C/.env";                    blocked "HOME=/: .env is still a secret" "$C/.env"
  # after a cd a relative path has no known folder: only its name is judged
  up="../../../../${HOME##*/}/.ssh/id_rsa"; b "cat $up" "$up"
  p "cd /tmp && cat $up"
  b 'cd /tmp && cat ~/.ssh/id_rsa' '~/.ssh/id_rsa'
  b 'cd /tmp && cat sub/.env' 'sub/.env'
  # the word shown is the word as typed, also for a glob
  b 'cat ~/.s*/id_rsa' '~/.s*/id_rsa'
  # a trailing slash does not hide the name
  run_tool Glob '{"pattern":"**/.env/"}';       blocked "Glob **/.env/" "**/.env/"
  run_tool Glob '{"pattern":"**/src/"}';        hook_ok "Glob **/src/"
  # the raw scan of an odd input: letter case, .env followed by * or ?
  local v
  for v in "$C/.ENV" ".Env.Local" ".env*" ".env?"; do
    run_tool Read "$(printf '{"file_path":["%s"]}' "$v")"; blocked "odd input: $v" "${v##*/}"
  done
  for v in ".envrc" ".env-x" ".ENV.EXAMPLE" "x-.env"; do
    run_tool Read "$(printf '{"file_path":["%s"]}' "$v")"; hook_ok "odd input passes: $v"
  done
  # a key the tool needs is missing while a secret-looking string is elsewhere: fails closed
  run_tool Read '{"path":"src/.env"}';          blocked "Read without file_path, .env elsewhere" ".env"
  run_tool Read '{"path":"src/.envrc"}';        hook_ok "Read without file_path, nothing secret-looking"
  # a key that occurs twice: the second value is judged with its JSON escapes removed
  run_tool Read '{"file_path":"src/a.ts","file_path":"~\/.ssh\/id_rsa"}'; blocked "duplicate key, escaped slashes" "~/.ssh/id_rsa"
  run_tool Read '{"file_path":"src/a.ts","file_path":"src\/b.ts"}';       hook_ok "duplicate key, escaped slashes, no secret"
  # path and glob are judged joined, but not an exclusion, an absolute glob or one that starts at a home
  run_tool Glob '{"path":"~","pattern":".ssh/*"}';        blocked "Glob path ~ + pattern .ssh/*" "~/.ssh/*"
  run_tool Glob '{"path":"~","pattern":"/.ssh/y"}';       hook_ok "Glob path ~ + absolute pattern: not joined"
  run_tool Grep '{"pattern":"x","path":"src","glob":"!sub/.env"}'; hook_ok "Grep path + exclusion glob: not joined"
  for v in '~' '$HOME' '${HOME}'; do
    run_tool Glob "$(printf '{"path":"%s","pattern":"%s/../.ssh/y"}' "$HOME" "$v")"; hook_ok "Glob pattern that starts with $v: not joined"
  done
  # apply_patch whose command is no string: only its "***" lines count
  run_tool apply_patch '{"command":["*** Begin Patch\n*** Add File: a.txt\n+see .env\n*** End Patch"]}'; hook_ok "patch that is no string: .env in the body only"
  run_tool apply_patch '{"command":["*** Begin Patch\n*** Add File: .env\n+k\n*** End Patch"]}'; blocked "patch that is no string: a *** line names .env" ".env"
}
bg sec_hook

# --- guard-lib.sh: the characters the raw scan cuts at, and a carriage return in a command
sec_lib() {
  local ch
  for ch in '`' "'" '/' '\\' ' ' ',' ':' ';' '=' '(' ')' '<' '>' '&' '|' '{' '}'; do
    run_tool Read "$(printf '{"file_path":["x%s.env"]}' "$ch")"; blocked "odd input: a name cut at $ch" ".env"
  done
  for ch in '-' '_' '+' '@' '%'; do
    run_tool Read "$(printf '{"file_path":["x%s.env"]}' "$ch")"; hook_ok "odd input: no cut at $ch"
  done
  b "cat${CR}.env" '.env'              # a carriage return is a blank
  p "cat${CR}.envrc"
}
bg sec_lib

# --- bash-lex.awk: the tokenizer rules, each through a verdict of this hook
sec_lex() {
  # every shell that takes -c; options before -c; what is no command line
  local w
  for w in bash sh zsh dash ksh; do b "$w -c \"cat .env\"" '.env'; p "$w -c \"cat .envrc\""; done
  b "eval \"cat .env\"" '.env'
  b 'bash -o pipefail -c "cat .env"' '.env'
  b 'bash +o posix -c "cat .env"' '.env'
  b 'bash -ec "cat .env"' '.env'
  p 'bash -- -c "cat .env"'            # after --, -c is the script file
  p 'bash run.sh -c "cat .env"'        # a script file: what follows are its arguments
  p 'bash run.sh .env'
  # a quoted NAME=value word is a command word, an unquoted one is an assignment
  b 'X=1 cat .env' '.env'
  p '"X=1" cat .env'
  # a quote or backslash after the = keeps the word an assignment; one before the = makes it a command word
  b 'X="1" cat .env' '.env'
  b "X='a' cat .env" '.env'
  b 'X=a\ b cat .env' '.env'
  b 'A=1 B="2" cat .env' '.env'
  p 'X="cat .env" true'
  p "'X'=1 cat .env"
  p 'FOO="a b" cat .envrc'
  p 'X=1 ls'
  p 'FOO="a b" make test'
  # an append (X+=) and an array element (X[0]=) are assignments too
  b 'X+=1 cat .env' '.env'
  b 'X+="1" cat .env' '.env'
  b 'X[0]="1" cat .env' '.env'
  b 'X[0]+=1 cat .env' '.env'
  p 'X+=1 ls'
  p 'X[0]="a b" cat .envrc'
  # a here-string inside "$(...)" is not a heredoc: the lines after it are judged
  b "echo \"\$(cat <<<x)\"${NL}cat .env" '.env'
  b "echo \"\$(cat<<<x)\"${NL}cat .env" '.env'
  p "echo \"\$(cat <<<x)\"${NL}cat .envrc"
  # a wrapper option that takes a value, long and short
  b 'sudo --user root cat .env' '.env'
  b 'sudo -u root cat .env' '.env'
  b 'sudo -- cat .env' '.env'
  p 'sudo --user root cat .envrc'
  # heredocs: <<- strips leading tabs of the delimiter line; the command after the body is judged
  b "cat <<-EOF${NL}${TABC}x${NL}${TABC}EOF${NL}cat .env" '.env'
  b "cat <<-EOF${NL}x${NL}EOF${NL}cat .env" '.env'
  p "cat <<EOF${NL}cat .env${NL}EOF"
  p "cat <<-EOF${NL}${TABC}cat .env${NL}${TABC}EOF"
  # a here-string is text, not a file and not a heredoc
  b "cat <<< x${NL}cat .env" '.env'
  b 'cat <<< x .env' '.env'
  b "echo \"\$(cat <<< x${NL}cat .env)\"" '.env'
  p "echo \"\$(cat <<< x${NL}cat .envrc)\""
  # redirects: <&N and &> take their word, <> does not eat the command word
  b 'cat <&3 .env' '.env'
  b 'cat &> out .env' '.env'
  b "cat &>""> out .env" '.env'       # the appending form, written in two parts for tests/test_portability.sh
  b '<> a cat .env' '.env'
  p 'cat <&3 &> out .envrc'
  # a backslash-newline joins the two parts of a word, outside and inside double quotes
  b "cat .e\\${NL}nv" '.env'
  b "cat \".e\\${NL}nv\"" '.env'
  p "cat .e\\${NL}nvrc"
  # a # inside a word starts no comment
  b 'cat "x"#y .env' '.env'
  p 'cat x #y .env'
  # an unbalanced $( takes the rest of the word (fails closed)
  b 'echo "$(cat .env"' '.env'
  p 'echo "$(cat .envrc"'
  # reading stops at <<"WORD" inside "$(...)": nothing after it is judged as a word, the raw scan decides (shown: .env)
  b "echo \"\$(cat sub/.env)\" \"\$(cat <<\"E\"${NL}x${NL}E${NL})\"" '.env'
  # words the shell itself would not run, read as the tokenizer reads them today
  b 'cat/ .env' '.env'
  p '"2">x cat .env'
}
bg sec_lex

# --- bashlex-guard-secrets.awk: every reader command, every pattern command, the single option rules
sec_readers() {
  local w many cn
  for w in cat less more most head tail source . base64 xxd od hexdump strings diff cmp comm open vim vi view nvim nano \
    pico emacs code bat nl tac rev cut paste sort uniq fold fmt column ed tar zip gzip; do
    b "$w .env" '.env'
  done
  for w in grep egrep fgrep rg ag ack sed awk gawk mawk; do
    p "$w .env README.md"; b "$w x .env" '.env'
  done
  p 'ls .env'; p 'rm .env'; p 'gunzip .env'       # not in the list: these do not show the file
  # copies: the sources are judged, not the destination
  for w in cp scp rsync; do p "$w .env.example .env"; b "$w .env host:" '.env'; done
  b 'cp --target-directory=out .env' '.env'
  b 'cp -t out .env' '.env'
  p 'cp --suffix=.env a b'
  # globs that can match a secret name
  b 'cat .e*.local' '.e*.local'
  b 'cat .[e]nv' '.[e]nv'
  b 'cat .[!x]nv' '.[!x]nv'
  p 'cat .[!e]nv'
  p 'cat .[x]nv'
  # -- ends the options; a lone - is an operand; a trailing slash does not hide the name
  b 'cat -- .env' '.env'
  p 'grep -- .env README.md'
  b 'grep -- -x .env' '.env'
  b 'grep - .env' '.env'
  b 'cat .env/' '.env/'
  # single option rules
  b 'gawk -e 1 .env' '.env';              p 'gawk -e .env README.md'
  b 'gawk --source 1 .env' '.env';     p 'gawk -e 1 -e .env README.md'
  b 'ag -A 2 x .env' '.env';              p 'ag -A 2 .env README.md'
  b 'ack --context 2 x .env' '.env';      p 'ack -C 2 .env README.md'
  b 'ag -p .env x src' '.env';            p 'ag -p ignore.txt .env src'
  b 'ag --path-to-ignore .env x src' '.env'
  b 'sed -l 5 p .env' '.env';             p 'sed -l 5 .env README.md'
  p 'sed --line-length 5 .env README.md'
  p 'grep --regexp a --regexp .env README.md'
  b 'grep --regexp a .env' '.env'
  b 'diff --from-file=.env x' '.env'        # an unknown --option=value of a reader is judged
  # more than 200 candidates: reading stops and the raw scan decides
  many=""; cn=0; while [ "$cn" -lt 201 ]; do many="$many a$cn/.ssh/k"; cn=$((cn + 1)); done
  b "cat $many" '.ssh'
  p "cat${many% *}"
}
bg sec_readers

bg_wait

finish
