# lib-scaffold.sh — helpers that create things in the Core, for lib.sh (source lib.sh, not this file). They honour DRY=1
# (print "would create", touch nothing) and print paths relative to $CORE_DIR ("." for the Core itself).

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
