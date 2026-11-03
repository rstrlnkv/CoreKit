# Shared helpers for the plugin's scripts. Source it, or run it: bash lib.sh get|set <key> [value].
# Settings come from plugin options (CLAUDE_PLUGIN_OPTION_*) and from <Core>/.coredev
# (lines "key: value"). The settings file is read, never executed.
# load_settings sets: CORE_DIR, CORE_NAME, ATTRIBUTION, MODEL_PROFILE, APP_ID_PREFIX.

# expand_home <path> — a leading ~ or ~/ becomes $HOME.
expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#"~/"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# canon_dir <path> — the physical path if the directory exists, else the expanded path
# without trailing slashes.
canon_dir() {
  local p; p="$(expand_home "$1")"
  if [ -d "$p" ]; then
    (cd -P "$p" 2>/dev/null && pwd) && return 0
  fi
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s\n' "$p"
}

# coredev_get <key> — prints the value of "key: value" in $CORE_DIR/.coredev (first match).
coredev_get() {
  local f="${CORE_DIR:-}/.coredev" line
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$1: "*) printf '%s\n' "${line#"$1: "}"; return 0 ;;
      "$1:") printf '\n'; return 0 ;;
    esac
  done < "$f"
  return 0
}

# coredev_set <key> <value> — writes "key: value" in $CORE_DIR/.coredev: replaces the first
# line for the key (drops repeats), else appends. Creates the file if missing.
coredev_set() {
  local key="${1:-}" val="${2:-}" f="${CORE_DIR:-}/.coredev" tmp line done_=0
  [ -n "${CORE_DIR:-}" ] || { echo "coredev_set: CORE_DIR is not set" >&2; return 2; }
  LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9-]*$ ]]' _ "$key" \
    || { echo "coredev_set: bad key '$key'" >&2; return 2; }
  case "$val" in *$'\n'*|*$'\r'*) echo "coredev_set: value must be one line" >&2; return 2 ;; esac
  if [ "$key" = app-id-prefix ] && [ -n "$val" ]; then
    LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]' _ "$val" \
      || { echo "App id prefix must be reverse-DNS in lowercase, e.g. com.yourname." >&2; return 2; }
  fi
  mkdir -p "$CORE_DIR" || return 1
  tmp="$f.tmp.$$"
  : > "$tmp" || return 1
  if [ -f "$f" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$key:"|"$key: "*|"$key:"$'\r')
          if [ $done_ -eq 0 ]; then printf '%s: %s\n' "$key" "$val" >> "$tmp"; done_=1; fi ;;
        *) printf '%s\n' "$line" >> "$tmp" ;;
      esac
    done < "$f"
  fi
  [ $done_ -eq 1 ] || printf '%s: %s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$f"
}

# load_settings — CORE_DIR: $CORE_DIR, else $CLAUDE_PLUGIN_OPTION_CORE_DIR, else ~/Projects/Core.
load_settings() {
  CORE_DIR="$(canon_dir "${CORE_DIR:-${CLAUDE_PLUGIN_OPTION_CORE_DIR:-$HOME/Projects/Core}}")"
  CORE_NAME="$(basename "$CORE_DIR")"
  ATTRIBUTION="${CLAUDE_PLUGIN_OPTION_ATTRIBUTION:-allow}"
  MODEL_PROFILE="${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}"
  APP_ID_PREFIX="$(coredev_get app-id-prefix)"
}

# CLI: bash lib.sh get <key> | set <key> <value>
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value>" >&2; exit 2 ;;
  esac
fi
