#!/usr/bin/env bash
# allowed-files.sh <path>... — of the files and folders the user named, prints the files the skill may
# send (tracked or untracked, not git-ignored, and not a secret), one per line, relative to the current
# folder. A named path it does not print is a secret, missing or git-ignored.
# allowed-files.sh --pathspec — prints the exclusion pathspec (<EXCLUDE> in SKILL.md) on one line, each
# part in single quotes, for `git diff HEAD -- . <EXCLUDE>` and the like.
#
# The secret names come from secret-patterns.txt next to this script (ask-gpt.sh builds its Codex
# profile from the same list). Without a readable, non-empty list nothing is printed and it exits 4.
#
# Why a script and not `git ls-files -- <named> <excludes>`: when every named path lies in one folder
# (a single file is enough), git drops the exclude pathspecs' meaning — `:(exclude)*.env` then lists
# nothing at all, and `:(exclude,glob)**/*.env` lets the secret through (seen with git 2.54, macOS).
# Listed from `.` the excludes work, so the whole allowed list is taken once and the named paths are
# picked from it.
[ $# -gt 0 ] || { echo "usage: allowed-files.sh <path>... | --pathspec" >&2; exit 2; }
list_file="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/secret-patterns.txt"
ex=()
if [ -r "$list_file" ]; then
  while IFS= read -r g || [ -n "$g" ]; do
    g="${g#"${g%%[![:space:]]*}"}"; g="${g%%[[:space:]]*}"   # trim; text after a space is a comment
    case "$g" in
      ''|'#'*) continue ;;
      *[\"\'\\]*) echo "allowed-files.sh: a pattern with a quote or backslash in $list_file: $g" >&2; exit 4 ;;
    esac
    ex+=(":(exclude,glob,icase)**/$g")
    # a folder of that name: everything under it (with glob magic, * does not cross a /)
    [ "${g%/\*\*}" != "$g" ] || ex+=(":(exclude,glob,icase)**/$g/**")
  done < "$list_file"
fi
[ "${#ex[@]}" -gt 0 ] || { echo "allowed-files.sh: no secret patterns in $list_file; nothing may be sent" >&2; exit 4; }
if [ "$1" = --pathspec ]; then
  [ $# -eq 1 ] || { echo "usage: allowed-files.sh <path>... | --pathspec" >&2; exit 2; }
  out=""; for s in "${ex[@]}"; do out="$out${out:+ }'$s'"; done
  printf '%s\n' "$out"; exit 0
fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "allowed-files.sh: not a git repository" >&2; exit 3; }
list="$(git ls-files --cached --others --exclude-standard -- . "${ex[@]}")" || exit 1
for p in "$@"; do
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  # a file is matched whole, a folder by its prefix; "." is everything
  printf '%s\n' "$list" | P="$p" LC_ALL=C awk 'BEGIN { p = ENVIRON["P"] } $0 != "" && (p == "." || $0 == p || index($0, p "/") == 1)'
done | LC_ALL=C sort -u
