# lib-paths.sh — path helpers of lib.sh (source lib.sh, not this file): expand_home, canon_dir, lc, norm_path, resolve_abs.

# expand_home <path> — a leading ~ or ~/ becomes $HOME.
# shellcheck disable=SC2088  # the ~ is a literal to compare, not to expand
expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#"~/"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# canon_dir <path> — the physical path (symlinks resolved, letter case as on disk: /bin/pwd -P
# reports the case on disk, the shell's own pwd keeps what was typed). For a path that does not exist
# yet, the deepest existing ancestor is resolved and the missing components are appended, so
# the string stays the same after the directory is created. No trailing slash.
canon_dir() {
  local p rest="" base c; p="$(expand_home "$1")"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  base="$p"
  # the missing parts are cut off with ${..%/*} and ${..##*/} (no basename/dirname process per part: a guard judges
  # many deep new paths within its timeout)
  while [ ! -d "$base" ] && [ "$base" != "/" ] && [ "$base" != "." ]; do
    case "$base" in
      */*) rest="/${base##*/}$rest"; base="${base%/*}"
        while [ "${#base}" -gt 1 ] && [ "${base%/}" != "$base" ]; do base="${base%/}"; done
        [ -n "$base" ] || base="/" ;;
      *) rest="/$base$rest"; base="." ;;
    esac
  done
  c="$(cd -P "$base" 2>/dev/null && { /bin/pwd -P 2>/dev/null || pwd; })" || { printf '%s\n' "$p"; return 0; }
  [ "$c" = "/" ] && c=""
  [ -z "$c$rest" ] && c="/"
  printf '%s%s\n' "$c" "$rest"
}

# lc <text> — ASCII lower case (bytes above 127 are left alone, so Cyrillic stays as it is).
lc() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z'; }

# norm_path <absolute path> — "." and ".." and repeated slashes resolved lexically (what is left after
# canon_dir for a part of the path that does not exist yet).
norm_path() {
  local IFS=/ seg out=""
  set -f
  for seg in $1; do
    case "$seg" in ""|.) ;; ..) out="${out%/*}" ;; *) out="$out/$seg" ;; esac
  done
  set +f
  printf '%s' "${out:-/}"
}

# resolve_abs <path> — sets ABS: the canonical absolute path. A relative path is taken from $cwd (the hook's
# working directory, set by the caller); the directory part goes through canon_dir; a link as the last
# part is followed (up to 8 times).
# shellcheck disable=SC2088,SC2154,SC2034  # a literal ~ is compared; cwd is the caller's (the hooks set it); ABS is the result
resolve_abs() {
  local t="$1" dir base link n=0
  while :; do
    case "$t" in "~"|"~/"*) t="$(expand_home "$t")" ;; esac
    case "$t" in /*) ;; *) t="$cwd/$t" ;; esac
    while [ "${#t}" -gt 1 ] && [ "${t%/}" != "$t" ]; do t="${t%/}"; done
    base="${t##*/}"; dir="${t%/*}"; [ -n "$dir" ] || dir="/"
    case "$base" in
      ""|.|..) ABS="$(norm_path "$(canon_dir "$t")")"; return 0 ;;
    esac
    t="$(norm_path "$(canon_dir "$dir")/$base")"
    if [ -L "$t" ] && [ "$n" -lt 8 ]; then
      link="$(readlink "$t")" || break
      [ -n "$link" ] || break
      n=$((n + 1))
      case "$link" in /*) t="$link" ;; *) t="${t%/*}/$link" ;; esac
      continue
    fi
    break
  done
  ABS="$t"
}
