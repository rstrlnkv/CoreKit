# Shared by save and undo-step: locate repos from the current directory.
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
# file counts when it exists or git still tracks it (a deletion is part of the step too).
core_paths() {
  local core="$1" out="$2" f
  for f in PROJECTS.md README.md .gitignore .coredev standards knowledge session-rules.md bin hooks; do
    if [ -e "$core/$f" ] || git -C "$core" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      out="$out $f"
    fi
  done
  printf '%s\n' "$out"
}
