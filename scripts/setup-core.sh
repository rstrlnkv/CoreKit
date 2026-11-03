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
# Setup files that are not committed yet are committed as "Set up Core" (a failed commit is
# retried on the next run); only setup-owned files, nothing else in the repo. Git must know the
# user's name and email; if not, the run stops first with the commands to set them.
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

# need_work — true when a run is not a no-op (something to create or update).
need_work() {
  [ -d "$CORE_DIR/.git" ] || return 0
  core_ready || return 0
  local f
  for f in .gitignore README.md PROJECTS.md standards/README.md knowledge/README.md; do
    [ -e "$CORE_DIR/$f" ] || return 0
  done
  return 1
}

# Commit needs a git identity. Check first, so a missing one stops the run before anything is
# written (a plain message is better than a half-finished Core).
if [ "$DRY" -eq 0 ] && need_work; then
  if [ -d "$CORE_DIR" ]; then g() { git -C "$CORE_DIR" "$@"; }; else g() { git "$@"; }; fi
  if ! g var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! g var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    echo "Git does not know who you are yet, so setup cannot save its first commit. Run:" >&2
    echo "  git config --global user.name \"Your Name\"" >&2
    echo "  git config --global user.email \"you@example.com\"" >&2
    echo "then run setup again. Nothing was created." >&2
    exit 1
  fi
fi

if [ "$DRY" -eq 0 ]; then mkdir -p "$CORE_DIR" || exit 1; fi
git_init "$CORE_DIR" || exit 1
put "$TPL/gitignore"           "$CORE_DIR/.gitignore" copy || exit 1
put "$TPL/README.md"           "$CORE_DIR/README.md" copy || exit 1
put "$TPL/PROJECTS.md"         "$CORE_DIR/PROJECTS.md" copy || exit 1
put "$TPL/standards-README.md" "$CORE_DIR/standards/README.md" copy || exit 1
put "$TPL/knowledge-README.md" "$CORE_DIR/knowledge/README.md" copy || exit 1

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
    { echo "schema: $COREDEV_SCHEMA"
      if [ -f "$F" ]; then
        # drop an unusable schema line (e.g. "schema: x"); keep everything else
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in "schema:"*) ;; *) printf '%s\n' "$line" ;; esac
        done < "$F"
      fi
    } > "$tmp" && mv "$tmp" "$F" || { rm -f "$tmp"; echo "Could not write $F" >&2; exit 1; }
    echo "$done_word .coredev"
  fi
fi

# One commit for the setup items that are not committed yet. Chosen on every run (not only for
# what this run created), so a commit that failed earlier is retried. Only setup-owned files
# qualify: .coredev, and the others only while identical to our template — a user's own
# README.md or PROJECTS.md, or anything else in the repo, is never swept in.
if [ "$DRY" -eq 0 ]; then
  PENDING=()
  pend() {  # pend <relative path> <template or ""> — queue it if uncommitted and ours
    [ -f "$CORE_DIR/$1" ] || return 0
    [ -z "$2" ] || cmp -s "$2" "$CORE_DIR/$1" || return 0
    [ -n "$(git -C "$CORE_DIR" status --porcelain -- "$1" 2>/dev/null)" ] || return 0
    PENDING[${#PENDING[@]}]="$1"
  }
  pend .gitignore           "$TPL/gitignore"
  pend README.md            "$TPL/README.md"
  pend PROJECTS.md          "$TPL/PROJECTS.md"
  pend standards/README.md  "$TPL/standards-README.md"
  pend knowledge/README.md  "$TPL/knowledge-README.md"
  pend .coredev             ""
  if [ "${#PENDING[@]}" -gt 0 ]; then
    git -C "$CORE_DIR" add -- "${PENDING[@]}" \
      && git -C "$CORE_DIR" commit -q -m "Set up Core" -- "${PENDING[@]}" \
      || { echo "The Core files are in place, but git could not commit them. Fix the problem above and run setup again: it will commit them." >&2; exit 1; }
  fi
fi
exit 0
