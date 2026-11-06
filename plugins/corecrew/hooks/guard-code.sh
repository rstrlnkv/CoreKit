#!/usr/bin/env bash
# Claude Code PreToolUse hook on Write|Edit|NotebookEdit (and Bash, best effort): a project's
# internal files must not live in its code repo. It blocks writes of
#   CLAUDE.md (and CLAUDE.local.md), AGENTS.md (the cross-tool agent instructions), docs/**, .claude/**
# under the project's code folder (<Projects>/<Name>/**, or <Core>/<project>/code/** in the old layout),
# with exit 2 and a message naming the right place:
#   corecrew: <path> is an internal file and must not live in the code folder. Write it to <Core>/<project>/<relative path> instead.
#   Docs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in <Core>/<project>/CLAUDE.md.
# (spec section 14, item 3). Nothing is ever printed to stdout.
#
# Rules, all compared on the canonical path (".." and symlinks resolved, letter case as on disk
# for the part that exists, then folded to lower case for the comparison, ASCII only):
# - The code root is <Projects>/<Name>/ (the first folder of the path under <Projects>; the CLAUDE.local.md symlink there resolves into the
#   Core and so passes), or <Core>/<p>/code/ in the old layout, or a worktree root <code root>/.claude/worktrees/<w>/;
#   inside a worktree the path relative to the worktree root is what counts.
# - Blocked: docs and docs/** and .claude/** at the root, and CLAUDE.md / CLAUDE.local.md / AGENTS.md at
#   ANY depth (the same as scripts/git-hooks/blocked-patterns, so the hook and the commit check agree).
# - Allowed: .claude/settings.local.json, .claude/worktrees/** (the worktree dirs themselves: mkdir, an
#   existing directory or a trailing slash; a file written directly under .claude/worktrees/ is blocked), and the
#   paths on a "public-docs: <paths>" line of <Core>/<p>/CLAUDE.md (space or comma separated, relative
#   to the code root; a directory entry covers everything under it; a glob is not expanded), except
#   docs/superpowers/** (git ignores it and the pre-commit hook blocks it, so it is always private).
# - Bash is best effort. Targets of > >> 2> &> >| >&file, tee, touch, cp, mv (the destination; a
#   destination directory also gets the sources' names), mkdir. mkdir follows the same rules as a
#   write (docs, .claude/rules, ...) except the bare ".claude" dir, which holds settings.local.json.
#   After a cd, pushd or popd only absolute (and ~) targets are judged: the new directory is unknown, so
#   a relative target fails open (`cd .. && echo x >> docs/INDEX.md` is the Core wiki). A heredoc inside
#   "$(...)" (the commit-message idiom) has its body skipped; <<"WORD" there stops the judging.
#   Wrapper options with a value are skipped (timeout 5 tee, sudo -u x touch, nice -n 5). Documented limits:
#   relative targets after cd, xargs, find -exec, bash -c "...", and the guard being inert outside a project
#   cwd (spec D17).
#   Not followed: variables, globs, `sh -c "..."`, ln, install, in-place sed, rsync, scripts. A target
#   that has $ ` * ? [ { is not judged. Quoted text is not a command, heredoc bodies and comments are
#   skipped. At most 100 targets are looked at. The tokenizer is one linear pass in awk. A command this
#   hook cannot parse passes (exit 0). The git pre-commit hook stays the last layer.
#   The tokenizer lives in scripts/bash-lex.awk and scripts/bashlex-guard-code.awk: if they are missing the
#   Bash path fails open (silently); the file tools are still judged.
# - Inert outside a project (<Core>/<project>/
#   or its code folder beside the Core): a target and a cwd that are not in a project pass (exit 0).
#   No network, no git; only canon_dir, project_of and one grep of the CLAUDE.md public-docs line.
# - Input it cannot read (not JSON, no cwd, no path or command) passes.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting

tool="$(json_str "$in" tool_name)"
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0

# is_public <project> <lower-case path relative to the code root> — exit 0 when a public-docs: entry covers it.
is_public() {
  local f="$CORE_DIR/$1/CLAUDE.md" line t
  [ -f "$f" ] || return 1
  line="$(LC_ALL=C grep -m1 '^public-docs:' "$f" 2>/dev/null)" || return 1
  line="$(printf '%s' "${line#public-docs:}" | LC_ALL=C tr 'A-Z,\r`' 'a-z   ')"
  set -f
  for t in $line; do
    t="${t#./}"
    while [ "${t%/}" != "$t" ]; do t="${t%/}"; done
    [ -n "$t" ] || continue
    case "$2" in "$t"|"$t"/*) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# check_path <path> [dir] — exits 2 with the message when the path is an internal file under a
# project's code root; returns 0 otherwise. Mode "dir" (mkdir) lets the bare .claude through.
check_path() {
  local mode="${2:-write}" proj root abs_l root_l sub sub_l shown w n tgt first
  resolve_abs "$1"
  proj="$(project_of "$ABS")" || return 0
  # the code root: the project folder in <Projects> taken from the path itself (new layout; so no case
  # clash between folders can switch the guard off), or <Core>/<p>/code for a path inside the Core (old)
  case "$ABS" in
    "$CORE_DIR"/*) root="$CORE_DIR/$proj/code" ;;
    "$PROJECTS_DIR"/*) first="${ABS#"$PROJECTS_DIR"/}"; root="$PROJECTS_DIR/${first%%/*}" ;;
    *) return 0 ;;
  esac
  abs_l="$(lc "$ABS")"; root_l="$(lc "$root")"
  case "$abs_l" in "$root_l"/?*) ;; *) return 0 ;; esac
  sub="${ABS:$((${#root} + 1))}"; sub_l="${abs_l:$((${#root} + 1))}"
  shown="$root/$sub"
  # a worktree: the path relative to its root counts (repeatedly, a worktree may hold a .claude/worktrees)
  while :; do
    case "$sub_l" in
      .claude/worktrees/*/?*)
        w="${sub_l#.claude/worktrees/}"; w="${w%%/*}"
        n=$((18 + ${#w} + 1))   # ".claude/worktrees/" is 18 bytes
        sub="${sub:$n}"; sub_l="${sub_l:$n}" ;;
      # the worktrees folder and a worktree folder themselves (mkdir, an existing dir, a trailing slash);
      # a file written directly there is not one and falls through to the .claude/* rule
      .claude/worktrees|.claude/worktrees/?*)
        if [ "$mode" = dir ] || [ -d "$ABS" ] || [ "${1%/}" != "$1" ]; then return 0; fi
        break ;;
      *) break ;;
    esac
  done
  case "$sub_l" in
    .claude/settings.local.json) return 0 ;;
    .claude) [ "$mode" = dir ] && return 0 ;;
    .claude/*|docs|docs/*) ;;
    claude.md|claude.local.md|*/claude.md|*/claude.local.md) ;;
    agents.md|*/agents.md) ;;
    *) return 0 ;;
  esac
  # docs/superpowers stays private even under a public docs entry: .gitignore and the pre-commit hook keep
  # it out of git, so plans written there would never be versioned.
  case "$sub_l" in
    docs/superpowers|docs/superpowers/*) ;;
    *) if is_public "$proj" "$sub_l"; then return 0; fi ;;
  esac
  # the Core's copy is spelled the usual way even when the path was typed in another letter case
  tgt="$sub"
  case "$sub_l" in docs|docs/*) tgt="docs${sub:4}" ;; .claude/*) tgt=".claude${sub:7}" ;; esac
  case "$sub_l" in
    claude.md) tgt="CLAUDE.md" ;;
    claude.local.md) tgt="CLAUDE.local.md" ;;
    */claude.md) tgt="${tgt%/*}/CLAUDE.md" ;;
    */claude.local.md) tgt="${tgt%/*}/CLAUDE.local.md" ;;
    agents.md) tgt="AGENTS.md" ;;
    */agents.md) tgt="${tgt%/*}/AGENTS.md" ;;
  esac
  printf '%s\n' "$(msg guard_code_blocked "$shown" "$CORE_DIR/$proj/$tgt")" >&2
  printf '%s\n' "$(msg guard_code_public "$CORE_DIR/$proj/CLAUDE.md")" >&2
  exit 2
}

# --- The read-only checkers (designer, localizer, security, verifier): their tools leave out Write and
# Edit, and in Bash they may change nothing but the temp folders. The hook input names the agent
# (agent_type) inside a subagent, so this holds wherever the agent runs, in a project or not.
# A temp folder that holds a project (a test sandbox) is still that project.
ro_agent() {
  local a; a="$(json_str "$in" agent_type)"
  case "$a" in corecrew:*) a="${a#corecrew:}" ;; *:*) return 1 ;; esac
  case "$a" in designer|localizer|security|verifier) printf '%s\n' "$a" ;; *) return 1 ;; esac
}
in_temp() {   # in_temp <absolute path>
  local r
  for r in "${TMPDIR:-/tmp}" /tmp /private/tmp /var/folders /private/var/folders; do
    r="$(canon_dir "$r")"
    case "$1" in "$r"|"$r"/*) project_of "$1" >/dev/null 2>&1 && return 1; return 0 ;; esac
  done
  return 1
}
if [ "$tool" = Bash ] && agent="$(ro_agent)"; then
  cmd="$(json_str "$in" command)"
  [ -n "$cmd" ] || exit 0
  load_settings
  TAB="$(printf '\t')"
  # A checker that cannot run refuses: these agents should change nothing, so unknown is no.
  found="$(printf '%s' "$cmd" | LC_ALL=C tr '\n\r' '\002 ' \
    | LC_ALL=C awk -f "$SELF/scripts/bash-lex.awk" -f "$SELF/scripts/bashlex-readonly.awk" 2>/dev/null)" \
    || found="X${TAB}a command this check could not read"
  while IFS="$TAB" read -r kind a; do
    case "$kind" in
      X) what="$a" ;;
      P) resolve_abs "$a"; in_temp "$ABS" && continue; what="$ABS" ;;
      *) continue ;;
    esac
    printf '%s\n' "$(msg readonly_agent "$agent" "$what" "${TMPDIR:-/tmp}")" >&2
    exit 2
  done <<< "$found"
fi

# --- Write, Edit, MultiEdit, NotebookEdit: one path in the tool input. Any other tool passes.
case "$tool" in Write|Edit|MultiEdit|NotebookEdit|Bash) ;; *) exit 0 ;; esac
if [ "$tool" != Bash ]; then
  key=file_path; [ "$tool" = NotebookEdit ] && key=notebook_path
  path="$(json_str "$in" "$key")"
  [ -n "$path" ] || exit 0
  load_settings
  check_path "$path"
  exit 0
fi

# --- Bash: targets of redirects and file commands, found by one awk pass.
cmd="$(json_str "$in" command)"
[ -n "$cmd" ] || exit 0
# Cheap exit: nothing in the command can write a file.
case "$cmd" in *">"*|*tee*|*touch*|*cp*|*mv*|*mkdir*) ;; *) exit 0 ;; esac

# bash_targets — stdin: the command (newlines turned into \002 by the caller). Prints "<kind>\t<path>[\t<name>]":
# W a file written, D a directory made (mkdir), J a destination (cp/mv) that may be a directory: <name> is a source's name.
bash_targets() {
  LC_ALL=C awk -f "$SELF/scripts/bash-lex.awk" -f "$SELF/scripts/bashlex-guard-code.awk" 2>/dev/null
}

targets="$(printf '%s' "$cmd" | LC_ALL=C tr '\n\r' '\002 ' | bash_targets)"
[ -n "$targets" ] || exit 0
load_settings
TAB="$(printf '\t')"
while IFS="$TAB" read -r kind a b; do
  case "$kind" in
    W) check_path "$a" ;;
    D) check_path "$a" dir ;;
    J)
      case "$b" in ""|.|..) continue ;; esac
      resolve_abs "$a"
      if [ -d "$ABS" ] || [ "${a%/}" != "$a" ]; then check_path "${a%/}/$b"; fi ;;
  esac
done <<< "$targets"
exit 0
