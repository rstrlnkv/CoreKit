#!/usr/bin/env bash
# hooks/guard-code.sh: a project's internal files (CLAUDE.md, docs/**, .claude/**) must not be
# written under <Core>/<project>/code/**. Write|Edit|NotebookEdit read the path from the tool input;
# Bash is judged best effort (redirects, tee, touch, cp, mv, mkdir). Inert outside the Core project.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/guard-code.sh"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

mkdir -p "$CORE_DIR/p/code/src" "$CORE_DIR/p/docs" "$CORE_DIR/q/code" "$SANDBOX/elsewhere"
: > "$CORE_DIR/p/CLAUDE.md"; : > "$CORE_DIR/q/CLAUDE.md"
C="$CORE_DIR/p/code"

# The sections below that share nothing run at the same time (bg <function>): each in a subshell with its
# own scratch folder OD and its own counts, and the output and counts are collected by bg_wait. This keeps
# the file near 5 s (a hook run is about 40 ms and there are about 350 of them).
OD="$SANDBOX"; BGN=0
bg() { # bg <function>
  BGN=$((BGN + 1)); local n=$BGN
  ( OD="$SANDBOX/bg$n"; mkdir -p "$OD"; FAILS=0; PASSES=0; "$1"; echo "$PASSES $FAILS" > "$SANDBOX/bg$n.count" ) > "$SANDBOX/bg$n.log" 2>&1 &
}
bg_wait() {
  local n p f
  wait
  for n in $(seq 1 $BGN); do
    cat "$SANDBOX/bg$n.log"
    if [ -f "$SANDBOX/bg$n.count" ]; then read -r p f < "$SANDBOX/bg$n.count"; PASSES=$((PASSES + p)); FAILS=$((FAILS + f))
    else fail "background section $n did not finish"; fi
  done
}

# run_json <json> — stdout in OUT, stderr in ERR, exit code in RC
run_json() { printf '%s' "$1" | bash "$H" >"$OD/out" 2>"$OD/err"; RC=$?; OUT="$(<"$OD/out")"; ERR="$(<"$OD/err")"; }
# run_file <tool> <path> [cwd] — Write, Edit or NotebookEdit; the path is put in the JSON as is
run_file() {
  local key=file_path; [ "$1" = NotebookEdit ] && key=notebook_path
  run_json "$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "${3-$C}" "$1" "$key" "$2")"
}
# run_bash <json-escaped command> [cwd]
run_bash() { run_json "$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2-$C}" "$1")"; }
# The second line points at public-docs: in the project's CLAUDE.md (<Core>/<p>, the part of the shown
# path before its first /code/).
msg() {
  printf 'corecrew: %s is an internal file and must not live in code/. Write it to %s instead.\n' "$1" "$2"
  printf 'Docs meant to stay public in code/: list them on a "public-docs: <paths>" line in %s.' "${1%%/code/*}/CLAUDE.md"
}
# ok <label> — exit 0, silent
ok() { assert_eq "$RC" "0" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "" "$1: stderr"; }
# blocked <label> <path shown> <target in the Core> — exit 2, the exact message, nothing on stdout
blocked() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "$(msg "$2" "$3")" "$1: message"; }


# Write, Edit, NotebookEdit, MultiEdit: paths, worktrees, public-docs, symlinks
sec_write() {
# --- Write: the three internal kinds are refused, with the right target in the message
run_file Write "$C/CLAUDE.md";               blocked "Write code/CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/docs/a.md";               blocked "Write code/docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/docs/deep/er/a.md";       blocked "Write code/docs/deep/er/a.md" "$C/docs/deep/er/a.md" "$CORE_DIR/p/docs/deep/er/a.md"
run_file Write "$C/.claude/rules/x.md";      blocked "Write code/.claude/rules/x.md" "$C/.claude/rules/x.md" "$CORE_DIR/p/.claude/rules/x.md"
run_file Edit  "$C/docs/a.md";               blocked "Edit code/docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/.claude/worktrees/w/CLAUDE.md"
blocked "Write worktree CLAUDE.md" "$C/.claude/worktrees/w/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/.claude/worktrees/w/docs/a.md"
blocked "Write worktree docs/a.md" "$C/.claude/worktrees/w/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/.claude/worktrees/w/.claude/rules/x.md"
blocked "Write worktree .claude/rules" "$C/.claude/worktrees/w/.claude/rules/x.md" "$CORE_DIR/p/.claude/rules/x.md"

# --- allowed: settings.local.json, ordinary code, the Core's own copies, worktree dirs
run_file Write "$C/.claude/settings.local.json"; ok "settings.local.json"
run_file Write "$C/src/a.sh";                    ok "code/src/a.sh"
run_file Write "$C/README.md";                   ok "code/README.md"
run_file Write "$CORE_DIR/p/docs/a.md";          ok "Core project docs/a.md"
run_file Write "$CORE_DIR/p/CLAUDE.md";          ok "Core project CLAUDE.md"
run_file Write "$CORE_DIR/p/.claude/rules/x.md"; ok "Core project .claude/rules"
run_file Write "$CORE_DIR/README.md";            ok "Core root file"
run_file Write "$C/.claude/worktrees/w";         ok "the worktree dir itself"
run_file Write "$C/.claude/worktrees/w2/";       ok "another worktree dir, trailing slash"
run_file Write "$C/.claude/worktrees";           ok "worktrees dir"
run_file Write "$C/.claude/worktrees/w/src/a.sh";ok "worktree ordinary code"
run_file Write "$C/.claude/worktrees/w/.claude/settings.local.json"; ok "worktree settings.local.json"
run_file Write "$C/.claude/worktrees/w/.claude/worktrees/v"; ok "worktree inside a worktree"

# --- nested CLAUDE.md: blocked at any depth, like the git pre-commit hook; CLAUDE.local.md too
run_file Write "$C/src/CLAUDE.md";           blocked "nested CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/deep/CLAUDE.md";      blocked "deeper CLAUDE.md" "$C/src/deep/CLAUDE.md" "$CORE_DIR/p/src/deep/CLAUDE.md"
run_file Write "$C/CLAUDE.local.md";         blocked "CLAUDE.local.md" "$C/CLAUDE.local.md" "$CORE_DIR/p/CLAUDE.local.md"
run_file Write "$C/src/CLAUDE.local.md";     blocked "nested CLAUDE.local.md" "$C/src/CLAUDE.local.md" "$CORE_DIR/p/src/CLAUDE.local.md"
run_file Write "$C/.claude/worktrees/w/src/CLAUDE.md"
blocked "worktree nested CLAUDE.md" "$C/.claude/worktrees/w/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/MYCLAUDE.md";         ok "name that only ends like CLAUDE.md"
run_file Write "$C/src/CLAUDE.md.bak";       ok "CLAUDE.md.bak"
run_file Write "$C/src/docs/a.md";           ok "docs/ below src/ is not the internal docs/"
run_file Write "$C/docsx/a.md";              ok "docsx/"
run_file Write "$C/.claudex/a";              ok ".claudex/"

# --- NotebookEdit uses notebook_path; a relative Edit path resolves against cwd
run_file NotebookEdit "$C/docs/n.ipynb";     blocked "NotebookEdit docs" "$C/docs/n.ipynb" "$CORE_DIR/p/docs/n.ipynb"
run_file NotebookEdit "$C/src/n.ipynb";      ok "NotebookEdit src"
run_file Edit "docs/a.md";                   blocked "Edit relative docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Edit "src/a.sh";                    ok "Edit relative src/a.sh"
run_file Edit "a.md" "$C/docs";              blocked "Edit relative, cwd in docs/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Edit "../CLAUDE.md" "$C/src";       blocked "Edit ../CLAUDE.md from src/ (nested level)" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Edit "../../CLAUDE.md" "$C/src";    ok "Edit ../../CLAUDE.md from src/ is the Core's own file"
run_file Edit "docs/a.md" "$SANDBOX/elsewhere"; ok "relative path, cwd outside the Core"
run_file Edit "$C/docs/a.md" "$SANDBOX/elsewhere"; blocked "absolute path inside, cwd outside" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"

# --- .. is resolved; letter case is folded (also for a part that does not exist yet)
run_file Write "$CORE_DIR/p/code/../code/CLAUDE.md"; blocked "path with .. back into code" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/src/../docs/x.md";        blocked ".. through an existing dir" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_file Write "$C/nope/../docs/x.md";       blocked ".. through a missing dir" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_file Write "$C/nope/../../docs/a.md";    ok ".. out of code/ into the Core's docs/"
run_file Write "$C/./docs/./a.md";           blocked "single dots" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C//docs//a.md";             blocked "double slashes" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/claude.md";               blocked "claude.md lower case" "$C/claude.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/Claude.MD";               blocked "Claude.MD mixed case" "$C/Claude.MD" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/DOCS/a.md";               blocked "DOCS/ upper case (missing dir)" "$C/DOCS/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/.CLAUDE/x";               blocked ".CLAUDE/ upper case" "$C/.CLAUDE/x" "$CORE_DIR/p/.claude/x"
run_file Write "$C/.Claude/Settings.LOCAL.json"; ok "settings.local.json in other case"
run_file Write "$C/.Claude/WorkTrees/w/CLAUDE.MD"
blocked "worktree in other case" "$C/.Claude/WorkTrees/w/CLAUDE.MD" "$CORE_DIR/p/CLAUDE.md"

# --- public-docs: in <Core>/<p>/CLAUDE.md
Q="$CORE_DIR/q/code"
run_file Write "$Q/docs/x.md";               blocked "no public-docs line" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\ncheck: true\npublic-docs: docs/\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               ok "public-docs: docs/"
run_file Write "$Q/docs/sub/deep/y.md";      ok "public-docs: docs/ covers everything under it"
run_file Write "$Q/docs";                    ok "public-docs: docs/ covers docs itself"
run_file Write "$Q/DOCS/x.md";               ok "public-docs is case-insensitive too"
run_file Write "$Q/CLAUDE.md";               blocked "public-docs: docs/ does not open CLAUDE.md" "$Q/CLAUDE.md" "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/.claude/rules/x.md";      blocked "public-docs: docs/ does not open .claude" "$Q/.claude/rules/x.md" "$CORE_DIR/q/.claude/rules/x.md"
run_file Write "$Q/docsx/a.md";              ok "docsx is not blocked at all"
printf '# q\r\npublic-docs: README.md docs/guide.md, `docs/api/` ./CLAUDE.local.md\r\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/guide.md";           ok "public-docs: a file entry"
run_file Write "$Q/docs/api/v1/a.md";        ok "public-docs: a dir entry among several (comma, backticks, CRLF)"
run_file Write "$Q/CLAUDE.local.md";         ok "public-docs: ./ prefix"
run_file Write "$Q/docs/other.md";           blocked "public-docs: a file entry opens only that file" "$Q/docs/other.md" "$CORE_DIR/q/docs/other.md"
run_file Write "$Q/docs/guide.md.bak";       blocked "public-docs: prefix of a name is not a match" "$Q/docs/guide.md.bak" "$CORE_DIR/q/docs/guide.md.bak"
printf '# q\nsee public-docs: docs/ for details\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               blocked "public-docs must start the line" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\npublic-docs: *\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               blocked "public-docs: a glob opens nothing" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\npublic-docs: docs/\n' > "$CORE_DIR/q/CLAUDE.md"
mkdir -p "$Q/.claude/worktrees/w"
run_file Write "$Q/.claude/worktrees/w/docs/x.md"; ok "public-docs applies relative to a worktree root"
run_file Write "$Q/.claude/worktrees/w/CLAUDE.md"; blocked "public-docs: worktree CLAUDE.md" "$Q/.claude/worktrees/w/CLAUDE.md" "$CORE_DIR/q/CLAUDE.md"

# --- symlinks: a directory link is resolved; a file link is followed
mkdir -p "$C/src/real"; ln -s "$CORE_DIR/p/docs" "$C/linkdocs"; ln -s "$C/docs" "$C/src/real/tocodedocs"
run_file Write "$C/linkdocs/a.md";           ok "code/linkdocs -> <Core>/p/docs (writing to the Core)"
mkdir -p "$C/docs"
run_file Write "$C/src/real/tocodedocs/a.md"; blocked "link into code/docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
ln -s docs/x.md "$C/notes.md"
run_file Write "$C/notes.md";                blocked "file link to code/docs/x.md" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
ln -s ../p/docs/x.md "$CORE_DIR/q/code/lnk.md"
run_file Write "$CORE_DIR/q/code/lnk.md";    ok "file link out of code/ into the Core"
ln -s lnk-loop "$C/lnk-loop"
run_file Write "$C/lnk-loop";                ok "a link loop does not hang"

}
bg sec_write

# Bash: commands that must pass, the commit-message heredoc
sec_bash_pass() {
# --- Bash: things that must pass
for c in 'cat CLAUDE.md' 'cat docs/a.md | head' 'ls docs .claude' 'grep -rn x docs' 'echo x > src/a.txt' 'echo x > /dev/null' \
         'ls 2>/dev/null' 'ls docs >/dev/null 2>&1' 'ls docs 2>&1' 'echo x >&2' 'echo x 1>&2' 'cat a >&-' \
         'cp docs/a.md /tmp/' 'cp -r docs /tmp/docs-copy' 'mv src/a src/b' 'tee src/x.txt' 'touch src/a' 'cp a b' \
         'echo x > /tmp/CLAUDE.md' 'git status' 'git commit -m \"docs: update\"' \
         'echo \"a > docs/b.md\"' "echo 'a > docs/b.md'" 'git commit -m \"write > docs/x.md\"' \
         'ls # > docs/a.md' 'echo a#b' 'cat < docs/a.md' 'cat <<< \"x > docs/a\"' \
         'cat > notes.txt <<'"'"'EOF'"'"'\necho x > docs/a.md\ncp a docs/b\nEOF' 'cat <<-EOF\n\tx > docs/a.md\n\tEOF\nls' \
         'echo x > ../docs/a.md' 'echo x > ../CLAUDE.md' 'echo x > docs/*.md' 'echo x > $HOME/docs/a.md' 'echo x > `pwd`/docs/a' \
         'echo \"unterminated > docs/a.md' "echo 'unterminated > docs/a.md" 'echo x >' 'cp' 'mv a' 'tee' 'touch' 'mkdir' '> ' '>>' '2>' \
         'python3 -c \"open(1)\"' 'sed -n 1p CLAUDE.md > out.txt'; do
  run_bash "$c"; ok "Bash passes: $c"
done
# the Claude Code commit idiom: a heredoc inside "$(...)"; an odd number of double quotes in the body must not flip the quoting
run_bash 'git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: guard for 5\" screens\n\nMoved notes -> docs/notes.md\nEOF\n)\"'; ok "Bash commit heredoc in \"\$(...)\", odd quote in the body"
run_bash 'git commit -m \"$(cat <<EOF\nsay \"hi\nx > docs/a.md\nEOF\n)\" && echo y > docs/b.md'
blocked "Bash command after a commit heredoc is judged again" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash 'git commit -m \"$(cat <<-EOF\n\tit\"s > docs/a.md\n\tEOF\n)\"'; ok "Bash commit heredoc <<- in \"\$(...)\""
run_bash 'git commit -m \"$(cat <<\"EOF\"\nx\" > docs/a.md\nEOF\n)\"'; ok "Bash commit heredoc with a double-quoted delimiter fails open"
# a heredoc body that is not closed, and one closed on the last line, are not parsed as commands
run_bash 'grep -n \"<<'"'"'\" f.sh && echo '"'"'ok'"'"' \"> docs/y\"'; ok "Bash a <<' inside a double-quoted grep pattern does not flip the quoting"
run_bash 'cat <<EOF\necho x > docs/a.md'; ok "Bash unterminated heredoc body"
run_bash 'cat <<EOF > notes\nx\nEOF\ncp a docs/b'; blocked "Bash command after a closed heredoc is judged" "$C/docs/b" "$CORE_DIR/p/docs/b"

}
bg sec_bash_pass

# JSON escapes, odd core_dir values, letter case, no git
sec_json() {
# --- JSON with escapes, extra whitespace and newlines: the real path is read
# the Core folder with Cyrillic and a space, written as \u escapes
CYR="$SANDBOX/Мои проекты/Ядро"
mkdir -p "$CYR/app/code"; : > "$CYR/app/CLAUDE.md"
export CORE_DIR="$CYR"
run_json '{"cwd":"'"$CYR"'/app/code","tool_name":"Write","tool_input":{"file_path":"'"$CYR"'/app/code/CLAUDE.md"}}'
blocked "core_dir with a space and Cyrillic: CLAUDE.md" "$CYR/app/code/CLAUDE.md" "$CYR/app/CLAUDE.md"
run_file Write "$CYR/app/code/docs/a.md" "$CYR/app/code";     blocked "core_dir with a space and Cyrillic: docs" "$CYR/app/code/docs/a.md" "$CYR/app/docs/a.md"
run_file Write "$CYR/app/code/.claude/rules/x.md" "$CYR/app/code"; blocked "core_dir with a space and Cyrillic: .claude" "$CYR/app/code/.claude/rules/x.md" "$CYR/app/.claude/rules/x.md"
run_file Write "$CYR/app/code/src/a.sh" "$CYR/app/code";      ok "core_dir with a space and Cyrillic: code"
run_file Write "$CYR/app/docs/a.md" "$CYR/app/code";          ok "core_dir with a space and Cyrillic: the Core's docs"
run_bash 'echo x > \"docs/a b.md\"' "$CYR/app/code";          blocked "core_dir Cyrillic: Bash quoted" "$CYR/app/code/docs/a b.md" "$CYR/app/docs/a b.md"
run_bash 'cp a docs/b.md' "$CYR/app/code";                    blocked "core_dir Cyrillic: Bash cp" "$CYR/app/code/docs/b.md" "$CYR/app/docs/b.md"
# the same path as \u escapes (Мои проекты/Ядро) and with newlines and spaces around the keys
U='\u041c\u043e\u0438 \u043f\u0440\u043e\u0435\u043a\u0442\u044b/\u042f\u0434\u0440\u043e'
run_json '{"cwd":"'"$SANDBOX"'/'"$U"'/app/code","tool_name":"Write","tool_input":{"file_path":"'"$SANDBOX"'/'"$U"'/app/code/CLAUDE.md"}}'
blocked "escaped (\\u) Cyrillic path" "$CYR/app/code/CLAUDE.md" "$CYR/app/CLAUDE.md"
run_json "$(printf '{\n  "tool_name" : "Write",\n  "cwd"\n  :\n  "%s/app/code",\n  "tool_input" : {\n    "content" : "a\\n\\"file_path\\": \\"/x\\"",\n    "file_path" :\n      "%s/app/code/docs/a.md"\n  }\n}\n' "$CYR" "$CYR")"
blocked "pretty-printed JSON, a decoy key inside a string" "$CYR/app/code/docs/a.md" "$CYR/app/docs/a.md"
run_json '{"tool_name":"Bash","cwd":"'"$CYR"'/app/code","tool_input":{"command":"echo \"x\" > \"docs/q\\\"uote.md\""}}'
blocked "escaped quotes in a Bash command" "$CYR/app/code/docs/q\"uote.md" "$CYR/app/docs/q\"uote.md"
mkdir -p "$CYR/app/code/src/we\"ird"
run_json '{"cwd":"'"$CYR"'/app/code","tool_name":"Write","tool_input":{"file_path":"'"$CYR"'/app/code/src/we\"ird/a.sh"}}'; ok "escaped quote in a folder name, ordinary code"
run_json '{"cwd":"'"$CYR"'/app/code","tool_name":"Write","tool_input":{"file_path":"'"$CYR"'/app/code/src/we\"ird/CLAUDE.md"}}'
blocked "escaped quote in a folder name, nested CLAUDE.md" "$CYR/app/code/src/we\"ird/CLAUDE.md" "$CYR/app/src/we\"ird/CLAUDE.md"
mkdir -p "$CYR/app/code/src/back\\slash"
run_json '{"cwd":"'"$CYR"'/app/code","tool_name":"Write","tool_input":{"file_path":"'"$CYR"'/app/code/src/back\\slash/CLAUDE.md"}}'
blocked "escaped backslash in a folder name" "$CYR/app/code/src/back\\slash/CLAUDE.md" "$CYR/app/src/back\\slash/CLAUDE.md"

# --- core_dir given with ~, with a trailing slash, through a symlink
mkdir -p "$HOME/MyCore/app/code" "$SANDBOX/real/app/code"; : > "$HOME/MyCore/app/CLAUDE.md"; : > "$SANDBOX/real/app/CLAUDE.md"
export CORE_DIR='~/MyCore'
run_file Write "$HOME/MyCore/app/code/docs/a.md" "$HOME/MyCore/app/code"; blocked "core_dir with ~" "$HOME/MyCore/app/code/docs/a.md" "$HOME/MyCore/app/docs/a.md"
export CORE_DIR="$HOME/MyCore///"
run_file Write "$HOME/MyCore/app/code/CLAUDE.md" "$HOME/MyCore/app/code"; blocked "core_dir with a trailing slash" "$HOME/MyCore/app/code/CLAUDE.md" "$HOME/MyCore/app/CLAUDE.md"
ln -s "$SANDBOX/real" "$SANDBOX/linkcore"
export CORE_DIR="$SANDBOX/linkcore"
run_file Write "$SANDBOX/real/app/code/docs/a.md" "$SANDBOX/real/app/code"; blocked "core_dir is a symlink, path real" "$SANDBOX/real/app/code/docs/a.md" "$SANDBOX/real/app/docs/a.md"
run_file Write "$SANDBOX/linkcore/app/code/docs/a.md" "$SANDBOX/linkcore/app/code"; blocked "core_dir is a symlink, path through it" "$SANDBOX/real/app/code/docs/a.md" "$SANDBOX/real/app/docs/a.md"
export CORE_DIR="$SANDBOX/real"
run_file Write "$SANDBOX/linkcore/app/code/docs/a.md" "$SANDBOX/real/app/code"; blocked "real core_dir, path through a symlink" "$SANDBOX/real/app/code/docs/a.md" "$SANDBOX/real/app/docs/a.md"
run_file Write "docs/a.md" "$SANDBOX/linkcore/app/code";      blocked "relative path, cwd through a symlink" "$SANDBOX/real/app/code/docs/a.md" "$SANDBOX/real/app/docs/a.md"

# --- core_dir typed in another letter case than on disk (macOS volumes are case-insensitive)
mkdir -p "$SANDBOX/cs/a"
if [ -d "$SANDBOX/cs/A" ]; then
  mkdir -p "$SANDBOX/CaseCore/Ядро/MyApp/code"; : > "$SANDBOX/CaseCore/Ядро/MyApp/CLAUDE.md"
  CP="$SANDBOX/CaseCore/Ядро/MyApp"
  export CORE_DIR="$SANDBOX/casecore/ядро"
  run_file Write "$CP/code/docs/a.md" "$CP/code";             blocked "CORE_DIR in other case, path as on disk" "$CP/code/docs/a.md" "$CP/docs/a.md"
  run_file Write "$SANDBOX/CASECORE/ЯДРО/myapp/code/CLAUDE.md" "$SANDBOX/casecore/ядро/MYAPP/CODE"
  blocked "path and cwd in other case" "$CP/code/CLAUDE.md" "$CP/CLAUDE.md"
  run_file Write "$SANDBOX/CASECORE/ЯДРО/MYAPP/Code/Docs/a.md" "$CP/code"
  blocked "every part in other case, docs missing" "$CP/code/Docs/a.md" "$CP/docs/a.md"
  run_bash 'echo x > DOCS/a.md' "$SANDBOX/casecore/ядро/myapp/code"; blocked "Bash, cwd in other case" "$CP/code/DOCS/a.md" "$CP/docs/a.md"
  run_file Write "$SANDBOX/CASECORE/ЯДРО/myapp/docs/a.md" "$CP/code"; ok "other case, the Core's own docs"
else
  echo "  note: case-sensitive volume, letter-case test skipped"; pass
fi
export CORE_DIR="$SANDBOX/Projects/Core"

# --- no network, no git: the hook runs without git on PATH and without a repo
mkdir -p "$SANDBOX/nogit"
for t in cat sed tr grep date mkdir head dirname basename awk rm readlink pwd; do ln -sf "$(command -v $t)" "$SANDBOX/nogit/$t" 2>/dev/null; done
OUT="$(printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/docs/a.md"}}' "$C" "$C" | PATH="$SANDBOX/nogit" "$(command -v bash)" "$H" 2>&1 >/dev/null)"
assert_eq "$?" "2" "run without git/PATH tools: blocked"
case "$OUT" in "corecrew: $C/docs/a.md is an internal file"*) pass ;; *) fail "no git on PATH: $OUT" ;; esac

}
bg sec_json

# size and speed
sec_size() {
# --- speed and size: a huge command is judged in time (the tokenizer is linear)
timed_json() { # timed_json <file> — RC, OUT, ERR as run_json; T = seconds; a hook that spins is killed after 20 s (RC 143)
  local t0=$SECONDS
  bash "$H" < "$1" >"$OD/out" 2>"$OD/err" & local hp=$!
  ( sleep 20; kill "$hp" 2>/dev/null ) >/dev/null 2>&1 & local wd=$!; disown "$wd" 2>/dev/null
  wait "$hp"; RC=$?; kill "$wd" 2>/dev/null
  T=$((SECONDS - t0)); OUT="$(<"$OD/out")"; ERR="$(<"$OD/err")"
}
words="$(yes 'ab' | head -n 40000 | tr '\n' ' ')"           # about 120 KB of short words
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$C" "$words" > "$SANDBOX/big1.json"
timed_json "$SANDBOX/big1.json"; ok "120 KB of words"; [ "$T" -lt 5 ] && pass || fail "120 KB of words took ${T} s"
one="$(head -c 100000 /dev/zero | tr '\0' 'x')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s > docs/a.md"}}' "$C" "$one" > "$SANDBOX/big3.json"
timed_json "$SANDBOX/big3.json"; blocked "one 100 KB word, then a redirect" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 5 ] && pass || fail "one 100 KB word took ${T} s"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"%s\\" > docs/a.md; echo %s"}}' "$C" "$one" "'$one'" > "$SANDBOX/big4.json"
timed_json "$SANDBOX/big4.json"; blocked "100 KB double-quoted word" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 5 ] && pass || fail "100 KB quoted word took ${T} s"
esc="$(yes 'a\\\"b' | head -n 20000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"%s\\""}}' "$C" "$esc" > "$SANDBOX/big5.json"
timed_json "$SANDBOX/big5.json"; ok "100 KB of escapes in one quoted string"; [ "$T" -lt 5 ] && pass || fail "escapes took ${T} s"
reds="$(yes '>x' | head -n 20000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$C" "$reds" > "$SANDBOX/big6.json"
timed_json "$SANDBOX/big6.json"; ok "20000 redirects to an ordinary file (the target count is capped)"; [ "$T" -lt 8 ] && pass || fail "many redirects took ${T} s"
# the one big case, over 1 MB of words and then a redirect into docs/, under a 20 s watchdog
words="$(yes 'ab' | head -n 360000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s > docs/a.md"}}' "$C" "$words" > "$SANDBOX/big2.json"
timed_json "$SANDBOX/big2.json"; blocked "1 MB of words, then a redirect into docs/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 15 ] && pass || fail "1 MB then redirect took ${T} s"
# a Write with a 1 MB content field: the path is still read
printf '{"cwd":"%s","tool_name":"Write","tool_input":{"content":"%s","file_path":"%s/docs/big.md"}}' "$C" "$(head -c 1000000 /dev/zero | tr '\0' 'y')" "$C" > "$SANDBOX/big7.json"
timed_json "$SANDBOX/big7.json"; blocked "Write with 1 MB of content" "$C/docs/big.md" "$CORE_DIR/p/docs/big.md"; [ "$T" -lt 5 ] && pass || fail "1 MB Write took ${T} s"

}
bg sec_size

# --- in the foreground: Bash cases that must be refused, and input that is not judged
# --- Bash: redirects and the file commands (cwd = code/)
run_bash 'echo x > CLAUDE.md';               blocked "Bash > CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'echo x > code/CLAUDE.md' "$CORE_DIR/p"; blocked "Bash > code/CLAUDE.md from the project folder" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'echo x>CLAUDE.md';                 blocked "Bash no spaces" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'echo x >> docs/a.md';              blocked "Bash >>" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x 2> docs/err.log';           blocked "Bash 2>" "$C/docs/err.log" "$CORE_DIR/p/docs/err.log"
run_bash 'echo x &> docs/all.log';           blocked "Bash &>" "$C/docs/all.log" "$CORE_DIR/p/docs/all.log"
run_bash 'echo x >| docs/a.md';              blocked "Bash >|" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x >& docs/a.md';              blocked "Bash >& file" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > \"docs/a b.md\"';         blocked "Bash > quoted target with a space" "$C/docs/a b.md" "$CORE_DIR/p/docs/a b.md"
run_bash "echo x > 'docs/a b.md'";           blocked "Bash > single-quoted target" "$C/docs/a b.md" "$CORE_DIR/p/docs/a b.md"
run_bash 'echo x > docs/a\\ b.md';           blocked "Bash > escaped space" "$C/docs/a b.md" "$CORE_DIR/p/docs/a b.md"
run_bash 'cp a docs/b.md';                   blocked "Bash cp a docs/b.md" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash 'cp -r a b docs/';                  blocked "Bash cp -r into docs/" "$C/docs" "$CORE_DIR/p/docs"
run_bash 'cp -t docs/ a b'; blocked "Bash cp -t docs/ (the first source named in the dir)" "$C/docs/a" "$CORE_DIR/p/docs/a"
run_bash 'mv a .claude/b';                   blocked "Bash mv a .claude/b" "$C/.claude/b" "$CORE_DIR/p/.claude/b"
run_bash 'tee docs/x.md < /dev/null';        blocked "Bash tee docs/x.md" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_bash 'echo hi | tee -a docs/x.md';       blocked "Bash | tee -a" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_bash 'echo hi | tee src/ok.txt docs/x.md'; blocked "Bash tee, second file" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_bash 'touch .claude/rules/x.md';         blocked "Bash touch" "$C/.claude/rules/x.md" "$CORE_DIR/p/.claude/rules/x.md"
run_bash 'touch -t 202001010000 src/a CLAUDE.md'; blocked "Bash touch -t" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'cp /tmp/CLAUDE.md .';              blocked "Bash cp CLAUDE.md into code/ (dest is a dir)" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'mv ../x/CLAUDE.md src/';           blocked "Bash mv CLAUDE.md into src/" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
# after cd / pushd / popd a relative target is unknown (cwd is not tracked): only absolute and ~ targets are judged
run_bash 'cd /tmp && echo x > docs/a.md';    ok "Bash after cd: relative target is not judged"
run_bash 'cd .. && echo \"- step 3\" >> docs/INDEX.md'; ok "Bash cd .. && echo >> docs/INDEX.md (the wiki in the Core)"
run_bash 'cd .. && cat > docs/features/x.md <<EOF\n# x\nbody\nEOF'; ok "Bash cd .. && cat > docs/... <<EOF"
run_bash '(cd .. && cp /tmp/notes.md docs/)'; ok "Bash (cd .. && cp notes docs/)"
run_bash 'cd /tmp && echo x > CLAUDE.md';    ok "Bash cd /tmp && echo x > CLAUDE.md"
run_bash 'cd .. && echo x > code/CLAUDE.md'; ok "Bash cd .. then a relative code/CLAUDE.md: unknown, passes (best effort)"
run_bash "cd src && echo x > $C/CLAUDE.md";  blocked "Bash cd src, then an absolute target" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash "pushd .. >/dev/null; echo x > docs/a.md; popd"; ok "Bash pushd: relative target passes"
run_bash "popd; touch docs/a.md";            ok "Bash popd: relative target passes"
run_bash 'cd src; mkdir -p docs';            ok "Bash cd then mkdir docs"
run_bash "cd .. && cp a $C/docs/b.md";       blocked "Bash cd then cp to an absolute docs path" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash 'echo x > docs/a.md && cd ..';      blocked "Bash target before the cd is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo cd; echo x > docs/a.md';      blocked "Bash: cd as an argument is no cd" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > ~/nothing/docs/a.md';     ok "Bash ~ target outside the Core"
run_bash 'ls; echo x > docs/a.md';           blocked "Bash after ;" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'ls\necho x > docs/a.md';           blocked "Bash after a newline" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'sudo tee docs/a.md';               blocked "Bash behind sudo" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'FOO=1 /usr/bin/touch docs/a.md';   blocked "Bash behind an assignment and a path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'cat <<EOF > docs/a.md\nbody\nEOF'; blocked "Bash heredoc into docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash '(echo x > docs/a.md)';             blocked "Bash in a subshell" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo $(cat x > docs/a.md)';        blocked "Bash in a command substitution" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > $C/docs/a.md' "$SANDBOX/elsewhere"; ok "Bash: an unexpanded variable is not judged"
run_bash "echo x > $C/docs/a.md" "$SANDBOX/elsewhere"; blocked "Bash absolute target, cwd outside" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > src/CLAUDE.md';           blocked "Bash nested CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
# mkdir: docs/ and .claude/<anything> are refused; the bare .claude dir is the home of settings.local.json
run_bash 'mkdir docs';                       blocked "Bash mkdir docs" "$C/docs" "$CORE_DIR/p/docs"
run_bash 'mkdir -p docs/features';           blocked "Bash mkdir -p docs/features" "$C/docs/features" "$CORE_DIR/p/docs/features"
run_bash 'mkdir -m 755 -p .claude/rules';    blocked "Bash mkdir -p .claude/rules" "$C/.claude/rules" "$CORE_DIR/p/.claude/rules"
run_bash 'mkdir -p .claude';                 ok "Bash mkdir .claude (for settings.local.json)"
run_bash 'mkdir -p src/docs src/.claude';    ok "Bash mkdir below src"
run_bash 'mkdir -p .claude/worktrees/w';     ok "Bash mkdir a worktree dir"


# --- inert outside the Core project: cwd and target both outside, or only the Core's own files
run_file Write "$SANDBOX/elsewhere/CLAUDE.md" "$SANDBOX/elsewhere";   ok "Write CLAUDE.md outside the Core"
run_file Write "$SANDBOX/elsewhere/docs/a.md" "$SANDBOX/elsewhere";   ok "Write docs/ outside the Core"
run_file Write "$SANDBOX/elsewhere/code/docs/a.md" "$SANDBOX/elsewhere"; ok "Write elsewhere/code/docs"
run_file Write "$CORE_DIR/standards/code/docs/a.md" "$CORE_DIR";      ok "standards/ is not a project"
run_file Write "$CORE_DIR/nonproject/code/CLAUDE.md" "$CORE_DIR";     ok "a folder without CLAUDE.md or code/ is not a project"
run_file Write "$CORE_DIR/.git/code/CLAUDE.md" "$CORE_DIR";           ok "dot-folder of the Core"
run_file Write "$C" "$C";                                             ok "the code folder itself"
run_bash 'echo x > CLAUDE.md' "$SANDBOX/elsewhere";                   ok "Bash outside the Core"
run_bash 'echo x > docs/a.md' "$CORE_DIR";                            ok "Bash with cwd = Core root, target nonexistent project"
run_bash 'echo x > docs/a.md' "$CORE_DIR/p";                          ok "Bash in the project folder: docs/ is the Core's own"
run_bash 'echo x > CLAUDE.md' "$CORE_DIR/p";                          ok "Bash in the project folder: CLAUDE.md is the Core's own"

# --- input the hook cannot judge passes (exit 0, silent)
for in in '' 'not json at all' '{}' '[]' 'null' '{"cwd":"'"$C"'"}' '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{}}' \
          '{"tool_name":"Write","tool_input":{"file_path":"'"$C"'/CLAUDE.md"}}' \
          '{"cwd":"","tool_name":"Write","tool_input":{"file_path":"'"$C"'/CLAUDE.md"}}' \
          '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":42}}' \
          '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":""}}' \
          '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":"'"$C"'/CLAUDE.md' \
          '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":"'"$C"'/CLAUDE.md\' \
          '{"cwd":"'"$C"'","tool_name":"Bash","tool_input":{}}' '{"cwd":"'"$C"'","tool_name":"Bash","tool_input":{"command":""}}' \
          '{"cwd":"'"$C"'","tool_name":"Bash","tool_input":{"command":7}}' \
          '{"cwd":"'"$C"'","tool_name":"NotebookEdit","tool_input":{"file_path":"'"$C"'/CLAUDE.md"}}' \
          '{"cwd":"unterminated'; do
  run_json "$in"; ok "unjudgeable input passes: $in"
done
OUT="$(bash "$H" </dev/null 2>&1)"; assert_eq "$?" "0" "closed stdin"
# a tool the hook does not know and no path in it
# only Write, Edit, MultiEdit and NotebookEdit are file tools; any other tool passes
for tl in Read Grep Glob WebFetch Task ''; do
  run_json '{"cwd":"'"$C"'","tool_name":"'"$tl"'","tool_input":{"file_path":"'"$C"'/CLAUDE.md","notebook_path":"'"$C"'/CLAUDE.md","command":"echo x > CLAUDE.md"}}'; ok "tool '$tl' is not judged"
done
run_json '{"cwd":"'"$C"'","tool_input":{"file_path":"'"$C"'/CLAUDE.md"}}'; ok "no tool_name"
run_file MultiEdit "$C/docs/a.md";           blocked "MultiEdit docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file MultiEdit "$C/src/a.sh";            ok "MultiEdit src/a.sh"


# --- <> opens a file for reading AND writing and creates it: it is a write target (it used to pass)
run_bash 'exec 3<> docs/x.md';               blocked "Bash exec 3<> docs/x.md" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_bash 'cat <> docs/rw.md';                blocked "Bash cat <> docs/rw.md" "$C/docs/rw.md" "$CORE_DIR/p/docs/rw.md"
run_bash 'cat <> src/rw.md';                 ok "Bash cat <> src/rw.md"

# --- a "<<" that ends a double-quoted string is not a heredoc: the judging goes on
run_bash 'grep -n \"<<\" f.sh; echo x > docs/a.md'; blocked "Bash \"<<\" as a string, then a write" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'grep -n \"<<\" f.sh'; ok "Bash \"<<\" as a string"

# --- if scripts/*.awk is missing, the Bash path fails open (silently); file tools are still judged
PL="$SANDBOX/plugin-noawk"; mkdir -p "$PL/hooks" "$PL/scripts"
cp "$HOOKS/guard-code.sh" "$PL/hooks/"; cp "$SCRIPTS/lib.sh" "$PL/scripts/"; cp "$HOOKS/messages.sh" "$PL/hooks/"
printf '%s' '{"cwd":"'"$C"'","tool_name":"Bash","tool_input":{"command":"echo x > docs/a.md"}}' | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "0" "no awk files: Bash passes"; assert_eq "$(<"$OD/out")$(<"$OD/err")" "" "no awk files: silent"
printf '%s' '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":"'"$C"'/docs/a.md"}}' | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no awk files: file tools are still judged"


bg_wait

finish
