#!/usr/bin/env bash
# Creates a project skeleton in $CORE_DIR/<name>/ from templates.
# Never overwrites existing files. Usage:
#   bash scaffold.sh --name <name> [--purpose "<text>"] [--dry-run]
# Env: CORE_DIR overrides the configured location (see configure.sh)
set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$SKILL_DIR/templates"
. "$SKILL_DIR/scripts/config-lib.sh"
load_config
CORE_NAME="$(basename "$CORE_DIR")"
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

P="$CORE_DIR/$NAME"
DATE="$(date +%Y-%m-%d)"

# Escape a value for use as a sed replacement with '|' delimiter.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {  # render <template> <dest>
  sed -e "s|{{NAME}}|$(esc "$NAME")|g" \
      -e "s|{{PURPOSE}}|$(esc "$PURPOSE")|g" \
      -e "s|{{PROJECT_DIR}}|$(esc "$P")|g" \
      -e "s|{{CORE_DIR}}|$(esc "$CORE_DIR")|g" \
      -e "s|{{CORE_NAME}}|$(esc "$CORE_NAME")|g" \
      -e "s|{{DATE}}|$DATE|g" "$1" > "$2"
}

# put <template> <dest> [copy] — create dest from template unless it exists.
put() {
  local src="$1" dest="$2" mode="${3:-render}"
  if [ -e "$dest" ]; then echo "skipped ${dest#$CORE_DIR/}"; return; fi
  if [ $DRY -eq 1 ]; then echo "would create ${dest#$CORE_DIR/}"; return; fi
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = copy ]; then cp "$src" "$dest"; else render "$src" "$dest"; fi
  echo "created ${dest#$CORE_DIR/}"
}

mkdir_p() {
  if [ -d "$1" ]; then return; fi
  if [ $DRY -eq 1 ]; then echo "would create ${1#$CORE_DIR/}/"; return; fi
  mkdir -p "$1"; echo "created ${1#$CORE_DIR/}/"
}

git_init() {  # git_init <dir>
  if [ -d "$1/.git" ]; then echo "skipped ${1#$CORE_DIR/}/.git"; return; fi
  if [ $DRY -eq 1 ]; then echo "would create ${1#$CORE_DIR/}/.git"; return; fi
  git init -q "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main
  echo "created ${1#$CORE_DIR/}/.git"
}

# Core repo
mkdir_p "$CORE_DIR"
git_init "$CORE_DIR"
put "$TPL/core/gitignore"   "$CORE_DIR/.gitignore" copy
put "$TPL/core/README.md"   "$CORE_DIR/README.md" copy
put "$TPL/core/PROJECTS.md" "$CORE_DIR/PROJECTS.md" copy

# Shared commands and hook sources (copied once; never overwritten)
put "$SKILL_DIR/core-bin/save"           "$CORE_DIR/bin/save" copy
put "$SKILL_DIR/core-bin/undo-step"      "$CORE_DIR/bin/undo-step" copy
put "$SKILL_DIR/core-bin/_locate.sh"     "$CORE_DIR/bin/_locate.sh" copy
put "$SKILL_DIR/core-bin/stop-remind.sh" "$CORE_DIR/bin/stop-remind.sh" copy
put "$SKILL_DIR/scripts/install-hooks.sh" "$CORE_DIR/bin/install-hooks" copy
for h in blocked-patterns pre-commit-code pre-push-code pre-push-core; do
  put "$SKILL_DIR/hooks/$h" "$CORE_DIR/hooks/$h" copy
done
[ $DRY -eq 1 ] || chmod +x "$CORE_DIR/bin/save" "$CORE_DIR/bin/undo-step" "$CORE_DIR/bin/install-hooks" 2>/dev/null

# Project docs
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
