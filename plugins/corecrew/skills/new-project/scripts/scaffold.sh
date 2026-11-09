#!/usr/bin/env bash
# Creates a project skeleton from templates: the internal docs in $CORE_DIR/<name>/ and the code
# repo beside the Core in $PROJECTS_DIR/<name> (with CLAUDE.local.md and AGENTS.md symlinks to the private CLAUDE.md).
# Never overwrites existing files. Needs a set-up Core (scripts/setup-core.sh); exits 3 if not.
# Usage:
#   bash scaffold.sh --name <name> [--purpose "<text>"] [--dry-run]
# Env: CORE_DIR overrides the plugin option core_dir (CLAUDE_PLUGIN_OPTION_CORE_DIR); see scripts/lib.sh
set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
TPL="$ROOT_DIR/templates"
. "$ROOT_DIR/scripts/lib.sh"
load_settings
NAME=""; PURPOSE="TODO: one or two sentences."; DRY=0
usage() { echo 'Usage: scaffold.sh --name <name> [--purpose "<text>"] [--dry-run]' >&2; exit 2; }

# An option that takes a value needs one: `shift 2` with one argument left does not shift (bash 3.2),
# and the loop would never end.
while [ $# -gt 0 ]; do
  case "$1" in
    --name) [ $# -ge 2 ] || usage; NAME="$2"; shift 2 ;;
    --purpose) [ $# -ge 2 ] || usage; PURPOSE="$2"; shift 2 ;;
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
K="$PROJECTS_DIR/$NAME"
# shellcheck disable=SC2034  # render() in lib.sh fills the templates with it
DATE="$(date +%Y-%m-%d)"

# A folder in <Projects> that is not ours (no project in the Core yet) is never touched.
if [ -e "$K" ] && [ ! -e "$P" ]; then
  echo "target exists: $K" >&2
  exit 2
fi

# Project docs (the Core itself comes from setup-core.sh)
put_project_docs "$TPL" "$P" || exit 1
# docs/INDEX.md is generated from the pages' front matter (same path form as the lines above)
if [ "$DRY" -eq 1 ]; then
  if [ -f "$P/docs/INDEX.md" ]; then echo "skipped $(rel_core "$P")/docs/INDEX.md"; else echo "would create $(rel_core "$P")/docs/INDEX.md"; fi
else
  R="$(rel_core "$P")"
  IDX_OUT="$(bash "$ROOT_DIR/scripts/wiki-index.sh" "$P")" || { echo "wiki-index.sh failed for $P" >&2; exit 1; }
  while IFS=' ' read -r word rest; do
    [ -n "$word" ] || continue
    case "$rest" in docs/*) echo "$word $R/$rest" ;; *) echo "$word${rest:+ $rest}" ;; esac
  done <<< "$IDX_OUT"
fi

# Code repo, beside the Core; a step that fails stops the run (no PROJECTS.md entry after it)
mkdir_p "$K" || exit 1
git_init "$K" || exit 1
put "$TPL/code/gitignore-common"          "$K/.gitignore" copy || exit 1
put "$TPL/code/settings.local.json.tmpl"  "$K/.claude/settings.local.json" || exit 1
put "$TPL/code/worktreeinclude"           "$K/.worktreeinclude" copy || exit 1
link_local_claude "$K" "$P" || exit 1
link_agents "$K" "$P" || exit 1

# Project list
projects_entry "$NAME" "$PURPOSE" "$NAME/" || exit 1
