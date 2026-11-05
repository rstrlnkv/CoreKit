#!/usr/bin/env bash
# wiki-pages.sh — the one rule for "which files are wiki pages".
#
# Usage: wiki-pages.sh <docs_dir>
#   <docs_dir>  the project's docs/ folder.
#
# Output: one page per line, relative to <docs_dir> ("features/login.md"), sorted with LC_ALL=C.
# A page is docs/**/*.md except INDEX.md, knowledge/, standards/, superpowers/ and .obsidian/.
# Exit: 0 listed; 2 usage error (no argument, or the folder does not exist).
set -u
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: wiki-pages.sh <docs_dir>" >&2; exit 2; }
d="${1%/}"
(cd "$d" && find . -type f -name '*.md' \
  ! -path './knowledge/*' ! -path './standards/*' ! -path './superpowers/*' ! -path './.obsidian/*' \
  ! -path './INDEX.md' | sed 's|^\./||' | LC_ALL=C sort)
