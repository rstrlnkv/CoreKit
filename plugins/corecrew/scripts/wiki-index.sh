#!/usr/bin/env bash
# wiki-index.sh — generate docs/INDEX.md, one line per page, from the pages' front matter.
#
# Usage: wiki-index.sh <project_dir> [--check]
#   <project_dir>  the Core project folder (has docs/); the title uses its folder name.
#   --check        write nothing; compare with the file on disk.
#
# Output (write mode): "created docs/INDEX.md", "updated docs/INDEX.md" or "skipped docs/INDEX.md".
# Output (--check): nothing when INDEX.md is current, "wiki-index: stale" when it differs or is missing.
# Groups in order: brief architecture decision feature spec plan glossary; pages by name as
# "[[name]] description". Done or superseded pages are left out and counted in a "history:" line.
# Pages without a known type are left out (wiki-check reports them).
# Exit: 0 ok; 1 stale (--check only); 2 usage error.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
mode=write; proj=""
for a in "$@"; do
  case "$a" in
    --check) mode=check ;;
    -*) echo "usage: wiki-index.sh <project_dir> [--check]" >&2; exit 2 ;;
    *) [ -z "$proj" ] && proj="$a" || { echo "usage: wiki-index.sh <project_dir> [--check]" >&2; exit 2; } ;;
  esac
done
proj="${proj%/}"
[ -n "$proj" ] && [ -d "$proj/docs" ] || { echo "usage: wiki-index.sh <project_dir> [--check]" >&2; exit 2; }
docs="$proj/docs"; idx="$docs/INDEX.md"
tmp="$(mktemp "${TMPDIR:-/tmp}/wiki-index.XXXXXX")" || exit 2
rows="$tmp.rows"; out="$tmp.out"
trap 'rm -f "$tmp" "$rows" "$out"' EXIT
: > "$rows"

# one awk reads the front matter: prints type, status, description (tab separated)
while IFS= read -r page; do
  name="$(basename "$page" .md)"
  awk -v n="$name" '
    function val(s) { sub(/^[^:]*:/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (length(s) >= 2 && ((s ~ /^".*"$/) || (s ~ /^'"'"'.*'"'"'$/))) s = substr(s, 2, length(s) - 2)
      return s }
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^type:/ { t = val($0) }
    /^status:/ { s = val($0) }
    /^description:/ { d = val($0) }
    END { printf "%s\t%s\t%s\t%s\n", t, n, s, d }
  ' "$docs/$page" >> "$rows"
done < <("$HERE/wiki-pages.sh" "$docs")

{
  printf '# %s wiki\nOne line per page; open only the page you need.\n' "$(basename "$proj")"
  echo
  for t in brief architecture decision feature spec plan glossary; do
    awk -F'\t' -v t="$t" '$1 == t && $3 != "done" && $3 != "superseded" { print $2 "\t" $4 }' "$rows" \
      | LC_ALL=C sort -t "$(printf '\t')" -k1,1 > "$tmp"
    [ -s "$tmp" ] || continue
    printf '## %s\n' "$t"
    awk -F'\t' '{ printf "[[%s]] %s\n", $1, $2 }' "$tmp"
  done
  hist="$(awk -F'\t' '$1 ~ /^(brief|architecture|decision|feature|spec|plan|glossary)$/ && ($3 == "done" || $3 == "superseded") { n++ } END { print n + 0 }' "$rows")"
  [ "$hist" -gt 0 ] && printf 'history: %s done or superseded pages, see wiki.base\n' "$hist"
} > "$out"

if [ "$mode" = check ]; then
  if [ -f "$idx" ] && cmp -s "$out" "$idx"; then exit 0; fi
  echo "wiki-index: stale"; exit 1
fi
if [ ! -f "$idx" ]; then verb=created
elif cmp -s "$out" "$idx"; then echo "skipped docs/INDEX.md"; exit 0
else verb=updated; fi
chmod 644 "$out"; mv "$out" "$idx" && echo "$verb docs/INDEX.md"
