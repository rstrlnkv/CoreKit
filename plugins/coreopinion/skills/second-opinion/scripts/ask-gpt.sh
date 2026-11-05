#!/usr/bin/env bash
# ask-gpt.sh <temp folder> [medium|high] — one read-only Codex run for the second-opinion skill.
# The temp folder holds prompt.md (what GPT reads) and dir (the project folder path, nothing else:
# it is read from the file, so the path never goes through shell parsing). Prints the exit code,
# GPT's answer and the log tail, then removes the temp folder however the run ends (it holds the diff).
#
# What the profile confines (checked with `codex sandbox`, codex 0.166; see SKILL.md step 3):
# reads of the project folder, minimal system paths and temp folders only; every secret name the
# skill's send filter drops is blocked inside the project too; no writes, no network for commands.
# --ignore-user-config keeps ~/.codex/config.toml (MCP servers, plugins) out; web search is off.
T="$1"; effort="${2:-medium}"
case "$T" in ''|/) echo "usage: ask-gpt.sh <temp folder> [medium|high]" >&2; exit 2 ;; esac
[ -f "$T/prompt.md" ] && [ -f "$T/dir" ] || { echo "ask-gpt.sh: $T/prompt.md or $T/dir is missing" >&2; exit 2; }
# The folder is removed at the end, so it must be a `mktemp -d` folder (tmp.*) right in the temp
# folder ($TMPDIR, /tmp): a wrong path, the project say, is refused and left alone.
t_dir="$(cd "$T" 2>/dev/null && pwd -P)" || exit 2
t_ok=""
for r in "${TMPDIR:-/tmp}" /tmp; do
  r="$(cd "$r" 2>/dev/null && pwd -P)" || continue
  case "$t_dir" in "$r"/tmp.*) case "${t_dir#"$r"/}" in */*) ;; *) t_ok=1 ;; esac ;; esac
done
[ -n "$t_ok" ] || { echo "ask-gpt.sh: $T is not a mktemp -d folder in the temp folder; nothing was run or removed" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
trap 'exit 130' HUP INT TERM   # a signal ends the run; the EXIT trap then cleans up
case "$effort" in medium|high) ;; *) effort=medium ;; esac
dir="$(cat "$T/dir")"
# Outside a git repository Codex refuses to start without the flag; GPT then gets an empty folder.
extra=""
if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  mkdir -p "$T/empty"; dir="$T/empty"; extra="--skip-git-repo-check"
fi
profile='permissions.review.filesystem={":minimal"="read", ":project_roots"={"."="read", "**/.env*"="none", "**/*.env"="none", "**/*.env.*"="none", "**/*.pem"="none", "**/*.key"="none", "**/*.p12"="none", "**/*.pfx"="none", "**/id_rsa*"="none", "**/id_ed25519*"="none", "**/*[cC]redentials*"="none", "**/*CREDENTIALS*"="none", "**/.npmrc"="none", "**/.netrc"="none", "**/.pypirc"="none", "**/.git-credentials"="none", "**/*.tfvars"="none", "**/*.tfstate*"="none", "**/*.jks"="none", "**/*.keystore"="none", "**/*.p8"="none", "**/*[sS]ecret*"="none", "**/*SECRET*"="none", "**/*[tT]oken*"="none", "**/*TOKEN*"="none", "**/*[kK]ube[cC]onfig*"="none", "**/*KUBECONFIG*"="none", "**/*.kdbx"="none", "**/.aws/**"="none", "**/*[sS]ervice?[aA]ccount*.json"="none", "**/*[sS]ervice[aA]ccount*.json"="none", "**/*SERVICE?ACCOUNT*.json"="none"}}'
# shellcheck disable=SC2086
codex exec --ignore-user-config -c 'default_permissions="review"' -c "$profile" -c web_search="disabled" \
  -C "$dir" -c model_reasoning_effort="$effort" --ephemeral $extra \
  --output-last-message "$T/answer.md" - < "$T/prompt.md" > "$T/log.txt" 2>&1
echo "exit=$?"
echo "--- answer"; cat "$T/answer.md" 2>/dev/null
echo "--- log tail"; tail -n 20 "$T/log.txt" 2>/dev/null
