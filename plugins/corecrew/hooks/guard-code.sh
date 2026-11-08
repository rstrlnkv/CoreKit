#!/usr/bin/env bash
# Claude Code and Codex PreToolUse hook on Write|Edit|NotebookEdit|apply_patch (and Bash, best effort): a project's
# internal files must not live in its code repo. It blocks writes of
#   CLAUDE.md (and CLAUDE.local.md), AGENTS.md (the cross-tool agent instructions), docs/**, .claude/**
# under the project's code folder (<Projects>/<Name>/**, or <Core>/<project>/code/** in the old layout),
# with exit 2 and a message naming the right place:
#   corecrew: <path> is an internal file and must not live in the code folder. Write it to <Core>/<project>/<relative path> instead.
#   Docs meant to stay public in the code folder: list them on a "public-docs: <paths>" line in <Core>/<project>/CLAUDE.md.
# Nothing is ever printed to stdout.
#
# Rules, all compared on the canonical path (".." and symlinks resolved, letter case as on disk
# for the part that exists, then folded to lower case for the comparison, ASCII only):
# - The code root is <Projects>/<Name>/ (the first folder of the path under <Projects>; the CLAUDE.local.md symlink there resolves into the
#   Core and so passes), or <Core>/<p>/code/ in the old layout, or a worktree root <code root>/.claude/worktrees/<w>/ or any other linked git worktree of the code folder (worktree_of);
#   inside a worktree the path relative to the worktree root is what counts.
# - Blocked: docs and docs/** and .claude/** at the root, and CLAUDE.md / CLAUDE.local.md / AGENTS.md at
#   ANY depth (the same as scripts/git-hooks/blocked-patterns, so the hook and the commit check agree).
# - Allowed: .claude/settings.local.json, .claude/worktrees/** (the worktree dirs themselves: mkdir, an
#   existing directory or a trailing slash; a file written directly under .claude/worktrees/ is blocked), and the
#   paths on a "public-docs: <paths>" line of <Core>/<p>/CLAUDE.md (space or comma separated, relative
#   to the code root; a directory entry covers everything under it; a glob is not expanded), except
#   docs/superpowers/** (git ignores it and the pre-commit hook blocks it, so it is always private).
# - Codex: the tool is apply_patch (tool_input.command is the patch text) and the shell is "Bash"; Write and Edit
#   are only matcher aliases there. The paths of Add File, Update File and Move to are judged
#   (scripts/patch-paths.awk; a relative path against the stdin cwd; Delete File and the source of a move are
#   not; the D kind is not consumed). More than 100 paths (a C line) are refused, with the message to split the patch.
#   A text with an X line (no Begin Patch, an unknown "***" line, a header after other text on its line) still has its
#   W lines judged; besides, its "***" lines are checked raw (internal_hit: a component docs, .claude, claude.md,
#   claude.local.md or agents.md in any case, no public-docs exception) and a hit is refused; no hit passes. Header lines and
#   paths are trimmed like Codex does (Unicode spaces too). A text with no string to read passes.
#   In Codex only (scripts/shell-patch.sh shell_patch_host: the plugin lies under CODEX_HOME, or the input carries Codex's turn_id; Claude
#   Code has no apply_patch tool, so nothing is refused there) a patch handed to the shell is refused, not judged, in every
#   folder, and the message names what matched. This is BEST EFFORT, NOT A SECURITY BOUNDARY: it
#   catches plain and accidental shell patches and many disguised ones, cannot see names the shell builds at run time, and the
#   apply_patch tool form is the checked path (known ways past it: the Limits below, plus $'apply'$'_patch', 'apply_pat'?h,
#   extglob, IFS changes, write_stdin) (a scope gate by cwd or by wrapper was bypassed
#   twice; paths built by cd, quoting, $(...) or a variable cannot be checked from the command text). Rule, in
#   scripts/shell-patch.sh shell_patch_refused (no shell parsing; a missing file lets every call pass, like a missing
#   lib.sh): a hit is apply_patch, applypatch or apply-patch (any letter case) in the text
#   once ' " \ and newlines are deleted (also --codex-run-as-apply-patch), or "*** Begin Patch" followed by an Add File,
#   Update File, Delete File or Move to marker, or a $' with an escape, or an unquoted glob word that can match the name
#   and is a command word or keeps 4 or more literal characters (../bin/apply_pat?h, ls; * x; not rm -rf dist/*); in a
#   heredoc body it is never a command word and counts when it has a / (../bin/*pply_patch*), or is Markdown emphasis whose
#   text holds apply_ apply- or applyp (*apply_pat*; **Patch**, *apply* pass), or is no emphasis and its literal part holds
#   "apply" or it has a ? or [ or an inner * (apply_pa*, ap?ly_patch, appl*_patch; a leading-star *ply_patch is a limit).
#   A hit passes only in the simple form: one read-only
#   command (grep egrep fgrep rg, git log|show|diff|grep|status|blame|commit -m, cat head tail ls wc find) piped only through
#   sort uniq cut tr nl wc head tail grep rg; quoted text is opaque there, outside quotes no $ ` \ ; & < > ( ) { } ! or newline;
#   no assignment first, and no program-running option (git -c -p -O --pag* --ext* --output* --open-files-in-pager* and their
#   abbreviations, not --oneline; rg --pre -z, find -exec -delete, sort --co*). Exit 2 with
#   "run patches with the apply_patch tool ... (matched: <what>)". Over-blocking by design (Codex): echo apply_patch, cd x && grep apply_patch .,
#   grep apply_patch f > out, man apply_patch, FOO=apply_patch make, grep apply_patch $FILE. Limits: a name built at run time (a=apply;
#   ${a}_patch, $(...) or backticks (also empty), brace expansion, $'apply'$'_patch', 'apply_pat'?h, extglob), a glob that expands to a file whose name is an option (-...), a script file or
#   interpreter that runs it.
#   Limit: Codex does send agent_type for subagents, but ro_agent never fires there: Codex agent names are neither
#   corecrew:* nor the bare checker names (a Codex crew is started by text; task 4 adds a git status check).
#   Limit: write_stdin into an open exec session: no evidence that it runs the hook (to be checked live).
# - Bash: a plain reading for honest mistakes (ADR 009: the host's permissions and the git pre-commit and pre-push hooks
#   are the boundary; deliberate evasion is out of scope). scripts/bashlex-guard-code.awk reads words, quotes, comments,
#   heredoc bodies and separators, and prints the write targets: > >> >| &> >&file <>, tee, touch, mkdir, install
#   (-d makes dirs), cp, mv and git mv (the destination; a destination directory also gets the sources' names), ln (a
#   CLAUDE.local.md or AGENTS.md at the code root that links a file in the Core, not in a code folder, passes: session
#   start asks for that link; a relative source is read from the cwd; a source made at run time, such as
#   "$HOME/Projects/Core/<p>/CLAUDE.md", is unknown and gets the same pass; a link named .claude/worktrees/<name> passes
#   like a worktree folder), and the files that sed and perl edit in place (-i; BSD sed's suffix as its own word,
#   -i .bak or -i '', is no file). mkdir follows the same rules as a write except the bare ".claude" dir, which holds
#   settings.local.json.
#   A target is judged by check_path below, like a file tool's path. Wrappers (sudo -u x, timeout 5, nice -n 5,
#   env, if, do, ...) and VAR=value prefixes are skipped. A heredoc inside "$(...)" (the commit-message idiom) has its
#   body skipped. The first 100 distinct targets are judged; past that only the targets whose text names docs, .claude,
#   CLAUDE.md, CLAUDE.local.md or AGENTS.md. More than 100 such targets past the first 100 refuse the whole command
#   (guard_code_too_many) when the cwd or a target is in scope: judging them all would outlast the hook timeout. A link
#   or a copy into a folder counts as three targets. A missing reader lets the Bash call pass;
#   the file tools are still judged. The shell-patch refusal (Codex) runs before all this, in every folder.
#   LIMIT (not followed, each pinned as a passing case in tests/test_hook_guard_code.sh): a relative target after cd,
#   pushd or popd (`cd .. && echo x >> docs/INDEX.md` is the Core wiki); a target with $ ` * ? [ { (variables,
#   $(...), globs, braces); a command line handed to another shell (bash -c, sh -c, eval) or a script file; xargs,
#   find -exec, interpreters (python -c, node -e); git -C <dir> mv; other writers (rsync, dd of=, tar -C, curl -o);
#   a wrapper option whose value is not skipped (only -u -g -n -s -k -C -c take one: stdbuf -o L tee); past 100
#   targets, a target that reaches docs/ only through a link; the file-target judging outside a project.
# - Inert outside a project (<Core>/<project>/
#   or its code folder beside the Core): a target and a cwd that are not in a project pass (exit 0).
#   No network, no git; only canon_dir, project_of and one grep of the CLAUDE.md public-docs line.
# - Input it cannot read (not JSON, no cwd, no path or command) passes.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/scripts/shell-patch.sh" 2>/dev/null || exit 0   # shell_patch_host, shell_patch_refused (Codex)
# A writer into a pipe whose reader may stop early has its stderr dropped: with SIGPIPE ignored, bash 5's printf
# builtin and tr report "Broken pipe" to the user (seen on Linux CI).
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

# check_path <path> [dir|link|corelink] — exits 2 with the message when the path is an internal file under a
# project's code root; returns 0 otherwise. Mode "dir" (mkdir) lets the bare .claude through; modes "link" and
# "corelink" (ln) let a link named .claude/worktrees/<name> through, like a worktree folder; mode "corelink" (ln to
# a file in the Core, or to a source made at run time) also lets CLAUDE.local.md and AGENTS.md at the code root
# through: the layout links them so.
check_path() {
  local mode="${2:-write}" proj root abs_l root_l sub sub_l shown w n tgt first
  resolve_abs "$1"
  abs_l="$(lc "$ABS")"
  # no internal component anywhere in the path: nothing to judge (most targets stop here, without project_of)
  case "/$abs_l/" in */docs/*|*/.claude/*|*/claude.md/*|*/claude.local.md/*|*/agents.md/*) ;; *) return 0 ;; esac
  proj="$(project_of "$ABS")" || return 0
  # the code root: the project folder in <Projects> taken from the path itself (new layout; so no case
  # clash between folders can switch the guard off), or <Core>/<p>/code for a path inside the Core (old)
  # A linked git worktree wherever it lives (Codex keeps them outside Projects) is its own code root.
  # Only a worktree its main folder knows, of this project's own code folder (worktree_of, wt_is_main_of). One inside
  # the main folder is its own root too, except under docs/ or .claude/ there (a worktree must not unprotect them;
  # Claude's .claude/worktrees/<w> is read from the main root below).
  if worktree_of "$ABS" && wt_is_main_of "$proj" && case "$(lc "$WT_ROOT")/" in
      "$(lc "$WT_MAIN")"/docs/*|"$(lc "$WT_MAIN")"/.claude/*) false ;; *) true ;; esac; then
    root="$WT_ROOT"
  else
    case "$ABS" in
      "$CORE_DIR"/*) root="$CORE_DIR/$proj/code" ;;
      "$PROJECTS_DIR"/*) first="${ABS#"$PROJECTS_DIR"/}"; root="$PROJECTS_DIR/${first%%/*}" ;;
      *) return 0 ;;
    esac
  fi
  root_l="$(lc "$root")"
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
      # the worktrees folder and a worktree folder themselves (mkdir, an existing dir, a trailing slash, or a
      # link named .claude/worktrees/<name>); a file written directly there is not one and falls through to the .claude/* rule
      .claude/worktrees|.claude/worktrees/?*)
        if [ "$mode" = dir ] || [ -d "$ABS" ] || [ "${1%/}" != "$1" ]; then return 0; fi
        case "$mode:$sub_l" in link:.claude/worktrees/?*|corelink:.claude/worktrees/?*) return 0 ;; esac
        break ;;
      *) break ;;
    esac
  done
  if [ "$mode" = corelink ]; then case "$sub_l" in claude.local.md|agents.md) return 0 ;; esac; fi
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
  # (tr's stderr is dropped: an awk that fails early would make it print "write error: Broken pipe", see internal_hit;
  # spaces become \004 when the command has no \004 byte: the tokenizer then reads a plain word whole, bash-lex.awk Speed)
  sp=' '; lexsp=0; eot="$(printf '\004')"; case "$cmd" in *"$eot"*) ;; *) sp="$eot"; lexsp=1 ;; esac
  found="$({ printf '%s' "$cmd"; } 2>/dev/null | LC_ALL=C tr '\n\r ' "$(printf '\002')$sp$sp" 2>/dev/null \
    | LC_ALL=C awk -v lexsp="$lexsp" -f "$SELF/scripts/bash-lex.awk" -f "$SELF/scripts/bashlex-readonly.awk" 2>/dev/null)" \
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
case "$tool" in Write|Edit|MultiEdit|NotebookEdit|apply_patch|Bash) ;; *) exit 0 ;; esac

# internal_hit — stdin: raw text. Prints what looks like an internal path in it and exits 0, or exits 1. The text
# is cut into components at / \ quotes, blanks and shell punctuation; a component docs, .claude, claude.md,
# claude.local.md or agents.md (any letter case) is a hit. Used where a patch cannot be read as headers: no
# public-docs entry or settings.local.json exception applies there, so this errs on the side of blocking.
# Every reader in these pipelines takes all of its input (sed -n 1p, not grep -m1 or head): the host may run the hook
# with SIGPIPE ignored, and then a writer whose reader stopped early prints "write error: Broken pipe" to the user.
internal_hit() {
  local hit
  hit="$(LC_ALL=C tr '\134\057\042[:space:]\054:;=()<>&|\173\175\140\047' '\n' | LC_ALL=C tr 'A-Z' 'a-z' \
    | LC_ALL=C grep -xE 'docs|\.claude|claude\.md|claude\.local\.md|agents\.md' | LC_ALL=C sed -n 1p)"
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}
# refuse_raw <text with *** lines> — exit 2 when a *** line of an unreadable patch names an internal path
refuse_raw() {
  local hit line
  hit="$(printf '%s\n' "$1" | LC_ALL=C grep -F '***' | internal_hit)" || return 0
  # the message quotes the first "***" line that holds the component (cut to 200 bytes), not the bare component
  line="$(printf '%s\n' "$1" | LC_ALL=C grep -F '***' | LC_ALL=C grep -iF -- "$hit" | LC_ALL=C sed -n 1p | LC_ALL=C cut -c1-200)"
  printf '%s\n' "$(msg patch_unjudgeable "${line:-$hit}")" >&2
  exit 2
}
# judge_patch <kind> <path> — one line of patch_paths output (a W line is judged; a C line refuses the patch);
# $PATCH_X is set for X.
judge_patch() {
  case "$1" in
    C) printf '%s\n' "$(msg patch_too_many 100)" >&2; exit 2 ;;
    X) PATCH_X=1 ;;
    W) check_path "$2" ;;
  esac
}

# --- apply_patch (Codex): the paths of the patch text. W lines are judged (Add, Update without a move,
# the destination of a move); a deleted file and a move source are not (cleaning up is legitimate).
# Relative paths resolve against the stdin cwd. More than 100 paths (a C line) are refused. A text with an X line
# (not a patch, or a header the reader cannot place) still has its W lines judged, and its *** lines are checked
# raw for an internal path. A reader that is missing or failed (patch_paths status non-zero) refuses the call outright;
# a reader that ran and printed nothing (a patch naming no file) passes. A text with no string to read passes (exit 0).
if [ "$tool" = apply_patch ]; then
  patch="$(json_str "$in" command)"
  [ -n "$patch" ] || exit 0
  load_settings
  TAB="$(printf '\t')"
  PATCH_X=""
  # The reader is missing or failed: nothing can be judged, not even raw (a path may be cwd-relative or hide a TAB),
  # so the call is refused outright. A reader that ran and printed nothing: no path to judge, pass.
  found="$(patch_paths "$patch")" || { printf '%s\n' "$(msg patch_no_reader)" >&2; exit 2; }
  [ -n "$found" ] || exit 0
  while IFS="$TAB" read -r kind a; do
    judge_patch "$kind" "$a"
  done <<< "$found"
  [ -z "$PATCH_X" ] || refuse_raw "$patch"
  exit 0
fi

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
# A Codex patch applied through the shell is refused, in Codex only (see the header).
if shell_patch_host "$in" && shell_patch_refused "$cmd"; then printf '%s\n' "$(msg patch_shell "$SHELL_PATCH_HIT")" >&2; exit 2; fi
# Cheap exit: nothing in the command can write a file.
case "$cmd" in *">"*|*tee*|*touch*|*mkdir*|*cp*|*mv*|*ln*|*install*|*sed*|*perl*) ;; *) exit 0 ;; esac

# The targets: "W <path>" a file written, "D <path>" a directory made, "J <dir> <source>" and "L <dest> <source>"
# (see scripts/bashlex-guard-code.awk).
# tr's stderr is dropped: the reader stops early when it is missing or has too many targets (C), and with SIGPIPE
# ignored tr would then print "write error: Broken pipe" to the user.
targets="$({ printf '%s' "$cmd"; } 2>/dev/null | LC_ALL=C tr '\n\r' '\002 ' 2>/dev/null | LC_ALL=C awk -f "$SELF/scripts/bashlex-guard-code.awk" 2>/dev/null)"
[ -n "$targets" ] || exit 0
NL='
'
load_settings
# A last line C: too many internal-looking targets to judge within the hook timeout. Refuse the whole command, but only
# in scope: the cwd is in a project, or a target names the folder that holds the Core (the code folders sit beside it).
if [ "${targets##*"$NL"}" = C ]; then
  case "$targets" in *"$(dirname "$CORE_DIR")"/*) printf '%s\n' "$(msg guard_code_too_many)" >&2; exit 2 ;; esac
  project_of "$(canon_dir "$cwd")" >/dev/null 2>&1 || exit 0
  printf '%s\n' "$(msg guard_code_too_many)" >&2; exit 2
fi
TAB="$(printf '\t')"
# into_dir <dest> <source> [mode] — cp, mv, ln into a directory: <dest>/<base name of source> is judged when <dest> is one
into_dir() {
  local s="$2"
  while [ "${s%/}" != "$s" ]; do s="${s%/}"; done
  s="${s##*/}"
  case "$s" in ""|.|..) return 0 ;; esac
  resolve_abs "$1"
  if [ -d "$ABS" ] || [ "${1%/}" != "$1" ]; then check_path "${1%/}/$s" "$3"; fi
}
while IFS="$TAB" read -r kind a b; do
  case "$kind" in
    W) check_path "$a" ;;
    D) check_path "$a" dir ;;
    J) into_dir "$a" "$b" ;;
    L) # ln -s "<Core>/<p>/CLAUDE.md" CLAUDE.local.md (session start asks for it) links the private copy: mode corelink.
      # A source made at run time ("$HOME/...", empty here) is unknown: given the same pass, and no name to put in a dir.
      if [ -z "$b" ]; then check_path "$a" corelink; continue; fi
      m="link"; resolve_abs "$b"
      case "$ABS/" in "$CORE_DIR"/*/code/*) ;; "$CORE_DIR"/*) m=corelink ;; esac
      check_path "$a" "$m"; into_dir "$a" "$b" "$m" ;;
  esac
done <<< "$targets"
exit 0
