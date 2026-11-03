#!/usr/bin/env bash
# Claude Code Stop hook: reminds Claude to run `save` when the code repo or this
# project's docs have uncommitted changes. Reminds once per stop (stop_hook_active) and
# once per set of changes, so it stays quiet while Claude waits for the user's approval.
# _locate.sh sits next to this file (old copies in <Core>/bin) or under ../scripts in the plugin;
# `save` sits next to _locate.sh.
D="$(dirname "$0")"
[ -f "$D/_locate.sh" ] || D="$D/../scripts"
. "$D/_locate.sh"
# json_str comes from lib.sh; an old copy of this hook in <Core>/bin has no lib.sh next to it.
if [ -f "$D/lib.sh" ]; then . "$D/lib.sh"
else json_str() { printf '%s' "$1" | sed -nE "s/.*\"$2\" *: *\"([^\"]*)\".*/\1/p"; }; fi
SAVE="$(cd "$D" && pwd)/save"
in=$(cat)
printf '%s' "$in" | tr -d '\r\n' | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
cwd=$(json_str "$in" cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0
locate 2>/dev/null || exit 0
dirty=""
[ -n "$(git -C "$CODE" status --porcelain)" ] && dirty="code"
# shellcheck disable=SC2086
[ -n "$(git -C "$CORE" status --porcelain -- $CORE_PATHS)" ] && dirty="${dirty:+$dirty and }docs"
STATE="$(git -C "$CODE" rev-parse --absolute-git-dir)/new-project-stop-remind"
[ -z "$dirty" ] && { rm -f "$STATE"; exit 0; }

# changes <repo> [paths] — status, staged and unstaged diffs (work without commits) and
# checksums of untracked files (-z: no quoting of non-ASCII names; xargs: one cksum per batch)
changes() {
  local repo="$1"; shift
  git -C "$repo" status --porcelain -- "$@"
  git -C "$repo" diff -- "$@"; git -C "$repo" diff --cached -- "$@"
  (cd "$repo" && git ls-files -z --others --exclude-standard -- "$@" | xargs -0 cksum 2>/dev/null)
}
# shellcheck disable=SC2086
sum=$({ changes "$CODE"; changes "$CORE" $CORE_PATHS; } | cksum)
[ "$(cat "$STATE" 2>/dev/null)" = "$sum" ] && exit 0
echo "$sum" > "$STATE"
echo "Uncommitted changes in $dirty. If this working step is finished, run: bash \"$SAVE\" \"<short English message>\". If you are waiting for the user's answer or approval, do not save; just end your turn." >&2
exit 2
