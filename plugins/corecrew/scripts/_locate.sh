# Shared by save and undo-step: locate repos from the current directory (locate), and check that a
# repo can commit before anything changes (can_commit).
# Sets: CODE (code repo or worktree toplevel), MAIN (main code checkout), PROJECT (<Core>/<name>),
# NAME, CORE, CORE_PATHS. Two layouts: old (<Core>/<name>/code) and new (<Projects>/<Name> beside
# the Core, with a CLAUDE.local.md symlink to <Core>/<name>/CLAUDE.md).
# shellcheck disable=SC2034  # CODE MAIN PROJECT NAME CORE CORE_PATHS are read by save and undo-step, which source this file
locate() {
  local here="$PWD" common link ldir n
  [ -d "$here/code/.git" ] && here="$here/code"
  CODE=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Run this inside a project's code folder." >&2; return 1; }
  # A session in <Core>/<name>/ (a new-layout project, or a subfolder of an old-layout one): git finds
  # the Core repo (it has .coredev); the code folder is the project's, from code_dir_of.
  if [ -f "$CODE/.coredev" ]; then
    type project_of >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || return 1
    CORE_DIR="$CODE"; load_settings
    if n=$(project_of "$here"); then
      here=$(code_dir_of "$n" 2>/dev/null) && CODE=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || {
        echo "Run this inside a project's code folder." >&2; return 1; }
    fi
  fi
  # CDPATH='' and >/dev/null: with CDPATH exported, cd to the relative .git could print the folder or go elsewhere
  common=$(cd "$CODE" && CDPATH='' cd -- "$(git rev-parse --git-common-dir)" >/dev/null && pwd)
  MAIN=$(dirname "$common")
  PROJECT=$(dirname "$MAIN"); NAME=$(basename "$PROJECT")
  CORE=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)
  if [ "$(basename "$MAIN")" = "code" ] && [ -n "$CORE" ] && [ "$CORE" != "$MAIN" ]; then
    _name_splits "$NAME" && return 1
    CORE_PATHS="$(core_paths "$CORE" "$NAME")"
    return 0
  fi
  # New layout. lib.sh sits next to this file (in the plugin and in the tools copy).
  type project_of >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || return 1
  link=$(readlink "$MAIN/CLAUDE.local.md" 2>/dev/null)
  case "$link" in
    /*/CLAUDE.md) ;;
    */CLAUDE.md) link="$MAIN/$link" ;;
    *) link="" ;;
  esac
  if [ -n "$link" ]; then
    ldir=$(cd "$(dirname "$link")/.." 2>/dev/null && pwd -P) && CORE_DIR="$ldir"
  fi
  load_settings
  NAME=$(project_of "$MAIN") && [ "$(code_dir_of "$NAME" 2>/dev/null)" = "$(canon_dir "$MAIN")" ] \
    && [ -d "$CORE_DIR/.git" ] || {
    echo "This folder is not a corecrew project (<Projects>/<Name> with <Core>/<name>/CLAUDE.md)." >&2
    return 1; }
  _name_splits "$NAME" && return 1
  CORE="$CORE_DIR"; PROJECT="$CORE/$NAME"
  CORE_PATHS="$(core_paths "$CORE" "$NAME")"
  return 0
}

# _name_splits <project> — exit 0 (and a line on stderr) when the project name holds a space or a tab. save and
# undo-step pass CORE_PATHS to git unquoted, so such a name would split into words: the code commit would be made and
# the docs commit would fail. locate refuses it first, before either script changes anything.
_name_splits() {
  case "$1" in
    *[[:blank:]]*)
      echo "save and undo-step cannot handle a project name with a space: $1. Rename <Core>/$1 (and its code folder) without spaces, or commit by hand with git." >&2
      return 0 ;;
  esac
  return 1
}

# core_paths <core> <project> — the Core paths that belong to every step of <project>, on one line,
# space-separated: the project folder plus the shared files. `save` commits exactly these, and the
# task skill's clean-tree checks look at exactly these (`lib.sh core-paths <project>`). A shared
# file counts when it exists or git still tracks it (a deletion is part of the step too). The entries
# missing on disk are asked about in one `git ls-files`; each path it prints counts for its first
# component, the entry it is under. The output keeps the fixed order of the list.
core_paths() {
  local core="$1" out="$2" f p missing="" tracked=" " IFS=$' \t\n'
  local list="PROJECTS.md README.md .gitignore .coredev standards knowledge session-rules.md bin hooks"
  for f in $list; do
    [ -e "$core/$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    # shellcheck disable=SC2086  # the fixed names above, none with a space
    while IFS= read -r -d '' p; do tracked="$tracked${p%%/*} "; done < <(git -C "$core" ls-files -z -- $missing 2>/dev/null)
  fi
  for f in $list; do
    if [ -e "$core/$f" ]; then out="$out $f"
    else case "$tracked" in *" $f "*) out="$out $f" ;; esac; fi
  done
  printf '%s\n' "$out"
}

# can_commit <repo> <tool> <what was not done> — exit 0 when git can commit in <repo>: a readable repo, a
# writable git folder, no index.lock, a git identity. Else one line on stderr, "<tool>: <cause>; <what
# was not done>.", and exit 1. save and undo-step call it before their first commit, so a step is not
# left half saved or half undone for a reason known in advance. With CDPATH set, cd can print the folder
# it went to; the cd here ignores CDPATH and prints nothing.
can_commit() {
  local r="$1" tool="$2" what="$3" gd common
  gd=$(git -C "$r" rev-parse --absolute-git-dir 2>/dev/null) &&
    common=$(cd "$r" && CDPATH='' cd -- "$(git rev-parse --git-common-dir)" >/dev/null && pwd) || {
    echo "$tool: $r is not a readable git repo; $what." >&2; return 1; }
  if [ ! -w "$gd" ] || [ ! -w "$common" ] || [ ! -w "$common/objects" ]; then
    echo "$tool: git could not write $r/.git (read-only? in Codex allow the commit when asked); $what." >&2; return 1
  fi
  if [ -e "$gd/index.lock" ]; then
    echo "$tool: $gd/index.lock exists: another git command is running in $r, or one crashed. Wait for it, or remove that file if no git command is running; $what." >&2
    return 1
  fi
  if ! git -C "$r" var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! git -C "$r" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    echo "$tool: git has no user identity in $r (set user.name and user.email); $what." >&2; return 1
  fi
}
