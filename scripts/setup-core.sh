#!/usr/bin/env bash
# Creates or completes the Core skeleton: a git repo with .gitignore, README.md, PROJECTS.md,
# standards/README.md, knowledge/README.md and .coredev ("schema: 1"). Run it again any time:
# existing files are never overwritten (a user's README.md or PROJECTS.md stays as it is) and
# nothing is deleted. It never creates a GitHub repo.
# Usage: bash setup-core.sh [<core_dir>] [--dry-run]
#   <core_dir> defaults to $CORE_DIR, then the plugin option core_dir (see lib.sh).
# Output, one line per item: created|skipped <item>, would create|would update <item> (dry run),
#   updated .coredev (the file existed without "schema:" — e.g. only "app-id-prefix:" — so
#   "schema: 1" is put first and the other lines are kept as they were).
# New files are committed as "Set up Core"; only those files, nothing else in the repo.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT_DIR/skills/new-project/templates/core"
. "$ROOT_DIR/scripts/lib.sh"
DRY=0; ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -*) echo "Unknown argument: $1" >&2; exit 2 ;;
    *) [ -z "$ARG" ] || { echo "Usage: setup-core.sh [<core_dir>] [--dry-run]" >&2; exit 2; }
       ARG="$1"; shift ;;
  esac
done
[ -z "$ARG" ] || CORE_DIR="$ARG"
load_settings

CREATED=()   # paths (relative to the Core) of files this run created, for the commit
track() { CREATED[${#CREATED[@]}]="$1"; }
put_tracked() {  # put_tracked <template> <relative dest> — put, and remember it if created
  local out; out="$(put "$1" "$CORE_DIR/$2" copy)" || { echo "$out"; exit 1; }
  echo "$out"
  case "$out" in "created "*) track "$2" ;; esac
}

if [ "$DRY" -eq 0 ]; then mkdir -p "$CORE_DIR" || exit 1; fi
git_init "$CORE_DIR" || exit 1
put_tracked "$TPL/gitignore"          .gitignore
put_tracked "$TPL/README.md"          README.md
put_tracked "$TPL/PROJECTS.md"        PROJECTS.md
put_tracked "$TPL/standards-README.md" standards/README.md
put_tracked "$TPL/knowledge-README.md" knowledge/README.md

# .coredev: "schema: 1" first; lines already there (e.g. app-id-prefix) follow.
F="$CORE_DIR/.coredev"
if core_ready; then
  echo "skipped .coredev"
else
  if [ -f "$F" ]; then verb=update; done_word=updated; else verb=create; done_word=created; fi
  if [ "$DRY" -eq 1 ]; then
    echo "would $verb .coredev"
  else
    tmp="$F.tmp.$$"
    { echo "schema: 1"
      if [ -f "$F" ]; then
        # drop an unusable schema line (e.g. "schema: x"); keep everything else
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in "schema:"*) ;; *) printf '%s\n' "$line" ;; esac
        done < "$F"
      fi
    } > "$tmp" && mv "$tmp" "$F" || { rm -f "$tmp"; echo "Could not write $F" >&2; exit 1; }
    echo "$done_word .coredev"
    track .coredev
  fi
fi

# One commit for what this run created or updated.
if [ "$DRY" -eq 0 ] && [ "${#CREATED[@]}" -gt 0 ]; then
  git -C "$CORE_DIR" add -- "${CREATED[@]}" \
    && git -C "$CORE_DIR" commit -q -m "Set up Core" -- "${CREATED[@]}" \
    || { echo "Files were created, but the commit failed (is git user.name/user.email set?)." >&2; exit 1; }
fi
exit 0
