# Shared by save and undo-step: locate repos from the current directory.
# Sets: CODE (code repo or worktree toplevel), MAIN (main code checkout), PROJECT, NAME, CORE.
locate() {
  local here="$PWD"
  [ -d "$here/code/.git" ] && here="$here/code"
  CODE=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Run this inside a project's code/ folder." >&2; return 1; }
  local common; common=$(cd "$CODE" && cd "$(git rev-parse --git-common-dir)" && pwd)
  MAIN=$(dirname "$common")
  PROJECT=$(dirname "$MAIN"); NAME=$(basename "$PROJECT")
  CORE=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)
  if [ "$(basename "$MAIN")" != "code" ] || [ -z "$CORE" ] || [ "$CORE" = "$MAIN" ]; then
    echo "This folder is not a new-project layout (Core/<name>/code)." >&2; return 1
  fi
  CORE_PATHS="$(core_paths "$CORE" "$NAME")"
  return 0
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
