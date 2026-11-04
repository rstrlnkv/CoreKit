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

if ! valid_project_name "$NAME"; then
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

# Project docs (the Core itself comes from setup-core.sh)
put_project_docs "$TPL" "$P" || exit 1

# Code repo
mkdir_p "$P/code"
git_init "$P/code"
put "$TPL/code/gitignore-common"          "$P/code/.gitignore" copy
put "$TPL/code/settings.local.json.tmpl"  "$P/code/.claude/settings.local.json"
put "$TPL/code/worktreeinclude"           "$P/code/.worktreeinclude" copy

# Project list
projects_entry "$NAME" "$PURPOSE" "$NAME/code/" || exit 1
