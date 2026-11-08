# Shared helpers for the plugin's scripts. Source it, or run it: bash lib.sh get|set <key> [value].
# User settings (core_dir, attribution, model_profile, ui_language) come, per key, from: the CORE_DIR
# env (core_dir only), the plugin option CLAUDE_PLUGIN_OPTION_<KEY> (Claude Code), the settings file
# ~/.config/corecrew/settings or $CORECREW_CONFIG (lines "key: value"; the only source in Codex), the
# default. Project facts live in <Core>/.coredev (lines "key: value"). Files are read, never executed.
# load_settings sets: CORE_DIR, CORE_NAME, PROJECTS_DIR, ATTRIBUTION, MODEL_PROFILE, UI_LANGUAGE,
# APP_ID_PREFIX, SETTINGS_WARN (records "key<TAB>value<TAB>source<TAB>value in effect" of values ignored as invalid).

# The Core layout schema this plugin version writes and expects (the one place it is defined).
COREDEV_SCHEMA=2

# HOME unset (a stripped environment): the account's home folder, so ~ and ~/.ssh still mean something.
if [ -z "${HOME:-}" ]; then
  HOME="$(eval 'printf %s ~' 2>/dev/null)"
  case "${HOME:-}" in /*) ;; *) HOME="" ;; esac
fi

# expand_home <path> — a leading ~ or ~/ becomes $HOME.
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
  while [ ! -d "$base" ] && [ "$base" != "/" ] && [ "$base" != "." ]; do
    rest="/$(basename "$base")$rest"; base="$(dirname "$base")"
  done
  c="$(cd -P "$base" 2>/dev/null && { /bin/pwd -P 2>/dev/null || pwd; })" || { printf '%s\n' "$p"; return 0; }
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

# --- Hook helpers (no jq).

# json_str <json> <key> — prints the first string value of "<key>" anywhere in the JSON text.
# Unescapes \" \\ \/ \b \f \n \r \t and decodes \uXXXX to UTF-8 (surrogate pairs too; a lone
# surrogate becomes U+FFFD; \u0000 is dropped). Whitespace and newlines around ':' are fine.
# A missing key, a value that is not a string, or malformed input prints nothing; the exit
# status is always 0. A key name that only appears inside a string value is not a key.
# Linear time: the text is split at the quote characters once, so a string is a run of pieces
# (a piece that ends in an odd number of backslashes ends at an escaped quote), and a value is
# decoded by splitting each piece at its backslashes. No loop walks single characters.
json_str() {
  printf '%s' "${1:-}" | JSON_KEY="${2:-}" LC_ALL=C awk '
    function hexval(h,   i, d, v) {
      v = 0
      for (i = 1; i <= length(h); i++) {
        d = index("0123456789abcdef", tolower(substr(h, i, 1)))
        if (d == 0) return -1
        v = v * 16 + d - 1
      }
      return v
    }
    function utf8(cp) {
      if (cp < 128) return chr[cp]
      if (cp < 2048) return chr[192 + int(cp / 64)] chr[128 + cp % 64]
      if (cp < 65536) return chr[224 + int(cp / 4096)] chr[128 + int(cp / 64) % 64] chr[128 + cp % 64]
      return chr[240 + int(cp / 262144)] chr[128 + int(cp / 4096) % 64] chr[128 + int(cp / 64) % 64] chr[128 + cp % 64]
    }
    # 1 when the piece ends in an odd number of backslashes (the quote after it is escaped)
    function oddbs(s,   l) {
      l = length(s)
      if (l == 0 || substr(s, l, 1) != "\\") return 0
      if (match(s, /[^\\]\\+$/)) return (RLENGTH - 1) % 2   # anchored on a non-backslash: linear
      return l % 2
    }
    # print the decoded text t (pieces joined with escaped quotes already appended)
    function emit(t,   m, S, j, c, r, cp, lo) {
      m = split(t, S, "\\")
      for (j = 1; j <= m; j++) gsub(/\002/, "\n", S[j])   # after split: split() also cuts at newlines
      printf "%s", S[1]
      for (j = 2; j <= m; j++) {
        r = S[j]
        if (r == "") {                      # "\\" : one backslash; the next piece is plain text
          if (j == m) break
          printf "%s", "\\"; j++; printf "%s", S[j]; continue
        }
        c = substr(r, 1, 1); r = substr(r, 2)
        if (c == "n") printf "%s", "\n"
        else if (c == "t") printf "%s", "\t"
        else if (c == "r") printf "%s", "\r"
        else if (c == "b") printf "%s", chr[8]
        else if (c == "f") printf "%s", chr[12]
        else if (c == "u") {
          if (length(r) < 4) continue       # short escape: dropped with what is left
          cp = hexval(substr(r, 1, 4)); r = substr(r, 5)
          if (cp < 0) { printf "%s", r; continue }
          if (cp >= 55296 && cp <= 56319) {
            lo = -1
            if (r == "" && j < m && length(S[j + 1]) >= 5 && substr(S[j + 1], 1, 1) == "u") lo = hexval(substr(S[j + 1], 2, 4))
            if (lo >= 56320 && lo <= 57343) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); j++; r = substr(S[j], 6) }
            else cp = 65533
          } else if (cp >= 56320 && cp <= 57343) cp = 65533
          if (cp > 0) printf "%s", utf8(cp)
        }
        else printf "%s", c                 # \" \/ and unknown escapes: the character itself
        printf "%s", r
      }
    }
    BEGIN { RS = "\001" }
    { buf = (NR == 1 ? "" : buf "\001") $0 }
    END {
      key = ENVIRON["JSON_KEY"] ""
      if (key == "") exit 0
      for (n = 1; n < 256; n++) chr[n] = sprintf("%c", n)
      chr[0] = ""
      gsub(/\n/, "\002", buf)               # BWK awk split() also splits at newlines
      n = split(buf, P, "\"")               # P[1] is outside a string, P[2] inside, and so on
      i = 2
      while (i < n) {
        e = i
        while (e < n && oddbs(P[e])) e++
        if (e >= n) exit 0                  # unterminated string
        if (e == i && (P[i] "") == key && e + 2 <= n && P[e + 1] ~ /^[ \t\r\002]*:[ \t\r\002]*$/) {
          v = e + 2; w = v                  # a string value starts at piece v
          while (w < n && oddbs(P[w])) w++
          if (w >= n) exit 0
          for (k = v; k < w; k++) emit(P[k] "\"")
          emit(P[w])
          exit 0
        }
        i = e + 2
      }
    }
  ' || true
  return 0
}

# _project_of_path <path> — with CORE_DIR loaded (load_settings), prints <project> and exits 0 when the path is
# inside a project; otherwise prints nothing and exits 1. Two places count:
#  - inside the Core: <Core>/<project> or anything below it (old layout, worktrees under code/ included);
#    a project is a top-level folder of the Core that holds a CLAUDE.md or a code/ folder; dot-folders,
#    standards/ and knowledge/ never count.
#  - beside the Core: the first folder under <Projects> (the Core's parent) is <Name>; it is a project
#    when lc <Name> is a valid project name and <Core>/<name>/CLAUDE.md exists.
_project_of_path() {
  local p rest first name pd
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  p="$(canon_dir "$1")"
  case "$p" in
    "$CORE_DIR"/*)
      rest="${p#"$CORE_DIR"/}"; first="${rest%%/*}"
      case "$first" in ""|.*|standards|knowledge) return 1 ;; esac
      [ -d "$CORE_DIR/$first" ] || return 1
      [ -f "$CORE_DIR/$first/CLAUDE.md" ] || [ -d "$CORE_DIR/$first/code" ] || return 1
      printf '%s\n' "$first" ;;
    "$CORE_DIR") return 1 ;;
    *)
      pd="${PROJECTS_DIR:-$(dirname "$CORE_DIR")}"
      case "$p" in "$pd"/*) ;; *) return 1 ;; esac
      rest="${p#"$pd"/}"; first="${rest%%/*}"
      name="$(lc "$first")"
      valid_project_name "$name" || return 1
      [ -f "$CORE_DIR/$name/CLAUDE.md" ] || return 1
      printf '%s\n' "$name" ;;
  esac
}

# worktree_of <path> — exit 0 and sets WT_ROOT (the worktree folder) and WT_MAIN (the main checkout it belongs to)
# when the path lies in a linked git worktree, wherever that worktree is; else exit 1 and both empty. Reads files
# only (no git process): from the nearest existing folder it walks up to the first ".git"; a ".git" folder
# means a main checkout or a clone (1); a ".git" file must say "gitdir: <main>/.git/worktrees/<name>" and <main>/.git
# must be a folder, which knows this worktree: <main>/.git/worktrees/<name>/gitdir names "<this folder>/.git" (a submodule,
# a dangling, a forged or a renamed-main file gives 1). Callers that give a worktree any power (project_of, the guard's
# root, the links) also check that WT_MAIN is the project's own code folder (wt_is_main_of).
worktree_of() {
  local d g x e b
  WT_ROOT=""; WT_MAIN=""
  [ -n "${1:-}" ] || return 1
  d="$(canon_dir "$1")"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="${d%/*}"; [ -n "$d" ] || d=/; done
  while :; do
    [ -d "$d/.git" ] && return 1
    if [ -f "$d/.git" ]; then
      g=""; { IFS= read -r g < "$d/.git"; } 2>/dev/null || [ -n "$g" ] || return 1
      g="${g%$'\r'}"
      while case "$g" in *[[:blank:]]) true ;; *) false ;; esac; do g="${g%?}"; done
      case "$g" in "gitdir: "?*) x="${g#gitdir: }" ;; *) return 1 ;; esac
      case "$x" in /*) ;; *) x="$d/$x" ;; esac
      case "$x" in */.git/worktrees/?*) ;; *) return 1 ;; esac
      e="$x"; x="${x%/.git/worktrees/*}"
      x="$(canon_dir "$x")"
      [ -d "$x/.git" ] || return 1
      b=""; { IFS= read -r b < "$e/gitdir"; } 2>/dev/null || [ -n "$b" ] || return 1
      b="${b%$'\r'}"
      case "$b" in /*) ;; *) b="$e/$b" ;; esac
      case "$b" in */.git) b="$(canon_dir "${b%/.git}")/.git" ;; *) return 1 ;; esac
      [ "$b" = "$d/.git" ] || return 1
      WT_ROOT="$d"; WT_MAIN="$x"
      return 0
    fi
    [ "$d" = "/" ] && return 1
    d="${d%/*}"; [ -n "$d" ] || d=/
  done
}

# project_of <path> — as _project_of_path, and a path in a linked git worktree of a project's code folder (the
# worktree can be anywhere) counts as the project of that main folder.
project_of() {
  local n
  _project_of_path "$1" && return 0
  worktree_of "$1" || return 1
  n="$(_project_of_path "$WT_MAIN")" || return 1
  wt_is_main_of "$n" || return 1
  printf '%s\n' "$n"
}

# wt_is_main_of <project> — exit 0 when WT_MAIN (set by worktree_of) is the project's own main code folder.
wt_is_main_of() {
  local c
  c="$(code_dir_of "$1" 2>/dev/null)" || return 1
  [ -n "$WT_MAIN" ] && [ "$(canon_dir "$c")" = "$WT_MAIN" ]
}

# code_root_of <path> — prints the code root git sees from <path>: the worktree folder in a linked worktree, else the
# project's main code folder; exit 1 when that is not a project's code folder. (git runs; for skills, not for hooks.)
code_root_of() {
  local t n r here
  here="$(canon_dir "${1:-.}")"
  t="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || t=""
  if [ -n "$t" ] && project_of "$t" >/dev/null; then
    # only a root that holds the folder asked about: a forged gitfile or core.worktree must not point elsewhere
    r="$(canon_dir "$t")"
    case "$here/" in "$r"/*) printf '%s\n' "$t"; return 0 ;; esac
    echo "code-root: $here is not inside $r" >&2; return 1
  fi
  # a session in <Core>/<name>/ (git sees the Core): the project's main code folder
  n="$(project_of "${1:-.}")" || return 1
  case "$here/" in "$CORE_DIR/$n"/*) ;; *) echo "code-root: $here is not inside $CORE_DIR/$n" >&2; return 1 ;; esac
  code_dir_of "$n" 2>/dev/null
}

# host — "claude" or "codex": COREKIT_HOST when it says so (tests), else codex when this plugin lies under
# ${CODEX_HOME:-$HOME/.codex} (an absolute base), else claude.
host() {
  local base="${CODEX_HOME:-}" r
  case "${COREKIT_HOST:-}" in claude|codex) printf '%s' "$COREKIT_HOST"; return 0 ;; esac
  if [ -z "$base" ]; then case "${HOME:-}" in /*) base="$HOME/.codex" ;; esac; fi
  case "$base" in
    /*) r="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"
        case "$r" in "$(canon_dir "$base")"/*|"${base%/}"/*) printf codex; return 0 ;; esac ;;
  esac
  printf claude
}

# tools_dir — where the tools copy (git hook shims run it) lives: COREDEV_TOOLS, else $CLAUDE_PLUGIN_DATA/tools, else
# the host's data folder under an absolute HOME or CODEX_HOME; prints nothing when none is known.
tools_dir() {
  local base
  if [ -n "${COREDEV_TOOLS:-}" ]; then printf '%s' "$COREDEV_TOOLS"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then printf '%s/tools' "$CLAUDE_PLUGIN_DATA"; return 0; fi
  if [ "$(host)" = codex ]; then
    base="${CODEX_HOME:-}"
    if [ -z "$base" ]; then case "${HOME:-}" in /*) base="$HOME/.codex" ;; esac; fi
    case "$base" in /*) printf '%s/plugins/data/corecrew-corekit/tools' "${base%/}" ;; esac
  else
    case "${HOME:-}" in /*) printf '%s/.claude/plugins/data/corecrew-corekit/tools' "$HOME" ;; esac
  fi
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

# code_dir_of <name> — prints the main code folder of a project: <Core>/<name>/code when that is a
# directory (only the old layout has one, so an unrelated <Projects>/<Name> never takes its place); else
# the one folder in <Projects> (not the Core) whose lower-case name is <name>. Exit 1 when there is
# neither; exit 3 (and a line on stderr) when two folders there differ only in letter case.
code_dir_of() {
  local pd d b found="" n=0 second=""
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  if [ -d "$CORE_DIR/$1/code" ]; then printf '%s\n' "$CORE_DIR/$1/code"; return 0; fi
  pd="${PROJECTS_DIR:-$(dirname "$CORE_DIR")}"
  for d in "$pd"/*/; do
    d="${d%/}"; [ -d "$d" ] || continue
    [ "$d" = "$CORE_DIR" ] && continue
    b="$(basename "$d")"
    [ "$(lc "$b")" = "$1" ] || continue
    n=$((n + 1))
    if [ $n -eq 1 ]; then found="$d"; else second="$d"; fi
  done
  if [ $n -gt 1 ]; then
    printf 'two folders differ only in case: %s, %s\n' "$(basename "$found")" "$(basename "$second")" >&2
    return 3
  fi
  [ $n -eq 1 ] || return 1
  printf '%s\n' "$found"
}

# layout_of <name> — prints "new" (code folder beside the Core) or "old" (<Core>/<name>/code); exit 1
# when the project has no code folder (or exit 3 on a case clash, from code_dir_of).
layout_of() {
  local d rc=0
  d="$(code_dir_of "$1")" || rc=$?
  [ $rc -eq 0 ] || return $rc
  case "$d" in "$CORE_DIR"/*) echo old ;; *) echo new ;; esac
}

# patch_paths <text> — the file paths in a Codex apply_patch text, one "<kind>\t<path>" per line: W written, S move
# source, D deleted, X unreadable, C more than 100 paths. See scripts/patch-paths.awk. Needs $SELF (the plugin
# root). Status 1 when the reader (patch-paths.awk) is missing or awk failed; status 0 when it ran, even if it printed
# nothing (a patch that names no file, e.g. Begin Patch + End Patch).
patch_paths() {
  [ -r "$SELF/scripts/patch-paths.awk" ] || return 1
  printf '%s\n' "$1" | LC_ALL=C awk -f "$SELF/scripts/patch-paths.awk" 2>/dev/null
}

# shell_patch_host <hook input JSON> — exit 0 when the shell-patch refusal applies: the host is Codex (host: the plugin
# lies under CODEX_HOME), or the input carries Codex's turn_id (a dev install whose path says nothing; Claude Code sends no
# turn_id). Claude Code has no apply_patch tool, so there a program of that name is the person's own and nothing is refused.
shell_patch_host() {
  [ "$(host)" = codex ] && return 0
  [ -n "$(json_str "${1:-}" turn_id)" ]
}

# shell_patch_refused <command> — exit 0 when a Bash command applies a patch through the shell, which no hook can
# judge (a path may be built by cd, quoting, $(...) or a variable); SHELL_PATCH_HIT is then what matched (the spelling as
# written, "*** Begin Patch", "$'\...'" or the glob word, at most 80 bytes). The hooks call it only when shell_patch_host
# says Codex. The rule reads no shell syntax (seven review passes in all,
# five of them against the tokenizer rule); it is a substring hit plus a narrow allowlist.
# BEST EFFORT, NOT A SECURITY BOUNDARY: it catches plain and accidental shell patches and many disguised ones; it cannot
# see a name the shell builds at run time. The apply_patch tool form is the checked path. Known ways past it: variables
# and ${...}; $(...) and backticks (also empty ones); brace expansion; $'...' / $"..." splitting ($'apply'$'_patch');
# a quoted part glued to a glob ('apply_pat'?h); extglob (shopt -s extglob, then apply_pat@(c)h); a glob that expands to
# an option-named file; IFS changes; scripts and interpreters; write_stdin.
# Hit (any letter case): the text, with every ' " \ and newline deleted, holds apply_patch, applypatch or apply-patch
# (that covers --codex-run-as-apply-patch); or "*** Begin Patch" is followed by an Add File, Update File, Delete File or
# Move to marker; or $' is followed by a \x, \u, \U or octal escape (an encoded name cannot be read); or an unquoted word
# holds ? * or [ and its part after the last / read as a glob can match one of the three spellings (../bin/apply_pat?h,
# ../bin/appl*_patch), and the word either is a command word (the first word, after ; & | ( ) an opening backtick or a
# newline, after a reserved word such as then/do/if/!/{/coproc, an assignment, find -exec/-execdir/-ok/-okdir, or a
# wrapper such as sudo/env/xargs/exec/timeout, also named by path, and its options and numeric values) or keeps 4 or more
# literal characters in that last part. So a wildcard argument (rm -rf dist/*, wc -l a/* 2>/dev/null, cp assets/* out/)
# is no hit, while ls; * x and sudo ../bin/apply_pat?h are. A redirect target is skipped. A case pattern (a word followed
# by ) or by | words and then )) is no command word while a case is open, and * ? [ inside $((...)) are arithmetic. A
# heredoc body is data: its words are never command words (cat > f.js <<'EOF' and git commit -m "$(cat <<'EOF' with a
# * in the body pass); the name and the patch markers are still found there (bash <<EOF / apply_patch / EOF is refused).
# Heredoc starts are found by a quoting-state scan (a << inside quotes, after \ or in a # comment is none). Limits of the
# command-word reading: a bare wildcard in a heredoc body fed to a shell (cat <<EOF | sh / * / EOF); one after a wrapper
# option or argument that takes a non-numeric value (sudo -u x ./a*, exec -a name ./a*); a << inside (( )) without $,
# or a ) of a case pattern inside $(...), which the scan may misread. No hit: pass.
# A hit passes only in the simple form. Quoted text is opaque there: each single-quoted string and each double-quoted
# string without $, backtick or \ is replaced by one placeholder byte (\001; a string that starts with - keeps that -, so
# an option cannot hide in quotes), and then no $ ` \ quote, ; & newline < > ( ) { } ! may be left (so any $ outside single
# quotes makes the line non-simple); the first word is no assignment; the line split on | gives elements whose first word
# is a bare name; the first is a reader (grep egrep fgrep rg, git log|show|diff|grep|status|blame, git commit with only
# -m -a -am --message -s --amend --no-edit, cat head tail ls wc find), the others a filter (sort uniq cut tr nl wc head
# tail grep rg); an option word with a glued quote is only -e -S -G -m -g --regexp= --grep= --author= --committer=
# --message= --glob=; no word is an option that runs a program or writes a file (git -c -C -p --paginate -O, --pag*,
# --ext*, --output*, --open-files-in-pager*, and any --o... that abbreviates --output or --open-files-in-pager, but not
# --oneline; rg --pre* --hostname-bin* --search-zip -z; find -exec -execdir -ok -okdir -delete -fprint* -fls; sort --co*);
# and an option word that holds the spelling is one of -e --regexp= --grep= --author= --committer= -S -G -m --message=
# -g --glob= -name -iname -path -ipath with the value glued by =.
# Over-blocking by design (in Codex only): cd x && grep apply_patch ., a for loop, gh pr create --body "apply_patch",
# echo apply_patch, a redirect, command -v, man, /usr/bin/grep, grep apply_patch $FILE, and a glob argument that spells
# much of the name outside the simple form (ls ../bin/appl*_patch; true), and a bare wildcard right after a ) (echo $(ls) *)
# or after a ( in (( (i+1) * 2 )) without $.
# Limits (no hit, no refusal; pinned as LIMIT in tests/test_shell_patch.sh): a name built at run time (a variable:
# a=apply; ${a}_patch; $(...) or backticks, also empty; brace expansion; $'apply'$'_patch'; 'apply_pat'?h; extglob), a glob
# that expands to a file whose name is an option (-...), IFS changes, a script or an interpreter that runs it, write_stdin. Plain bash 3.2 + BSD
# grep/sed/awk; linear in the text.
shell_patch_refused() {
  local q="'" flat plain hit="" out s one quote_re
  SHELL_PATCH_HIT=""
  one="$(printf '\001')"
  quote_re='s/'"'"'(-?)[^'"'"']*'"'"'|"(-?)[^"$`\]*"/'"$one"'\1\2/g'
  flat="$(printf '%s' "$1" | LC_ALL=C tr '\n\r' '  ')"
  plain="$(printf '%s' "$1" | LC_ALL=C tr -d '\047\042\134\012\015')"
  # s: the text with its quoted strings opaque (see above); newline and CR become \005
  s="$(printf '%s' "$1" | LC_ALL=C tr '\n\r' '\005\005' | LC_ALL=C sed -E "$quote_re")"
  hit="$(printf '%s\n' "$plain" | LC_ALL=C grep -oiE 'apply_patch|applypatch|apply-patch' | head -n 1)"
  [ -n "$hit" ] || { printf '%s\n' "$flat" | LC_ALL=C grep -qE '\*\*\* Begin Patch.*\*\*\* (Add File|Update File|Delete File|Move to):' && hit='*** Begin Patch'; }
  [ -n "$hit" ] || { printf '%s\n' "$flat" | LC_ALL=C grep -qE "\\\$$q.*\\\\([xuU]|[0-7])" && hit="\$'\\...'"; }
  if [ -z "$hit" ]; then
    # Heredoc bodies and arithmetic first, on the raw text, by a quoting-state scan that carries across lines: a stack of
    # S '...', D "...", P $(...) or (...), B `...`, A $((...)) and a ( inside A. A << outside S and D starts a heredoc
    # (<<< does not; \< and a # comment hide it), so "$(cat <<'EOF' is one. Each body line gets a leading \006 word (data,
    # no command words) and loses its quotes, backslashes, $ and backticks, so an apostrophe there cannot pair with a quote
    # outside. In A, * ? [ are operators and become blanks, unless A turns out to be $( (...) ) (a ) not followed by )).
    # Linear: the line is split into characters once (substr on a long line is not O(1) in every awk).
    out="$(printf '%s\n' "$1" | LC_ALL=C awk '
      END { print "\001done" }
      BEGIN { nq = 0; qi = 1; sp = 0; q1 = sprintf("%c", 39) }
      {
        line = $0
        if (qi <= nq) {
          cmp = line
          if (DASH[qi]) sub(/^\t+/, "", cmp)
          if (cmp == Q[qi]) { qi++; print line; next }
          gsub(/["\047`\\$]/, "", line); print "\006 " line; next
        }
        n = split(line, C, ""); nb = 0
        for (i = 1; i <= n; i++) {
          c = C[i]; t = sp ? ST[sp] : "U"
          if (t == "S") { if (c == q1) sp--; continue }
          if (c == "\\") { i++; continue }
          if (c == "$" && C[i + 1] == "(") {
            if (C[i + 2] == "(") { ST[++sp] = "A"; AS[sp] = nb; i += 2 } else { ST[++sp] = "P"; i++ }
            continue
          }
          if (c == "`") { if (t == "B") sp--; else ST[++sp] = "B"; continue }
          if (t == "D") { if (c == "\"") sp--; continue }
          if (c == q1) { ST[++sp] = "S"; continue }
          if (c == "\"") { ST[++sp] = "D"; continue }
          if (t == "A" || t == "a") {
            if (c == "(") ST[++sp] = "a"
            else if (c == ")") {
              if (t == "a") sp--
              else if (C[i + 1] == ")") { sp--; i++ }
              else { while (nb > AS[sp]) { C[BL[nb]] = BC[nb]; nb-- } ST[sp] = "P" }
            }
            else if (c == "*" || c == "?" || c == "[") { BL[++nb] = i; BC[nb] = c; C[i] = " " }
            continue
          }
          if (c == "(") { ST[++sp] = "P"; continue }
          if (c == ")") { if (t == "P") sp--; continue }
          if (c == "#" && (i == 1 || C[i - 1] ~ /[ \t;&|()]/)) break
          if (c != "<" || C[i + 1] != "<") continue
          if (C[i + 2] == "<") { i += 2; continue }
          j = i + 2; dash = 0; d = ""
          if (C[j] == "-") { dash = 1; j++ }
          while (C[j] == " " || C[j] == "\t") j++
          while (j <= n && length(d) < 1000) {
            c = C[j]
            if (c == q1 || c == "\"") { j++; while (j <= n && C[j] != c) d = d C[j++]; j++; continue }
            if (c == "\\") { d = d C[j + 1]; j += 2; continue }
            if (c ~ /[ \t;&|<>()]/) break
            d = d c; j++
          }
          if (d != "" && length(d) < 1000) { nq++; Q[nq] = d; DASH[nq] = dash }
          i = j - 1
        }
        # an A still open at the end of the line may yet turn out to be $( (...) ): keep this line as written
        open = 0; for (k = 1; k <= sp; k++) if (ST[k] == "A") { open = 1; AS[k] = 0 }
        if (nb == 0 || open) { print line; next }
        for (k = 1; k <= n; k++) printf "%s", C[k]
        print ""
      }' 2>/dev/null)"
    # the last line is the \001done the reader prints at its end: without it the reader failed, so the text is unknown
    case "$out" in *"$one"done) out="${out%"$one"done}" ;; *) out="" ;; esac
    [ -n "$out" ] && out="$(printf '%s' "$out" | LC_ALL=C tr '\n\r' '\005\005' | LC_ALL=C sed -E "$quote_re" | LC_ALL=C awk '
      # glob_re: the regex of a glob word; LIT counts its literal characters
      function glob_re(w,   re, i, j, c, L, cls) {
        re = "^"; L = length(w); LIT = 0
        for (i = 1; i <= L; i++) {
          c = substr(w, i, 1)
          if (c == "?") re = re "."
          else if (c == "*") re = re ".*"
          else if (c == "[") {
            j = i + 1
            if (substr(w, j, 1) == "!" || substr(w, j, 1) == "^") j++
            if (substr(w, j, 1) == "]") j++
            while (j <= L && substr(w, j, 1) != "]") j++
            if (j > L) { re = re "\\["; LIT++ }
            else {
              cls = substr(w, i, j - i + 1)
              if (substr(cls, 2, 1) == "!") cls = "[^" substr(cls, 3)
              re = re cls; i = j
            }
          }
          else if (c ~ /[.+(){}^$|\\]/) { re = re "\\" c; LIT++ }
          else { re = re c; LIT++ }
        }
        return re "$"
      }
      # pattern(i): W[i] is a case pattern: the next words are ) or | word | word ... ) (20 words at most)
      function pattern(i,   j, k) {
        j = i + 1
        for (k = 0; k < 20; k++) {
          while (j <= n && W[j] == "") j++
          if (W[j] == ")") return 1
          if (W[j] != "|") return 0
          j++; while (j <= n && W[j] == "") j++
          if (W[j] ~ /^[|;&()`\005\006\007]$/) return 0
          j++
        }
        return 0
      }
      BEGIN { N[1] = "apply_patch"; N[2] = "applypatch"; N[3] = "apply-patch"; hit = ""; bt = 0; incase = 0 }
      {
        line = $0
        gsub(/&?[0-9]*[<>]+[&|]?-?/, " \007 ", line)   # a redirect operator: the next word is its target
        gsub(/[|;&()`\005]/, " & ", line)               # a command separator is a word of its own
        n = split(line, W, /[ \t]+/)
        cmd = 1; skip = 0; data = 0; wrap = 0
        for (i = 1; i <= n && hit == ""; i++) {
          w = W[i]
          if (w == "") continue
          if (w == "\005") { cmd = 1; data = 0; skip = 0; wrap = 0; continue }
          if (w == "`") { bt = !bt; cmd = bt; skip = 0; wrap = 0; continue }   # an opening backtick starts a command
          if (w ~ /^[|;&()]$/) { cmd = !data; skip = 0; wrap = 0; continue }
          if (w == "\006") { data = 1; cmd = 0; continue }
          if (w == "\007") { skip = 1; continue }
          if (skip) { skip = 0; continue }
          c = w; gsub(/[\001"\047`$\\]/, "", c)
          if (!cmd && !data && c ~ /^-(exec|execdir|ok|okdir)$/) { cmd = 1; wrap = 0; continue }   # find runs the next word
          at = cmd
          if (cmd) {
            cb = c; sub(/.*\//, "", cb)
            if (c ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/ || c ~ /^(!|[{]|then|do|else|elif|if|while|until|time|coproc)$/ || (wrap && c ~ /^(-|[0-9]+([.][0-9]+)?[smhd]?$)/)) ;
            else if (cb ~ /^(exec|command|builtin|sudo|doas|env|nohup|xargs|nice|ionice|timeout|setsid|stdbuf|eval|watch|parallel|strace|ltrace|chroot|flock|busybox)$/) wrap = 1
            else {
              if (c == "case") incase++
              else if (c == "esac" && incase) incase--
              else if (incase && c ~ /[?*[]/ && pattern(i)) at = 0
              cmd = 0; wrap = 0
            }
          }
          if (c !~ /[?*[]/) continue
          m = split(c, P, "/"); b = P[m]
          if (b !~ /[?*[]/) continue
          gsub(/\*+/, "*", b)
          if (length(b) > 200) { hit = c; break }
          re = glob_re(tolower(b))
          for (k = 1; k <= 3; k++) if (N[k] ~ re && (at || LIT >= 4)) hit = c
        }
      }
      END { if (hit == "") print "none"; else print "hit " hit }' 2>/dev/null)"
    case "$out" in none) ;; "hit "*) hit="${out#hit }" ;; *) hit="a command this check could not read" ;; esac
  fi
  [ -n "$hit" ] || return 1
  # at most 80 bytes; a UTF-8 character the cut would split is dropped
  SHELL_PATCH_HIT="$(printf '%s\n' "$hit" | LC_ALL=C awk '{ s = substr($0, 1, 80); if (length($0) > 80) sub(/[\300-\367][\200-\277]*$/, "", s); print s; exit }')"
  # the simple form: no construct that runs or hides a command (quoted text is already opaque in $s)
  printf '%s\n' "$s" | LC_ALL=C grep -q '[;&<>(){}!`$"\'"$q$(printf '\005')"']' && return 0
  out="$(printf '%s\n' "$s" | LC_ALL=C awk '
    BEGIN { ok = 1 }
    {
      n = split($0, E, "|")
      for (i = 1; i <= n && ok; i++) {
        m = split(E[i], W, " "); nm = W[1]
        if (m == 0 || nm ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || nm !~ /^[A-Za-z0-9._+-]+$/) { ok = 0; break }
        sub_ = W[2]; commit = 0
        if (i == 1) {
          if (nm == "git") {
            if (sub_ !~ /^(log|show|diff|grep|status|blame|commit)$/) { ok = 0; break }
            commit = (sub_ == "commit")
          } else if (nm !~ /^(grep|egrep|fgrep|rg|cat|head|tail|ls|wc|find)$/) { ok = 0; break }
        } else if (nm !~ /^(sort|uniq|cut|tr|nl|wc|head|tail|grep|rg)$/) { ok = 0; break }
        for (j = 2; j <= m; j++) {
          w = W[j]; b = w; sub(/^\001+/, "", b)
          if (substr(b, 1, 1) != "-") continue
          if (index(w, "\001") > 0) {
            p = w; sub(/\001.*/, "", p)
            if (p !~ /^(--regexp=|--grep=|--author=|--committer=|--message=|--glob=|-e|-S|-G|-m|-g)$/) { ok = 0; break }
            w = p
          }
          if (tolower(w) ~ /apply[_-]?patch/ && w !~ /^(-e|--regexp|--grep|--author|--committer|-S|-G|-m|--message|-g|--glob|-name|-iname|-path|-ipath)=/) { ok = 0; break }
          if (commit && j > 2 && w !~ /^(-m|-a|-am|--message(=.*)?|-s|--amend|--no-edit)$/) { ok = 0; break }
          if (nm == "git") {
            x = w; sub(/=.*/, "", x)
            if (w ~ /^(-c|-C|-p|-O)$/ || w ~ /^--(output|open-files-in-pager|ext|pag)/ || w ~ /^-[A-Za-z]*O/ || \
                (x ~ /^--o/ && (index("--output", x) == 1 || index("--open-files-in-pager", x) == 1))) { ok = 0; break }
          }
          if (nm == "rg" && (w ~ /^--(pre|hostname-bin|search-zip)/ || w ~ /^-[A-Za-z]*z/)) { ok = 0; break }
          if (nm == "find" && w ~ /^-(exec|execdir|ok|okdir|delete|fprint|fprint0|fprintf|fls)$/) { ok = 0; break }
          if (nm == "sort" && w ~ /^--co/) { ok = 0; break }
        }
      }
    }
    END { print (ok ? "ok" : "no") }' 2>/dev/null)"
  [ "$out" = ok ] && return 1
  return 0
}

# --- Path helpers for the path-judging hooks (guard-code.sh, guard-secrets.sh).

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

# --- Helpers that create things in the Core. They honour DRY=1 (print "would create", touch
# nothing) and print paths relative to $CORE_DIR ("." for the Core itself).

# rel_core <path> — path relative to $CORE_DIR; a path beside the Core (under <Projects>) prints as
# ../<path relative to <Projects>>.
rel_core() {
  local pd="${PROJECTS_DIR:-$(dirname "$CORE_DIR")}"
  case "$1" in
    "$CORE_DIR") printf '.' ;;
    "$CORE_DIR"/*) printf '%s' "${1#"$CORE_DIR"/}" ;;
    "$pd"/*) printf '../%s' "${1#"$pd"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# valid_project_name <name> — exit 0 when it is 3-40 Latin lowercase letters, digits and hyphens,
# starting with a letter and not ending with a hyphen (the rule for <Core>/<name>/), and is not
# core, standards or knowledge.
valid_project_name() {
  case "$1" in core|standards|knowledge) return 1 ;; esac
  LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ ]]' _ "$1"
}

# esc <value> — escape a value for use as a sed replacement with '|' delimiter.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# render <template> <dest> — fill the template placeholders. Reads the caller's variables NAME,
# PURPOSE, P (the project folder in the Core), DATE; CORE_DIR and CORE_NAME come from load_settings.
render() {
  sed -e "s|{{NAME}}|$(esc "$NAME")|g" \
      -e "s|{{PURPOSE}}|$(esc "$PURPOSE")|g" \
      -e "s|{{PROJECT_DIR}}|$(esc "$P")|g" \
      -e "s|{{CORE_DIR}}|$(esc "$CORE_DIR")|g" \
      -e "s|{{CORE_NAME}}|$(esc "$CORE_NAME")|g" \
      -e "s|{{DATE}}|$DATE|g" "$1" > "$2"
}

# put <template> <dest> [copy] — create dest from template unless it exists. Default mode
# renders placeholders through render() above; "copy" copies the file as is.
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

# project_docs_manifest — the project's internal files made from templates, one per line:
# "<template path under the templates dir>|<path in the project folder>", or "mkdir|<dir>".
project_docs_manifest() {
  cat <<'EOF'
CLAUDE.md.tmpl|CLAUDE.md
docs/brief.md.tmpl|docs/brief.md
docs/architecture.md.tmpl|docs/architecture.md
docs/decisions/001-stack-and-architecture.md.tmpl|docs/decisions/001-stack-and-architecture.md
docs/wiki.base|docs/wiki.base
docs/obsidian-app.json|docs/.obsidian/app.json
docs/obsidian-gitignore|docs/.obsidian/.gitignore
mkdir|docs/features
mkdir|docs/specs
mkdir|docs/plans
mkdir|docs/knowledge
EOF
}

# put_project_docs <templates dir> <dest dir> — create the manifest's files and folders in dest
# (existing ones are kept). Rendering uses render() above.
put_project_docs() {
  local tpl="$1" dest="$2" a b
  while IFS='|' read -r a b; do
    if [ "$a" = mkdir ]; then mkdir_p "$dest/$b" || return 1
    else put "$tpl/$a" "$dest/$b" || return 1; fi
  done <<< "$(project_docs_manifest)"
}

# link_file_to_claude <code_dir> <core_project_dir> <file name> — make <code_dir>/<file name> a
# symlink to <core_project_dir>/CLAUDE.md. Prints "created|skipped <path>" ("would create" with DRY=1,
# nothing written). Exit 1 when the target CLAUDE.md is missing (no dangling link). A real file or a link to somewhere else is never touched: exit 1 with a plain line.
link_file_to_claude() {
  local link="$1/$3" target="$2/CLAUDE.md" lnerr lnrc
  # (a DRY=1 plan for a project folder that is not there yet, as scaffold --dry-run, is let through)
  if [ ! -f "$target" ] && { [ "${DRY:-0}" -ne 1 ] || [ -d "$2" ]; }; then echo "$target does not exist; nothing to link $3 to" >&2; return 1; fi
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    echo "skipped $(rel_core "$link")"; return 0
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    echo "$3 exists and is not a link to $target; leave it or remove it yourself" >&2
    return 1
  fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$link")"; return 0; fi
  mkdir -p "$1" || return 1
  # (a directory that appeared at $link since the -e test would take the link inside itself: BSD and GNU ln -n
  # only cover a link to a directory, so look again right after and take our stray link out)
  lnerr="$(ln -s "$target" "$link" 2>&1)"; lnrc=$?
  if [ -d "$link" ] && [ ! -L "$link" ]; then
    [ ! -L "$link/CLAUDE.md" ] || [ "$(readlink "$link/CLAUDE.md")" != "$target" ] || rm -f "$link/CLAUDE.md"
    echo "$3 exists and is not a link to $target; leave it or remove it yourself" >&2
    return 1
  fi
  if [ "$lnrc" -ne 0 ]; then
    # another run may have made the same link a moment ago: that counts as skipped
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then echo "skipped $(rel_core "$link")"; return 0; fi
    [ -z "$lnerr" ] || echo "$lnerr" >&2
    return 1
  fi
  echo "created $(rel_core "$link")"
}

# link_local_claude <code_dir> <core_project_dir> — <code_dir>/CLAUDE.local.md links to the private CLAUDE.md.
link_local_claude() { link_file_to_claude "$1" "$2" CLAUDE.local.md; }

# link_agents <code_dir> <core_project_dir> — <code_dir>/AGENTS.md links to the private CLAUDE.md, like
# link_local_claude. Refuses (exit 1) when <core_project_dir>/AGENTS.md exists and the code folder has no AGENTS.md link yet
# (the link would hide it); an existing link is judged by link_file_to_claude alone.
link_agents() {
  if [ ! -L "$1/AGENTS.md" ] && [ -e "$2/AGENTS.md" ]; then
    echo "AGENTS.md exists in the Core at $2/AGENTS.md and the link would hide it; fold $2/AGENTS.md into CLAUDE.md, then remove it" >&2
    return 1
  fi
  link_file_to_claude "$1" "$2" AGENTS.md
}

# projects_entry <name> <purpose> <entry> — add "- <name> — <purpose> — <entry>" to $CORE_DIR/PROJECTS.md
# unless a line for the name is there. Prints "created|skipped PROJECTS.md entry" ("would create"
# with DRY=1, nothing written).
projects_entry() {
  local line="- $1 — $2 — $3"
  if [ -f "$CORE_DIR/PROJECTS.md" ] && grep -q "^- $1 " "$CORE_DIR/PROJECTS.md"; then
    echo "skipped PROJECTS.md entry"
  elif [ "${DRY:-0}" -eq 1 ]; then
    echo "would create PROJECTS.md entry"
  else
    printf '%s\n' "$line" >> "$CORE_DIR/PROJECTS.md" || return 1
    echo "created PROJECTS.md entry"
  fi
}

# CLI: bash lib.sh get <key> | set <key> <value> | ready (exit 0 when core_ready) | core-dir (absolute path; warnings for ignored values on stderr)
#      | settings [key[=optionvalue] ...] (resolved user settings, one "key: value" line each)
#      | setting-path (the settings file path)
#      | plugin-root (the absolute plugin folder this script is in; exit 1 when it is not the corecrew plugin)
#      | schema (the plugin's schema number) | core-paths <project> (the Core paths `save` commits for
#      the project, one line, space-separated; from _locate.sh next to this file)
#      | project-of <path> | code-root <path> | code-dir <name> | layout <name> (see project_of, code_root_of, code_dir_of, layout_of)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _ORIG_CORE_DIR="${CORE_DIR:-}"
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    ready) core_ready ;;
    core-dir) [ -z "$CORE_DIR" ] || printf '%s\n' "$CORE_DIR"; settings_warning_lines >&2; [ -n "$CORE_DIR" ] ;;
    setting-path) settings_file_path; echo ;;
    settings)
      shift; keys=""; CORE_DIR="$_ORIG_CORE_DIR"; SETTINGS_WARN=""; _settings_file_check
      for a in "$@"; do
        k="${a%%=*}"; v=""; [ "$k" = "$a" ] || v="${a#*=}"
        case "$k" in
          core_dir) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_CORE_DIR="$v" ;;
          attribution) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_ATTRIBUTION="$v" ;;
          model_profile) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_MODEL_PROFILE="$v" ;;
          ui_language) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="$v" ;;
          *) echo "Usage: lib.sh settings [core_dir|attribution|model_profile|ui_language[=value] ...]" >&2; exit 2 ;;
        esac
        keys="$keys $k"
      done
      [ -n "$keys" ] || keys="core_dir attribution model_profile ui_language"
      for k in $keys; do
        _resolve_setting "$k"
        if [ "$k" = core_dir ]; then _core_raw "$REPLY"; if [ -n "$CORE_RAW" ]; then printf 'core_dir: %s\n' "$(canon_dir "$CORE_RAW")"; else printf 'core_dir: \n'; fi
        else printf '%s: %s\n' "$k" "$REPLY"; fi
      done
      settings_warning_lines >&2 ;;
    plugin-root)
      # A mix-up catch, not a security boundary: a script cannot vet itself, so a look-alike folder
      # that carries its own copy of this script passes. The Paths text of the skills adds the
      # Codex cache-location rule for the model.
      r="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
      m=""
      if [ -f "$r/.codex-plugin/plugin.json" ]; then m="$r/.codex-plugin/plugin.json"
      elif [ -f "$r/.claude-plugin/plugin.json" ]; then m="$r/.claude-plugin/plugin.json"; fi
      if [ -d "$r/skills" ] && [ -n "$m" ]; then
        grep -q '"name"[[:space:]]*:[[:space:]]*"corecrew"' "$m" || { echo "corecrew: not a corecrew plugin folder: $r" >&2; exit 1; }
        printf '%s\n' "$r"
      else
        echo "corecrew: not a plugin folder: $r" >&2; exit 1
      fi ;;
    codex-profile)
      # A TOML fragment for ~/.codex/config.toml (never written by corecrew): a workspace-write permission profile
      # that keeps secret files unreadable. Patterns as in coreopinion's ask-gpt.sh review profile. Checked with
      # `codex sandbox`, codex 0.166 (tests/test_codex_profile.sh).
      printf '%s\n' '# corecrew: a Codex permission profile for coding.' \
        '# Put the line default_permissions = "corecrew" at the very top of config.toml (before any line that starts with [)' \
        '# and the rest at the end of the file. It then applies to every Codex session, in every project.' \
        '# Keep the tables and the key together: tables without the key make every plain Codex run fail. To try it first,' \
        '# put the whole fragment into a separate CODEX_HOME folder (CODEX_HOME=<folder> codex).' \
        '# What it does: reads and writes the project folder and temp folders, reads minimal system paths, and blocks the' \
        '# secret files named below inside the project. ~/.ssh and the rest of the home folder are not listed, so they stay closed.' \
        '# Codex keeps .git read-only, so commits ask for approval.' \
        '# What it is NOT: a default, not a hard boundary.' \
        '#  - It is switched off by --sandbox, --dangerously-bypass-approvals-and-sandbox or -c sandbox_mode=... on the command' \
        '#    line, by sandbox_mode in any config layer (a profile, the system config), and by the' \
        '#    .codex/config.toml of a trusted project (a cloned repository can bring one).' \
        '#  - It protects files in the working tree, not git history (git show HEAD:.env, git log -p), and not a hard link' \
        '#    made outside the sandbox.' \
        '#  - /tmp and /var/tmp stay readable and writable (the git helper needs them). Environment variables are not filtered.' \
        '# Names are matched by pattern. Still over-blocked: source files named credentials*, secrets* or secret.*' \
        '# (credentials_form.ts, secrets_helper.py). Still open: .envrc (project config), other names not listed.' \
        'default_permissions = "corecrew"' '' '[permissions.corecrew.filesystem]' \
        '":minimal" = "read"' '":tmpdir" = "write"' '' '[permissions.corecrew.filesystem.":workspace_roots"]' '"." = "write"'
      for g in '.env' '.env.*' '*.env' '*.env.*' '*.pem' '*.key' '*.p12' '*.pfx' 'id_rsa*' 'id_ed25519*' 'id_ecdsa*' 'id_dsa*' \
        '*[cC]redentials*' '*CREDENTIALS*' '.npmrc' '.netrc' '.pypirc' '.git-credentials' '.htpasswd' '.pgpass' '*.tfvars' '*.tfstate*' \
        '*.jks' '*.keystore' '*.p8' '*.ppk' '*.keytab' '.s3cfg' '.gnupg/**' '[sS]ecrets*' 'SECRETS*' '[sS]ecret.*' '*.secret' '*.secrets' \
        '[tT]oken' '[tT]oken.txt' '[tT]oken.json' '*.token' '*_[tT]oken.json' '*-[tT]oken.json' \
        '*_[tT]oken' '*-[tT]oken' '*_[tT]oken.*' '.*[tT]oken' '.secrets*' '*client_secret*.json' '.dockercfg' '*-secret.*' '*_secret.*' \
        '*[kK]ube[cC]onfig*' '*KUBECONFIG*' '*.kdbx' '.aws/**' '.kube/**' '.ssh/**' '.docker/config.json' \
        '*[sS]ervice?[aA]ccount*.json' '*[sS]ervice[aA]ccount*.json' '*SERVICE?ACCOUNT*.json'; do
        printf '"**/%s" = "deny"\n' "$g"
      done ;;
    host) host; echo ;;
    role-model)
      # The model for a crew role: claude prints the model alone (empty line for architect and explorer, which are
      # feature-dev agents in Claude), codex prints "<model> <reasoning effort>". Same table as the task SKILL.md.
      [ $# -eq 4 ] || { echo "Usage: lib.sh role-model <claude|codex> <economy|balanced|strong> <role>" >&2; exit 2; }
      case "$2:$3" in
        claude:economy) rm_e=haiku; rm_c=sonnet ;; claude:balanced) rm_e=sonnet; rm_c=sonnet ;; claude:strong) rm_e=sonnet; rm_c=opus ;;
        codex:economy) rm_e="gpt-6-luna medium"; rm_c="gpt-6.1-sol low" ;;
        codex:balanced) rm_e="gpt-6.1-sol medium"; rm_c="gpt-6.1-sol medium" ;;
        codex:strong) rm_e="gpt-6.1-sol high"; rm_c="gpt-6-astra high" ;;
        *) echo "Usage: lib.sh role-model <claude|codex> <economy|balanced|strong> <role>" >&2; exit 2 ;;
      esac
      case "$4" in
        engineer|tester) printf '%s\n' "$rm_e" ;;
        security|verifier|localizer|designer) printf '%s\n' "$rm_c" ;;
        architect|explorer) if [ "$2" = claude ]; then echo; else printf '%s\n' "$rm_c"; fi ;;
        *) echo "Usage: lib.sh role-model <claude|codex> <economy|balanced|strong> <role>" >&2; exit 2 ;;
      esac ;;
    core-writable)
      # Exit 0 when <dir> accepts a new file (a mktemp probe, removed at once; only the probe is removed).
      [ $# -eq 2 ] && case "$2" in /*) true ;; *) false ;; esac || { echo "Usage: lib.sh core-writable <absolute dir>" >&2; exit 2; }
      cw_probe="$(mktemp "$2/.corecrew-probe.XXXXXX" 2>/dev/null)" || {
        echo "corecrew: $2 is not writable from this session. Start Codex with: codex --add-dir \"$2\"" >&2; exit 1; }
      rm -f "$cw_probe" ;;
    tree-state)
      # One line fingerprinting a work tree: HEAD, status, diff against HEAD, the index, and the content of untracked
      # files that are not ignored (an untracked nested repo by its own tree-state). Ignored files are NOT covered (a change there is not seen).
      [ $# -eq 2 ] && [ -n "$2" ] || { echo "Usage: lib.sh tree-state <dir>" >&2; exit 2; }
      [ "$(git -C "$2" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || { echo "corecrew: $2 is not a git work tree" >&2; exit 1; }
      {
        git -C "$2" rev-parse HEAD 2>/dev/null
        git -C "$2" status --porcelain -uall 2>/dev/null
        git -C "$2" diff HEAD --binary 2>/dev/null
        git -C "$2" ls-files -s 2>/dev/null
        git -C "$2" ls-files -z --others --exclude-standard 2>/dev/null | while IFS= read -r -d '' ts_f; do
          printf '%s ' "$ts_f"
          if [ -L "$2/$ts_f" ]; then readlink "$2/$ts_f"
          elif [ -d "$2/$ts_f" ]; then bash "${BASH_SOURCE[0]}" tree-state "$2/$ts_f" 2>/dev/null   # untracked nested repo
          else cksum < "$2/$ts_f" 2>/dev/null; fi
        done
      } | cksum | tr ' ' '-' ;;
    schema) printf '%s\n' "$COREDEV_SCHEMA" ;;
    code-root) [ $# -eq 2 ] || { echo "Usage: lib.sh code-root <path>" >&2; exit 2; }; code_root_of "$2" ;;
    project-of) [ $# -eq 2 ] || { echo "Usage: lib.sh project-of <path>" >&2; exit 2; }; project_of "$2" ;;
    code-dir) [ $# -eq 2 ] || { echo "Usage: lib.sh code-dir <name>" >&2; exit 2; }; code_dir_of "$2" ;;
    layout) [ $# -eq 2 ] || { echo "Usage: lib.sh layout <name>" >&2; exit 2; }; layout_of "$2" ;;
    core-paths)
      [ $# -eq 2 ] && [ -n "$2" ] || { echo "Usage: lib.sh core-paths <project>" >&2; exit 2; }
      [ -n "$CORE_DIR" ] || { echo "lib.sh core-paths: no Core path" >&2; exit 1; }
      . "$(dirname "${BASH_SOURCE[0]}")/_locate.sh" || exit 1
      core_paths "$CORE_DIR" "$2" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value> | ready | core-dir | settings [key[=value] ...] | setting-path | plugin-root | codex-profile | host | role-model <host> <profile> <role> | core-writable <dir> | tree-state <dir> | schema | core-paths <project> | project-of <path> | code-root <path> | code-dir <name> | layout <name>" >&2; exit 2 ;;
  esac
fi
