# lib-host.sh — the host (Claude Code or Codex) and the plugin's own folders, for lib.sh (source lib.sh, not this file).

# codex_home — Codex's home folder: $CODEX_HOME when it is an absolute path, else ~/.codex under an absolute HOME (no
# trailing slash). Prints nothing and exits 1 when neither is usable (a relative CODEX_HOME is never followed).
codex_home() {
  local b="${CODEX_HOME:-}"
  if [ -z "$b" ]; then case "${HOME:-}" in /*) b="$HOME/.codex" ;; esac; fi
  case "$b" in /*) printf '%s' "${b%/}" ;; *) return 1 ;; esac
}

# host — "claude" or "codex": COREKIT_HOST when it says so (tests), else codex when this plugin lies under codex_home,
# else claude.
host() {
  local base r
  case "${COREKIT_HOST:-}" in claude|codex) printf '%s' "$COREKIT_HOST"; return 0 ;; esac
  if base="$(codex_home)"; then
    r="$(cd "$_LIB_DIR/.." 2>/dev/null && pwd -P)"
    case "$r" in "$(canon_dir "$base")"/*|"$base"/*) printf codex; return 0 ;; esac
  fi
  printf claude
}

# marketplace_name [plugin root] — the marketplace this plugin was installed from, read from the plugin root's path (the
# folder of this lib.sh when none is given): Claude Code and Codex keep a plugin at .../plugins/cache/<marketplace>/corecrew/
# <version>, and a marketplace clone lies under .../plugins/marketplaces/<marketplace>/. Any other shape (a checkout,
# --plugin-dir), or a name that is no plain folder name, is "corekit", the marketplace corecrew is published in.
marketplace_name() {
  local r="${1:-}" m="" rest
  [ -n "$r" ] || r="$(cd "$_LIB_DIR/.." 2>/dev/null && pwd)"
  case "$r" in
    */plugins/cache/?*/corecrew/?*) rest="${r#*/plugins/cache/}"; m="${rest%%/*}"; rest="${rest#*/}"
      case "$rest" in corecrew/?*) ;; *) m="" ;; esac ;;
    */plugins/marketplaces/?*/?*) rest="${r#*/plugins/marketplaces/}"; m="${rest%%/*}" ;;
  esac
  case "$m" in ""|*[!A-Za-z0-9._-]*|.|..) m=corekit ;; esac
  printf '%s' "$m"
}

# default_data_dir [plugin root] — the plugin's data folder when the host names none (CLAUDE_PLUGIN_DATA unset):
# <CODEX_HOME>/plugins/data/corecrew-<marketplace> on Codex, <HOME>/.claude/plugins/data/corecrew-<marketplace> else, under
# an absolute CODEX_HOME or HOME only; prints nothing when none is known (a relative HOME must not put it under the cwd).
default_data_dir() {
  local d m; m="$(marketplace_name "${1:-}")"
  if [ "$(host)" = codex ]; then
    d="$(codex_home)" && printf '%s/plugins/data/corecrew-%s' "$d" "$m"
  else
    case "${HOME:-}" in /*) printf '%s/.claude/plugins/data/corecrew-%s' "$HOME" "$m" ;; esac
  fi
  return 0
}

# tools_dir — where the tools copy (git hook shims run it) lives: COREDEV_TOOLS, else $CLAUDE_PLUGIN_DATA/tools, else
# <data>/tools when this lib.sh is a tools copy that knows its data folder (.data-dir, written by sync-tools.sh), else
# default_data_dir/tools; prints nothing when none is known.
tools_dir() {
  local d=""
  if [ -n "${COREDEV_TOOLS:-}" ]; then printf '%s' "$COREDEV_TOOLS"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then printf '%s/tools' "$CLAUDE_PLUGIN_DATA"; return 0; fi
  if [ -f "$_LIB_DIR/.data-dir" ]; then
    { IFS= read -r d < "$_LIB_DIR/.data-dir"; } 2>/dev/null
    case "$d" in /*) printf '%s/tools' "${d%/}"; return 0 ;; esac
  fi
  d="$(default_data_dir)"; [ -z "$d" ] || printf '%s/tools' "$d"
  return 0
}

# hooks_marker_path — the file session-start writes the plugin version into once the hooks run (Codex runs them only
# after the person trusts them); empty when no settings folder is known.
hooks_marker_path() {
  local f; f="$(settings_file_path)" || return 0
  [ -n "$f" ] || return 0
  printf '%s/state/hooks-seen-%s' "$(dirname "$f")" "$(host)"
}

# plugin_version <plugin root> — the version in the manifest, nothing when there is none.
plugin_version() {
  local m="$1/.claude-plugin/plugin.json"
  [ -r "$m" ] || m="$1/.codex-plugin/plugin.json"
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" 2>/dev/null | head -1
}
