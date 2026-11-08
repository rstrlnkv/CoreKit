#!/usr/bin/env bash
# Claude Code Stop hook: reminds Claude to run `save` when the code repo or this
# project's docs have uncommitted changes. Reminds once per stop (stop_hook_active) and
# once per set of changes, so it stays quiet while Claude waits for the user's approval.
# Inert outside a project (<Core>/<project>/ or
# its code folder beside the Core): a repo with the same shape elsewhere passes.
# _locate.sh, lib.sh and `save` sit under ../scripts in the plugin.
D="$(dirname "$0")/../scripts"
. "$D/_locate.sh"
. "$D/lib.sh" 2>/dev/null || exit 0   # json_str, load_settings, project_of; next to _locate.sh
. "$(dirname "$0")/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting
SAVE="$(cd "$D" && pwd)/save"
in=$(cat)
printf '%s' "$in" | tr -d '\r\n' | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
cwd=$(json_str "$in" cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0
load_settings
project_of "$cwd" >/dev/null || exit 0
locate 2>/dev/null || exit 0
dirty=""
[ -n "$(git -C "$CODE" status --porcelain)" ] && dirty="code"
# shellcheck disable=SC2086
if [ -n "$(git -C "$CORE" status --porcelain -- $CORE_PATHS)" ]; then
  if [ -n "$dirty" ]; then dirty="both"; else dirty="docs"; fi
fi
STATE="$(git -C "$CODE" rev-parse --absolute-git-dir)/new-project-stop-remind"
[ -z "$dirty" ] && { rm -f "$STATE"; exit 0; }

# Untracked files are fingerprinted by name, size and time, never by content (a large untracked file
# costs nothing, an unreadable one still counts): `ls -lnd` gives name, size and a time to the
# minute; `find -newer` against the state file catches an edit within the same minute.
# untracked — NUL-separated absolute paths of the untracked files of the code repo and of this
# project's Core paths (-z: no quoting of non-ASCII names; absolute: no name reads as an option).
untracked() {
  local repo f
  for repo in "$CODE" "$CORE"; do
    # shellcheck disable=SC2086
    if [ "$repo" = "$CODE" ]; then set --; else set -- $CORE_PATHS; fi
    git -C "$repo" ls-files -z --others --exclude-standard -- "$@" |
      while IFS= read -r -d '' f; do printf '%s/%s\0' "$repo" "$f"; done
  done
}
# newer_than <file> — the untracked paths changed after <file> was written, one per line.
newer_than() {
  untracked | xargs -0 -r sh -c 'r=$1; shift; find "$@" -prune -newer "$r" -print' sh "$1" 2>/dev/null
}
# changes <repo> [paths] — status, staged and unstaged diffs (work without commits)
changes() {
  local repo="$1"; shift
  git -C "$repo" status --porcelain -- "$@"
  git -C "$repo" diff -- "$@"; git -C "$repo" diff --cached -- "$@"
}
# shellcheck disable=SC2086
sum=$({ changes "$CODE"; changes "$CORE" $CORE_PATHS; untracked | LC_ALL=C xargs -0 -r ls -lnd -- 2>/dev/null; } | cksum)
# The state file: the sum, then the untracked paths dated after it was written (a clock ahead, a
# file unpacked with a future date): those stay "newer" and are not news at the next stop.
if [ -f "$STATE" ]; then
  fresh=$(newer_than "$STATE" | grep -vxF -f <(tail -n +2 "$STATE"))
  [ "$(head -1 "$STATE")" = "$sum" ] && [ -z "$fresh" ] && exit 0
fi
echo "$sum" > "$STATE"
future=$(newer_than "$STATE")
[ -z "$future" ] || printf '%s\n' "$future" >> "$STATE"
noattr=""; [ "$ATTRIBUTION" = forbid ] && noattr=" --no-attribution"
case "$dirty" in
  code) what="$(msg dirty_code)" ;;
  docs) what="$(msg dirty_docs)" ;;
  *) what="$(msg dirty_both)" ;;
esac
# Exit 2 with the reminder on stderr: the one continuation form verified for both hosts (Codex
# rust-v0.166.0 makes that stderr the continuation prompt, ADR 004; Claude Code shows it to Claude).
# A JSON reply on stdout is not verified for Codex, and the same hooks.json serves both.
printf '%s\n' "$(msg stop_remind "$what" "$SAVE" "$noattr")" >&2
exit 2
