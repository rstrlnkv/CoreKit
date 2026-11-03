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

# canon_dir <path> — the physical path (symlinks resolved). For a path that does not exist
# yet, the deepest existing ancestor is resolved and the missing components are appended, so
# the string stays the same after the directory is created. No trailing slash.
canon_dir() {
  local p rest="" base c; p="$(expand_home "$1")"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  base="$p"
  while [ ! -d "$base" ] && [ "$base" != "/" ] && [ "$base" != "." ]; do
    rest="/$(basename "$base")$rest"; base="$(dirname "$base")"
  done
  c="$(cd -P "$base" 2>/dev/null && pwd)" || { printf '%s\n' "$p"; return 0; }
  [ "$c" = "/" ] && c=""
  [ -z "$c$rest" ] && c="/"
  printf '%s%s\n' "$c" "$rest"
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

# core_ready — exit 0 when $CORE_DIR/.coredev has a line "schema: <n>" (n = digits), else 1.
# A .coredev that only holds other keys (e.g. app-id-prefix) does not count as a set-up Core.
core_ready() {
  local f="${CORE_DIR:-}/.coredev" line
  [ -n "${CORE_DIR:-}" ] && [ -f "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "schema: "?*) case "${line#"schema: "}" in *[!0-9]*) ;; *) return 0 ;; esac ;;
    esac
  done < "$f"
  return 1
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

# opt_value <value> — the value, or nothing when it is empty or still holds the literal text
# "${user_config." (Claude Code leaves placeholders unsubstituted while the plugin is not configured).
opt_value() {
  case "$1" in *'${user_config.'*) return 0 ;; esac
  printf '%s' "$1"
}

# load_settings — CORE_DIR: $CORE_DIR, else $CLAUDE_PLUGIN_OPTION_CORE_DIR, else ~/Projects/Core.
# A value that is an unsubstituted ${user_config.*} placeholder counts as unset.
load_settings() {
  local c o a m
  c="$(opt_value "${CORE_DIR:-}")"; o="$(opt_value "${CLAUDE_PLUGIN_OPTION_CORE_DIR:-}")"
  a="$(opt_value "${CLAUDE_PLUGIN_OPTION_ATTRIBUTION:-}")"; m="$(opt_value "${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-}")"
  CORE_DIR="$(canon_dir "${c:-${o:-$HOME/Projects/Core}}")"
  CORE_NAME="$(basename "$CORE_DIR")"
  ATTRIBUTION="${a:-allow}"
  MODEL_PROFILE="${m:-balanced}"
  APP_ID_PREFIX="$(coredev_get app-id-prefix)"
}

# --- Helpers that create things in the Core. They honour DRY=1 (print "would create", touch
# nothing) and print paths relative to $CORE_DIR ("." for the Core itself).

# rel_core <path> — path relative to $CORE_DIR.
rel_core() {
  if [ "$1" = "$CORE_DIR" ]; then printf '.'; else printf '%s' "${1#"$CORE_DIR"/}"; fi
}

# put <template> <dest> [copy] — create dest from template unless it exists. Default mode
# renders placeholders through the caller's render() function; "copy" copies the file as is.
put() {
  local src="$1" dest="$2" mode="${3:-render}"
  if [ -e "$dest" ]; then echo "skipped $(rel_core "$dest")"; return 0; fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$dest")"; return 0; fi
  mkdir -p "$(dirname "$dest")" || return 1
  if [ "$mode" = copy ]; then cp "$src" "$dest" || return 1; else render "$src" "$dest" || return 1; fi
  echo "created $(rel_core "$dest")"
}

# mkdir_p <dir> — create a directory, announce it only when it is new.
mkdir_p() {
  if [ -d "$1" ]; then return 0; fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$1")/"; return 0; fi
  mkdir -p "$1" || return 1
  echo "created $(rel_core "$1")/"
}

# git_init <dir> — git init with branch main, unless <dir>/.git exists.
git_init() {
  local rel; rel="$(rel_core "$1")"
  if [ -d "$1/.git" ]; then echo "skipped $rel/.git"; return 0; fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $rel/.git"; return 0; fi
  mkdir -p "$1" || return 1
  git init -q "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main || return 1
  echo "created $rel/.git"
}

# CLI: bash lib.sh get <key> | set <key> <value> | ready (exit 0 when core_ready) | core-dir (absolute path)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    ready) core_ready ;;
    core-dir) printf '%s\n' "$CORE_DIR" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value> | ready | core-dir" >&2; exit 2 ;;
  esac
fi
