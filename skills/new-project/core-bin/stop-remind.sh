#!/usr/bin/env bash
# Claude Code Stop hook: reminds Claude to run `save` when the code repo or this
# project's docs have uncommitted changes. Reminds once per stop (stop_hook_active).
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
[ -z "$dirty" ] && exit 0
echo "Uncommitted changes in $dirty. If this working step is finished, run: bash \"$CORE/bin/save\" \"<short English message>\"" >&2
exit 2
