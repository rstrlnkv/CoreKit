#!/usr/bin/env bash
# ask-gpt.sh <temp folder> [medium|high] — one read-only Codex run for the second-opinion skill.
# The temp folder holds prompt.md (what GPT reads) and dir (the project folder path, nothing else:
# it is read from the file, so the path never goes through shell parsing). Prints the exit code,
# GPT's answer and the log tail (20 lines, 80 after a failed run), then removes the temp folder however the run
# ends (it holds the diff). Exit 2: bad arguments; exit 3: run inside a Codex session (refused, nothing sent).
#
# What the profile confines (checked with `codex sandbox`, codex 0.166; see SKILL.md, section Ask GPT):
# reads of the project folder, minimal system paths and temp folders only; every secret name the
# skill's send filter drops (secret-patterns.txt) is blocked inside the project too; no writes, no network for commands.
# --ignore-user-config keeps ~/.codex/config.toml (MCP servers, plugins) out; web search is off.
T="$1"; effort="${2:-medium}"
case "$T" in ''|/) echo "usage: ask-gpt.sh <temp folder> [medium|high]" >&2; exit 2 ;; esac
[ -f "$T/prompt.md" ] && [ -f "$T/dir" ] || { echo "ask-gpt.sh: $T/prompt.md or $T/dir is missing" >&2; exit 2; }
# The folder is removed at the end, so it must be a mktemp folder (coreopinion.* as SKILL.md makes it, or tmp.* from a
# bare `mktemp -d`) right in a temp folder: $TMPDIR, the system one (macOS: getconf DARWIN_USER_TEMP_DIR, where a bare
# `mktemp -d` lands whatever TMPDIR says) or /tmp, all compared after resolving links (/tmp is /private/tmp on macOS).
# A wrong path, the project say, is refused and left alone; a temp folder that resolves to / counts as none.
t_dir="$(cd "$T" 2>/dev/null && pwd -P)" || exit 2
t_ok=""
for r in "${TMPDIR:-}" "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" /tmp; do
  [ -n "$r" ] || continue
  r="$(cd "$r" 2>/dev/null && pwd -P)" || continue
  [ "$r" != / ] || continue
  case "${t_dir#"$r"/}" in "$t_dir"|*/*) ;; tmp.?*|coreopinion.?*) t_ok=1 ;; esac
done
[ -n "$t_ok" ] || { echo "ask-gpt.sh: $T is not a mktemp -d folder in the temp folder; nothing was run or removed" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
trap 'exit 130' HUP INT TERM   # a signal ends the run; the EXIT trap then cleans up
# Claude Code only: inside a Codex session (Codex sets CODEX_THREAD_ID in every shell it runs, 0.166) GPT would
# review its own session's work. Refused after the trap, so the temp folder is still removed.
if [ -n "${CODEX_THREAD_ID:-}" ]; then
  echo "ask-gpt.sh: coreopinion works only in Claude Code, and this runs inside a Codex session; nothing was sent. Ask for the second opinion in Claude Code." >&2
  exit 3
fi
case "$effort" in medium|high) ;; *) effort=medium ;; esac
dir="$(cat "$T/dir")"
# Outside a git repository Codex refuses to start without the flag; GPT then gets an empty folder.
extra=""
if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  mkdir -p "$T/empty"; dir="$T/empty"; extra="--skip-git-repo-check"
fi
# Every secret name in secret-patterns.txt (the list allowed-files.sh filters the material with) is denied
# at any depth of the project, and so is everything under a folder of that name. Without a readable, non-empty list codex is not run.
list_file="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/secret-patterns.txt"
deny=""
if [ -r "$list_file" ]; then
  while IFS= read -r g || [ -n "$g" ]; do
    g="${g#"${g%%[![:space:]]*}"}"; g="${g%%[[:space:]]*}"   # trim; text after a space is a comment
    case "$g" in
      ''|'#'*) continue ;;
      *[\"\'\\]*) echo "ask-gpt.sh: a pattern with a quote or backslash in $list_file: $g; nothing was run" >&2; exit 2 ;;
    esac
    deny="$deny, \"**/$g\"=\"deny\""
    # a folder of that name: everything under it
    [ "${g%/\*\*}" != "$g" ] || deny="$deny, \"**/$g/**\"=\"deny\""
  done < "$list_file"
fi
[ -n "$deny" ] || { echo "ask-gpt.sh: no secret patterns in $list_file; nothing was run" >&2; exit 2; }
profile='permissions.review.filesystem={":minimal"="read", ":workspace_roots"={"."="read"'"$deny"'}}'
# shellcheck disable=SC2086
codex exec --ignore-user-config -c 'default_permissions="review"' -c "$profile" -c web_search="disabled" \
  -C "$dir" -c model_reasoning_effort="$effort" --ephemeral $extra \
  --output-last-message "$T/answer.md" - < "$T/prompt.md" > "$T/log.txt" 2>&1
rc=$?
echo "exit=$rc"
echo "--- answer"; cat "$T/answer.md" 2>/dev/null
# the folder is removed on exit, so stdout is all the skill can read: more of the log when the run failed
n=20; [ "$rc" -eq 0 ] || n=80
echo "--- log tail"; tail -n "$n" "$T/log.txt" 2>/dev/null
