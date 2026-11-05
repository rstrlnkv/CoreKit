# Shared helpers for the plugin's scripts. Source it, or run it: bash lib.sh get|set <key> [value].
# Settings come from plugin options (CLAUDE_PLUGIN_OPTION_*) and from <Core>/.coredev
# (lines "key: value"). The settings file is read, never executed.
# load_settings sets: CORE_DIR, CORE_NAME, ATTRIBUTION, MODEL_PROFILE, APP_ID_PREFIX.
# (ui_language is read by hooks/messages.sh through opt_value.)

# The Core layout schema this plugin version writes and expects (the one place it is defined).
COREDEV_SCHEMA=2

# HOME unset (a stripped environment): the account's home folder, so ~ and ~/.ssh still mean something.
if [ -z "${HOME:-}" ]; then
  HOME="$(eval 'printf %s ~' 2>/dev/null)"
  case "$HOME" in /*) ;; *) HOME="" ;; esac
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

# load_settings — CORE_DIR: $CORE_DIR, else $CLAUDE_PLUGIN_OPTION_CORE_DIR, else ~/Projects/Core.
# A value that is an unsubstituted ${user_config.*} placeholder counts as unset.
load_settings() {
  local c o a m
  c="$(opt_value "${CORE_DIR:-}")"; o="$(opt_value "${CLAUDE_PLUGIN_OPTION_CORE_DIR:-}")"
  a="$(opt_value "${CLAUDE_PLUGIN_OPTION_ATTRIBUTION:-}")"; m="$(opt_value "${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-}")"
  local raw; raw="$(expand_home "${c:-${o:-$HOME/Projects/Core}}")"
  while [ "${#raw}" -gt 1 ] && [ "${raw%/}" != "$raw" ]; do raw="${raw%/}"; done
  CORE_DIR="$(canon_dir "$raw")"
  CORE_NAME="$(basename "$CORE_DIR")"
  # beside the Core as typed: a core_dir that is a symlink keeps the code folders next to the link,
  # not next to its target
  PROJECTS_DIR="$(canon_dir "$(dirname "$raw")")"
  ATTRIBUTION="${a:-allow}"
  MODEL_PROFILE="${m:-balanced}"
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

# project_of <path> — with CORE_DIR loaded (load_settings), prints <project> and exits 0 when the path is
# inside a project; otherwise prints nothing and exits 1. Two places count:
#  - inside the Core: <Core>/<project> or anything below it (old layout, worktrees under code/ included);
#    a project is a top-level folder of the Core that holds a CLAUDE.md or a code/ folder; dot-folders,
#    standards/ and knowledge/ never count.
#  - beside the Core: the first folder under <Projects> (the Core's parent) is <Name>; it is a project
#    when lc <Name> is a valid project name and <Core>/<name>/CLAUDE.md exists.
project_of() {
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
  local link="$1/$3" target="$2/CLAUDE.md"
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
  ln -s "$target" "$link" || return 1
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

# CLI: bash lib.sh get <key> | set <key> <value> | ready (exit 0 when core_ready) | core-dir (absolute path)
#      | schema (the plugin's schema number) | core-paths <project> (the Core paths `save` commits for
#      the project, one line, space-separated; from _locate.sh next to this file)
#      | project-of <path> | code-dir <name> | layout <name> (see project_of, code_dir_of, layout_of)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    ready) core_ready ;;
    core-dir) printf '%s\n' "$CORE_DIR" ;;
    schema) printf '%s\n' "$COREDEV_SCHEMA" ;;
    project-of) [ $# -eq 2 ] || { echo "Usage: lib.sh project-of <path>" >&2; exit 2; }; project_of "$2" ;;
    code-dir) [ $# -eq 2 ] || { echo "Usage: lib.sh code-dir <name>" >&2; exit 2; }; code_dir_of "$2" ;;
    layout) [ $# -eq 2 ] || { echo "Usage: lib.sh layout <name>" >&2; exit 2; }; layout_of "$2" ;;
    core-paths)
      [ $# -eq 2 ] && [ -n "$2" ] || { echo "Usage: lib.sh core-paths <project>" >&2; exit 2; }
      . "$(dirname "${BASH_SOURCE[0]}")/_locate.sh" || exit 1
      core_paths "$CORE_DIR" "$2" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value> | ready | core-dir | schema | core-paths <project> | project-of <path> | code-dir <name> | layout <name>" >&2; exit 2 ;;
  esac
fi
