# Paths received by a Bash hook may come from a native Windows process.
absolute_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    [A-Za-z]:[\\/]*|\\\\*)
      command -v cygpath >/dev/null 2>&1 && cygpath -u "$1" ;;
    *) return 1 ;;
  esac
}

# Prefer an absolute configured directory, then the default under HOME.
base_dir() {
  absolute_path "$1" && return 0
  local home_dir
  home_dir="$(absolute_path "${HOME:-}")" || return 1
  printf '%s/%s' "${home_dir%/}" "$2"
}

settings_file() {
  absolute_path "$1" && return 0
  local config_dir
  config_dir="$(base_dir "${XDG_CONFIG_HOME:-}" .config)" || return 1
  printf '%s/%s/settings' "${config_dir%/}" "$2"
}
