#!/usr/bin/env bash
# wiki-check.sh — deterministic wiki checks (rules in reference/wiki.md).
#
# Usage: wiki-check.sh <project_dir> [--code <dir>] [--changed <path>...]
#   <project_dir>  the Core project folder <Core>/<name>: CLAUDE.md, docs/ (map docs/INDEX.md).
#                  The code lives elsewhere (beside the Core, or in the old layout in code/).
#   --code <dir>   the code root: every files: entry of an active page must exist there.
#
# Wiki pages are what wiki-pages.sh lists (docs/**/*.md except INDEX.md, knowledge/, standards/,
# superpowers/, .obsidian/). A page's name is its file name without ".md".
#
# Checks (one line per failure, "wiki-check: <file>: <problem>", exit 1; silent and 0 when green):
#   missing front matter field <f>             type/status/description/files/related/updated absent,
#                                              or type/status/description/updated empty
#   unknown front matter field <f>             a key beyond those six (the wiki allows exactly six)
#   bad type: <v>                              not brief architecture decision feature spec plan glossary
#   bad status: <v>                            not draft active done superseded
#   bad updated: <v>                           not YYYY-MM-DD
#   description over 80 chars                 counted in characters, surrounding quotes removed
#   description not one line                  the value starts with > or | (a folded or literal block)
#   related is not a wikilink: <item>          a related: item that is not [[...]] ([] passes)
#   duplicate page name <name>                 on each later page (sorted path order) with a taken name
#   broken wikilink [[<target>]]               no such page/file, or no such heading (alias dropped)
#   use a wikilink: <target>                   a Markdown link from a page to a wiki page
#   broken link <target>                       a Markdown link whose file does not exist
#   unclosed front matter                      opening --- without a closing ---
#   duplicate heading <h>                      the same "## " heading twice in one page
#   page over 8 KB without ## headings
#   INDEX.md stale                             on INDEX.md: "wiki-index.sh --check" fails
#   drift: <code path> changed, page not updated      (only with --changed; not on done or superseded pages)
#   missing file <path>                        (only with --code) a files: entry of an active page is not there
# Two lines stand alone: "wiki-check: INDEX.md: missing" (there is no docs/INDEX.md; the other
# checks still run) and "wiki-check: docs: missing docs/ directory" (exit 1, nothing else checked).
# <file> is relative to docs/ ("features/login.md"); CLAUDE.md is printed as "../CLAUDE.md".
# Pages are read for wikilinks (body and the related: field) and Markdown links; CLAUDE.md for
# Markdown links only; all outside code fences and `inline code`. Markdown links ignore other
# schemes (http:, mailto:...) and pure "#anchor"; "page.md#anchor" checks the file only.
# A wikilink [[t]], [[t#h]], [[t|alias]] or ![[t]] resolves: t with a "/" to docs/t.md or the file
# docs/t; t without one to the page named t, else a file named t anywhere under docs/; an empty
# t to the page itself. h is the exact text of a # to ###### heading of that page, outside fences.
#
# --changed paths: code files as code-root-relative paths (what "git diff --name-only" prints in
# the code root). A changed wiki page is passed as "<project_dir>/docs/<page>.md" (absolute, the
# unambiguous form), "../docs/<page>.md" or "docs/<page>.md"; all mean docs/<page>.md of the project. So a code file that lives in a
# top-level docs/ folder of code/ cannot be told apart from a wiki page; it is taken as a page.
# (An absolute path under another folder is a code path, not a page.) Any other "../<path>" lies
# outside the project's code and docs and is ignored.
# A page's files: entries match a changed path exactly, or by prefix when the entry ends in "/".
#
# --code <dir>: each files: entry of a page with status active is tested in the working tree of the
# code root, a folder entry (ending in "/") with -d, any other with -e. Draft pages list files they
# will create and done or superseded pages are history: neither is tested. The working tree is what
# counts, so a gitignored file that is absent there (CLAUDE.local.md in a fresh worktree) is missing.
#
# Exit: 0 green, 1 problems found, 2 usage or internal error (e.g. awk failed: never "green"). Portable bash 3.2 + BSD awk.
# The checks themselves are one awk program, scripts/wiki-check.awk, run once per file.

set -u

usage() { echo "usage: wiki-check.sh <project_dir> [--code <dir>] [--changed <path>...]" >&2; exit 2; }

[ $# -ge 1 ] || usage
PROJ="$1"; shift
CODE=""
if [ "${1-}" = "--code" ]; then
  { [ $# -ge 2 ] && [ -n "$2" ] && [ "$2" != "--changed" ]; } || usage
  CODE="$2"; shift 2
  [ -d "$CODE" ] || { echo "wiki-check: $CODE: not a directory" >&2; exit 2; }
  CODE="$(cd "$CODE" && pwd)"
fi
HAVE_CHANGED=0
if [ $# -gt 0 ]; then
  [ "$1" = "--changed" ] || usage
  HAVE_CHANGED=1; shift
  for a in "$@"; do [ "$a" != "--code" ] || usage; done   # --code goes before --changed
fi
[ -d "$PROJ" ] || { echo "wiki-check: $PROJ: not a directory" >&2; exit 2; }
PROJ="$(cd "$PROJ" && pwd)"
DOCS="$PROJ/docs"
[ -d "$DOCS" ] || { echo "wiki-check: docs: missing docs/ directory"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-check.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

HERE="$(cd "$(dirname "$0")" && pwd)"

# Wiki pages (docs-relative, one per line) and every file under docs/ (wikilinks may name any).
"$HERE/wiki-pages.sh" "$DOCS" > "$T/pages" || exit 2
( set -o pipefail; cd "$DOCS" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$T/files" || exit 2

# Changed paths: "C <code path>" or "P <docs-relative page>".
: > "$T/changed"
if [ "$HAVE_CHANGED" = 1 ]; then
  for a in "$@"; do
    a="${a#./}"
    case "$a" in
      "$PROJ"/docs/*) printf 'P %s\n' "${a#"$PROJ"/docs/}" ;;
      ../docs/*) printf 'P %s\n' "${a#../docs/}" ;;
      docs/*)    printf 'P %s\n' "${a#docs/}" ;;
      ../*)      ;;                         # outside the project's code and docs
      *)         printf 'C %s\n' "$a" ;;
    esac
  done >> "$T/changed"
fi

# The checks: one awk program beside this script. Missing means a broken install: an error, never "green".
CHECK_AWK="$HERE/wiki-check.awk"
[ -r "$CHECK_AWK" ] || { echo "wiki-check: internal error: $CHECK_AWK is missing" >&2; exit 2; }

# run_awk <mode> <display name> <file> <dir of file relative to project>
run_awk() {
  LC_ALL=C WC_MODE="$1" WC_REL="$2" WC_PROJ="$PROJ" WC_FDIR="$4" WC_SIZE="$(wc -c < "$3" | tr -d ' ')" WC_CODE="$CODE" \
  WC_CHANGED="$T/changed" WC_PAGES="$T/pages" WC_FILES="$T/files" awk -f "$CHECK_AWK" "$3"
}

# A failing awk must not read as "green": remember it in $T/failed and exit 2 below.
run_checked() { run_awk "$@" || echo "$2" >> "$T/failed"; }

OUT="$(
  if [ ! -f "$DOCS/INDEX.md" ]; then echo "wiki-check: INDEX.md: missing"
  else
    "$HERE/wiki-index.sh" "$PROJ" --check > /dev/null 2>&1; rc=$?      # (no "case" here: bash 3.2 misparses it in $( ))
    if [ "$rc" = 1 ]; then echo "wiki-check: INDEX.md: INDEX.md stale"
    elif [ "$rc" != 0 ]; then echo INDEX.md >> "$T/failed"; fi
  fi
  while IFS= read -r page; do
    d="$(dirname "$page")"; if [ "$d" = . ]; then d=docs; else d="docs/$d"; fi
    run_checked page "$page" "$DOCS/$page" "$d"
  done < "$T/pages"
  if [ -f "$PROJ/CLAUDE.md" ]; then run_checked claude ../CLAUDE.md "$PROJ/CLAUDE.md" ""; fi
)"

if [ -s "$T/failed" ]; then
  echo "wiki-check: internal error: awk failed on: $(tr '\n' ' ' < "$T/failed")" >&2
  exit 2
fi
if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; exit 1; fi
exit 0
