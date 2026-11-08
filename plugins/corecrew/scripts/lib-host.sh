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

# tools_dir — where the tools copy (git hook shims run it) lives: COREDEV_TOOLS, else $CLAUDE_PLUGIN_DATA/tools, else
# <data>/tools when this lib.sh is a tools copy that knows its data folder (.data-dir, written by sync-tools.sh), else the
# host's data folder under an absolute HOME or CODEX_HOME; prints nothing when none is known.
tools_dir() {
  local d=""
  if [ -n "${COREDEV_TOOLS:-}" ]; then printf '%s' "$COREDEV_TOOLS"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then printf '%s/tools' "$CLAUDE_PLUGIN_DATA"; return 0; fi
  if [ -f "$_LIB_DIR/.data-dir" ]; then
    { IFS= read -r d < "$_LIB_DIR/.data-dir"; } 2>/dev/null
    case "$d" in /*) printf '%s/tools' "${d%/}"; return 0 ;; esac
  fi
  if [ "$(host)" = codex ]; then
    d="$(codex_home)" && printf '%s/plugins/data/corecrew-corekit/tools' "$d"
  else
    case "${HOME:-}" in /*) printf '%s/.claude/plugins/data/corecrew-corekit/tools' "$HOME" ;; esac
  fi
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
