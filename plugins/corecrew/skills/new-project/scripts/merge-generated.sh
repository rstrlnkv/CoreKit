#!/usr/bin/env bash
# Copies a project generated in a temp dir into the code folder (<Projects>/<name>) without overwriting anything,
# and appends the generator's .gitignore lines that the code .gitignore lacks (creating it when missing).
# Exits 1 and names every file that could not be copied; the other files are still copied.
# Usage: bash merge-generated.sh <generated_dir> <code_dir>
set -u
SRC="${1:?generated dir}"; DST="${2:?code dir}"
[ -d "$SRC" ] && [ -d "$DST" ] || { echo "Both directories must exist." >&2; exit 1; }
# Work files live in a temp folder of our own, never in the user's code folder.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/merge-generated.XXXXXX")" || { echo "Could not make a temp folder." >&2; exit 1; }
trap 'rm -rf "$TMPD"' EXIT
FAILED="$TMPD/failed"; : > "$FAILED"
( cd "$SRC" && find . -type f -not -path './.git/*' -not -path ./.gitignore ) > "$TMPD/list" || {
  echo "Could not list the files of $SRC." >&2; exit 1; }
while IFS= read -r f; do
  if [ -e "$DST/$f" ] || [ -L "$DST/$f" ]; then echo "skipped ${f#./}"
  elif ! { mkdir -p "$DST/$(dirname "$f")" && cp -p "$SRC/$f" "$DST/$f"; }; then
    echo "${f#./}" >> "$FAILED"
  fi
done < "$TMPD/list"
if [ -f "$SRC/.gitignore" ]; then
  ADD="$TMPD/gitignore.add"
  { echo ""; echo "# From the stack generator"; } > "$ADD"
  added=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ -f "$DST/.gitignore" ] && grep -qxF -- "$line" "$DST/.gitignore"; then continue; fi
    grep -qxF -- "$line" "$ADD" && continue   # a line the generator lists twice
    echo "$line" >> "$ADD"; added=1
  done < "$SRC/.gitignore"
  if [ $added -eq 1 ]; then
    if [ -f "$DST/.gitignore" ]; then cat "$ADD" >> "$DST/.gitignore"
    elif [ -e "$DST/.gitignore" ] || [ -L "$DST/.gitignore" ]; then false   # not a regular file: left alone
    else tail -n +2 "$ADD" > "$DST/.gitignore"; fi || echo ".gitignore (the generator's lines were not added)" >> "$FAILED"
  fi
fi
if [ -s "$FAILED" ]; then
  echo "merge into $DST is incomplete; these were not copied (check the folder's permissions, then run this again):" >&2
  sed 's/^/  /' "$FAILED" >&2
  exit 1
fi
echo "merged into $DST"
