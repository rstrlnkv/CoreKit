#!/usr/bin/env bash
# Creates a project skeleton in $CORE_DIR/<name>/ from templates.
# Never overwrites existing files. Needs a set-up Core (scripts/setup-core.sh); exits 3 if not.
# Usage:
#   bash scaffold.sh --name <name> [--purpose "<text>"] [--dry-run]
# Env: CORE_DIR overrides the plugin option core_dir (CLAUDE_PLUGIN_OPTION_CORE_DIR); see scripts/lib.sh
set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$SKILL_DIR/templates"
ROOT_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
. "$ROOT_DIR/scripts/lib.sh"
load_settings
NAME=""; PURPOSE="TODO: one or two sentences."; DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --purpose) PURPOSE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
# The purpose is one line in PROJECTS.md and a sed replacement: no line breaks.
PURPOSE="$(printf '%s' "$PURPOSE" | tr '\r\n' '  ' | tr -s ' ')"

if ! LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ ]]' _ "$NAME"; then
  echo "Invalid project name '$NAME': use 3-40 Latin lowercase letters, digits and hyphens," >&2
  echo "starting with a letter and not ending with a hyphen (e.g. my-notes-app)." >&2
  exit 2
fi

if ! core_ready; then
  echo "Core is not set up at $CORE_DIR: run setup-core.sh first" >&2
  exit 3
fi

P="$CORE_DIR/$NAME"
DATE="$(date +%Y-%m-%d)"

# Escape a value for use as a sed replacement with '|' delimiter.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# render <template> <dest> — used by lib.sh's put
render() {
  sed -e "s|{{NAME}}|$(esc "$NAME")|g" \
      -e "s|{{PURPOSE}}|$(esc "$PURPOSE")|g" \
      -e "s|{{PROJECT_DIR}}|$(esc "$P")|g" \
      -e "s|{{CORE_DIR}}|$(esc "$CORE_DIR")|g" \
      -e "s|{{CORE_NAME}}|$(esc "$CORE_NAME")|g" \
      -e "s|{{DATE}}|$DATE|g" "$1" > "$2"
}

# Project docs (the Core itself comes from setup-core.sh)
put "$TPL/CLAUDE.md.tmpl"            "$P/CLAUDE.md"
put "$TPL/docs/INDEX.md.tmpl"        "$P/docs/INDEX.md"
put "$TPL/docs/brief.md.tmpl"        "$P/docs/brief.md"
put "$TPL/docs/architecture.md.tmpl" "$P/docs/architecture.md"
put "$TPL/docs/decisions/001-stack-and-architecture.md.tmpl" \
    "$P/docs/decisions/001-stack-and-architecture.md"
mkdir_p "$P/docs/features"
put "$TPL/rules/tests.md.tmpl"       "$P/.claude/rules/tests.md"

# Code repo
mkdir_p "$P/code"
git_init "$P/code"
put "$TPL/code/gitignore-common"          "$P/code/.gitignore" copy
put "$TPL/code/settings.local.json.tmpl"  "$P/code/.claude/settings.local.json"
put "$TPL/code/worktreeinclude"           "$P/code/.worktreeinclude" copy

# Project list
LINE="- $NAME — $PURPOSE — $NAME/code/"
if [ -f "$CORE_DIR/PROJECTS.md" ] && grep -q "^- $NAME " "$CORE_DIR/PROJECTS.md"; then
  echo "skipped PROJECTS.md entry"
elif [ $DRY -eq 1 ]; then
  echo "would create PROJECTS.md entry"
else
  printf '%s\n' "$LINE" >> "$CORE_DIR/PROJECTS.md"; echo "created PROJECTS.md entry"
fi
