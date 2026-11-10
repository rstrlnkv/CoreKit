# lib-layout.sh — where a path belongs, for lib.sh (source lib.sh, not this file): the project of a path, linked worktrees,
# the code folder and layout of a project, and the project name rule.

# _project_of_path <path> — with CORE_DIR loaded (load_settings), prints <project> and exits 0 when the path is
# inside a project; otherwise prints nothing and exits 1. Two places count:
#  - inside the Core: <Core>/<project> or anything below it (old layout, worktrees under code/ included);
#    a project is a top-level folder of the Core that holds a CLAUDE.md or a code/ folder; dot-folders,
#    standards/ and knowledge/ never count.
#  - beside the Core: the first folder under <Projects> (the Core's parent) is <Name>; it is a project
#    when lc <Name> (ASCII letters lowered, other bytes as they are) names a project of the Core: <Core>/<name>/CLAUDE.md
#    exists, and <name> is no dot-folder, standards or knowledge. The name rule of valid_project_name is not applied here:
#    a project in the Core may have any folder name (uni проект), and its code folder beside the Core is found the same way.
_project_of_path() {
  local p rest first name pd
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  p="$(canon_dir "$1")"
  case "$p" in
    "$CORE_DIR"/*)
      rest="${p#"$CORE_DIR"/}"; first="${rest%%/*}"
      case "$first" in ""|.*|standards|knowledge) return 1 ;; esac
      [ -d "$CORE_DIR/$first" ] || return 1
      [ -f "$CORE_DIR/$first/CLAUDE.md" ] || [ -d "$CORE_DIR/$first/code" ] || return 1
      printf '%s\n' "$first" ;;
    "$CORE_DIR") return 1 ;;
    *)
      pd="${PROJECTS_DIR:-$(dirname "$CORE_DIR")}"
      case "$p" in "$pd"/*) ;; *) return 1 ;; esac
      rest="${p#"$pd"/}"; first="${rest%%/*}"
      name="$(lc "$first")"
      case "$name" in ""|.*|standards|knowledge|*$'\n'*|*$'\r'*) return 1 ;; esac
      [ -f "$CORE_DIR/$name/CLAUDE.md" ] || return 1
      printf '%s\n' "$name" ;;
  esac
}

# worktree_of <path> — exit 0 and sets WT_ROOT (the worktree folder) and WT_MAIN (the main checkout it belongs to)
# when the path lies in a linked git worktree, wherever that worktree is; else exit 1 and both empty. Reads files
# only (no git process): from the nearest existing folder it walks up to the first ".git"; a ".git" folder
# means a main checkout or a clone (1); a ".git" file must say "gitdir: <main>/.git/worktrees/<name>" and <main>/.git
# must be a folder, which knows this worktree: <main>/.git/worktrees/<name>/gitdir names "<this folder>/.git" (a submodule,
# a dangling, a forged or a renamed-main file gives 1). Callers that give a worktree any power (project_of, the guard's
# root, the links) also check that WT_MAIN is the project's own code folder (wt_is_main_of).
# shellcheck disable=SC2034  # WT_ROOT is read by the callers (guard-code.sh, prepare.sh)
worktree_of() {
  local d g x e b
  WT_ROOT=""; WT_MAIN=""
  [ -n "${1:-}" ] || return 1
  d="$(canon_dir "$1")"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="${d%/*}"; [ -n "$d" ] || d=/; done
  while :; do
    [ -d "$d/.git" ] && return 1
    if [ -f "$d/.git" ]; then
      g=""; { IFS= read -r g < "$d/.git"; } 2>/dev/null || [ -n "$g" ] || return 1
      g="${g%$'\r'}"
      while case "$g" in *[[:blank:]]) true ;; *) false ;; esac; do g="${g%?}"; done
      case "$g" in "gitdir: "?*) x="${g#gitdir: }" ;; *) return 1 ;; esac
      case "$x" in /*) ;; *) x="$d/$x" ;; esac
      case "$x" in */.git/worktrees/?*) ;; *) return 1 ;; esac
      e="$x"; x="${x%/.git/worktrees/*}"
      x="$(canon_dir "$x")"
      [ -d "$x/.git" ] || return 1
      b=""; { IFS= read -r b < "$e/gitdir"; } 2>/dev/null || [ -n "$b" ] || return 1
      b="${b%$'\r'}"
      case "$b" in /*) ;; *) b="$e/$b" ;; esac
      case "$b" in */.git) b="$(canon_dir "${b%/.git}")/.git" ;; *) return 1 ;; esac
      [ "$b" = "$d/.git" ] || return 1
      WT_ROOT="$d"; WT_MAIN="$x"
      return 0
    fi
    [ "$d" = "/" ] && return 1
    d="${d%/*}"; [ -n "$d" ] || d=/
  done
}

# project_of <path> — as _project_of_path, and a path in a linked git worktree of a project's code folder (the
# worktree can be anywhere) counts as the project of that main folder.
project_of() {
  local n
  _project_of_path "$1" && return 0
  worktree_of "$1" || return 1
  n="$(_project_of_path "$WT_MAIN")" || return 1
  wt_is_main_of "$n" || return 1
  printf '%s\n' "$n"
}

# wt_is_main_of <project> — exit 0 when WT_MAIN (set by worktree_of) is the project's own main code folder.
wt_is_main_of() {
  local c
  c="$(code_dir_of "$1" 2>/dev/null)" || return 1
  [ -n "$WT_MAIN" ] && [ "$(canon_dir "$c")" = "$WT_MAIN" ]
}

# code_root_of <path> — prints the code root git sees from <path>: the worktree folder in a linked worktree, else the
# project's main code folder; exit 1 when that is not a project's code folder. (git runs; for skills, not for hooks.)
code_root_of() {
  local t n r here
  here="$(canon_dir "${1:-.}")"
  t="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || t=""
  if [ -n "$t" ] && project_of "$t" >/dev/null; then
    # only a root that holds the folder asked about: a forged gitfile or core.worktree must not point elsewhere
    r="$(canon_dir "$t")"
    case "$here/" in "$r"/*) printf '%s\n' "$t"; return 0 ;; esac
    echo "code-root: $here is not inside $r" >&2; return 1
  fi
  # a session in <Core>/<name>/ (git sees the Core): the project's main code folder
  n="$(project_of "${1:-.}")" || return 1
  case "$here/" in "$CORE_DIR/$n"/*) ;; *) echo "code-root: $here is not inside $CORE_DIR/$n" >&2; return 1 ;; esac
  code_dir_of "$n" 2>/dev/null
}

# code_dir_of <name> — prints the main code folder of a project: <Core>/<name>/code when that is a
# directory (only the old layout has one, so an unrelated <Projects>/<Name> never takes its place); else
# the one folder in <Projects> (not the Core) whose lower-case name is <name>. Exit 1 when there is
# neither; exit 3 (and a line on stderr) when two folders there differ only in letter case.
code_dir_of() {
  local pd d b found="" n=0 second=""
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  if [ -d "$CORE_DIR/$1/code" ]; then printf '%s\n' "$CORE_DIR/$1/code"; return 0; fi
  pd="${PROJECTS_DIR:-$(dirname "$CORE_DIR")}"
  for d in "$pd"/*/; do
    d="${d%/}"; [ -d "$d" ] || continue
    [ "$d" = "$CORE_DIR" ] && continue
    b="$(basename "$d")"
    [ "$(lc "$b")" = "$1" ] || continue
    n=$((n + 1))
    if [ $n -eq 1 ]; then found="$d"; else second="$d"; fi
  done
  if [ $n -gt 1 ]; then
    printf 'two folders differ only in case: %s, %s\n' "$(basename "$found")" "$(basename "$second")" >&2
    return 3
  fi
  [ $n -eq 0 ] && ! ls "$pd" >/dev/null 2>&1 && { _code_dir_from_cwd "$pd" "$1"; return; }
  [ $n -eq 1 ] || return 1
  printf '%s\n' "$found"
}

# _code_dir_from_cwd <Projects> <name> — for code_dir_of when <Projects> cannot be listed (the corecrew Codex profile
# does not open it: it holds other projects' secrets): prints <Projects>/<b> when the cwd is that folder or below it,
# lc <b> is <name> and it is a folder; else exit 1. No case-clash check: the other folders cannot be seen.
_code_dir_from_cwd() {
  local p rest b
  for p in "$(pwd -P)" "${PWD:-}"; do
    case "$p/" in "$1"/?*) ;; *) continue ;; esac
    rest="${p#"$1"/}"; b="${rest%%/*}"
    [ "$(lc "$b")" = "$2" ] && [ -d "$1/$b" ] && [ "$1/$b" != "$CORE_DIR" ] || continue
    printf '%s\n' "$1/$b"; return 0
  done
  return 1
}

# layout_of <name> — prints "new" (code folder beside the Core) or "old" (<Core>/<name>/code); exit 1
# when the project has no code folder (or exit 3 on a case clash, from code_dir_of).
layout_of() {
  local d rc=0
  d="$(code_dir_of "$1")" || rc=$?
  [ $rc -eq 0 ] || return $rc
  case "$d" in "$CORE_DIR"/*) echo old ;; *) echo new ;; esac
}

# old_code_of <name> — prints <Core>/<name>/code and exits 0 when it holds a git repo (a .git folder or file): a project
# in the old layout of corecrew 0.4 and older, which this version does not support (session start names it; adopt,
# save, undo-step and code_dir_of refuse it). Else exit 1.
old_code_of() {
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  { [ -e "$CORE_DIR/$1/code/.git" ] || [ -L "$CORE_DIR/$1/code/.git" ]; } || return 1
  printf '%s\n' "$CORE_DIR/$1/code"
}

# old_layout_msg <code folder> — the line that refuses an old-layout code folder (adopt, save, undo-step, code_dir_of).
# Session start says the same in the person's language (messages.sh old_layout).
old_layout_msg() {
  local t=/corecrew:task
  # shellcheck disable=SC2016  # $corecrew is literal text: Codex calls the skill so
  [ "$(host)" != codex ] || t='$corecrew:task'
  printf '%s keeps the code inside the Core, the layout of corecrew 0.4 and older, which corecrew 1.0 no longer supports; move the project beside the Core with corecrew 0.15 first (%s adopt %s)\n' "$1" "$t" "$1"
}

# valid_project_name <name> — exit 0 when it is 3-40 Latin lowercase letters, digits and hyphens,
# starting with a letter and not ending with a hyphen (the rule for <Core>/<name>/), and is not
# core, standards or knowledge.
valid_project_name() {
  case "$1" in core|standards|knowledge) return 1 ;; esac
  LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ ]]' _ "$1"
}
