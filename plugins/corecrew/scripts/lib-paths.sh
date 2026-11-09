# lib-paths.sh — path helpers of lib.sh (source lib.sh, not this file): expand_home, canon_dir, lc, norm_path, resolve_abs.
# The *_r forms set a variable instead of printing, so a caller needs no "$(...)" subshell.

# _nl_trim <text> — sets _NT: the text without its trailing newlines, as "$(...)" gives a printed value.
_nl_trim() { _NT="$1"; while [ "${_NT%$'\n'}" != "$_NT" ]; do _NT="${_NT%$'\n'}"; done; }

# expand_home_r <path> — sets _EH: a leading ~ or ~/ becomes $HOME; trailing newlines are dropped (as
# "$(expand_home ...)" dropped them). No subshell: load_settings runs in every hook.
# shellcheck disable=SC2088  # the ~ is a literal to compare, not to expand
expand_home_r() {
  case "$1" in
    "~") _nl_trim "$HOME" ;;
    "~/"*) _nl_trim "$HOME/${1#"~/"}" ;;
    *) _nl_trim "$1" ;;
  esac
  _EH="$_NT"
}
# expand_home <path> — prints what expand_home_r sets.
expand_home() { expand_home_r "$1"; printf '%s' "$_EH"; }

# _basename_r <path>, _dirname_r <path> — set _BN and _DN as basename and dirname print them (trailing slashes
# ignored; "/" stays "/"; a bare name has the dirname "."), without starting a program.
_basename_r() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in /) ;; */*) p="${p##*/}" ;; esac
  _nl_trim "$p"; _BN="$_NT"
}
_dirname_r() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    /) ;;
    */*) p="${p%/*}"
      while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
      [ -n "$p" ] || p="/" ;;
    *) p="." ;;
  esac
  _nl_trim "$p"; _DN="$_NT"
}

# canon_dir_r <path> — sets _CANON: the physical path (symlinks resolved, letter case as on disk: /bin/pwd -P
# reports the case on disk, the shell's own pwd keeps what was typed). For a path that does not exist
# yet, the deepest existing ancestor is resolved and the missing components are appended, so
# the string stays the same after the directory is created. No trailing slash, no trailing newline.
# One subshell: the cd -P.
canon_dir_r() {
  local p rest="" base c; expand_home_r "$1"; p="$_EH"
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
  c="$(cd -P "$base" 2>/dev/null && { /bin/pwd -P 2>/dev/null || pwd; })" || { _nl_trim "$p"; _CANON="$_NT"; return 0; }
  [ "$c" = "/" ] && c=""
  [ -z "$c$rest" ] && c="/"
  _nl_trim "$c$rest"; _CANON="$_NT"
}
# canon_dir <path> — prints what canon_dir_r sets, with a newline.
canon_dir() { canon_dir_r "$1"; printf '%s\n' "$_CANON"; }

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
