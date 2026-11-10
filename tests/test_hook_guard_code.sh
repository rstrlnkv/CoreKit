#!/usr/bin/env bash
# hooks/guard-code.sh: a project's internal files (CLAUDE.md, docs/**, .claude/**) must not be
# written under the project's code folder: <Projects>/<Name>/** (beside the Core; the old layout of corecrew 0.4,
# <Core>/<project>/code, is no code root any more). Write|Edit|NotebookEdit read the path from the tool input;
# Bash is judged best effort for honest mistakes (ADR 009): redirects, tee, touch, mkdir, cp, mv, install, ln,
# in-place sed and perl, git mv. Deliberate evasion is a documented limit (the LIMIT cases below). Inert outside the Core project.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
H="$HOOKS/guard-code.sh"
assert_file "$H"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR

PRJ="$(dirname "$CORE_DIR")"   # <Projects>: the code folders <Projects>/<name> live beside the Core
mkdir -p "$PRJ/p/src" "$CORE_DIR/p/docs" "$PRJ/q" "$CORE_DIR/q" "$SANDBOX/elsewhere"
: > "$CORE_DIR/p/CLAUDE.md"; : > "$CORE_DIR/q/CLAUDE.md"
C="$PRJ/p"

# The sections below that share nothing run at the same time (bg <function>, lib.sh): each in a subshell with
# its own scratch folder OD and its own counts. This keeps the file near 5 s (a hook run is about 40 ms and
# there are about 350 of them). The foreground uses OD="$SANDBOX".
OD="$SANDBOX"

# run_hook, hook_ok, hook_blocked_any, hook_refused_patch and hook_event: tests/lib-hook.sh
# run_file <tool> <path> [cwd] — Write, Edit or NotebookEdit; the path is put in the JSON as is
run_file() {
  local key=file_path; [ "$1" = NotebookEdit ] && key=notebook_path
  run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "${3-$C}" "$1" "$key" "$2")"
}
# run_bash <json-escaped command> [cwd]
run_bash() { run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2-$C}" "$1")"; }
# The second line points at public-docs: in the project's CLAUDE.md: the Core project folder <Core>/<p> of the target,
# the nearest folder above it that holds a CLAUDE.md (no fixture puts one deeper in a Core project).
msg() {
  local d="${2%/*}"
  while [ -n "$d" ] && [ ! -f "$d/CLAUDE.md" ]; do d="${d%/*}"; done
  printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\n' "$1" "$2"
  printf 'Docs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' "$d/CLAUDE.md"
}
# blocked <label> <path shown> <target in the Core> — exit 2, the exact message, nothing on stdout
blocked() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "$(msg "$2" "$3")" "$1: message"; }


# Write, Edit, NotebookEdit: paths, worktrees, public-docs, symlinks
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
run_file Write "$C/.claude/settings.local.json"; hook_ok "settings.local.json"
run_file Write "$C/src/a.sh";                    hook_ok "code/src/a.sh"
run_file Write "$C/README.md";                   hook_ok "code/README.md"
run_file Write "$CORE_DIR/p/docs/a.md";          hook_ok "Core project docs/a.md"
run_file Write "$CORE_DIR/p/CLAUDE.md";          hook_ok "Core project CLAUDE.md"
run_file Write "$CORE_DIR/p/.claude/rules/x.md"; hook_ok "Core project .claude/rules"
run_file Write "$CORE_DIR/README.md";            hook_ok "Core root file"
QW="$PRJ/q"; mkdir -p "$QW/.claude/worktrees/w9/.claude/worktrees/v"   # a Write to a path that is not an existing dir is a file
run_file Write "$QW/.claude/worktrees/w9";       hook_ok "the worktree dir itself (it exists)"
run_file Write "$C/.claude/worktrees/w2/";       hook_ok "another worktree dir, trailing slash"
run_file Write "$QW/.claude/worktrees";          hook_ok "worktrees dir (it exists)"
run_file Write "$C/.claude/worktrees/w/src/a.sh";hook_ok "worktree ordinary code"
run_file Write "$C/.claude/worktrees/w/.claude/settings.local.json"; hook_ok "worktree settings.local.json"
run_file Write "$QW/.claude/worktrees/w9/.claude/worktrees/v"; hook_ok "worktree inside a worktree"

# --- nested CLAUDE.md: blocked at any depth, like the git pre-commit hook; CLAUDE.local.md too
run_file Write "$C/src/CLAUDE.md";           blocked "nested CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/deep/CLAUDE.md";      blocked "deeper CLAUDE.md" "$C/src/deep/CLAUDE.md" "$CORE_DIR/p/src/deep/CLAUDE.md"
run_file Write "$C/CLAUDE.local.md";         blocked "CLAUDE.local.md" "$C/CLAUDE.local.md" "$CORE_DIR/p/CLAUDE.local.md"
run_file Write "$C/src/CLAUDE.local.md";     blocked "nested CLAUDE.local.md" "$C/src/CLAUDE.local.md" "$CORE_DIR/p/src/CLAUDE.local.md"
run_file Write "$C/.claude/worktrees/w/src/CLAUDE.md"
blocked "worktree nested CLAUDE.md" "$C/.claude/worktrees/w/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_file Write "$C/src/MYCLAUDE.md";         hook_ok "name that only ends like CLAUDE.md"
run_file Write "$C/src/CLAUDE.md.bak";       hook_ok "CLAUDE.md.bak"
# --- AGENTS.md (the cross-tool agent instructions): the same as CLAUDE.md, at any depth
run_file Write "$C/AGENTS.md";               blocked "AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Edit "$C/AGENTS.md";                blocked "Edit AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$C/src/deep/AGENTS.md";      blocked "nested AGENTS.md" "$C/src/deep/AGENTS.md" "$CORE_DIR/p/src/deep/AGENTS.md"
run_file Write "$C/agents.md";               blocked "agents.md lower case" "$C/agents.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$C/src/Agents.MD";           blocked "nested Agents.MD mixed case" "$C/src/Agents.MD" "$CORE_DIR/p/src/AGENTS.md"
run_file Write "$C/.claude/worktrees/w/AGENTS.md"
blocked "worktree AGENTS.md" "$C/.claude/worktrees/w/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_file Write "$CORE_DIR/p/AGENTS.md";      hook_ok "Core project AGENTS.md"
run_file Write "$C/src/MYAGENTS.md";         hook_ok "name that only ends like AGENTS.md"
run_file Write "$C/AGENTS.md.bak";           hook_ok "AGENTS.md.bak"
run_file Write "$C/docs-agents/AGENTS.txt";  hook_ok "AGENTS.txt"
run_file Write "$C/src/docs/a.md";           hook_ok "docs/ below src/ is not the internal docs/"
run_file Write "$C/docsx/a.md";              hook_ok "docsx/"
run_file Write "$C/.claudex/a";              hook_ok ".claudex/"

# --- NotebookEdit uses notebook_path; a relative Edit path resolves against cwd
run_file NotebookEdit "$C/docs/n.ipynb";     blocked "NotebookEdit docs" "$C/docs/n.ipynb" "$CORE_DIR/p/docs/n.ipynb"
run_file NotebookEdit "$C/src/n.ipynb";      hook_ok "NotebookEdit src"
run_file Edit "docs/a.md";                   blocked "Edit relative docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Edit "src/a.sh";                    hook_ok "Edit relative src/a.sh"
run_file Edit "a.md" "$C/docs";              blocked "Edit relative, cwd in docs/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Edit "../CLAUDE.md" "$C/src";       blocked "Edit ../CLAUDE.md from src/ (nested level)" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Edit "../../Core/p/CLAUDE.md" "$C/src"; hook_ok "Edit ../../Core/p/CLAUDE.md from src/ is the Core's own file"
run_file Edit "docs/a.md" "$SANDBOX/elsewhere"; hook_ok "relative path, cwd outside the Core"
run_file Edit "$C/docs/a.md" "$SANDBOX/elsewhere"; blocked "absolute path inside, cwd outside" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"

# --- .. is resolved; letter case is folded (also for a part that does not exist yet)
run_file Write "$PRJ/p/../p/CLAUDE.md";      blocked "path with .. back into code" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/src/../docs/x.md";        blocked ".. through an existing dir" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_file Write "$C/nope/../docs/x.md";       blocked ".. through a missing dir" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_file Write "$C/nope/../../Core/p/docs/a.md"; hook_ok ".. out of the code folder into the Core's docs/"
run_file Write "$C/./docs/./a.md";           blocked "single dots" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C//docs//a.md";             blocked "double slashes" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/claude.md";               blocked "claude.md lower case" "$C/claude.md" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/Claude.MD";               blocked "Claude.MD mixed case" "$C/Claude.MD" "$CORE_DIR/p/CLAUDE.md"
run_file Write "$C/DOCS/a.md";               blocked "DOCS/ upper case (missing dir)" "$C/DOCS/a.md" "$CORE_DIR/p/docs/a.md"
run_file Write "$C/.CLAUDE/x";               blocked ".CLAUDE/ upper case" "$C/.CLAUDE/x" "$CORE_DIR/p/.claude/x"
run_file Write "$C/.Claude/Settings.LOCAL.json"; hook_ok "settings.local.json in other case"
run_file Write "$C/.Claude/WorkTrees/w/CLAUDE.MD"
blocked "worktree in other case" "$C/.Claude/WorkTrees/w/CLAUDE.MD" "$CORE_DIR/p/CLAUDE.md"

# --- public-docs: in <Core>/<p>/CLAUDE.md
Q="$PRJ/q"
run_file Write "$Q/docs/x.md";               blocked "no public-docs line" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\ncheck: true\npublic-docs: docs/\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               hook_ok "public-docs: docs/"
run_file Write "$Q/docs/sub/deep/y.md";      hook_ok "public-docs: docs/ covers everything under it"
run_file Write "$Q/docs";                    hook_ok "public-docs: docs/ covers docs itself"
run_file Write "$Q/DOCS/x.md";               hook_ok "public-docs is case-insensitive too"
# docs/superpowers stays private under a public docs/ (.gitignore and the pre-commit hook keep it out of git)
run_file Write "$Q/docs/superpowers/plans/p.md"; blocked "public-docs: docs/ does not open docs/superpowers" "$Q/docs/superpowers/plans/p.md" "$CORE_DIR/q/docs/superpowers/plans/p.md"
run_file Write "$Q/Docs/SuperPowers/x.md";    blocked "docs/superpowers in another letter case" "$Q/Docs/SuperPowers/x.md" "$CORE_DIR/q/docs/SuperPowers/x.md"
run_file Write "$Q/docs/superpowers-notes.md"; hook_ok "public-docs: docs/superpowers-notes.md is not docs/superpowers"
run_file Write "$Q/CLAUDE.md";               blocked "public-docs: docs/ does not open CLAUDE.md" "$Q/CLAUDE.md" "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/AGENTS.md";               blocked "public-docs: docs/ does not open AGENTS.md" "$Q/AGENTS.md" "$CORE_DIR/q/AGENTS.md"
run_file Write "$Q/.claude/rules/x.md";      blocked "public-docs: docs/ does not open .claude" "$Q/.claude/rules/x.md" "$CORE_DIR/q/.claude/rules/x.md"
run_file Write "$Q/docsx/a.md";              hook_ok "docsx is not blocked at all"
printf '# q\r\npublic-docs: README.md docs/guide.md, `docs/api/` ./CLAUDE.local.md\r\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/guide.md";           hook_ok "public-docs: a file entry"
run_file Write "$Q/docs/api/v1/a.md";        hook_ok "public-docs: a dir entry among several (comma, backticks, CRLF)"
run_file Write "$Q/CLAUDE.local.md";         hook_ok "public-docs: ./ prefix"
printf '# q\npublic-docs: AGENTS.md\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/AGENTS.md";               hook_ok "public-docs: AGENTS.md listed on purpose"
run_file Write "$Q/docs/other.md";           blocked "public-docs: a file entry opens only that file" "$Q/docs/other.md" "$CORE_DIR/q/docs/other.md"
run_file Write "$Q/docs/guide.md.bak";       blocked "public-docs: prefix of a name is not a match" "$Q/docs/guide.md.bak" "$CORE_DIR/q/docs/guide.md.bak"
printf '# q\nsee public-docs: docs/ for details\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               blocked "public-docs must start the line" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\npublic-docs: *\n' > "$CORE_DIR/q/CLAUDE.md"
run_file Write "$Q/docs/x.md";               blocked "public-docs: a glob opens nothing" "$Q/docs/x.md" "$CORE_DIR/q/docs/x.md"
printf '# q\npublic-docs: docs/\n' > "$CORE_DIR/q/CLAUDE.md"
mkdir -p "$Q/.claude/worktrees/w"
run_file Write "$Q/.claude/worktrees/w/docs/x.md"; hook_ok "public-docs applies relative to a worktree root"
run_file Write "$Q/.claude/worktrees/w/CLAUDE.md"; blocked "public-docs: worktree CLAUDE.md" "$Q/.claude/worktrees/w/CLAUDE.md" "$CORE_DIR/q/CLAUDE.md"

# --- symlinks: a directory link is resolved; a file link is followed
mkdir -p "$C/src/real"; ln -s "$CORE_DIR/p/docs" "$C/linkdocs"; ln -s "$C/docs" "$C/src/real/tocodedocs"
run_file Write "$C/linkdocs/a.md";           hook_ok "code/linkdocs -> <Core>/p/docs (writing to the Core)"
mkdir -p "$C/docs"
run_file Write "$C/src/real/tocodedocs/a.md"; blocked "link into code/docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
ln -s docs/x.md "$C/notes.md"
run_file Write "$C/notes.md";                blocked "file link to code/docs/x.md" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
ln -s ../Core/p/docs/x.md "$PRJ/q/lnk.md"
run_file Write "$PRJ/q/lnk.md";              hook_ok "file link out of the code folder into the Core"
ln -s lnk-loop "$C/lnk-loop"
run_file Write "$C/lnk-loop";                hook_ok "a link loop does not hang"

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
  run_bash "$c"; hook_ok "Bash passes: $c"
done
# the Claude Code commit idiom: a heredoc inside "$(...)"; an odd number of double quotes in the body must not flip the quoting
run_bash 'git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: guard for 5\" screens\n\nMoved notes -> docs/notes.md\nEOF\n)\"'; hook_ok "Bash commit heredoc in \"\$(...)\", odd quote in the body"
run_bash 'git commit -m \"$(cat <<EOF\nsay \"hi\nx > docs/a.md\nEOF\n)\" && echo y > docs/b.md'
blocked "Bash command after a commit heredoc is judged again" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash 'git commit -m \"$(cat <<-EOF\n\tit\"s > docs/a.md\n\tEOF\n)\"'; hook_ok "Bash commit heredoc <<- in \"\$(...)\""
run_bash 'git commit -m \"$(cat <<\"EOF\"\nx\" > docs/a.md\nEOF\n)\"'; hook_ok "Bash commit heredoc with a double-quoted delimiter: its body is skipped"
run_bash 'git commit -m \"$(cat <<\"EOF\"\nx\nEOF\n)\" && echo y > docs/b.md'
blocked "Bash command after a commit heredoc with a double-quoted delimiter is judged" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
# a heredoc body that is not closed, and one closed on the last line, are not parsed as commands
run_bash 'grep -n \"<<'"'"'\" f.sh && echo '"'"'ok'"'"' \"> docs/y\"'; hook_ok "Bash a <<' inside a double-quoted grep pattern does not flip the quoting"
run_bash 'cat <<EOF\necho x > docs/a.md'; hook_ok "Bash unterminated heredoc body"
run_bash 'cat <<EOF > notes\nx\nEOF\ncp a docs/b'; blocked "Bash command after a closed heredoc is judged" "$C/docs/b" "$CORE_DIR/p/docs/b"

}
bg sec_bash_pass

# JSON escapes, odd core_dir values, letter case, no git
sec_json() {
# --- JSON with escapes, extra whitespace and newlines: the real path is read
# the Core folder with Cyrillic and a space, written as \u escapes
CYR="$SANDBOX/Мои проекты/Ядро"; CYRP="$SANDBOX/Мои проекты"   # the Core, and the Projects folder that holds it
mkdir -p "$CYRP/app" "$CYR/app"; : > "$CYR/app/CLAUDE.md"
export CORE_DIR="$CYR"
run_hook "$H" '{"cwd":"'"$CYRP"'/app","tool_name":"Write","tool_input":{"file_path":"'"$CYRP"'/app/CLAUDE.md"}}'
blocked "core_dir with a space and Cyrillic: CLAUDE.md" "$CYRP/app/CLAUDE.md" "$CYR/app/CLAUDE.md"
run_file Write "$CYRP/app/docs/a.md" "$CYRP/app";     blocked "core_dir with a space and Cyrillic: docs" "$CYRP/app/docs/a.md" "$CYR/app/docs/a.md"
run_file Write "$CYRP/app/.claude/rules/x.md" "$CYRP/app"; blocked "core_dir with a space and Cyrillic: .claude" "$CYRP/app/.claude/rules/x.md" "$CYR/app/.claude/rules/x.md"
run_file Write "$CYRP/app/src/a.sh" "$CYRP/app";      hook_ok "core_dir with a space and Cyrillic: code"
run_file Write "$CYR/app/docs/a.md" "$CYRP/app";          hook_ok "core_dir with a space and Cyrillic: the Core's docs"
run_bash 'echo x > \"docs/a b.md\"' "$CYRP/app";          blocked "core_dir Cyrillic: Bash quoted" "$CYRP/app/docs/a b.md" "$CYR/app/docs/a b.md"
run_bash 'cp a docs/b.md' "$CYRP/app";                    blocked "core_dir Cyrillic: Bash cp" "$CYRP/app/docs/b.md" "$CYR/app/docs/b.md"
# the same path as \u escapes (Мои проекты/Ядро) and with newlines and spaces around the keys
U='\u041c\u043e\u0438 \u043f\u0440\u043e\u0435\u043a\u0442\u044b'   # Мои проекты, the Projects folder
run_hook "$H" '{"cwd":"'"$SANDBOX"'/'"$U"'/app","tool_name":"Write","tool_input":{"file_path":"'"$SANDBOX"'/'"$U"'/app/CLAUDE.md"}}'
blocked "escaped (\\u) Cyrillic path" "$CYRP/app/CLAUDE.md" "$CYR/app/CLAUDE.md"
run_hook "$H" "$(printf '{\n  "tool_name" : "Write",\n  "cwd"\n  :\n  "%s/app",\n  "tool_input" : {\n    "content" : "a\\n\\"file_path\\": \\"/x\\"",\n    "file_path" :\n      "%s/app/docs/a.md"\n  }\n}\n' "$CYRP" "$CYRP")"
blocked "pretty-printed JSON, a decoy key inside a string" "$CYRP/app/docs/a.md" "$CYR/app/docs/a.md"
run_hook "$H" '{"tool_name":"Bash","cwd":"'"$CYRP"'/app","tool_input":{"command":"echo \"x\" > \"docs/q\\\"uote.md\""}}'
blocked "escaped quotes in a Bash command" "$CYRP/app/docs/q\"uote.md" "$CYR/app/docs/q\"uote.md"
mkdir -p "$CYRP/app/src/we\"ird"
run_hook "$H" '{"cwd":"'"$CYRP"'/app","tool_name":"Write","tool_input":{"file_path":"'"$CYRP"'/app/src/we\"ird/a.sh"}}'; hook_ok "escaped quote in a folder name, ordinary code"
run_hook "$H" '{"cwd":"'"$CYRP"'/app","tool_name":"Write","tool_input":{"file_path":"'"$CYRP"'/app/src/we\"ird/CLAUDE.md"}}'
blocked "escaped quote in a folder name, nested CLAUDE.md" "$CYRP/app/src/we\"ird/CLAUDE.md" "$CYR/app/src/we\"ird/CLAUDE.md"
mkdir -p "$CYRP/app/src/back\\slash"
run_hook "$H" '{"cwd":"'"$CYRP"'/app","tool_name":"Write","tool_input":{"file_path":"'"$CYRP"'/app/src/back\\slash/CLAUDE.md"}}'
blocked "escaped backslash in a folder name" "$CYRP/app/src/back\\slash/CLAUDE.md" "$CYR/app/src/back\\slash/CLAUDE.md"

# --- core_dir given with ~, with a trailing slash, through a symlink
mkdir -p "$HOME/MyCore/app" "$HOME/app" "$SANDBOX/real/app" "$SANDBOX/app"; : > "$HOME/MyCore/app/CLAUDE.md"; : > "$SANDBOX/real/app/CLAUDE.md"
# the code folders beside each Core: $HOME/app (Core ~/MyCore) and $SANDBOX/app (Core $SANDBOX/real, also through linkcore);
# linkapp is a link to the code folder
export CORE_DIR='~/MyCore'
run_file Write "$HOME/app/docs/a.md" "$HOME/app"; blocked "core_dir with ~" "$HOME/app/docs/a.md" "$HOME/MyCore/app/docs/a.md"
export CORE_DIR="$HOME/MyCore///"
run_file Write "$HOME/app/CLAUDE.md" "$HOME/app"; blocked "core_dir with a trailing slash" "$HOME/app/CLAUDE.md" "$HOME/MyCore/app/CLAUDE.md"
ln -s "$SANDBOX/real" "$SANDBOX/linkcore"; ln -s "$SANDBOX/app" "$SANDBOX/linkapp"
export CORE_DIR="$SANDBOX/linkcore"
run_file Write "$SANDBOX/app/docs/a.md" "$SANDBOX/app"; blocked "core_dir is a symlink, path real" "$SANDBOX/app/docs/a.md" "$SANDBOX/real/app/docs/a.md"
run_file Write "$SANDBOX/linkapp/docs/a.md" "$SANDBOX/linkapp"; blocked "core_dir is a symlink, path through a link to the code folder" "$SANDBOX/app/docs/a.md" "$SANDBOX/real/app/docs/a.md"
export CORE_DIR="$SANDBOX/real"
run_file Write "$SANDBOX/linkapp/docs/a.md" "$SANDBOX/app"; blocked "real core_dir, path through a symlink" "$SANDBOX/app/docs/a.md" "$SANDBOX/real/app/docs/a.md"
run_file Write "docs/a.md" "$SANDBOX/linkapp";      blocked "relative path, cwd through a symlink" "$SANDBOX/app/docs/a.md" "$SANDBOX/real/app/docs/a.md"

# --- core_dir typed in another letter case than on disk (macOS volumes are case-insensitive)
mkdir -p "$SANDBOX/cs/a"
if [ -d "$SANDBOX/cs/A" ]; then
  mkdir -p "$SANDBOX/CaseCore/Ядро/myapp" "$SANDBOX/CaseCore/MyApp"; : > "$SANDBOX/CaseCore/Ядро/myapp/CLAUDE.md"
  CP="$SANDBOX/CaseCore/Ядро/myapp"; CC="$SANDBOX/CaseCore/MyApp"   # the Core project and its code folder
  export CORE_DIR="$SANDBOX/casecore/ядро"
  run_file Write "$CC/docs/a.md" "$CC";             blocked "CORE_DIR in other case, path as on disk" "$CC/docs/a.md" "$CP/docs/a.md"
  run_file Write "$SANDBOX/CASECORE/myapp/CLAUDE.md" "$SANDBOX/casecore/MYAPP"
  blocked "path and cwd in other case" "$CC/CLAUDE.md" "$CP/CLAUDE.md"
  run_file Write "$SANDBOX/CASECORE/MYAPP/Docs/a.md" "$CC"
  blocked "every part in other case, docs missing" "$CC/Docs/a.md" "$CP/docs/a.md"
  run_bash 'echo x > DOCS/a.md' "$SANDBOX/casecore/myapp"; blocked "Bash, cwd in other case" "$CC/DOCS/a.md" "$CP/docs/a.md"
  run_file Write "$SANDBOX/CASECORE/ЯДРО/myapp/docs/a.md" "$CC"; hook_ok "other case, the Core's own docs"
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
# watched <file> — runs the hook on the file; RC = its exit code. A watchdog kills a hook that hangs after 60 s (RC 143):
# it only stops a hang, the speed is judged by CPU time (cpu_run, tests/lib.sh).
watched() {
  ( trap '' PIPE; exec bash "$H" < "$1" ) >"$OD/out" 2>"$OD/err" & local hp=$!
  ( sleep 60; kill "$hp" 2>/dev/null ) >/dev/null 2>&1 & local wd=$!; disown "$wd" 2>/dev/null
  wait "$hp"; RC=$?; kill "$wd" 2>/dev/null
  [ "$RC" != 143 ] || fail "$1: the hook hung and was killed by the 60 s watchdog"
}
# timed_json <file> — RC, OUT, ERR as run_hook; T = the hook's CPU time in ms
timed_json() { cpu_run watched "$1"; T=$CPU_MS; OUT="$(<"$OD/out")"; ERR="$(<"$OD/err")"; }
words="$(yes 'ab' | head -n 40000 | tr '\n' ' ')"           # about 120 KB of short words
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$C" "$words" > "$SANDBOX/big1.json"
timed_json "$SANDBOX/big1.json"; hook_ok "120 KB of words"; [ "$T" -lt 5000 ] && pass || fail "120 KB of words took ${T} ms of CPU"
one="$(head -c 100000 /dev/zero | tr '\0' 'x')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s > docs/a.md"}}' "$C" "$one" > "$SANDBOX/big3.json"
timed_json "$SANDBOX/big3.json"; blocked "one 100 KB word, then a redirect" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 5000 ] && pass || fail "one 100 KB word took ${T} ms of CPU"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"%s\\" > docs/a.md; echo %s"}}' "$C" "$one" "'$one'" > "$SANDBOX/big4.json"
timed_json "$SANDBOX/big4.json"; blocked "100 KB double-quoted word" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 5000 ] && pass || fail "100 KB quoted word took ${T} ms of CPU"
esc="$(yes 'a\\\"b' | head -n 20000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo \\"%s\\""}}' "$C" "$esc" > "$SANDBOX/big5.json"
timed_json "$SANDBOX/big5.json"; hook_ok "100 KB of escapes in one quoted string"; [ "$T" -lt 5000 ] && pass || fail "escapes took ${T} ms of CPU"
reds="$(yes '>x' | head -n 20000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$C" "$reds" > "$SANDBOX/big6.json"
timed_json "$SANDBOX/big6.json"; hook_ok "20000 redirects to an ordinary file (the target count is capped)"; [ "$T" -lt 8000 ] && pass || fail "many redirects took ${T} ms of CPU"
# the one big case, over 1 MB of words and then a redirect into docs/
words="$(yes 'ab' | head -n 360000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s > docs/a.md"}}' "$C" "$words" > "$SANDBOX/big2.json"
timed_json "$SANDBOX/big2.json"; blocked "1 MB of words, then a redirect into docs/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"; [ "$T" -lt 15000 ] && pass || fail "1 MB then redirect took ${T} ms of CPU"
# a Write with a 1 MB content field: the path is still read
printf '{"cwd":"%s","tool_name":"Write","tool_input":{"content":"%s","file_path":"%s/docs/big.md"}}' "$C" "$(head -c 1000000 /dev/zero | tr '\0' 'y')" "$C" > "$SANDBOX/big7.json"
timed_json "$SANDBOX/big7.json"; blocked "Write with 1 MB of content" "$C/docs/big.md" "$CORE_DIR/p/docs/big.md"; [ "$T" -lt 5000 ] && pass || fail "1 MB Write took ${T} ms of CPU"
# growth: four times the targets cost about three times the CPU (a quadratic reader would cost 16 times)
words="$(yes 'ab' | head -n 25000 | tr '\n' ' ')"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"touch %s"}}' "$C" "$words" > "$SANDBOX/lin1.json"
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"touch %s%s%s%s"}}' "$C" "$words" "$words" "$words" "$words" > "$SANDBOX/lin4.json"
assert_linear "bash-lex.awk + bashlex-guard-code.awk: 25000 against 100000 touch targets" 6 'watched "$SANDBOX/lin1.json"' 'watched "$SANDBOX/lin4.json"'

}
bg sec_size

# --- in the foreground: Bash cases that must be refused, and input that is not judged
# --- Bash: redirects and the file commands (cwd = code/)
run_bash 'echo x > CLAUDE.md';               blocked "Bash > CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash 'echo x > ../../p/CLAUDE.md' "$CORE_DIR/p"; blocked "Bash > ../../p/CLAUDE.md from the Core project folder" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
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
# a command that starts with `cd <absolute folder> &&` (or `;`, or a newline): the relative targets after it are judged
# against that folder, the one simple form the plain reading follows (the hook's cwd is not where the shell writes then)
run_bash "cd $C && printf x > docs/y.md";    blocked "Bash cd <code> && printf > docs/y.md" "$C/docs/y.md" "$CORE_DIR/p/docs/y.md"
run_bash "cd $C; cat > docs/y.md";           blocked "Bash cd <code>; cat > docs/y.md" "$C/docs/y.md" "$CORE_DIR/p/docs/y.md"
run_bash "cd $C\\necho x > docs/y.md";       blocked "Bash cd <code>, newline, echo > docs/y.md" "$C/docs/y.md" "$CORE_DIR/p/docs/y.md"
run_bash "cd '$C' && echo x > docs/y.md";    blocked "Bash cd '<code>' (quoted) && echo > docs/y.md" "$C/docs/y.md" "$CORE_DIR/p/docs/y.md"
run_bash "cd $C/ && touch CLAUDE.md";        blocked "Bash cd <code>/ && touch CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash "cd $C && echo x > src/ok.sh && cp a docs/b.md"; blocked "Bash cd <code> && two writes, the second into docs/" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash "cd $C/src && echo x > ../docs/y.md" "$SANDBOX/elsewhere"; blocked "Bash cd <code>/src && ../docs/y.md from outside" "$C/docs/y.md" "$CORE_DIR/p/docs/y.md"
run_bash "cd $C && cat docs/y.md";           hook_ok "Bash cd <code> && cat docs/y.md (a read)"
run_bash "cd $C && printf x > src/y.sh";     hook_ok "Bash cd <code> && printf > src/y.sh"
run_bash "cd $C && echo x > README.md";      hook_ok "Bash cd <code> && echo > README.md"
run_bash "cd $SANDBOX/elsewhere && printf x > docs/y.md"; hook_ok "Bash cd /elsewhere && printf > docs/y.md (outside the project)"
run_bash "cd $CORE_DIR/p && echo x > docs/y.md"; hook_ok "Bash cd <Core>/p && docs/y.md (the Core's own docs)"
run_bash "cd $C && cd .. && echo x > docs/y.md"; hook_ok "Bash cd <code> && cd .. then a relative target: unknown again"
run_bash "cd $C && (cd .. && echo x > docs/y.md)"; hook_ok "Bash cd <code> && (cd .. && ...): unknown again"
run_bash "cd $C || exit 1; echo x > docs/y.md"; hook_ok "LIMIT: cd <code> || ... is not the simple form"
run_bash "cd -P $C && echo x > docs/y.md";   hook_ok "LIMIT: cd with an option is not the simple form"
run_bash "cd $C \$X && echo x > docs/y.md";  hook_ok "LIMIT: cd with two words is not the simple form"
run_bash "(cd $C && echo x > docs/y.md)";    hook_ok "LIMIT: (cd <code> && ...) in a subshell is not the leading form"
run_bash "ls; cd $C && echo x > docs/y.md";  hook_ok "LIMIT: a cd that is not the first command"
run_bash "cd ~/Projects/p && echo x > docs/y.md"; hook_ok "LIMIT: cd ~/... is not a plain absolute path"
# any other cd / pushd / popd: a relative target is unknown (cwd is not tracked), only absolute and ~ targets are judged
run_bash 'cd /tmp && echo x > docs/a.md';    hook_ok "Bash cd /tmp && a relative target: /tmp is outside a project"
run_bash 'cd .. && echo \"- step 3\" >> docs/INDEX.md'; hook_ok "Bash cd .. && echo >> docs/INDEX.md (the wiki in the Core)"
run_bash 'cd .. && cat > docs/features/x.md <<EOF\n# x\nbody\nEOF'; hook_ok "Bash cd .. && cat > docs/... <<EOF"
run_bash '(cd .. && cp /tmp/notes.md docs/)'; hook_ok "Bash (cd .. && cp notes docs/)"
run_bash 'cd /tmp && echo x > CLAUDE.md';    hook_ok "Bash cd /tmp && echo x > CLAUDE.md"
run_bash 'cd .. && echo x > code/CLAUDE.md'; hook_ok "Bash cd .. then a relative code/CLAUDE.md: unknown, passes (best effort)"
run_bash "cd src && echo x > $C/CLAUDE.md";  blocked "Bash cd src, then an absolute target" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
run_bash "pushd .. >/dev/null; echo x > docs/a.md; popd"; hook_ok "Bash pushd: relative target passes"
run_bash "popd; touch docs/a.md";            hook_ok "Bash popd: relative target passes"
run_bash 'cd src; mkdir -p docs';            hook_ok "Bash cd then mkdir docs"
run_bash "cd .. && cp a $C/docs/b.md";       blocked "Bash cd then cp to an absolute docs path" "$C/docs/b.md" "$CORE_DIR/p/docs/b.md"
run_bash 'echo x > docs/a.md && cd ..';      blocked "Bash target before the cd is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo cd; echo x > docs/a.md';      blocked "Bash: cd as an argument is no cd" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > ~/nothing/docs/a.md';     hook_ok "Bash ~ target outside the Core"
run_bash 'ls; echo x > docs/a.md';           blocked "Bash after ;" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'ls\necho x > docs/a.md';           blocked "Bash after a newline" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'sudo tee docs/a.md';               blocked "Bash behind sudo" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'FOO=1 /usr/bin/touch docs/a.md';   blocked "Bash behind an assignment and a path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'cat <<EOF > docs/a.md\nbody\nEOF'; blocked "Bash heredoc into docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash '(echo x > docs/a.md)';             blocked "Bash in a subshell" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo $(cat x > docs/a.md)';        blocked "Bash in a command substitution" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > $C/docs/a.md' "$SANDBOX/elsewhere"; hook_ok "Bash: an unexpanded variable is not judged"
run_bash "echo x > $C/docs/a.md" "$SANDBOX/elsewhere"; blocked "Bash absolute target, cwd outside" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'echo x > src/CLAUDE.md';           blocked "Bash nested CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
run_bash 'echo x > AGENTS.md';                blocked "Bash > AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_bash 'cp /tmp/AGENTS.md src/';           blocked "Bash cp AGENTS.md into src/" "$C/src/AGENTS.md" "$CORE_DIR/p/src/AGENTS.md"
run_bash 'touch AGENTS.md';                  blocked "Bash touch AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
run_bash 'cat AGENTS.md';                    hook_ok "Bash reading AGENTS.md passes"
# mkdir: docs/ and .claude/<anything> are refused; the bare .claude dir is the home of settings.local.json
run_bash 'mkdir docs';                       blocked "Bash mkdir docs" "$C/docs" "$CORE_DIR/p/docs"
run_bash 'mkdir -p docs/features';           blocked "Bash mkdir -p docs/features" "$C/docs/features" "$CORE_DIR/p/docs/features"
run_bash 'mkdir -m 755 -p .claude/rules';    blocked "Bash mkdir -p .claude/rules" "$C/.claude/rules" "$CORE_DIR/p/.claude/rules"
run_bash 'mkdir -p .claude';                 hook_ok "Bash mkdir .claude (for settings.local.json)"
run_bash 'mkdir -p src/docs src/.claude';    hook_ok "Bash mkdir below src"
run_bash 'mkdir -p .claude/worktrees/w';     hook_ok "Bash mkdir a worktree dir"


# --- inert outside the Core project: cwd and target both outside, or only the Core's own files
run_file Write "$SANDBOX/elsewhere/CLAUDE.md" "$SANDBOX/elsewhere";   hook_ok "Write CLAUDE.md outside the Core"
run_file Write "$SANDBOX/elsewhere/docs/a.md" "$SANDBOX/elsewhere";   hook_ok "Write docs/ outside the Core"
run_file Write "$SANDBOX/elsewhere/code/docs/a.md" "$SANDBOX/elsewhere"; hook_ok "Write elsewhere/code/docs"
run_file Write "$CORE_DIR/standards/code/docs/a.md" "$CORE_DIR";      hook_ok "standards/ is not a project"
run_file Write "$CORE_DIR/nonproject/code/CLAUDE.md" "$CORE_DIR";     hook_ok "a folder without CLAUDE.md is not a project"
# the old layout of corecrew 0.4 (<Core>/<p>/code, a repo): no code root any more; writes there are Core writes and pass,
# and so do the Core project's own files
mkdir -p "$CORE_DIR/oldp/code/src" "$CORE_DIR/oldp/docs"; : > "$CORE_DIR/oldp/CLAUDE.md"; git init -q "$CORE_DIR/oldp/code"
run_file Write "$CORE_DIR/oldp/code/src/a.sh" "$CORE_DIR/oldp/code"; hook_ok "old layout: ordinary code passes"
run_bash 'echo x > src/b.sh' "$CORE_DIR/oldp/code";                 hook_ok "old layout: Bash ordinary code passes"
run_file Write "$CORE_DIR/oldp/CLAUDE.md" "$CORE_DIR/oldp/code";    hook_ok "old layout: the Core project's CLAUDE.md passes"
run_file Write "$CORE_DIR/oldp/docs/x.md" "$CORE_DIR/oldp/code";    hook_ok "old layout: the Core project's docs pass"
run_file Write "$CORE_DIR/.git/code/CLAUDE.md" "$CORE_DIR";           hook_ok "dot-folder of the Core"
run_file Write "$C" "$C";                                             hook_ok "the code folder itself"
run_bash 'echo x > CLAUDE.md' "$SANDBOX/elsewhere";                   hook_ok "Bash outside the Core"
run_bash 'echo x > docs/a.md' "$CORE_DIR";                            hook_ok "Bash with cwd = Core root, target nonexistent project"
run_bash 'echo x > docs/a.md' "$CORE_DIR/p";                          hook_ok "Bash in the project folder: docs/ is the Core's own"
run_bash 'echo x > CLAUDE.md' "$CORE_DIR/p";                          hook_ok "Bash in the project folder: CLAUDE.md is the Core's own"

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
  run_hook "$H" "$in"; hook_ok "unjudgeable input passes: $in"
done
OUT="$(bash "$H" </dev/null 2>&1)"; assert_eq "$?" "0" "closed stdin"
# a tool the hook does not know and no path in it
# only Write, Edit and NotebookEdit are file tools; any other tool passes (MultiEdit is gone from hooks.json)
for tl in Read Grep Glob WebFetch Task MultiEdit ''; do
  run_hook "$H" '{"cwd":"'"$C"'","tool_name":"'"$tl"'","tool_input":{"file_path":"'"$C"'/CLAUDE.md","notebook_path":"'"$C"'/CLAUDE.md","command":"echo x > CLAUDE.md"}}'; hook_ok "tool '$tl' is not judged"
done
run_hook "$H" '{"cwd":"'"$C"'","tool_input":{"file_path":"'"$C"'/CLAUDE.md"}}'; hook_ok "no tool_name"


# --- <> opens a file for reading AND writing and creates it: it is a write target (it used to pass)
run_bash 'exec 3<> docs/x.md';               blocked "Bash exec 3<> docs/x.md" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
run_bash 'cat <> docs/rw.md';                blocked "Bash cat <> docs/rw.md" "$C/docs/rw.md" "$CORE_DIR/p/docs/rw.md"
run_bash 'cat <> src/rw.md';                 hook_ok "Bash cat <> src/rw.md"

# --- a "<<" that ends a double-quoted string is not a heredoc: the judging goes on
run_bash 'grep -n \"<<\" f.sh; echo x > docs/a.md'; blocked "Bash \"<<\" as a string, then a write" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
run_bash 'grep -n \"<<\" f.sh'; hook_ok "Bash \"<<\" as a string"

# --- if scripts/*.awk is missing, the Bash path fails open (silently); file tools are still judged
PL="$SANDBOX/plugin-noawk"; mkdir -p "$PL/hooks" "$PL/scripts"
cp "$HOOKS/guard-code.sh" "$HOOKS/messages.sh" "$PL/hooks/"; cp "$SCRIPTS"/lib*.sh "$SCRIPTS/shell-patch.sh" "$SCRIPTS/guard-lib.sh" "$PL/scripts/"
printf '%s' '{"cwd":"'"$C"'","tool_name":"Bash","tool_input":{"command":"echo x > docs/a.md"}}' | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "0" "no awk files: Bash passes"; assert_eq "$(<"$OD/out")$(<"$OD/err")" "" "no awk files: silent"
printf '%s' '{"cwd":"'"$C"'","tool_name":"Write","tool_input":{"file_path":"'"$C"'/docs/a.md"}}' | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no awk files: file tools are still judged"
# the apply_patch reader (patch-paths.awk) is missing: no path is read, nothing can be judged, every patch is refused
# pj <path> [cwd] — the JSON of an apply_patch call that adds one file
pj() { printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Add File: %s\\n+x\\n*** End Patch"}}' "${2-$C}" "$1"; }
pj docs/a.md | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no patch-paths.awk: apply_patch on docs/ is refused (fails closed)"
[ -s "$OD/err" ] && pass || fail "no patch-paths.awk: empty stderr on exit 2"
pj src/a.swift | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no patch-paths.awk: a harmless apply_patch is refused too (nothing can be judged)"
assert_contains "$OD/err" "patch-paths.awk is missing or failed"
# the same refusal holds with a cwd outside any project (guard-code has no cwd gate for apply_patch)
pj src/a.swift "$SANDBOX/elsewhere" | bash "$PL/hooks/guard-code.sh" >"$OD/out" 2>"$OD/err"; RC=$?
assert_eq "$RC" "2" "no patch-paths.awk, cwd outside a project: a harmless apply_patch is refused"
assert_contains "$OD/err" "patch-paths.awk is missing or failed"

# --- SIGPIPE ignored (as on GitHub's runners) and a reader that stops early: no "write error: Broken pipe" reaches the user
sec_sigpipe() {
  local pad lines; pad="$(head -c 200000 /dev/zero | tr '\0' 'a')"
  # nopipe <label> — no pipe noise in ERR
  nopipe() { case "$ERR" in *"Broken pipe"*|*"write error"*) fail "$1: pipe noise: $ERR" ;; *) pass ;; esac; }
  # no awk files, a long command: the Bash path still passes in silence
  printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo %s > docs/a.md"}}' "$C" "$pad" > "$OD/long.json"
  ( trap '' PIPE; bash "$PL/hooks/guard-code.sh" < "$OD/long.json" ) >"$OD/out" 2>"$OD/err"; RC=$?
  assert_eq "$RC" "0" "no awk files, long command: Bash passes"; assert_eq "$(<"$OD/out")$(<"$OD/err")" "" "no awk files, long command: silent"
  # a read-only checker whose tokenizer is missing: refused, with only the refusal on stderr
  printf '{"cwd":"%s","tool_name":"Bash","agent_type":"corecrew:verifier","tool_input":{"command":"echo %s > src/a"}}' "$C" "$pad" > "$OD/ro.json"
  ( trap '' PIPE; bash "$PL/hooks/guard-code.sh" < "$OD/ro.json" ) >"$OD/out" 2>"$OD/err"; RC=$?; ERR="$(<"$OD/err")"
  assert_eq "$RC" "2" "no awk files, read-only checker, long command: refused"; nopipe "no awk files, read-only checker"
  case "$ERR" in corecrew:*) pass ;; *) fail "read-only checker: the message is not first: $ERR" ;; esac
  # an unreadable patch (X) with many "***" lines naming docs: the raw check stops at the first hit
  lines="$(yes '*** frob docs/a.md' | head -n 20000 | awk '{ printf "%s\\n", $0 }')"
  run_hook "$H" "$(hook_event codex "" "$C" tool=apply_patch rawcmd="$lines")"
  assert_eq "$RC" "2" "unreadable patch, 20000 *** lines: refused"
  assert_eq "$ERR" 'corecrew: the patch cannot be judged: its text cannot be read, and the line "*** frob docs/a.md" names an internal path. Use the apply_patch tool and lines like "*** Add File: <full path>".' "unreadable patch, 20000 *** lines: exactly the message"
  # Codex: a long command that names apply_patch many times (the first match is taken)
  lines="$(yes 'echo apply_patch;' | head -n 20000 | tr '\n' ' ')"
  run_hook "$H" "$(hook_event codex "" "$C" tool=Bash command="$lines")"
  assert_eq "$RC" "2" "codex: 20000 apply_patch mentions: refused"; nopipe "codex: 20000 apply_patch mentions"
  case "$ERR" in "corecrew: run patches with the apply_patch tool"*) pass ;; *) fail "codex: 20000 mentions: message: $ERR" ;; esac
}
bg sec_sigpipe


# --- new layout: the code lives in <Projects>/<Name>, the private CLAUDE.md in the Core
sec_new_layout() {
  local PR="$SANDBOX/Projects" N="$SANDBOX/Projects/Foo"
  mkdir -p "$N/src" "$N/.claude" "$CORE_DIR/foo/docs" "$PR/Brain"
  echo '# foo' > "$CORE_DIR/foo/CLAUDE.md"; : > "$PR/Brain/CLAUDE.md"
  ln -s "$CORE_DIR/foo/CLAUDE.md" "$N/CLAUDE.local.md"
  nmsg() { printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\nDocs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' "$1" "$2" "$CORE_DIR/foo/CLAUDE.md"; }
  run_file Write "$N/CLAUDE.md" "$N"; assert_eq "$RC" "2" "new: Write CLAUDE.md"; assert_eq "$ERR" "$(nmsg "$N/CLAUDE.md" "$CORE_DIR/foo/CLAUDE.md")" "new: message"
  run_file Write "$N/docs/x.md" "$N"; assert_eq "$RC" "2" "new: Write docs/x.md"
  run_file Write "$N/.claude/worktrees/w/docs/x.md" "$N"; assert_eq "$RC" "2" "new: worktree docs/x.md"
  run_file Write "$N/.claude/settings.local.json" "$N"; hook_ok "new: settings.local.json"
  run_file Write "$N/src/a.sh" "$N"; hook_ok "new: src/a.sh"
  run_file Edit "$N/CLAUDE.local.md" "$N"; hook_ok "new: Edit through the CLAUDE.local.md symlink"
  # the code folder in another letter case is the same folder only on a case-insensitive volume (macOS)
  if [ -d "$(printf '%s' "$N" | tr 'F' 'f')" ]; then
    run_file Write "$(printf '%s' "$N" | tr 'F' 'f')/docs/x.md" "$N"; assert_eq "$RC" "2" "new: other letter case"
  else
    skip "new layout letter case" "case-sensitive volume"; pass
  fi
  run_file Write "$PR/Brain/CLAUDE.md" "$PR/Brain"; hook_ok "new: a folder that is not a project"
  run_bash 'echo x > docs/a.md' "$N"; assert_eq "$RC" "2" "new: Bash echo x > docs/a.md"
  run_bash 'echo x > src/a.md' "$N"; hook_ok "new: Bash src/a.md"
  # the link session start asks for (agents_link_wrong, local_link_failed): ln -s "<Core>/foo/CLAUDE.md" "<code>/AGENTS.md"
  run_bash 'ln -s \"'"$CORE_DIR"'/foo/CLAUDE.md\" \"'"$N"'/AGENTS.md\"' "$N"; hook_ok "new: ln -s of the Core CLAUDE.md as AGENTS.md"
  run_bash 'ln -s ~/notes.md AGENTS.md' "$N"; assert_eq "$RC" "2" "new: ln -s of a file outside the Core as AGENTS.md"
  run_bash 'ln -s \"'"$CORE_DIR"'/foo/CLAUDE.md\" src/AGENTS.md' "$N"; assert_eq "$RC" "2" "new: a Core link below the code root is refused"
  run_bash 'ln -s \"'"$CORE_DIR"'/foo/docs\" .claude/x' "$N"; assert_eq "$RC" "2" "new: a Core link into .claude/ is refused"
  printf 'public-docs: docs/\n' >> "$CORE_DIR/foo/CLAUDE.md"
  run_file Write "$N/docs/x.md" "$N"; hook_ok "new: public-docs"
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
  run_file Write "$N/src/a.sh" "$N"; hook_ok "odd path: src/a.sh"
}
bg sec_new_odd_path

# Codex: apply_patch and a patch handed to Bash (fixtures built from the rust-v0.166.0 structs)
FX="$ROOT/tests/fixtures/codex"
mkdir -p "$PRJ/r/docs" "$PRJ/r/sub" "$CORE_DIR/r"; printf 'public-docs: docs/pub/\n' > "$CORE_DIR/r/CLAUDE.md"
sec_codex() {
  local R="$PRJ/r"
  # fx <fixture> [cwd] — runs a fixture with @CWD@ replaced
  fx() { run_hook "$H" "$(sed "s|@CWD@|${2-$C}|g" "$FX/$1.json")"; }
  # patch <patch text> [cwd] [tool] — a Codex tool call with the given patch text
  patch() { run_hook "$H" "$(hook_event codex PreToolUse "${2-$C}" tool="${3-apply_patch}" command="$1")"; }
  # big5k — a patch of 5000 harmless Add File entries, JSON-escaped by awk (bash 3.2 is slow on a string this long)
  local big5k; big5k="$(awk 'BEGIN { printf "*** Begin Patch\\n"; for (i = 1; i <= 5000; i++) printf "*** Add File: src/f%d.c\\n+x\\n", i; printf "*** End Patch" }')"
  local nl=$'\n' B='*** Begin Patch' E='*** End Patch'
  fx pre-apply-patch-add;    blocked "codex add docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-update; blocked "codex update CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  fx pre-apply-patch-delete; hook_ok "codex delete docs/a.md passes"
  fx pre-apply-patch-move;   blocked "codex move into docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-multi;  blocked "codex multi names the internal path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  fx pre-apply-patch-secret; hook_ok "codex .env is not guard-code's business"
  patch "$B${nl}*** Add File: AGENTS.md${nl}+x${nl}$E"; blocked "codex AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  patch "$B${nl}*** Add File: .claude/rules/x.md${nl}+x${nl}$E"; blocked "codex .claude/rules" "$C/.claude/rules/x.md" "$CORE_DIR/p/.claude/rules/x.md"
  patch "$B${nl}*** Update File: docs/a.md${nl}*** Move to: src/a.md${nl}@@${nl}-a${nl}+b${nl}$E"; hook_ok "codex move out of docs passes"
  patch "$B${nl}*** Add File: docs/pub/a.md${nl}+x${nl}$E" "$R"; hook_ok "codex public-docs entry passes"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$R"; assert_eq "$RC" "2" "codex public-docs does not cover the rest of docs/"
  patch "$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}*** Add File: src/b.swift${nl}+x${nl}*** Update File: .claude/settings.local.json${nl}@@${nl}-a${nl}+b${nl}$E"; hook_ok "codex legitimate patch"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$C/src"; hook_ok "codex relative docs/a.md from src/ is src/docs/a.md, not the root docs"
  patch "$B${nl}*** Add File: ../docs/a.md${nl}+x${nl}$E" "$C/src"; blocked "codex ../docs/a.md from src/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E" "$SANDBOX/elsewhere"; hook_ok "codex outside a project is inert"
  patch "hello, not a patch"; hook_ok "codex unparseable text passes"
  patch ""; hook_ok "codex empty command passes"
  patch "$B${nl}*** Add File: src/a.md${nl}+see docs/a.md and CLAUDE.md${nl}+*** Add File: docs/x${nl}$E"; hook_ok "codex content lines mentioning docs/ pass"
  patch "$B${nl}*** Bogus${nl}*** Add File: docs/a.md${nl}$E"; blocked "codex a path before an unknown line is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # the Codex shell
  fx pre-bash; hook_ok "codex Bash without a patch passes"
  fx pre-bash-subagent; hook_ok "codex Bash in a subagent: no ro_agent for a Codex agent_type"
  # the same subagent with a command that writes (a read-only checker would be refused): still no ro_agent
  run_hook "$H" "$(sed -e "s|@CWD@|$C|g" -e 's|swift test --filter Foo|echo x > src/a|' "$FX/pre-bash-subagent.json")"
  hook_ok "codex Bash in a subagent that writes: no ro_agent for a Codex agent_type"
  # A patch handed to the shell is refused with one message, wherever it points: a patch run through the Bash command line
  # cannot be checked. Both hooks call the same function in one line (scripts/shell-patch.sh); its cases are in
  # test_shell_patch.sh and the hook-level matrix (both hooks, both cwds, both hosts) in test_shell_patch_exec.sh.
  local D="docs/a.md" O="$SANDBOX/elsewhere" c
  fx pre-bash-applypatch-heredoc; hook_refused_patch "codex Bash apply_patch heredoc"
  fx pre-bash-applypatch-quotedarg; hook_refused_patch "codex Bash apply_patch quoted arg"
  fx pre-bash-applypatch-cd; hook_refused_patch "codex Bash cd sub && apply_patch"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}${E}${nl}EOF" "$C" Bash; hook_refused_patch "codex Bash even a harmless heredoc patch"
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Delete File: docs/a.md${nl}${E}${nl}EOF" "$C" Bash; hook_refused_patch "codex Bash delete patch"
  # no scope gate: a patch run through the Bash command line is refused in every folder (a cwd or wrapper gate was bypassed twice)
  patch "apply_patch <<'EOF'${nl}$B${nl}*** Add File: $D${nl}+x${nl}${E}${nl}EOF" "$O" Bash; hook_refused_patch "codex Bash plain relative apply_patch outside a project"
  patch "cd $C && apply_patch <<'EOF'${nl}$B${nl}*** Add File: $D${nl}+x${nl}${E}${nl}EOF" "$O" Bash; hook_refused_patch "codex Bash cd /project && apply_patch from outside"
  # everyday commands pass in both hosts (a wildcard argument is no command); the input shapes of Claude Code and Codex
  local everyday=( 'wc -l a/* b/* 2>/dev/null | tail -1' 'cd x && ls scripts/* && cat .claude-plugin/marketplace.json' \
    'rm -rf dist/* && npm run build' 'cp assets/* public/' 'chmod +x bin/*' 'du -sh * | sort -h' \
    "cat > f.js <<'EOF'${nl}const y = a * b;${nl}console.log(\"*\", 'it''s');${nl}EOF${nl}node f.js" \
    "git commit -m \"\$(cat <<'EOF'${nl}Fix things${nl}${nl}* bullet one${nl}* bullet two${nl}EOF${nl})\"" \
    "gh pr create --title x --body \"\$(cat <<'EOF'${nl}## Summary${nl}* item${nl}EOF${nl})\"" \
    "case \"\$a\" in${nl}  *.md) echo md ;;${nl}  *) echo other ;;${nl}esac" 'echo $(( $(wc -l < f) * 2 ))' )
  for c in "${everyday[@]}"; do
    run_bash "$(json_esc "$c")"; hook_ok "claude Bash [$c] passes"
    patch "$c" "$C" Bash; hook_ok "codex Bash [$c] passes"
  done
  # the apply_patch TOOL still edits src/ files
  patch "$B${nl}*** Update File: src/a.swift${nl}@@${nl}-a${nl}+b${nl}*** Add File: src/b.swift${nl}+x${nl}$E"; hook_ok "codex apply_patch tool on src/ files passes"
  patch "$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E"; blocked "codex apply_patch tool on docs/ is still judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "echo '*** Begin Patch' | wc -l" "$C" Bash; hook_ok "codex Bash mentioning Begin Patch without paths passes"
  # --- tester: inputs nobody fed
  local P
  # several patches / blocks in one text
  patch "$B${nl}*** Add File: a${nl}+x${nl}$E${nl}$B${nl}*** Add File: $D${nl}+x${nl}$E"; blocked "codex two Begin blocks: the second is judged" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "echo '$B'" "$C" Bash; hook_ok "codex Bash echo of Begin Patch alone passes"
  patch "echo '$B' > src/notes.txt" "$C" Bash; hook_ok "codex Bash echo of Begin Patch into src/ passes"
  patch "echo '$B' > docs/notes.txt" "$C" Bash; blocked "codex Bash echo of Begin Patch into docs/ is still the redirect rule" "$C/docs/notes.txt" "$CORE_DIR/p/docs/notes.txt"
  # the patch inside a shell wrapper
  # path spellings
  for P in ./docs/../docs/a.md src/../docs/a.md docs//a.md ./docs/a.md; do
    patch "$B${nl}*** Add File: $P${nl}+x${nl}$E"; blocked "codex path $P" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  done
  patch "$B${nl}*** Add File: docs/${nl}+x${nl}$E"; blocked "codex path with a trailing slash" "$C/docs" "$CORE_DIR/p/docs"
  ln -s "$C" "$OD/linkcode"; ln -s "$CORE_DIR/p/docs" "$OD/linkdocs"
  patch "$B${nl}*** Add File: $OD/linkcode/docs/a.md${nl}+x${nl}$E"; blocked "codex absolute path through a symlinked folder into code/docs" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File: $OD/linkdocs/a.md${nl}+x${nl}$E"; hook_ok "codex absolute path through a symlink into the Core's docs is the right place"
  ln -s "$C/docs" "$C/src/dl"
  patch "$B${nl}*** Add File: src/dl/a.md${nl}+x${nl}$E"; blocked "codex relative path through a symlink inside the tree" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # header spellings
  patch "$B${nl}*** Add File:$D${nl}+x${nl}$E"; blocked "codex no space after the colon" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}*** Add File:	$D${nl}+x${nl}$E"; blocked "codex a tab after the colon" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}	*** Add File: $D${nl}+x${nl}$E"; blocked "codex a tab-indented header" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B"$'\r'"${nl}*** Add File: $D"$'\r'"${nl}+x"$'\r'"${nl}$E"$'\r'; blocked "codex CRLF line ends" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "*** ADD FILE: $D"; hook_blocked_any "codex uppercase header: unreadable text with an internal path in a *** line is refused"
  assert_eq "$ERR" "corecrew: the patch cannot be judged: its text cannot be read, and the line \"*** ADD FILE: $D\" names an internal path. Use the apply_patch tool and lines like \"*** Add File: <full path>\"." "codex unreadable patch: the message quotes the offending line"
  # raw JSON: \r\n, \t and a \/ in the string
  run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\r\\n*** Add File:\\tdocs\\/a.md\\r\\n+x\\r\\n*** End Patch\\r\\n"}}' "$C")"
  blocked "codex raw JSON escapes \\r\\n \\t \\/" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # a move whose source is harmless and destination internal; a move out of docs; a second Move to
  patch "$B${nl}*** Update File: src/a${nl}*** Move to: $D${nl}@@${nl}-a${nl}+b${nl}$E"; blocked "codex move into docs from src" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # non-string command: nothing to read, passes (as an unreadable text)
  run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":null}}' "$C")"; hook_ok "codex command null passes"
  run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":5}}' "$C")"; hook_ok "codex command number passes"
  run_hook "$H" "$(printf '{"session_id":"s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":["x"]}}' "$C")"; hook_ok "codex command array passes"
  # unreadable (X) patch: the *** lines are checked raw for an internal target
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}junk *** Add File: docs/a.md${nl}$E"; hook_blocked_any "codex junk before a docs/ header (X) is refused"
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}junk *** Add File: src/b.swift${nl}$E"; hook_ok "codex junk before a src/ header (X) passes"
  patch "$B${nl}*** Add File: src/a.swift${nl}+x${nl}$(printf '\302\240')*** Add File: docs/a.md${nl}$E"; blocked "codex NBSP-indented header (trimmed like Codex)" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$B${nl}$(printf '\343\200\200')*** Add File: AGENTS.md${nl}+x${nl}$E"; blocked "codex U+3000-indented header" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  patch "$B${nl}*** Add File: docs/a.md$(printf '\f')${nl}+x${nl}$E"; blocked "codex trailing form feed in the path" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  patch "$(printf '\f')$B${nl}*** Add File: docs/a.md${nl}+x${nl}$E"; blocked "codex leading form feed before Begin" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # the cap: the 101st path blocks (was a DEFECT: the adapter dropped it), 5000 paths are refused fast with the split message
  local big="$B${nl}" i=1; while [ "$i" -le 100 ]; do big="$big*** Add File: src/f$i.txt${nl}+x${nl}"; i=$((i + 1)); done
  patch "$big*** Add File: $D${nl}+x${nl}$E"; hook_blocked_any "codex 101st path (docs/a.md) is refused"
  patch "$big*** Add File: src/last.txt${nl}+x${nl}$E"; hook_blocked_any "codex 101 harmless paths are refused"
  grep -q 'at most 100' "$OD/err" && pass || fail "the cap message must say at most 100 files: $ERR"
  # outside any project two more refusals still hold: the cap and an unreadable text whose *** line names an internal path
  patch "$big*** Add File: src/last.txt${nl}+x${nl}$E" "$O"; hook_blocked_any "codex outside a project: 101 harmless paths are refused"
  grep -q 'at most 100' "$OD/err" && pass || fail "outside a project: the cap message must say at most 100 files: $ERR"
  patch "$big$E" "$O"; hook_ok "codex outside a project: 100 harmless paths pass"
  patch "*** Add File: $D${nl}+x" "$O"; hook_blocked_any "codex outside a project: no Begin Patch, a *** line naming docs/a.md is refused"
  patch "*** Add File: src/a.txt${nl}+x" "$O"; hook_ok "codex outside a project: no Begin Patch, a *** line naming src/a.txt passes"
  cpu_run run_hook "$H" "$(hook_event codex PreToolUse "$C" tool=apply_patch rawcmd="$big5k")"; hook_blocked_any "codex 5000 harmless paths are refused"
  [ "$CPU_MS" -lt 10000 ] && pass || fail "5000 paths took $CPU_MS ms of CPU (hook timeout 15 s)"
  grep -q 'at most 100' "$OD/err" && pass || fail "the cap message must say at most 100 files"
  cpu_run run_hook "$H" "$(hook_event codex PreToolUse "$C" tool=Bash rawcmd="apply_patch <<'EOF'\\n$big5k\\nEOF")"; hook_refused_patch "codex Bash 5000 paths are refused as a shell patch"
  [ "$CPU_MS" -lt 10000 ] && pass || fail "Bash form: 5000 paths took $CPU_MS ms of CPU (hook timeout 15 s)"
  # every exit-2 path writes a non-empty stderr (Codex ignores exit 2 with an empty one)
  fx pre-apply-patch-add; [ -n "$ERR" ] && pass || fail "exit 2 with an empty stderr"
}
bg sec_codex



# Bash through wrapper options and through another shell; a file directly under .claude/worktrees; a core_dir
# that is a symlink. Own project folder bp, so the worktree folder it makes does not touch the other sections.
sec_wrappers() {
  local B="$PRJ/bp"; mkdir -p "$B/src" "$CORE_DIR/bp"; : > "$CORE_DIR/bp/CLAUDE.md"
  code() { run_bash "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" "$B"; }
  # wrapper options take their values
  code 'timeout 5 tee docs/a'; assert_eq "$RC" "2" "timeout 5 tee docs/a"
  code 'sudo -u x touch CLAUDE.md'; assert_eq "$RC" "2" "sudo -u x touch CLAUDE.md"
  code 'nice -n 5 tee docs/a'; assert_eq "$RC" "2" "nice -n 5 tee docs/a"
  code 'timeout 5 tee src/a'; assert_eq "$RC" "0" "timeout 5 tee src/a passes"
  # a file directly under .claude/worktrees
  run_file Write "$B/.claude/worktrees/notes.md" "$B"; assert_eq "$RC" "2" "file directly under .claude/worktrees is blocked"
  mkdir -p "$B/.claude/worktrees/w"
  run_file Write "$B/.claude/worktrees/w" "$B"; assert_eq "$RC" "0" "an existing worktree dir passes"
  run_file Write "$B/.claude/worktrees/w/src/a.sh" "$B"; assert_eq "$RC" "0" "code inside a worktree passes"
  # LIMIT (ADR 009, documented in the guard-code.sh header): a command line handed to another shell is not read
  code 'bash -c "echo hi > CLAUDE.md"'; assert_eq "$RC" "0" "LIMIT: bash -c is not read"
  code "sh -c 'touch docs/a.md'"; assert_eq "$RC" "0" "LIMIT: sh -c is not read"
  code 'eval "tee AGENTS.md"'; assert_eq "$RC" "0" "LIMIT: eval is not read"
  code 'bash -c "echo hi > src/a.ts"'; assert_eq "$RC" "0" "bash -c writes src/a.ts passes"
  code 'bash -c "ls docs"'; assert_eq "$RC" "0" "bash -c ls docs passes"
  # a core_dir that is a symlink: the code folder beside the link's own path is still seen
  local S2="$OD/sl"; mkdir -p "$S2/Projects/Proj" "$S2/elsewhere/Core/proj"
  ln -s "$S2/elsewhere/Core" "$S2/Projects/Core"; : > "$S2/elsewhere/Core/proj/CLAUDE.md"
  local oc="$CORE_DIR"; export CORE_DIR="$S2/Projects/Core"
  run_file Write "$S2/Projects/Proj/CLAUDE.md" "$S2/Projects/Proj"
  assert_eq "$RC" "2" "symlinked core_dir: guard-code sees the code folder"
  CORE_DIR="$oc"
  # HOME="/" (absolute, but the root): no crash, a plain write passes
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/a.txt","content":"x"}}' "$OD" "$OD" \
    | env -u CORE_DIR HOME=/ XDG_CONFIG_HOME= bash "$H" >/dev/null 2>"$OD/e"; assert_eq "$?" "0" "HOME=/: guard-code passes a plain write"
}
bg sec_wrappers

# Bash: the plain write commands (install, ln, in-place sed and perl, git mv) and the accidental writes of everyday work
sec_writers() {
  sh() { run_bash "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" "${2-$C}"; }
  local c SED=sed   # spelled through a variable: tests/test_portability.sh flags the literal in-place form
  # accidental writes: refused with the exact message
  sh 'echo x > docs/plan.md';            blocked "echo x > docs/plan.md" "$C/docs/plan.md" "$CORE_DIR/p/docs/plan.md"
  sh 'cp notes.md CLAUDE.md';            blocked "cp notes.md CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh 'echo x | tee .claude/x';           blocked "tee .claude/x" "$C/.claude/x" "$CORE_DIR/p/.claude/x"
  sh 'ln -s notes.md CLAUDE.md';         blocked "ln -s notes.md CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh 'ln notes.md AGENTS.md';            blocked "ln (hard link) AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  sh 'ln -sf ../notes.md docs/';         blocked "ln -sf into docs/" "$C/docs" "$CORE_DIR/p/docs"
  sh "$SED -i '' 's/a/b/' CLAUDE.md";     blocked "$SED -i '' (BSD) on CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh "$SED -i.bak -e s/a/b/ docs/a.md";   blocked "$SED -i.bak -e on docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  sh 'sed --in-place s/a/b/ src/x.c AGENTS.md'; blocked "sed --in-place, second file" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  sh "$SED -Ei 's/a/b/' CLAUDE.md";       blocked "$SED -Ei on CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh "perl -pi -e 's/a/b/' AGENTS.md";   blocked "perl -pi -e on AGENTS.md" "$C/AGENTS.md" "$CORE_DIR/p/AGENTS.md"
  sh 'perl -i -pe s/a/b/ docs/a.md';     blocked "perl -i -pe on docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  sh 'git mv notes.md docs/notes.md';    blocked "git mv into docs/" "$C/docs/notes.md" "$CORE_DIR/p/docs/notes.md"
  sh 'git mv -f a b .claude/';           blocked "git mv -f into .claude/" "$C/.claude" "$CORE_DIR/p/.claude"
  sh 'install -m 644 a docs/a';          blocked "install -m into docs/" "$C/docs/a" "$CORE_DIR/p/docs/a"
  sh 'install -d docs/x';                blocked "install -d docs/x" "$C/docs/x" "$CORE_DIR/p/docs/x"
  sh 'install -t docs/ a b';             blocked "install -t docs/" "$C/docs/a" "$CORE_DIR/p/docs/a"
  sh 'cp -p a src/b && mv src/b CLAUDE.local.md'; blocked "mv after cp, CLAUDE.local.md" "$C/CLAUDE.local.md" "$CORE_DIR/p/CLAUDE.local.md"
  # a wrapper option that takes a value (the tokenizer's per-wrapper table): the command after it is judged
  for c in 'stdbuf -o L tee docs/a.md' 'sudo -k tee docs/a.md' 'exec -a x tee docs/a.md' 'time -o out tee docs/a.md'; do
    sh "$c"; blocked "$c" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  done
  # digits right after <&, <<< or << are the word of that redirect, not the descriptor of the next one
  sh 'cat <&3>docs/a.md';                blocked "cat <&3>docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  sh 'cat <&3 >docs/a.md';               blocked "cat <&3 >docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  sh 'cat 0<&3>CLAUDE.md';               blocked "cat 0<&3>CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh 'printf x <&0>.claude/settings.json'; blocked "printf x <&0>.claude/settings.json" "$C/.claude/settings.json" "$CORE_DIR/p/.claude/settings.json"
  sh 'cat <<<3>docs/a.md';               blocked "cat <<<3>docs/a.md" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  run_bash 'cat <<3>docs/a.md\nx\n3';    blocked "cat <<3>docs/a.md (heredoc delimiter 3)" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # tokenizer rules on the write side, each with its twin that passes: a <<- heredoc ends at a TAB-indented delimiter
  # and the command after it is judged; the word after <&3 is no redirect target, so cp's last word is the target; a
  # redirect inside >( ) is judged; a CR right after the redirect operator is a blank
  run_bash 'cat <<-EOF\n\tx\n\tEOF\necho x > docs/a'; blocked "a write after a <<- heredoc" "$C/docs/a" "$CORE_DIR/p/docs/a"
  run_bash 'cat <<-EOF\n\tx\n\tEOF\necho x > src/a'; hook_ok "a write into src/ after a <<- heredoc"
  sh 'cp <&3 src/a docs/b';              blocked "cp <&3 src/a docs/b" "$C/docs/b" "$CORE_DIR/p/docs/b"
  sh 'cp <&3 src/a src/b';               hook_ok "cp <&3 src/a src/b"
  sh 'tee >(cat > docs/a.md)';           blocked "tee >(cat > docs/a.md)" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  sh 'tee >(cat > src/a.md)';            hook_ok "tee >(cat > src/a.md)"
  run_bash 'echo x >\rdocs/a.md';        blocked "a CR after the redirect operator" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  run_bash 'echo x >\rsrc/a.md';         hook_ok "a CR after the redirect operator, into src/"
  # a command with a \004 byte of its own is read byte by byte (lexsp=0): still judged
  sh "echo x$(printf '\004')y > docs/a.md"; blocked "a command with a \\004 byte" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  # a link source spelled with a variable is unknown: the link itself is still judged where it lands
  sh 'ln -s "$HOME/notes.md" src/CLAUDE.md'; blocked "ln -s \$HOME/... src/CLAUDE.md" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
  sh 'ln -sf "$CORE_DIR/p/docs" docs';   blocked "ln -sf \$CORE_DIR/... docs" "$C/docs" "$CORE_DIR/p/docs"
  sh 'ln -s "$X" .claude/x';             blocked "ln -s \$X .claude/x" "$C/.claude/x" "$CORE_DIR/p/.claude/x"
  # BSD in-place sed with the suffix as its own word: the suffix is skipped, the script is no file
  sh "$SED -i .bak 's/a/b/' CLAUDE.md";   blocked "$SED -i .bak (BSD) on CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  sh "$SED -e s/a/b/ -i .claude/x";       blocked "$SED -e ... -i .claude/x (GNU: a path is a file, not a suffix)" "$C/.claude/x" "$CORE_DIR/p/.claude/x"
  # a link named inside .claude/worktrees/<name> is a worktree folder; one below it is judged as usual
  sh 'ln -s /tmp/x .claude/worktrees/w/CLAUDE.md'; blocked "ln -s into a worktree's CLAUDE.md" "$C/.claude/worktrees/w/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  # legitimate twins pass
  for c in "ln -s \"$CORE_DIR/p/CLAUDE.md\" \"$C/CLAUDE.local.md\"" "ln -s \"$CORE_DIR/p/CLAUDE.md\" AGENTS.md" \
           'ln -s "$HOME/Projects/Core/p/CLAUDE.md" CLAUDE.local.md' 'ln -sf "$CORE_DIR/p/CLAUDE.md" AGENTS.md' \
           "$SED -i .bak 's/x/CLAUDE.md/' src/a.py" "$SED -i '' 's/x/CLAUDE.md/' src/a.py" \
           'ln -s /tmp/x .claude/worktrees/w' \
           "ln -sf $CORE_DIR/p/docs docs-link" 'ln -s ../lib src/lib' 'ln -s a b' \
           'sed -n 1p CLAUDE.md' "sed 's/a/b/' CLAUDE.md > src/out" "$SED -i '' 's/docs/x/' src/a.c" "$SED -i -e 's|CLAUDE.md|x|' src/a.c" \
           "perl -pe 's/a/b/' AGENTS.md" "perl -pi -e 's/a/b/' src/a.c" "perl -ne 'print if /docs/' CLAUDE.md" \
           'git mv docs/a.md src/a.md' 'git mv a b' 'git log -- docs CLAUDE.md' 'git rm docs/a.md' 'git commit -m "mv notes to docs/"' \
           'install -m 755 build/app bin/app' 'install -d .claude' 'npm install' 'brew install docs' 'pip install -r docs/req.txt' \
           'make install DESTDIR=docs' 'echo cp a CLAUDE.md' 'grep -rn "tee docs" .' 'ls -la > src/listing.txt' \
           'sudo -k tee src/a.md' 'stdbuf -o L tee src/out.txt' 'exec -a x tee src/b.txt' 'time -o out tee src/c.txt' \
           'cat 0<in > src/a' 'cat <&3 >src/x' 'cat <&3>src/x'; do
    sh "$c"; hook_ok "Bash passes: $c"
  done
  # LIMIT (ADR 009): what the plain reading does not follow; each passes and is listed in the guard-code.sh header
  for c in 'f=CLAUDE.md; echo x > $f' 'echo x > doc?/a.md' 'echo x > {docs,src}/a.md' 'cd .. && echo x > code/CLAUDE.md' \
           'echo docs/a.md | xargs touch' 'find . -name a -exec cp {} docs/ \;' 'python3 -c "open(\"CLAUDE.md\",\"w\")"' \
           'bash -c "echo x > docs/a.md"' 'eval "touch CLAUDE.md"' 'sh write-docs.sh' 'rsync a docs/' 'dd of=docs/a.md' \
           'git -C . mv a docs/a' 'tar -xf a.tar -C docs' 'curl -o docs/a.md http://x' 'echo x > "$(echo docs)/a.md"' \
           'sudo -a x tee docs/a.md' 'nice 5 tee docs/a.md'; do
    sh "$c"; hook_ok "LIMIT, passes: $c"
  done
}
bg sec_writers

# More than 100 targets. The first 100 distinct targets are judged; past that, every target whose text names an
# internal component (docs, .claude, CLAUDE.md, CLAUDE.local.md, AGENTS.md) is still judged; the rest passes. More
# than 100 such targets past the first 100 refuse the whole command, so the hook stays well within its 15 s timeout.
# And many deep new paths are judged well within that timeout too.
sec_cap() {
  local i O links n150="" n100="" deep="" deepd="" X="$PRJ/cap" pub100="" pub101="" pub1000="" plain1000=""
  i=1; while [ $i -le 1000 ]; do
    pub1000="$pub1000 docs/pub/x$i"; plain1000="$plain1000 src/x$i"
    [ $i -le 100 ] && pub100="$pub1000"; [ $i -le 101 ] && pub101="$pub1000"; i=$((i + 1))
  done
  # the project exists, with a public docs/, before any run: the passing runs below judge inside a project
  mkdir -p "$X/src" "$CORE_DIR/cap"; printf '# cap\npublic-docs: docs/\n' > "$CORE_DIR/cap/CLAUDE.md"
  cpu_run run_bash "touch$pub1000" "$X"; hook_blocked_any "1000 internal-looking targets are refused"
  grep -q 'too many files to check' "$OD/err" && pass || fail "the too-many message: $ERR"
  [ "$CPU_MS" -lt 5000 ] && pass || fail "1000 internal-looking targets took $CPU_MS ms of CPU (hook timeout 15 s)"
  cpu_run run_bash "touch$plain1000" "$X"; hook_ok "1000 ordinary targets pass"
  [ "$CPU_MS" -lt 5000 ] && pass || fail "1000 ordinary targets took $CPU_MS ms of CPU (hook timeout 15 s)"
  run_bash "touch$plain1000; touch$pub100" "$X"; hook_ok "100 targets, then 100 public internal-looking ones pass"
  run_bash "touch$plain1000; touch$pub101" "$X"; hook_blocked_any "100 targets, then 101 internal-looking ones are refused"
  grep -q 'too many files to check' "$OD/err" && pass || fail "the too-many message after 101: $ERR"
  # outside a project the guard is inert, even for a command too long to judge
  O="$(mktemp -d)"
  run_bash "touch$pub1000" "$O"; hook_ok "1000 internal-looking targets outside a project pass"
  # a link costs more to judge than a plain target: 200 links into a public docs/ end in time
  links=""; i=1; while [ $i -le 200 ]; do links="$links s$i"; i=$((i + 1)); done
  cpu_run run_bash "ln -s$links docs/pub/" "$X"
  [ "$CPU_MS" -lt 5000 ] && pass || fail "200 links into docs/pub/ took $CPU_MS ms of CPU (hook timeout 15 s)"
  i=1; while [ $i -le 150 ]; do n150="${n150}touch x$i; "; [ $i -le 100 ] && n100="$n150"; i=$((i + 1)); done
  i=1; while [ $i -le 100 ]; do deep="${deep}touch d$i/a/b/c/d/e/f/g/h/i/j/x.txt; "; deepd="${deepd}mkdir -p docs/d$i/a/b/c/d/e/f/g/h/i/j; "; i=$((i + 1)); done
  run_bash "${n100}echo x > docs/late.md";   blocked "100 targets, then docs/late.md" "$C/docs/late.md" "$CORE_DIR/p/docs/late.md"
  run_bash "${n150}cp a CLAUDE.md";          blocked "150 targets, then cp a CLAUDE.md" "$C/CLAUDE.md" "$CORE_DIR/p/CLAUDE.md"
  run_bash "${n150}cp CLAUDE.md.tmpl .";     hook_ok "150 targets, then a harmless cp into the code root"
  run_bash "${n150}cp /tmp/CLAUDE.md src/";  blocked "150 targets, then cp CLAUDE.md into src/" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
  run_bash "${n150}echo x > src/late.md";    hook_ok "150 targets, then src/late.md"
  run_bash "${n150}echo x > /tmp/docs/a.md"; hook_ok "150 targets, then docs/ outside a project"
  run_bash "${n150}echo x > docs/a.md" "$X"; hook_ok "150 targets, then a public docs/ path"
  run_bash "${n150}echo x > CLAUDE.md" "$X"; blocked "150 targets, then CLAUDE.md beside a public docs/" "$X/CLAUDE.md" "$CORE_DIR/cap/CLAUDE.md"
  mkdir -p "$C/docs" "$C/src"; ln -s "$C/docs" "$C/src/capdocs"
  run_bash "echo x > src/capdocs/a.md";      blocked "a link into docs/ is followed" "$C/docs/a.md" "$CORE_DIR/p/docs/a.md"
  run_bash "${n150}echo x > src/capdocs/a.md"; hook_ok "LIMIT: past 100 targets, a link into docs/ is not followed"
  cpu_run run_bash "$deep"
  hook_ok "100 deep new paths"; [ "$CPU_MS" -lt 5000 ] && pass || fail "100 deep new paths took $CPU_MS ms of CPU (hook timeout 15 s)"
  cpu_run run_bash "$deepd" "$X"
  hook_ok "100 deep new public docs/ dirs"; [ "$CPU_MS" -lt 8000 ] && pass || fail "100 deep docs/ dirs took $CPU_MS ms of CPU (hook timeout 15 s)"
}
bg sec_cap

# --- The cheap cases first: the settings are loaded only where a path needs them, and never taken as loaded from the
# environment (SETTINGS_LOADED there would switch the guard off). count_execs (tests/lib.sh) counts the programs a call
# starts; run_hook's own bash is one of them.
sec_cheap() {
  local w
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/docs/x.md","content":"x"}}' "$C" "$C" \
    | SETTINGS_LOADED=1 bash "$H" >"$OD/out" 2>"$OD/err"; RC=$?; OUT="$(<"$OD/out")"; ERR="$(<"$OD/err")"
  blocked "SETTINGS_LOADED=1 in the environment: Write docs/x.md is still refused" "$C/docs/x.md" "$CORE_DIR/p/docs/x.md"
  # the same in the new layout with core_dir only in the settings file (CORE_DIR unset, as in Codex): there only
  # load_settings finds the code folder beside the Core, so a SETTINGS_LOADED taken from the environment would pass it
  local S3="$OD/settings-only" cfg
  mkdir -p "$S3/Projects/Core/app" "$S3/Projects/app/src"; : > "$S3/Projects/Core/app/CLAUDE.md"
  cfg="$S3/settings"; printf 'core_dir: %s\n' "$S3/Projects/Core" > "$cfg"
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s/docs/x.md","content":"x"}}' \
    "$S3/Projects/app" "$S3/Projects/app" \
    | env -u CORE_DIR -u CLAUDE_PLUGIN_OPTION_CORE_DIR CORECREW_CONFIG="$cfg" SETTINGS_LOADED=1 bash "$H" >"$OD/out" 2>"$OD/err"
  RC=$?; OUT="$(<"$OD/out")"; ERR="$(<"$OD/err")"
  assert_eq "$RC" "2" "SETTINGS_LOADED=1, new layout, core_dir only in the settings file: Write docs/x.md is still refused"
  assert_eq "$OUT" "" "SETTINGS_LOADED=1, new layout: stdout"
  assert_eq "$ERR" "$(printf 'corecrew: %s is an internal file and must not live in the code folder. Write it to %s instead.\nDocs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in %s.' \
    "$S3/Projects/app/docs/x.md" "$S3/Projects/Core/app/docs/x.md" "$S3/Projects/Core/app/CLAUDE.md")" "SETTINGS_LOADED=1, new layout: message"
  w='{"session_id":"s","cwd":"'"$C"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"'"$C"'/src/x.py","content":"x"}}'
  printf '%s' "$w" | bash -x "$H" >"$OD/out" 2>"$OD/err"; assert_eq "$?" "0" "bash -x: Write src/x.py passes"
  grep -q 'load_settings' "$OD/err" && fail "a Write of src/x.py loads the settings" || pass
  run_file Write "$C/src/x.py"; hook_ok "cheap case: Write src/x.py passes"
  run_file Write "$SANDBOX/elsewhere/x.py" "$SANDBOX/elsewhere"; hook_ok "cheap case: Write outside a project passes"
  count_execs run_hook "$H" "$w"; hook_ok "counted: Write src/x.py"
  echo "  programs: Write src/x.py: $EXECS ($(tr '\n' ' ' < "$EXEC_LOG"))"
  [ "$EXECS" -le 8 ] && pass || fail "a Write of src/x.py starts $EXECS programs (at most 8): $(tr '\n' ' ' < "$EXEC_LOG")"
  count_execs run_bash 'git status'; hook_ok "counted: git status"
  echo "  programs: git status: $EXECS ($(tr '\n' ' ' < "$EXEC_LOG"))"
  assert_eq "$(grep -vxE 'bash|dirname' "$EXEC_LOG" | LC_ALL=C sort | tr '\n' ' ')" "awk cat " "git status starts only cat, one awk and dirname"
}
bg sec_cheap

# Rules that one deleted line would drop: each case here is the only one that sees its rule.
sec_rules() {
  local G="$PRJ/gl" n i many="" O="$SANDBOX/elsewhere"
  sh() { run_bash "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" "${2-$C}"; }
  patch() { run_hook "$H" "$(hook_event codex PreToolUse "${2-$C}" tool="${3-apply_patch}" command="$1")"; }
  # a Core file is not judged, whatever its name (the path must lie under the code root)
  run_file Write "$CORE_DIR/p/docs/AGENTS.md";   hook_ok "Core project docs/AGENTS.md"
  run_file Write "$CORE_DIR/p/notes/CLAUDE.md";  hook_ok "Core project notes/CLAUDE.md"
  # public-docs: a glob is not expanded, even when the hook starts in a code folder that holds docs/
  mkdir -p "$G/docs" "$G/src" "$CORE_DIR/gl"; printf 'public-docs: *\n' > "$CORE_DIR/gl/CLAUDE.md"
  cd "$G" || return; run_file Write "$G/docs/x.md" "$G"; cd "$OLDPWD" || return
  blocked "public-docs: * is not expanded" "$G/docs/x.md" "$CORE_DIR/gl/docs/x.md"
  # docs/superpowers itself stays private under a public docs/
  printf 'public-docs: docs/\n' > "$CORE_DIR/gl/CLAUDE.md"
  run_file Write "$G/docs/superpowers" "$G"; blocked "a file named docs/superpowers" "$G/docs/superpowers" "$CORE_DIR/gl/docs/superpowers"
  run_file Write "$G/docs/superpowersx" "$G"; hook_ok "docs/superpowersx under a public docs/"
  # an unreadable patch: each internal name in a *** line is refused (raw check), an ordinary name passes
  for n in docs/a.md .claude/x CLAUDE.md CLAUDE.local.md AGENTS.md; do
    patch "*** ADD FILE: $n"; hook_blocked_any "unreadable patch naming $n"
    case "$ERR" in *"the line \"*** ADD FILE: $n\" names an internal path"*) pass ;; *) fail "unreadable patch naming $n: message: $ERR" ;; esac
  done
  patch "*** ADD FILE: src/AGENTS.txt"; hook_ok "unreadable patch naming src/AGENTS.txt passes"
  # too many internal-looking targets: refused when a target names the folder that holds the Core, from any cwd
  mkdir -p "$PRJ/cap2/src" "$CORE_DIR/cap2"; printf 'public-docs: docs/\n' > "$CORE_DIR/cap2/CLAUDE.md"
  i=1; while [ $i -le 201 ]; do many="$many $PRJ/cap2/docs/pub/x$i"; i=$((i + 1)); done
  run_bash "touch$many" "$O"; hook_blocked_any "201 internal-looking targets in a project, cwd outside"
  grep -q 'too many files to check' "$OD/err" && pass || fail "the too-many message, cwd outside: $ERR"
  # a link named .claude/worktrees/<name> passes like a worktree folder, also when it points into the Core
  sh "ln -s \"$CORE_DIR/p/docs\" .claude/worktrees/lw"; hook_ok "ln -s <Core>/p/docs .claude/worktrees/lw"
  sh 'ln -s "$X" .claude/worktrees/lv';          hook_ok "ln -s \$X .claude/worktrees/lv"
  sh "ln -s \"$CORE_DIR/p/docs\" .claude/lw";    blocked "ln -s <Core>/p/docs .claude/lw" "$C/.claude/lw" "$CORE_DIR/p/.claude/lw"
  # a link or a copy into a folder is judged by the name it gets there; a . or .. source gives no name
  sh 'ln -s /tmp/CLAUDE.md src/';                blocked "ln -s /tmp/CLAUDE.md src/" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
  sh 'ln -s ../CLAUDE.md' "$C/src";              blocked "ln -s ../CLAUDE.md (one operand) in src/" "$C/src/CLAUDE.md" "$CORE_DIR/p/src/CLAUDE.md"
  sh 'cp -r .. AGENTS.md/sub/';                  hook_ok "cp -r .. AGENTS.md/sub/ (a .. source names no file)"
  sh 'cp -r . src/';                             hook_ok "cp -r . src/"
  sh 'cp -r . .claude/worktrees/w/';             hook_ok "cp -r . .claude/worktrees/w/ (a . source names no file)"
}
bg sec_rules

# The writers' options, one row each: "p#<command>" passes, "r#<command>#<path refused, under the code folder>".
# %W is the code folder, %K the project's folder in the Core, %S the in-place sed. Own project wr, with docs/ and src/.
sec_rows() {
  local W="$PRJ/wr" K="$CORE_DIR/wr" SED=sed want c t i same="" n100="" n
  mkdir -p "$W/docs" "$W/src" "$K"; : > "$K/CLAUDE.md"
  sh() { run_bash "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" "${2-$W}"; }
  while IFS="#" read -r want c t; do
    c="${c//%W/$W}"; c="${c//%K/$K}"; c="${c//%S/$SED -i}"
    sh "$c"
    case "$want" in
      p) hook_ok "passes: $c" ;;
      r) blocked "refused: $c" "$W/$t" "$K/$t" ;;
    esac
  done <<'ROWS'
p#touch -r docs/ref src/a
p#touch -d now src/a
p#touch -d docs src/a
p#mkdir -m 755 src/x
p#mkdir -m docs src/x
p#install -m 644 a src/a
p#install -m 644 -g docs a .
p#install -m docs a .
p#install -o docs a .
p#install -S docs a .
r#install -o root a docs/a#docs/a
r#cp -S .bak a docs/a#docs/a
p#cp -b -S .claude settings.json .
p#mv -b -S .claude settings.json .
p#ln -S .claude -s ../settings.json .
r#cp --target-directory=docs a#docs/a
r#mv --target-directory=docs a#docs/a
r#ln -t docs a#docs
r#ln -s -t src /tmp/CLAUDE.md#src/CLAUDE.md
r#cp -- a docs/a#docs/a
r#mv -- -old/CLAUDE.md src/#src/CLAUDE.md
p#sed -e s/a/b/ src/a
p#%S -e s/x/CLAUDE.md/ src/a.c
p#%S -f docs/fix.sed src/a.c
r#%S -f fix.sed docs/a.md#docs/a.md
p#perl -e 1 src/a
p#perl -pi -e 1 -e AGENTS.md src/a.c
r#cd %W/ && echo x > docs/y.md#docs/y.md
p#cd %W/ && echo x > src/y.md
p#echo x > /dev/null
p#cd %K && ln -s CLAUDE.md %W/AGENTS.md
r#cd %W/src && ln -s notes.md %W/AGENTS.md#AGENTS.md
r#cd /srv/$D && cp CLAUDE.md %W/src/#src/CLAUDE.md
p#cp "$TPL/CLAUDE.md" src/
ROWS
  # ~ is the home folder, also after a cd (it is no relative path)
  HOME="$W" sh 'cd src && echo x > ~/docs/a.md'; blocked "a ~ target after a cd" "$W/docs/a.md" "$K/docs/a.md"
  HOME="$W" sh 'cd src && echo x > ~/src/a.md';  hook_ok "a ~ target after a cd, in src/"
  # a target with a TAB in its name is not judged (LIMIT: the reader's lines are TAB-separated)
  run_bash 'echo x > \"docs/a\tb\"' "$W";        hook_ok "LIMIT, passes: a target with a TAB"
  # each target counts once toward the cap
  i=1; while [ $i -le 201 ]; do same="$same /tmp/docs/a.md"; i=$((i + 1)); done
  sh "touch$same";                               hook_ok "the same target 201 times is one target"
  # past 100 targets every internal name is still judged
  i=1; while [ $i -le 100 ]; do n100="${n100}touch x$i; "; i=$((i + 1)); done
  for n in docs/late.md .claude/x CLAUDE.md CLAUDE.local.md AGENTS.md src/AGENTS.md; do
    sh "${n100}echo x > $n"; blocked "100 targets, then > $n" "$W/$n" "$K/$n"
  done
  sh "${n100}echo x > src/late.md";              hook_ok "100 targets, then > src/late.md"
}
bg sec_rows

bg_wait

finish
