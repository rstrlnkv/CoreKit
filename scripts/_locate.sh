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
  # Core-level files that belong to every step: this project plus shared files.
  CORE_PATHS="$NAME"
  for f in PROJECTS.md README.md .gitignore .coredev standards knowledge session-rules.md bin hooks; do
    [ -e "$CORE/$f" ] && CORE_PATHS="$CORE_PATHS $f"
  done
  return 0
}
