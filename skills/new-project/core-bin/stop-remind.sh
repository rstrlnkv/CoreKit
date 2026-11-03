#!/usr/bin/env bash
# Claude Code Stop hook: reminds Claude to run `save` when the code repo or this
# project's docs have uncommitted changes. Reminds once per stop (stop_hook_active) and
# once per set of changes, so it stays quiet while Claude waits for the user's approval.
. "$(dirname "$0")/_locate.sh"
in=$(cat)
printf '%s' "$in" | grep -qE '"stop_hook_active" *: *true' && exit 0
cwd=$(printf '%s' "$in" | sed -nE 's/.*"cwd" *: *"([^"]*)".*/\1/p')
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0
locate 2>/dev/null || exit 0
dirty=""
[ -n "$(git -C "$CODE" status --porcelain)" ] && dirty="code"
# shellcheck disable=SC2086
[ -n "$(git -C "$CORE" status --porcelain -- $CORE_PATHS)" ] && dirty="${dirty:+$dirty and }docs"
STATE="$(git -C "$CODE" rev-parse --absolute-git-dir)/new-project-stop-remind"
[ -z "$dirty" ] && { rm -f "$STATE"; exit 0; }

# untracked <repo> [paths] — checksums of untracked files, so their edits count as changes
untracked() {
  local repo="$1"; shift
  (cd "$repo" && git ls-files --others --exclude-standard -- "$@" | while IFS= read -r f; do
    cksum "$f"; done)
}
# shellcheck disable=SC2086
sum=$({ git -C "$CODE" status --porcelain; git -C "$CODE" diff HEAD 2>/dev/null; untracked "$CODE"
        git -C "$CORE" status --porcelain -- $CORE_PATHS; git -C "$CORE" diff HEAD -- $CORE_PATHS 2>/dev/null
        untracked "$CORE" $CORE_PATHS; } | cksum)
[ "$(cat "$STATE" 2>/dev/null)" = "$sum" ] && exit 0
echo "$sum" > "$STATE"
echo "Uncommitted changes in $dirty. If this working step is finished, run: bash \"$CORE/bin/save\" \"<short English message>\". If you are waiting for the user's answer or approval, do not save; just end your turn." >&2
exit 2
