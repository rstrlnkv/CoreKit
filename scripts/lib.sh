# Shared helpers for the plugin's scripts. Source it, or run it: bash lib.sh get|set <key> [value].
# Settings come from plugin options (CLAUDE_PLUGIN_OPTION_*) and from <Core>/.coredev
# (lines "key: value"). The settings file is read, never executed.
# load_settings sets: CORE_DIR, CORE_NAME, ATTRIBUTION, MODEL_PROFILE, APP_ID_PREFIX.

# The Core layout schema this plugin version writes and expects (the one place it is defined).
COREDEV_SCHEMA=1

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

# --- Hook helpers (no jq).

# json_str <json> <key> — prints the first string value of "<key>" anywhere in the JSON text.
# Unescapes \" \\ \/ \b \f \n \r \t and decodes \uXXXX to UTF-8 (surrogate pairs too; a lone
# surrogate becomes U+FFFD; \u0000 is dropped). Whitespace and newlines around ':' are fine.
# A missing key, a value that is not a string, or malformed input prints nothing; the exit
# status is always 0. A key name that only appears inside a string value is not a key.
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
    function isws(c) { return c == " " || c == "\t" || c == "\r" || c == "\n" }
    { buf = buf $0 "\n" }
    END {
      key = ENVIRON["JSON_KEY"] ""
      if (key == "") exit 0
      for (n = 1; n < 256; n++) chr[n] = sprintf("%c", n)
      chr[0] = ""
      len = length(buf); i = 1
      while (i <= len) {
        if (substr(buf, i, 1) != "\"") { i++; continue }
        s = i + 1; j = s
        while (j <= len) {
          d = substr(buf, j, 1)
          if (d == "\\") j += 2
          else if (d == "\"") break
          else j++
        }
        if (j > len) exit 0
        raw = substr(buf, s, j - s) ""
        i = j + 1
        if (raw != key) continue
        k = i
        while (k <= len && isws(substr(buf, k, 1))) k++
        if (substr(buf, k, 1) != ":") continue
        k++
        while (k <= len && isws(substr(buf, k, 1))) k++
        if (substr(buf, k, 1) != "\"") continue
        s = k + 1; j = s
        while (j <= len) {
          d = substr(buf, j, 1)
          if (d == "\\") j += 2
          else if (d == "\"") break
          else j++
        }
        if (j > len) exit 0
        raw = substr(buf, s, j - s)
        out = ""; p = 1; rl = length(raw)
        while (p <= rl) {
          d = substr(raw, p, 1)
          if (d != "\\") { out = out d; p++; continue }
          e = substr(raw, p + 1, 1); p += 2
          if (e == "n") out = out "\n"
          else if (e == "t") out = out "\t"
          else if (e == "r") out = out "\r"
          else if (e == "b") out = out chr[8]
          else if (e == "f") out = out chr[12]
          else if (e == "u") {
            cp = hexval(substr(raw, p, 4))
            if (length(substr(raw, p, 4)) < 4 || cp < 0) { p += 4; continue }
            p += 4
            if (cp >= 55296 && cp <= 56319) {
              lo = -1
              if (substr(raw, p, 2) == "\\u") lo = hexval(substr(raw, p + 2, 4))
              if (lo >= 56320 && lo <= 57343) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); p += 6 }
              else cp = 65533
            } else if (cp >= 56320 && cp <= 57343) cp = 65533
            if (cp > 0) out = out utf8(cp)
          }
          else out = out e
        }
        printf "%s", out
        exit 0
      }
    }
  ' || true
  return 0
}

# project_of <path> — with CORE_DIR loaded (load_settings), prints <project> when the canonical
# path is <Core>/<project> or anything below it (worktrees under code/.claude/worktrees included);
# exit 0. Otherwise prints nothing and exits 1. A project is a top-level folder of the Core that
# holds a CLAUDE.md or a code/ folder; dot-folders, standards/ and knowledge/ never count.
project_of() {
  local p rest first
  [ -n "${CORE_DIR:-}" ] && [ -n "${1:-}" ] || return 1
  p="$(canon_dir "$1")"
  case "$p" in "$CORE_DIR"/*) ;; *) return 1 ;; esac
  rest="${p#"$CORE_DIR"/}"; first="${rest%%/*}"
  case "$first" in ""|.*|standards|knowledge) return 1 ;; esac
  [ -d "$CORE_DIR/$first" ] || return 1
  [ -f "$CORE_DIR/$first/CLAUDE.md" ] || [ -d "$CORE_DIR/$first/code" ] || return 1
  printf '%s\n' "$first"
}

# --- Helpers that create things in the Core. They honour DRY=1 (print "would create", touch
# nothing) and print paths relative to $CORE_DIR ("." for the Core itself).

# rel_core <path> — path relative to $CORE_DIR.
rel_core() {
  if [ "$1" = "$CORE_DIR" ]; then printf '.'; else printf '%s' "${1#"$CORE_DIR"/}"; fi
}

# valid_project_name <name> — exit 0 when it is 3-40 Latin lowercase letters, digits and hyphens,
# starting with a letter and not ending with a hyphen (the rule for <Core>/<name>/).
valid_project_name() {
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
docs/INDEX.md.tmpl|docs/INDEX.md
docs/brief.md.tmpl|docs/brief.md
docs/architecture.md.tmpl|docs/architecture.md
docs/decisions/001-stack-and-architecture.md.tmpl|docs/decisions/001-stack-and-architecture.md
mkdir|docs/features
mkdir|docs/knowledge
rules/tests.md.tmpl|.claude/rules/tests.md
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

# projects_entry <name> <purpose> — add "- <name> — <purpose> — <name>/code/" to $CORE_DIR/PROJECTS.md
# unless a line for the name is there. Prints "created|skipped PROJECTS.md entry" ("would create"
# with DRY=1, nothing written).
projects_entry() {
  local line="- $1 — $2 — $1/code/"
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
#      | schema (the plugin's schema number)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    ready) core_ready ;;
    core-dir) printf '%s\n' "$CORE_DIR" ;;
    schema) printf '%s\n' "$COREDEV_SCHEMA" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value> | ready | core-dir | schema" >&2; exit 2 ;;
  esac
fi
