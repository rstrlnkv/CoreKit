#!/usr/bin/env bash
# Copies a project generated in a temp dir into code/ without overwriting anything,
# and appends the generator's .gitignore lines that code/.gitignore lacks.
# Usage: bash merge-generated.sh <generated_dir> <code_dir>
set -u
SRC="${1:?generated dir}"; DST="${2:?code dir}"
[ -d "$SRC" ] && [ -d "$DST" ] || { echo "Both directories must exist." >&2; exit 1; }
( cd "$SRC" && find . -type f -not -path './.git/*' -not -path ./.gitignore ) | while IFS= read -r f; do
  if [ -e "$DST/$f" ]; then echo "skipped ${f#./}"
  else mkdir -p "$DST/$(dirname "$f")"; cp -p "$SRC/$f" "$DST/$f"; fi
done
if [ -f "$SRC/.gitignore" ]; then
  { echo ""; echo "# From the stack generator"; } > "$DST/.gitignore.add"
  added=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    grep -qxF -- "$line" "$DST/.gitignore" || { echo "$line" >> "$DST/.gitignore.add"; added=1; }
  done < "$SRC/.gitignore"
  [ $added -eq 1 ] && cat "$DST/.gitignore.add" >> "$DST/.gitignore"
  rm -f "$DST/.gitignore.add"
fi
echo "merged into $DST"
