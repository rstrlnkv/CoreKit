#!/usr/bin/env bash
# hooks/guard-code.sh: a project's internal files (CLAUDE.md, docs/**, .claude/**) must not be
# written under the project's code folder: <Projects>/<Name>/** (new layout, beside the Core) or
# <Core>/<project>/code/** (old layout). Write|Edit|NotebookEdit read the path from the tool input;
# Bash is judged best effort (redirects, tee, touch, cp, mv, mkdir). Inert outside the Core project.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/guard-code.sh"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR

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
  printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\n' "$1" "$2"
  printf 'Docs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' "${1%%/code/*}/CLAUDE.md"
}
# ok <label> — exit 0, silent
ok() { assert_eq "$RC" "0" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "" "$1: stderr"; }
# blocked <label> <path shown> <target in the Core> — exit 2, the exact message, nothing on stdout
blocked() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "$(msg "$2" "$3")" "$1: message"; }
# blocked_any <label> — exit 2, nothing on stdout, a non-empty message (Codex ignores exit 2 with an empty one)
blocked_any() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; [ -n "$ERR" ] && pass || fail "$1: empty stderr"; }


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
QW="$CORE_DIR/q/code"; mkdir -p "$QW/.claude/worktrees/w9/.claude/worktrees/v"   # a Write to a path that is not an existing dir is a file
run_file Write "$QW/.claude/worktrees/w9";       ok "the worktree dir itself (it exists)"
run_file Write "$C/.claude/worktrees/w2/";       ok "another worktree dir, trailing slash"
run_file Write "$QW/.claude/worktrees";          ok "worktrees dir (it exists)"
run_file Write "$C/.claude/worktrees/w/src/a.sh";ok "worktree ordinary code"
run_file Write "$C/.claude/worktrees/w/.claude/settings.local.json"; ok "worktree settings.local.json"
run_file Write "$QW/.claude/worktrees/w9/.claude/worktrees/v"; ok "worktree inside a worktree"

# --- nested CLAUDE.md: blocked at any depth, like the git pre-commit hook; CLAUDE.local.md too
run_file Write "$C/src/CLAUDE.md";           blocked "nested CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/deep/CLAUDE.md";      blocked "deeper CLAUDE.md" "$C/src/deep/CLAUDE.md" "$CORE_DIR/p/src/deep/CLAUDE.md"
run_file Write "$C/CLAUDE.local.md";         blocked "CLAUDE.local.md" "$C/CLAUDE.local.md" "$CORE_DIR/p/CLAUDE.local.md"
run_file Write "$C/src/CLAUDE.local.md";     blocked "nested CLAUDE.local.md" "$C/src/CLAUDE.local.md" "$CORE_DIR/p/src/CLAUDE.local.md"
run_file Write "$C/.claude/worktrees/w/src/CLAUDE.md"
blocked "worktree nested CLAUDE.md" "$C/.claude/worktrees/w/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/MYCLAUDE.md";         ok "name that only ends like CLAUDE.md"
run_file Write "$C/src/CLAUDE.md.bak";       ok "CLAUDE.md.bak"
# --- AGENTS.md (the cross-tool agent instructions): the same as CLAUDE.md, at any depth
run_file Write "$C/AGENTS.md";               blocked "AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Edit "$C/AGENTS.md";                blocked "Edit AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$C/src/deep/AGENTS.md";      blocked "nested AGENTS.md" "$C/src/deep/AGENTS.md" "$CORE_DIR/p/src/deep/AGENTS.md"
run_file Write "$C/agents.md";               blocked "agents.md lower case" "$C/agents.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$C/src/Agents.MD";           blocked "nested Agents.MD mixed case" "$C/src/Agents.MD" "$CORE_DIR/p/src/AGENTS.md"
run_file Write "$C/.claude/worktrees/w/AGENTS.md"
blocked "worktree AGENTS.md" "$C/.claude/worktrees/w/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$CORE_DIR/p/AGENTS.md";      ok "Core project AGENTS.md"
run_file Write "$C/src/MYAGENTS.md";         ok "name that only ends like AGENTS.md"
run_file Write "$C/AGENTS.md.bak";           ok "AGENTS.md.bak"
run_file Write "$C/docs-agents/AGENTS.txt";  ok "AGENTS.txt"
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
# docs/superpowers stays private under a public docs/ (.gitignore and the pre-commit hook keep it out of git)
run_file Write "$Q/docs/superpowers/plans/p.md"; blocked "public-docs: docs/ does not open docs/superpowers" "$Q/docs/superpowers/plans/p.md" "$CORE_DIR/q/docs/superpowers/plans/p.md"
run_file Write "$Q/Docs/SuperPowers/x.md";    blocked "docs/superpowers in another letter case" "$Q/Docs/SuperPowers/x.md" "$CORE_DIR/q/docs/SuperPowers/x.md"
run_file Write "$Q/docs/superpowers-notes.md"; ok "public-docs: docs/superpowers-notes.md is not docs/superpowers"
run_file Write "$Q/CLAUDE.md";               blocked "public-docs: docs/ does not open CLAUDE.md" "$Q/CLAUDE.md" "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/AGENTS.md";               blocked "public-docs: docs/ does not open AGENTS.md" "$Q/AGENTS.md" "$CORE_DIR/q/AGENTS.md"
run_file Write "$Q/.claude/rules/x.md";      blocked "public-docs: docs/ does not open .claude" "$Q/.claude/rules/x.md" "$CORE_DIR/q/.claude/rules/x.md"
run_file Write "$Q/docsx/a.md";              ok "docsx is not blocked at all"
printf '# q\r\npublic-docs: README.md docs/guide.md, `docs/api/` ./CLAUDE.local.md\r\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/guide.md";           ok "public-docs: a file entry"
run_file Write "$Q/docs/api/v1/a.md";        ok "public-docs: a dir entry among several (comma, backticks, CRLF)"
run_file Write "$Q/CLAUDE.local.md";         ok "public-docs: ./ prefix"
printf '# q\npublic-docs: AGENTS.md\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/AGENTS.md";               ok "public-docs: AGENTS.md listed on purpose"
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
  skip "core_dir letter case" "case-sensitive volume"; pass
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
run_bash 'echo x > AGENTS.md';                blocked "Bash > AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_bash 'cp /tmp/AGENTS.md src/';           blocked "Bash cp AGENTS.md into src/" "$C/src/AGENTS.md" "$CORE_DIR/p/src/AGENTS.md"
run_bash 'touch AGENTS.md';                  blocked "Bash touch AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_bash 'cat AGENTS.md';                    ok "Bash reading AGENTS.md passes"
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
# the apply_patch reader (patch-paths.awk) is missing: no path is read, nothing can be judged, every patch is refused
pj() { printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Add File: %s\\n+x\\n*** End Patch"}}' "$C" "$1"; }
pj docs/a.md | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no patch-paths.awk: apply_patch on docs/ is refused (fails closed)"
[ -s "$OD/err" ] && pass || fail "no patch-paths.awk: empty stderr on exit 2"
pj src/a.swift | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no patch-paths.awk: a harmless apply_patch is refused too (nothing can be judged)"
assert_contains "$OD/err" "patch-paths.awk is missing or failed"


# --- new layout: the code lives in <Projects>/<Name>, the private CLAUDE.md in the Core
sec_new_layout() {
  local PR="$SANDBOX/Projects" N="$SANDBOX/Projects/Foo" W
  mkdir -p "$N/src" "$N/.claude" "$CORE_DIR/foo/docs" "$PR/Brain"
  echo '# foo' > "$CORE_DIR/foo/CLAUDE.md"; : > "$PR/Brain/CLAUDE.md"
  ln -s "$CORE_DIR/foo/CLAUDE.md" "$N/CLAUDE.local.md"
  local nmsg
  nmsg() { printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\nDocs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' "$1" "$2" "$CORE_DIR/foo/CLAUDE.md"; }
  run_file Write "$N/CLAUDE.md" "$N"; assert_eq "$RC" "2" "new: Write CLAUDE.md"; assert_eq "$ERR" "$(nmsg "$N/CLAUDE.md" "$CORE_DIR/foo/CLAUDE.md")" "new: message"
  run_file Write "$N/docs/x.md" "$N"; assert_eq "$RC" "2" "new: Write docs/x.md"
  run_file Write "$N/.claude/worktrees/w/docs/x.md" "$N"; assert_eq "$RC" "2" "new: worktree docs/x.md"
  run_file Write "$N/.claude/settings.local.json" "$N"; ok "new: settings.local.json"
  run_file Write "$N/src/a.sh" "$N"; ok "new: src/a.sh"
  run_file Edit "$N/CLAUDE.local.md" "$N"; ok "new: Edit through the CLAUDE.local.md symlink"
  run_file Write "$(printf '%s' "$N" | tr 'F' 'f')/docs/x.md" "$N"; assert_eq "$RC" "2" "new: other letter case"
  run_file Write "$PR/Brain/CLAUDE.md" "$PR/Brain"; ok "new: a folder that is not a project"
  run_bash 'echo x > docs/a.md' "$N"; assert_eq "$RC" "2" "new: Bash echo x > docs/a.md"
  run_bash 'echo x > src/a.md' "$N"; ok "new: Bash src/a.md"
  printf 'public-docs: docs/\n' >> "$CORE_DIR/foo/CLAUDE.md"
  run_file Write "$N/docs/x.md" "$N"; ok "new: public-docs"
  run_file Write "$N/CLAUDE.md" "$N"; assert_eq "$RC" "2" "new: public-docs does not free CLAUDE.md"
  # Russian text has no code/
  CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run_file Write "$N/CLAUDE.md" "$N"
  case "$ERR" in *"code/"*) fail "new: ru message names code/" ;; *) pass "new: ru message has no code/" ;; esac
}
bg sec_new_layout

# new layout with a space and non-ASCII in the Projects path, and two folders that differ only in case
sec_new_odd_path() {
  local PR="$SANDBOX/Мои проекты x" N
  export CORE_DIR="$PR/Core"; N="$PR/Foo"
  mkdir -p "$N/src" "$CORE_DIR/foo" "$PR/FOO"
  echo '# foo' > "$CORE_DIR/foo/CLAUDE.md"
  run_file Write "$N/docs/x.md" "$N"; assert_eq "$RC" "2" "odd path: Write docs/x.md"
  assert_eq "$ERR" "$(printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\nDocs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' "$N/docs/x.md" "$CORE_DIR/foo/docs/x.md" "$CORE_DIR/foo/CLAUDE.md")" "odd path: message"
  run_file Write "$N/src/a.sh" "$N"; ok "odd path: src/a.sh"
}
bg sec_new_odd_path

# Codex: apply_patch and a patch handed to Bash (fixtures built from the rust-v0.166.0 structs)
FX="$ROOT/tests/fixtures/codex"
mkdir -p "$CORE_DIR/r/code/docs" "$CORE_DIR/r/code/sub"; printf 'public-docs: docs/pub/\n' > "$CORE_DIR/r/CLAUDE.md"
sec_codex() {
  local R="$CORE_DIR/r/code" q
  # fx <fixture> [cwd] — runs a fixture with @CWD@ replaced
  fx() { run_json "$(sed "s|@CWD@|${2-$C}|g" "$FX/$1.json")"; }
  # patch <patch text> [cwd] [tool] — a Codex tool call with the given patch text
  patch() {
    local t="$1"; t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\n'/\\n}"
    run_json "$(printf '{"session_id":"s","turn_id":"turn-1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"}}' "${2-$C}" "${3-apply_patch}" "$t")"
  }
  # bigjson <paths> <tool> — a hook input with that many harmless Add File entries, built by awk (bash 3.2 is
  # quadratic on a string this long)
  bigjson() {
    awk -v n="$1" -v tool="$2" -v cwd="$C" 'BEGIN {
      printf "{\"session_id\":\"s\",\"turn_id\":\"turn-1\",\"cwd\":\"%s\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"%s\",\"tool_input\":{\"command\":\"", cwd, tool
      if (tool == "Bash") printf "apply_patch <<\x27EOF\x27\\n"
      printf "*** Begin Patch\\n"
      for (i = 1; i <= n; i++) printf "*** Add File: src/f%d.c\\n+x\\n", i
      printf "*** End Patch"
      if (tool == "Bash") printf "\\nEOF"
      printf "\"}}" }' > "$OD/big.json"
  }
  local nl=$'\n' B='*** Begin Patch' E='*** End Patch'
  fx pre-apply-patch-add;    blocked "codex add docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-update; blocked "codex update CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  fx pre-apply-patch-delete; ok "codex delete docs/a.md passes"
  fx pre-apply-patch-move;   blocked "codex move into docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-multi;  blocked "codex multi names the internal path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-secret; ok "codex .env is not guard-code's business"
  patch "$B${nl}*** Add File: AGENTS.md${nl}+x${nl}$E"; blocked "codex AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  patch "$B${nl}*** Add File: .claude/rules/x.md${nl}+x${nl}$E"; blocked "codex .claude/rules" "$C/.claude/rules/x.md" "$CORE_DIR/p/.claude/rules/x.md"
  patch "$B${nl}*** Update File: docs/a.md${nl}*** Move to: src/a.md${nl}@@${nl}-a${nl}+b${nl}$E"; ok "codex move out of docs passes"
  patch "$B${nl}*** Add File: docs/pub/a.md${nl}+x${nl}$E" "$R"; ok "codex public-docs entry passes"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$R"; assert_eq "$RC" "2" "codex public-docs does not cover the rest of docs/"
  patch "$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}*** Add File: src/b.swift${nl}+x${nl}*** Update File: .claude/settings.local.json${nl}@@${nl}-a${nl}+b${nl}$E"; ok "codex legitimate patch"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$C/src"; ok "codex relative docs/a.md from src/ is src/docs/a.md, not the root docs"
  patch "$B${nl}*** Add File: ../docs/a.md${nl}+x${nl}$E" "$C/src"; blocked "codex ../docs/a.md from src/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$SANDBOX/elsewhere"; ok "codex outside a project is inert"
  patch "hello, not a patch"; ok "codex unparseable text passes"
  patch ""; ok "codex empty command passes"
  patch "$B${nl}*** Add File: src/a.md${nl}+see docs/a.md and CLAUDE.md${nl}+*** Add File: docs/x${nl}$E"; ok "codex content lines mentioning docs/ pass"
  patch "$B${nl}*** Bogus${nl}*** Add File: docs/a.md${nl}$E"; blocked "codex a path before an unknown line is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # the Codex shell
  fx pre-bash; ok "codex Bash without a patch passes"
  fx pre-bash-subagent; ok "codex Bash in a subagent: no ro_agent for a Codex agent_type"
  # A patch handed to the shell is refused with one message, wherever it points: a patch run through the Bash command line cannot be checked
  # (each of these was a bypass of the old path judging)
  local SM="corecrew: run patches with the apply_patch tool, not through the Bash command line; that form cannot be checked"
  refused() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; case "$ERR" in "$SM"*) pass ;; *) fail "$1: message: $ERR" ;; esac; }
  fx pre-bash-applypatch-heredoc; refused "codex Bash apply_patch heredoc"
  fx pre-bash-applypatch-quotedarg; refused "codex Bash apply_patch quoted arg"
  fx pre-bash-applypatch-cd; refused "codex Bash cd sub && apply_patch"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}${E}${nl}EOF" "$C" Bash; refused "codex Bash even a harmless heredoc patch"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Delete File: docs/a.md${nl}${E}${nl}EOF" "$C" Bash; refused "codex Bash delete patch"
  # no scope gate: a patch run through the Bash command line is refused in every folder (a cwd or wrapper gate was bypassed twice)
  local O="$SANDBOX/elsewhere" PR; PR="$(dirname "$C")"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Add File: $D${nl}+x${nl}${E}${nl}EOF" "$O" Bash; refused "codex Bash plain relative apply_patch outside a project"
  patch "cd $C && apply_patch <<'EOF'${nl}$B${nl}*** Add File: $D${nl}+x${nl}${E}${nl}EOF" "$O" Bash; refused "codex Bash cd /project && apply_patch from outside"
  patch "cd sub && apply_patch <<'EOF'${nl}x${nl}EOF" "$O" Bash; refused "codex Bash cd sub && apply_patch from outside"
  patch "c''d $C && apply_patch" "$O" Bash; refused "codex Bash quoted cd from outside"
  patch "env -C $C apply_patch" "$O" Bash; refused "codex Bash env -C from outside"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Add File: $(basename "$C")/$D${nl}+x${nl}${E}${nl}EOF" "$PR" Bash; refused "codex Bash Proj/docs/x.md from the Projects folder"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Add File: ~/$D${nl}+x${nl}${E}${nl}EOF" "$O" Bash; refused "codex Bash ~ path in the patch from outside"
  patch "apply_patch \"\$(cat p)\"" "$O" Bash; refused "codex Bash \$ from outside"
  patch "$C/bin/apply_patch" "$O" Bash; refused "codex Bash absolute command from outside"
  patch "grep -rn apply_patch src" "$O" Bash; ok "codex Bash reader twin outside a project passes"
  patch "apply_patch <<'EOF'${nl}x${nl}EOF" "$C" Bash; refused "codex Bash plain relative apply_patch inside a project"
  for P in "cd src && " "cd . && " "cd && " "cd \$X && " "cd - && " "cd nonexistent; " "( cd src ); " "popd; " "pushd src && " "cd \$OLDPWD && " "echo cd; " "git log --grep='cd'; "; do
    patch "${P}apply_patch <<'EOF'${nl}$B${nl}*** Add File: $D${nl}+x${nl}${E}${nl}EOF" "$C" Bash; refused "codex Bash prefix [$P]"
  done
  for P in "do''cs/a.md" ".e''nv" "\$X" "\$(printf docs)/a.md" 'd${Z}ocs/a.md' '`echo docs`/a.md' 'docs\/a.md'; do
    patch "X=docs; apply_patch <<EOF${nl}$B${nl}*** Add File: $P${nl}+x${nl}${E}${nl}EOF" "$C" Bash; refused "codex Bash unquoted heredoc, path $P"
  done
  patch "apply_patch <<EOF${nl}$B${nl}*** Add File: src/a${nl}\$(printf '*** Add File: docs/a.md')${nl}${E}${nl}EOF" "$C" Bash; refused "codex Bash \$(...) in a heredoc body forging a header"
  patch "apply_patch \$'$B\\n*** Add File: CLAUDE.md\\n+x\\n$E'" "$C" Bash; refused "codex Bash \$'..\\n..' one-line patch"
  patch "printf '%s\\n' '$B' '*** Add File: $D' '+x' '$E' | apply_patch" "$C" Bash; refused "codex Bash printf-piped patch"
  patch "printf '%s\\n' '$B' '*** Add File: src/a.swift' '+x' '$E' | apply_patch" "$C" Bash; refused "codex Bash printf-piped harmless patch"
  patch "apply_patch \"\$(printf '$B\\n*** Add File: .claude/rules/x.md\\n$E')\"" "$C" Bash; refused "codex Bash \"\$(printf ...)\" patch"
  patch "cat p.txt | apply_patch" "$C" Bash; refused "codex Bash cat p.txt | apply_patch"
  patch "apply_patch \"\$(cat p.txt)\"" "$C" Bash; refused "codex Bash apply_patch \"\$(cat p.txt)\""
  patch "apply_patch < p.txt" "$C" Bash; refused "codex Bash apply_patch < p.txt"
  patch "echo '*** Begin Pat''ch' | apply_patch" "$C" Bash; refused "codex Bash quote-split Begin Patch into apply_patch"
  patch "apply_pa''tch <<'EOF'${nl}x${nl}EOF" "$C" Bash; refused "codex Bash quote-split apply_patch"
  for P in applypatch apply-patch /usr/local/bin/apply_patch "sudo apply_patch" "env X=1 apply_patch" "FOO=1 apply_patch" "time apply_patch" "command apply_patch" "xargs apply_patch" "xargs -0 -n1 apply_patch" "alias ap=apply_patch; ap" "F=apply_patch; \$F" "eval apply_patch" "bash -c apply_patch" "sh -c 'cat p | apply_patch'"; do
    patch "$P <<'EOF'${nl}x${nl}EOF" "$C" Bash; refused "codex Bash spelling [$P]"
  done
  patch "cat > src/fixture.txt <<'EOF'${nl}$B${nl}*** Add File: $D${nl}$E${nl}EOF" "$C" Bash; refused "LIMIT: a heredoc that writes patch text to src/ is a hit outside the simple form (over-block)"
  patch "cat > src/fixture.txt <<'EOF'${nl}$B${nl}*** Add File: $D${nl}$E${nl}EOF${nl}sh src/fixture.txt" "$C" Bash; refused "codex Bash patch text written to a file, then a shell: not all readers"
  patch "git commit -m \"$B${nl}*** Add File: src/a.swift\"" "$C" Bash; ok "a multi-line commit message that quotes a patch header is quoted text and passes"
  # legitimate twins: reading, searching and talking about apply_patch or a patch is not applying one
  for P in "grep -rn apply_patch src" "grep -rn apply_patch src | head" "rg 'apply_patch' tests" "rg '\\*\\*\\* Begin Patch' tests" "git log --grep=apply_patch" "git log --grep apply-patch" "git commit -m \"fix apply_patch docs\"" "git commit -m 'applypatch: Begin Patch notes'" "echo '$B' | wc -l" "cat src/a.swift" "ls apply_patch_notes"; do
    patch "$P" "$C" Bash; ok "codex Bash twin [$P] passes"
  done
  # the apply_patch TOOL still edits src/ files
  patch "$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}*** Add File: src/b.swift${nl}+x${nl}$E"; ok "codex apply_patch tool on src/ files passes"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E"; blocked "codex apply_patch tool on docs/ is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "echo '*** Begin Patch' | wc -l" "$C" Bash; ok "codex Bash mentioning Begin Patch without paths passes"
  # --- tester: inputs nobody fed
  local D="docs/a.md" P
  # several patches / blocks in one text
  patch "$B${nl}*** Add File: a${nl}+x${nl}$E${nl}$B${nl}*** Add File: $D${nl}+x${nl}$E"; blocked "codex two Begin blocks: the second is judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "echo '$B'" "$C" Bash; ok "codex Bash echo of Begin Patch alone passes"
  patch "echo '$B' > src/notes.txt" "$C" Bash; ok "codex Bash echo of Begin Patch into src/ passes"
  patch "echo '$B' > docs/notes.txt" "$C" Bash; blocked "codex Bash echo of Begin Patch into docs/ is still the redirect rule" "$C/docs/notes.txt" "$CORE_DIR/p/docs/notes.txt"
  # the patch inside a shell wrapper
  # path spellings
  for P in ./docs/../docs/a.md src/../docs/a.md docs//a.md ./docs/a.md; do
    patch "$B${nl}*** Add File: $P${nl}+x${nl}$E"; blocked "codex path $P" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  done
  patch "$B${nl}*** Add File: docs/${nl}+x${nl}$E"; blocked "codex path with a trailing slash" "$C/docs" "$CORE_DIR/p/docs"
  ln -s "$C" "$OD/linkcode"; ln -s "$CORE_DIR/p/docs" "$OD/linkdocs"
  patch "$B${nl}*** Add File: $OD/linkcode/docs/a.md${nl}+x${nl}$E"; blocked "codex absolute path through a symlinked folder into code/docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File: $OD/linkdocs/a.md${nl}+x${nl}$E"; ok "codex absolute path through a symlink into the Core's docs is the right place"
  ln -s "$C/docs" "$C/src/dl"
  patch "$B${nl}*** Add File: src/dl/a.md${nl}+x${nl}$E"; blocked "codex relative path through a symlink inside the tree" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # header spellings
  patch "$B${nl}*** Add File:$D${nl}+x${nl}$E"; blocked "codex no space after the colon" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File:	$D${nl}+x${nl}$E"; blocked "codex a tab after the colon" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}	*** Add File: $D${nl}+x${nl}$E"; blocked "codex a tab-indented header" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B"$'\r'"${nl}*** Add File: $D"$'\r'"${nl}+x"$'\r'"${nl}$E"$'\r'; blocked "codex CRLF line ends" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "*** ADD FILE: $D"; blocked_any "codex uppercase header: unreadable text with an internal path in a *** line is refused"
  assert_eq "$ERR" "corecrew: the patch cannot be judged: its text cannot be read, and the line \"*** ADD FILE: $D\" names an internal path. Use the apply_patch tool and lines like \"*** Add File: <full path>\"." "codex unreadable patch: the message quotes the offending line"
  # raw JSON: \r\n, \t and a \/ in the string
  run_json "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\r\\n*** Add File:\\tdocs\\/a.md\\r\\n+x\\r\\n*** End Patch\\r\\n"}}' "$C")"
  blocked "codex raw JSON escapes \\r\\n \\t \\/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # a move whose source is harmless and destination internal; a move out of docs; a second Move to
  patch "$B${nl}*** Update File: src/a${nl}*** Move to: $D${nl}@@${nl}-a${nl}+b${nl}$E"; blocked "codex move into docs from src" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  for P in "man apply_patch" "which apply_patch" "FOO=apply_patch_x make"; do
    patch "$P" "$C" Bash; refused "LIMIT: [$P] is a hit outside the allowlist (over-block)"
  done
  # non-string command: nothing to read, passes (as an unreadable text)
  run_json "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":null}}' "$C")"; ok "codex command null passes"
  run_json "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":5}}' "$C")"; ok "codex command number passes"
  run_json "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":["x"]}}' "$C")"; ok "codex command array passes"
  # pinned limit: a heredoc that merely writes patch text into a file is judged like a patch (over-block)
  # one-line and constructed patches: no header at line start, so the text after each marker is checked
  patch "grep -rn apply_patch src | head" "$C" Bash; ok "codex Bash grep for the word apply_patch passes"
  patch "echo apply_patch > src/notes.txt" "$C" Bash; refused "LIMIT: echo of the word apply_patch is a hit outside the simple form (over-block)"
  patch "sed s/a/apply_patch/ f" "$C" Bash; refused "LIMIT: sed is no reader: sed with the word apply_patch is refused"
  patch "git -c core.x=1 log --grep=apply_patch" "$C" Bash; refused "LIMIT: git with an option before the subcommand is no reader"
  # unreadable (X) patch: the *** lines are checked raw for an internal target
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}junk *** Add File: docs/a.md${nl}$E"; blocked_any "codex junk before a docs/ header (X) is refused"
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}junk *** Add File: src/b.swift${nl}$E"; ok "codex junk before a src/ header (X) passes"
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}$(printf '\302\240')*** Add File: docs/a.md${nl}$E"; blocked "codex NBSP-indented header (trimmed like Codex)" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}$(printf '\343\200\200')*** Add File: AGENTS.md${nl}+x${nl}$E"; blocked "codex U+3000-indented header" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  patch "$B${nl}*** Add File: docs/a.md$(printf '\f')${nl}+x${nl}$E"; blocked "codex trailing form feed in the path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$(printf '\f')$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E"; blocked "codex leading form feed before Begin" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # the cap: the 101st path blocks (was a DEFECT: the adapter dropped it), 5000 paths are refused fast with the split message
  local big="$B${nl}" i=1; while [ "$i" -le 100 ]; do big="$big*** Add File: src/f$i.txt${nl}+x${nl}"; i=$((i + 1)); done
  patch "$big*** Add File: $D${nl}+x${nl}$E"; blocked_any "codex 101st path (docs/a.md) is refused"
  patch "$big*** Add File: src/last.txt${nl}+x${nl}$E"; blocked_any "codex 101 harmless paths are refused"
  grep -q 'at most 100' "$OD/err" && pass || fail "the cap message must say at most 100 files: $ERR"
  local t0=$SECONDS
  bigjson 5000 apply_patch; run_json "$(<"$OD/big.json")"; blocked_any "codex 5000 harmless paths are refused"
  [ $((SECONDS - t0)) -lt 10 ] && pass || fail "5000 paths took $((SECONDS - t0)) s (hook timeout 15 s)"
  grep -q 'at most 100' "$OD/err" && pass || fail "the cap message must say at most 100 files"
  t0=$SECONDS
  bigjson 5000 Bash; run_json "$(<"$OD/big.json")"; refused "codex Bash 5000 paths are refused as a shell patch"
  [ $((SECONDS - t0)) -lt 10 ] && pass || fail "Bash form: 5000 paths took $((SECONDS - t0)) s (hook timeout 15 s)"
  # every exit-2 path writes a non-empty stderr (Codex ignores exit 2 with an empty one)
  fx pre-apply-patch-add; [ -n "$ERR" ] && pass || fail "exit 2 with an empty stderr"
}
bg sec_codex

# The shell-patch refusal runs only in Codex: the plugin installed under CODEX_HOME (host), or a hook input with
# Codex's turn_id (a dev install whose path says nothing). Claude Code has no apply_patch tool, so there everyday glob
# commands, and even the word apply_patch, pass, outside a project and inside one.
sec_host_gate() {
  local O="$OD/not a project" c h nl=$'\n'
  mkdir -p "$O"
  js() { local t="$1"; t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\n'/\\n}"; t="${t//$'\t'/\\t}"; printf '%s' "$t"; }
  cl() { run_json "$(printf '{"session_id":"s","transcript_path":"/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"toolu_1"}' "$2" "$(js "$1")")"; }
  cx() { run_json "$(printf '{"session_id":"s","turn_id":"turn-1","transcript_path":null,"cwd":"%s","hook_event_name":"PreToolUse","model":"gpt-5","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"call_1"}' "$2" "$(js "$1")")"; }
  local SM="corecrew: run patches with the apply_patch tool, not through the Bash command line; that form cannot be checked"
  named() { # named <label> <match> — exit 2, the message starts with the refusal and names the match
    assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"
    case "$ERR" in "$SM"*) pass ;; *) fail "$1: message: $ERR" ;; esac
    case "$ERR" in *"$2"*) pass ;; *) fail "$1: the message does not name [$2]: $ERR" ;; esac
  }
  local everyday=( 'wc -l a/* b/* 2>/dev/null | tail -1' 'cd x && ls scripts/* && cat .claude-plugin/marketplace.json' \
    'rm -rf dist/* && npm run build' 'cp assets/* public/' 'chmod +x bin/*' 'du -sh * | sort -h' \
    "cat > f.js <<'EOF'${nl}const y = a * b;${nl}console.log(\"*\", 'it''s');${nl}EOF${nl}node f.js" \
    "git commit -m \"\$(cat <<'EOF'${nl}Fix things${nl}${nl}* bullet one${nl}* bullet two${nl}EOF${nl})\"" \
    "gh pr create --title x --body \"\$(cat <<'EOF'${nl}## Summary${nl}* item${nl}EOF${nl})\"" \
    "case \"\$a\" in${nl}  *.md) echo md ;;${nl}  *) echo other ;;${nl}esac" 'echo $(( $(wc -l < f) * 2 ))' )
  for c in "${everyday[@]}"; do
    for h in "$O" "$C"; do
      cl "$c" "$h"; ok "claude Bash [$c] in $h passes"
      cx "$c" "$h"; ok "codex Bash [$c] in $h passes (a wildcard argument is no command)"
    done
  done
  # Claude Code: the word, and a shell line that would run a program named apply_patch, are the person's own business
  for c in 'cd src && grep -rn apply_patch .' 'echo apply_patch > notes.txt' 'apply_patch x' '../bin/apply_pat?h x'; do
    for h in "$O" "$C"; do cl "$c" "$h"; ok "claude Bash [$c] in $h passes"; done
  done
  # Codex: real shell patches are still refused, outside a project and inside, and the message names the match
  for h in "$O" "$C"; do
    cx "apply_patch <<'EOF'${nl}*** Begin Patch${nl}*** Add File: src/a${nl}+x${nl}*** End Patch${nl}EOF" "$h"; named "codex heredoc apply_patch in $h" "apply_patch"
    cx 'cd bin && ./app*y_patch x' "$h"; named "codex glob command in $h" "./app*y_patch"
    cx 'ls && * x' "$h"; named "codex bare wildcard as a command in $h" "*"
    cx 'sudo ../bin/apply_pat?h x 2>/dev/null' "$h"; named "codex glob spelling the name after a wrapper in $h" "../bin/apply_pat?h"
    cx "bash <<EOF${nl}cd src && apply_patch x${nl}EOF" "$h"; named "codex the name in a heredoc body fed to bash in $h" "apply_patch"
  done
  # the install path alone says Codex (COREKIT_HOST stands in for it): a Claude-shaped input is refused there too
  COREKIT_HOST=codex cl 'cat p | apply_patch' "$C"; named "host codex without turn_id" "apply_patch"
  COREKIT_HOST=claude cl 'cat p | apply_patch' "$C"; ok "host claude without turn_id passes"
  COREKIT_HOST=claude cx 'cat p | apply_patch' "$C"; named "turn_id says Codex even when the path does not (fails closed)" "apply_patch"
}
bg sec_host_gate

bg_wait

finish
