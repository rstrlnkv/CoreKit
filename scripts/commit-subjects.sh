#!/usr/bin/env bash
# Checks the commit subjects of this repository (CONTRIBUTING.md, Commits): a Conventional Commits
# type, an optional lowercase scope, then `: ` and text, at most 72 bytes. For contributors; not part
# of any plugin.
# Usage: commit-subjects.sh --range <a..b>     the subjects of the non-merge commits in the range (CI)
#        commit-subjects.sh --file <message>   the message file of a commit-msg hook
# Generated subjects are exempt in both modes: `Revert "...` and `Undo step ...`. In --file mode
# `fixup! `, `squash! ` and `amend! ` are exempt too: they are squashed before CI sees them.
# Exit 0 when every subject passes, 1 with one line per bad subject on stderr, 2 on a bad argument, outside a git
# repository ("not a git repository") or with a range git cannot read ("bad range <a..b>"); git's own stderr is silenced.
set -u
RE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|merge)(\([a-z0-9][a-z0-9-]*\))?!?: [^ ]'
MAX=72

usage() {
  echo 'Usage: commit-subjects.sh --range <a..b> | --file <message-file>' >&2
  exit 2
}

# check <subject> <file-mode 0|1> — prints the reason on stderr and returns 1 when the subject is bad
check() {
  local s="$1" n
  case "$s" in 'Revert "'*|'Undo step '*) return 0 ;; esac
  if [ "$2" = 1 ]; then case "$s" in 'fixup! '*|'squash! '*|'amend! '*) return 0 ;; esac; fi
  n=$(printf '%s' "$s" | LC_ALL=C wc -c | tr -d ' ')
  if [ "$n" -gt "$MAX" ]; then
    echo "commit-subjects: $n bytes, at most $MAX: $s" >&2; return 1
  fi
  if ! printf '%s\n' "$s" | LC_ALL=C grep -qE "$RE"; then
    echo "commit-subjects: not 'type(scope): subject' (a known type, a lowercase scope or none, one space): $s" >&2
    return 1
  fi
}

[ $# -eq 2 ] || usage
bad=0
case "$1" in
  --range)
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "commit-subjects: not a git repository" >&2; exit 2; }
    list=$(git log --no-merges --format=%s "$2" -- 2>/dev/null) || { echo "commit-subjects: bad range $2" >&2; exit 2; }
    [ -n "$list" ] || exit 0
    while IFS= read -r s; do check "$s" 0 || bad=1; done <<EOF_LIST
$list
EOF_LIST
    ;;
  --file)
    [ -f "$2" ] || usage
    # the subject: the first line that is neither blank nor a comment
    subject=$(grep -v '^#' "$2" | grep -m 1 -v '^[[:space:]]*$')
    if [ -z "$subject" ]; then echo "commit-subjects: the message has no subject line" >&2; exit 1; fi
    check "$subject" 1 || bad=1
    ;;
  *) usage ;;
esac
exit $bad
