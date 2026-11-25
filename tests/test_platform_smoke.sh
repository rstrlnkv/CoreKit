#!/usr/bin/env bash
# Exercise the installed plugins and the native Python client from paths with spaces.
source "$(dirname "$0")/lib.sh"
new_sandbox
if ! command -v codex >/dev/null 2>&1; then skip platform-smoke "codex not on PATH"; finish; fi

native_path() {
  case "$(uname -s)" in MINGW*|MSYS*) cygpath -aw "$1" ;; *) printf '%s\n' "$1" ;; esac
}
stage="$SANDBOX/platform smoke"
cache="$stage/Codex home"
core="$stage/Private Core"
mkdir -p "$cache" "$core" "$stage/working folder"
CODEX_HOME="$(native_path "$cache")"; export CODEX_HOME
# Offline app-server startup may try to refresh the model and marketplace lists.
export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 NO_PROXY=
export https_proxy="$HTTPS_PROXY" http_proxy="$HTTP_PROXY" all_proxy="$ALL_PROXY" no_proxy=
cx() { codex --disable remote_plugin --disable plugin_discovery_prefetch "$@"; }
cd "$stage/working folder" || exit 1
assert_exit 0 cx plugin marketplace add "$(native_path "$ROOT")"
for plugin in corecrew coremodel; do assert_exit 0 cx plugin add "$plugin@corekit"; done
# The cache is fresh, so each plugin has exactly one version.
set -- "$cache"/plugins/cache/corekit/corecrew/*/scripts/lib.sh
assert_file "$1"
cmp -s "$(dirname "$1")/lib-paths.sh" "$SCRIPTS/lib-paths.sh" || fail "Codex installed a different CoreCrew revision"
if [ -n "${RUNNER_OS:-}" ] && [ "$RUNNER_OS" = Windows ]; then
  echo "Windows shell: $OSTYPE, ${MSYSTEM:-}, $(uname -s)"
  command -v bash git cygpath
  git --exec-path
fi
CORE_DIR="$(native_path "$core")"; export CORE_DIR
assert_exit 0 bash "$1" core-dir
assert_eq "$OUT" "$(cd "$core" && pwd -P)" "installed CoreCrew resolves the host path"
set -- "$cache"/plugins/cache/corekit/coremodel/*/codex/hint.sh
assert_file "$1"
answer="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}' | bash "$1" --recommend)"
assert_eq "$answer" '{"keep":true}' "installed CoreModel routes a greeting locally"
# EOF ends the chat after the native app-server starts the thread, before any model call.
case "$(uname -s)" in MINGW*|MSYS*) py=python ;; *) py=python3 ;; esac
assert_exit 0 "$py" "$ROOT/clients/coremodel/client.py" </dev/null
finish
