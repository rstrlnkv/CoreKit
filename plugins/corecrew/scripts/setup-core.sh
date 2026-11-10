#!/usr/bin/env bash
# Creates or completes the Core skeleton: a git repo with .gitignore, README.md, PROJECTS.md,
# standards/README.md, knowledge/README.md and .coredev ("schema: 2"). Run it again any time:
# existing files are never overwritten (a user's README.md or PROJECTS.md stays as it is) and
# nothing is deleted. It never creates a GitHub repo.
# Usage: bash setup-core.sh [<core_dir>] [--dry-run]
#   <core_dir>: absolute or ~/...; a relative path is refused (exit 2, nothing created). Without it:
#   $CORE_DIR, then the plugin option core_dir (see lib.sh).
# Output, one line per item: created|skipped <item>, would create|would update <item> (dry run),
#   updated .coredev (the file existed without "schema:" — e.g. only "app-id-prefix:" — or with an
#   older schema number, so "schema: N" is put first and the other lines are kept as they were).
# Setup files that are not committed yet are committed as "Set up Core" (a failed commit is
# retried on the next run); only setup-owned files, nothing else in the repo. Git must know the
# user's name and email; if not, the run stops first with the commands to set them.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT_DIR/templates/core"
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
# An invalid argument stops the run: never set up the default Core in its place. It is judged as
# _resolve_setting judges a value (trailing newlines dropped; the "${user_config." placeholder is no
# value). An invalid plugin option or settings file keeps the documented default.
if [ -n "$ARG" ]; then
  _nl_trim "$ARG"
  # shellcheck disable=SC2016  # the placeholder text is literal
  case "$ARG" in *'${user_config.'*) _NT="" ;; esac
  _setting_valid core_dir "$_NT" || {
    echo "setup-core: $ARG: the Core path must be absolute or start with ~/; nothing was created." >&2; exit 2; }
  CORE_DIR="$ARG"
fi
load_settings
[ -n "$CORE_DIR" ] || { echo "setup-core: no Core path (give <core_dir>, or set core_dir, CORE_DIR or HOME); nothing was created." >&2; exit 2; }

# The setup files as "template|path in the Core", in the order their lines are printed (.coredev is written below).
FILES=("gitignore|.gitignore" "README.md|README.md" "PROJECTS.md|PROJECTS.md"
       "standards-README.md|standards/README.md" "knowledge-README.md|knowledge/README.md")

# schema_old — true when .coredev holds a schema number below this plugin's (core_ready is true).
schema_old() {
  local sv; sv="$(coredev_get schema | tr -d '[:space:]')"
  case "$sv" in ""|*[!0-9]*) return 1 ;; esac
  [ "$sv" -lt "$COREDEV_SCHEMA" ]
}

# need_work — true when a run is not a no-op (something to create or update).
need_work() {
  [ -d "$CORE_DIR/.git" ] || return 0
  core_ready || return 0
  ! schema_old || return 0
  local f
  for f in "${FILES[@]}"; do
    [ -e "$CORE_DIR/${f#*|}" ] || return 0
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
for pair in "${FILES[@]}"; do
  put "$TPL/${pair%%|*}" "$CORE_DIR/${pair#*|}" copy || exit 1
done

# .coredev: "schema: 2" first; lines already there (e.g. app-id-prefix) follow.
F="$CORE_DIR/.coredev"
if core_ready && ! schema_old; then
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
  for pair in "${FILES[@]}"; do pend "${pair#*|}" "$TPL/${pair%%|*}"; done
  pend .coredev ""
  if [ "${#PENDING[@]}" -gt 0 ]; then
    git -C "$CORE_DIR" add -- "${PENDING[@]}" \
      && git -C "$CORE_DIR" commit -q -m "Set up Core" -- "${PENDING[@]}" \
      || { echo "The Core files are in place, but git could not commit them. Fix the problem above and run setup again: it will commit them." >&2; exit 1; }
  fi
fi
exit 0
