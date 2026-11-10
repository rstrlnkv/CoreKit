#!/usr/bin/env bash
# ask-gpt.sh — the second-opinion skill's one script for Codex. Three modes:
#   ask-gpt.sh --check   says where codex is and its version; exit 4 when codex is not installed.
#   ask-gpt.sh --new     makes the temp folder, records in it the folder it was run from (the project) and
#                        prints the temp folder's path.
#   ask-gpt.sh <temp folder> [medium|high] < prompt   one read-only Codex run.
# The run reads the prompt from stdin into prompt.md (or uses prompt.md already there), and the project path from
# the folder's dir file, so the path never goes through shell parsing. Prints the exit code, GPT's answer and the
# log tail (20 lines, 80 after a failed run), then removes the temp folder however the run ends (it holds the diff).
# Exit 2: bad arguments; exit 3: run inside a Codex session (refused first, in every mode: nothing is made, sent or
# removed, so Codex's read-only sandbox prints no error about it).
#
# What the profile confines (checked with `codex sandbox`, codex 0.166; see SKILL.md, section Ask GPT):
# reads of the project folder, minimal system paths and temp folders only; every secret name the
# skill's send filter drops (secret-patterns.txt) is blocked inside the project too; no writes, no network for commands.
# --ignore-user-config keeps ~/.codex/config.toml (MCP servers, plugins) out; web search is off.
#
# Claude Code only: inside a Codex session (Codex sets CODEX_THREAD_ID in every shell it runs, 0.166) GPT would
# review its own session's work.
if [ -n "${CODEX_THREAD_ID:-}" ]; then
  echo "ask-gpt.sh: coreopinion works only in Claude Code, and this runs inside a Codex session; nothing was sent. Ask for the second opinion in Claude Code." >&2
  exit 3
fi
case "${1:-}" in
  --check)
    [ $# -eq 1 ] || { echo "usage: ask-gpt.sh --check" >&2; exit 2; }
    c="$(command -v codex 2>/dev/null)" || { echo "ask-gpt.sh: the Codex CLI (codex) is not installed or not on PATH" >&2; exit 4; }
    echo "codex: $c"
    codex --version </dev/null
    exit $? ;;
  --new)
    [ $# -eq 1 ] || { echo "usage: ask-gpt.sh --new" >&2; exit 2; }
    here="$(pwd -P)" || exit 1
    T="$(mktemp -d "${TMPDIR:-/tmp}/coreopinion.XXXXXXXXXX")" || { echo "ask-gpt.sh: could not make a temp folder" >&2; exit 1; }
    printf '%s' "$here" > "$T/dir" || { rm -rf "$T"; exit 1; }
    printf '%s\n' "$T"
    exit 0 ;;
esac
T="$1"; effort="${2:-medium}"
case "$T" in ''|/|-*) echo "usage: ask-gpt.sh --check | --new | <temp folder> [medium|high] < prompt" >&2; exit 2 ;; esac
# The folder is removed at the end, so it must be a folder as --new makes it (coreopinion.*) right in a temp folder:
# $TMPDIR, the system one (macOS: getconf DARWIN_USER_TEMP_DIR) or /tmp, all compared after resolving links (/tmp is
# /private/tmp on macOS).
# A wrong path, the project say, is refused and left alone; a temp folder that resolves to / counts as none.
t_dir="$(cd "$T" 2>/dev/null && pwd -P)" || { echo "ask-gpt.sh: $T is not a folder" >&2; exit 2; }
t_ok=""
for r in "${TMPDIR:-}" "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" /tmp; do
  [ -n "$r" ] || continue
  r="$(cd "$r" 2>/dev/null && pwd -P)" || continue
  [ "$r" != / ] || continue
  case "${t_dir#"$r"/}" in "$t_dir"|*/*) ;; coreopinion.?*) t_ok=1 ;; esac
done
[ -n "$t_ok" ] || { echo "ask-gpt.sh: $T is not a mktemp -d folder in the temp folder; nothing was run or removed" >&2; exit 2; }
[ -f "$T/dir" ] || { echo "ask-gpt.sh: $T/dir is missing (make the folder with ask-gpt.sh --new)" >&2; exit 2; }
# The prompt: from stdin (a heredoc in SKILL.md), unless a prompt.md is already there. A missing or empty prompt is
# refused and the folder is left as it is.
if [ ! -s "$T/prompt.md" ] && [ ! -t 0 ]; then cat > "$T/prompt.md"; fi
[ -s "$T/prompt.md" ] || { echo "ask-gpt.sh: no prompt: give it on stdin; nothing was run" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
trap 'exit 130' HUP INT TERM   # a signal ends the run; the EXIT trap then cleans up
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
# ":minimal" alone leaves /tmp and /var/tmp writable (macOS, codex 0.166): the four entries make them read-only.
profile='permissions.review.filesystem={":minimal"="read", "/tmp"="read", "/private/tmp"="read", "/var/tmp"="read", "/private/var/tmp"="read", ":workspace_roots"={"."="read"'"$deny"'}}'
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
