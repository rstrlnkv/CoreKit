# lib-settings.sh — user settings and the Core facts file, for lib.sh (source lib.sh, not this file). See the header of lib.sh.

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

# settings_file_path — the settings file: $CORECREW_CONFIG (absolute; a relative one is ignored, as it would
# follow the cwd), else $XDG_CONFIG_HOME/corecrew/settings (an empty or relative XDG_CONFIG_HOME is ignored),
# else ~/.config/corecrew/settings. With no usable HOME there is no file: prints nothing, exit 1.
settings_file_path() {
  case "${CORECREW_CONFIG:-}" in /*) printf '%s' "$CORECREW_CONFIG"; return 0 ;; esac
  case "${XDG_CONFIG_HOME:-}" in /*) printf '%s/corecrew/settings' "${XDG_CONFIG_HOME%/}"; return 0 ;; esac
  case "${HOME:-}" in /*) printf '%s/.config/corecrew/settings' "$HOME" ;; *) return 1 ;; esac
}

# _sf_big <file> — exit 0 when the settings file is over 64 KB: it is not read (a hook has 15 s), see _settings_file_check.
_sf_big() { [ "$(wc -c < "$1" 2>/dev/null | tr -d ' ')" -gt 65536 ] 2>/dev/null; }

# _sf_load — reads the settings file once per settings load (one linear awk pass, not in a subshell, so the result is
# kept): _SF_DATA holds "key<TAB>value" of the first line of every key; load_settings and resolve_setting reset _SF_DONE.
# A missing, unreadable or over-64 KB file leaves _SF_DATA empty.
_sf_load() {
  local f
  [ -z "${_SF_DONE:-}" ] || return 0
  _SF_DONE=1; _SF_DATA=""
  f="$(settings_file_path)" || return 0
  [ -f "$f" ] && [ -r "$f" ] && ! _sf_big "$f" || return 0
  _SF_DATA="$(LC_ALL=C awk '
      NR == 1 && substr($0, 1, 3) == "\357\273\277" { $0 = substr($0, 4) }
      { sub(/\r$/, "") }
      (i = index($0, ":")) == 0 { next }
      {
        k = substr($0, 1, i - 1); v = substr($0, i + 1)
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == "" || (k in seen)) next
        seen[k] = 1
        sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
        if (length(v) >= 2 && ((substr(v, 1, 1) == "\"" && substr(v, length(v), 1) == "\"") || (substr(v, 1, 1) == "\047" && substr(v, length(v), 1) == "\047")))
          v = substr(v, 2, length(v) - 2)
        printf "%s\t%s\n", k, v
      }' "$f" 2>/dev/null)" || _SF_DATA=""
}
# _sf_get <key> — prints the value of the first "key: value" line of the settings file: trimmed, one pair of matching
# quotes removed, CR dropped, "#" inside a value is data; blanks before the colon and a leading UTF-8 BOM are accepted.
_sf_get() {
  local k v
  while IFS=$'\t' read -r k v; do
    [ "$k" = "$1" ] && { printf '%s' "$v"; return 0; }
  done <<< "$_SF_DATA"
  return 0
}

# _setting_valid <key> <value> — exit 0 when the value is usable. core_dir: ~, ~/..., or an absolute path.
_setting_valid() {
  case "$1:$2" in
    core_dir:"~"|core_dir:"~/"*|core_dir:/*) return 0 ;;
    attribution:allow|attribution:forbid) return 0 ;;
    model_profile:economy|model_profile:balanced|model_profile:strong) return 0 ;;
    ui_language:en|ui_language:ru) return 0 ;;
  esac
  return 1
}

# _resolve_setting <key> — sets REPLY to the value of core_dir|attribution|model_profile|ui_language and
# appends the ignored invalid values to SETTINGS_WARN as "key<TAB>value<TAB>source<TAB>value in effect"
# (source: env, option or file). Order: env CORE_DIR (core_dir only), plugin option, settings file,
# default. Empty, placeholder and invalid values fall through to the next source.
# shellcheck disable=SC2088  # "~/Projects/Core" is the default as the user would type it; _core_raw expands it
_resolve_setting() {
  local key="$1" i v src bad="" k s
  REPLY=""; _sf_load
  for i in 1 2 3; do
    v=""; src=""
    case "$i:$key" in
      1:core_dir) v="${CORE_DIR:-}"; src="env" ;;
      2:core_dir) v="${CLAUDE_PLUGIN_OPTION_CORE_DIR:-}"; src="option" ;;
      2:attribution) v="${CLAUDE_PLUGIN_OPTION_ATTRIBUTION:-}"; src="option" ;;
      2:model_profile) v="${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-}"; src="option" ;;
      2:ui_language) v="${CLAUDE_PLUGIN_OPTION_UI_LANGUAGE:-}"; src="option" ;;
      3:*) v="$(_sf_get "$key")"; src="file" ;;
      *) continue ;;
    esac
    v="$(opt_value "$v")"
    [ -n "$v" ] || continue
    if _setting_valid "$key" "$v"; then REPLY="$v"; break; fi
    # an unknown ui_language is silently English (as documented in hooks/messages.sh); the rest is named
    [ "$key" = ui_language ] || bad="${bad}${v}"$'\t'"${src}"$'\n'
  done
  if [ -z "$REPLY" ]; then
    case "$key" in
      core_dir) REPLY="~/Projects/Core" ;; attribution) REPLY=allow ;;
      model_profile) REPLY=balanced ;; ui_language) REPLY=en ;;
    esac
  fi
  while IFS=$'\t' read -r v s; do
    [ -n "$v" ] || continue
    SETTINGS_WARN="${SETTINGS_WARN}${key}"$'\t'"${v}"$'\t'"${s}"$'\t'"${REPLY}"$'\n'
  done <<< "$bad"
  return 0
}

# _settings_file_check — a settings file that exists but cannot be read (or is over 64 KB) is named once (key settings_file).
_settings_file_check() {
  local f; f="$(settings_file_path)" || return 0
  if [ -f "$f" ] && { [ ! -r "$f" ] || _sf_big "$f"; }; then
    SETTINGS_WARN="${SETTINGS_WARN}settings_file"$'\t'"${f}"$'\t'"file"$'\t'"the defaults"$'\n'
  fi
  return 0
}

# resolve_setting <key> — prints the value (see _resolve_setting; warnings are not kept).
resolve_setting() { local SETTINGS_WARN=""; _SF_DONE=""; _resolve_setting "$1"; printf '%s' "$REPLY"; }

# settings_warning_lines — SETTINGS_WARN as English lines for stderr, one per ignored value: what is wrong,
# where to fix it, what is used instead. (hooks/messages.sh has the same texts in en and ru.)
settings_warning_lines() {
  local k v s e sl fx
  while IFS=$'\t' read -r k v s e; do
    [ -n "$k" ] || continue
    if [ "$k" = home ]; then
      printf 'corecrew: HOME is empty or not an absolute path, so ~ (the default core_dir ~/Projects/Core) has no meaning and there is no Core. Set HOME or give core_dir as an absolute path.\n'; continue
    fi
    if [ "$k" = settings_file ]; then
      printf 'corecrew: the settings file %s cannot be read (or is over 64 KB); its values are ignored and the defaults are used.\n' "$v"; continue
    fi
    case "$s" in
      env) sl="environment variable CORE_DIR"; fx="Unset or correct the CORE_DIR variable." ;;
      option) sl="plugin option"; fx="Correct it in the plugin's options in Claude Code." ;;
      *) sl="settings file"; fx="Correct it in $(settings_file_path)." ;;
    esac
    case "$k" in
      core_dir) printf 'corecrew: core_dir "%s" (%s) is not valid: it must be an absolute path or start with ~/. %s Using %s instead.\n' "$v" "$sl" "$fx" "$e" ;;
      attribution) printf 'corecrew: attribution "%s" (%s) is not valid: use allow or forbid. %s Using "%s" instead.\n' "$v" "$sl" "$fx" "$e" ;;
      model_profile) printf 'corecrew: model_profile "%s" (%s) is not valid: use economy, balanced or strong. %s Using "%s" instead.\n' "$v" "$sl" "$fx" "$e" ;;
      *) printf 'corecrew: %s "%s" (%s) is not valid. %s Using "%s" instead.\n' "$k" "$v" "$sl" "$fx" "$e" ;;
    esac
  done <<< "$SETTINGS_WARN"
}

# _core_raw <value> — sets CORE_RAW: the core_dir value with ~ expanded and no trailing slash.
# shellcheck disable=SC2088  # a literal ~ is compared, not expanded
_core_raw() {
  # a ~ with no usable HOME (empty or relative) has no meaning: no Core (CORE_RAW empty), one "home" warning
  case "$1" in
    "~"|"~/"*)
      case "${HOME:-}" in /*) ;; *)
        CORE_RAW=""
        case "$SETTINGS_WARN" in home$'\t'*|*$'\n'home$'\t'*) ;; *) SETTINGS_WARN="${SETTINGS_WARN}home"$'\t'"${HOME}"$'\t'"env"$'\t'"no Core"$'\n' ;; esac
        return 0 ;;
      esac ;;
  esac
  CORE_RAW="$(expand_home "$1")"
  while [ "${#CORE_RAW}" -gt 1 ] && [ "${CORE_RAW%/}" != "$CORE_RAW" ]; do CORE_RAW="${CORE_RAW%/}"; done
}

# load_settings — see the header. An invalid core_dir (not absolute, not ~...) is ignored with a warning,
# never read as relative to the current folder.
# shellcheck disable=SC2034  # the variables it sets are read by the scripts that source lib.sh
load_settings() {
  SETTINGS_WARN=""; _SF_DONE=""
  _settings_file_check
  _resolve_setting core_dir; _core_raw "$REPLY"
  if [ -z "$CORE_RAW" ]; then CORE_DIR=""; CORE_NAME=""; PROJECTS_DIR=""   # no usable HOME: no Core, hooks stay inert
  else
    CORE_DIR="$(canon_dir "$CORE_RAW")"
    CORE_NAME="$(basename "$CORE_DIR")"
    # beside the Core as typed: a core_dir that is a symlink keeps the code folders next to the link,
    # not next to its target
    PROJECTS_DIR="$(canon_dir "$(dirname "$CORE_RAW")")"
  fi
  _resolve_setting attribution; ATTRIBUTION="$REPLY"
  _resolve_setting model_profile; MODEL_PROFILE="$REPLY"
  _resolve_setting ui_language; UI_LANGUAGE="$REPLY"
  APP_ID_PREFIX="$(coredev_get app-id-prefix)"
}
