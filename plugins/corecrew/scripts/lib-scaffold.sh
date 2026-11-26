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
# PURPOSE, P (the project folder in the Core), DATE; CORE_NAME comes from load_settings.
render() {
  sed -e "s|{{NAME}}|$(esc "$NAME")|g" \
      -e "s|{{PURPOSE}}|$(esc "$PURPOSE")|g" \
      -e "s|{{PROJECT_DIR}}|$(esc "$P")|g" \
      -e "s|{{CORE_NAME}}|$(esc "$CORE_NAME")|g" \
      -e "s|{{DATE}}|$DATE|g" "$1" > "$2"
}

# put <template> <dest> [copy] — create dest from template unless it exists. Default mode
# renders placeholders through render() above; "copy" copies the file as is. The file is written
# to dest.tmp.<pid> and moved into place, so a failed write leaves no partial dest a rerun would skip.
# A dangling symlink at dest stays: the file goes to the end of the link chain, as a plain write would. A link
# that loops, or a chain of more than 16 links, is refused with a message that names dest; nothing is written.
put() {
  local src="$1" dest="$2" mode="${3:-render}" tmp out n=0 t
  if [ -e "$dest" ]; then echo "skipped $(rel_core "$dest")"; return 0; fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$dest")"; return 0; fi
  out="$dest"
  while [ -L "$out" ] && [ "$n" -lt 16 ]; do
    t="$(readlink "$out")" || return 1
    case "$t" in /*) out="$t" ;; *) out="$(dirname "$out")/$t" ;; esac
    n=$((n + 1))
  done
  if [ -L "$out" ]; then
    echo "Could not write $dest: it is a link that loops or a chain of more than 16 links. Fix or remove the link, then run again." >&2
    return 1
  fi
  [ "$out" = "$dest" ] && { mkdir -p "$(dirname "$dest")" || return 1; }
  tmp="$out.tmp.$$"
  if [ "$mode" = copy ]; then cp "$src" "$tmp"; else render "$src" "$tmp"; fi \
    && mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
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
CLAUDE.md.tmpl|AGENTS.md
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
    [ "$b" != AGENTS.md ] || b="$(basename "$(project_instructions "$dest")")"
    if [ "$a" = mkdir ]; then mkdir_p "$dest/$b" || return 1
    else put "$tpl/$a" "$dest/$b" || return 1; fi
  done <<< "$(project_docs_manifest)"
}

# symlink <target> <link> — ln -s that makes a real link or fails. Git Bash and Cygwin copy the target unless
# winsymlinks:nativestrict is set (then: a native link, or an error when Windows allows none). Exit 1 and the
# copied file taken out again when <link> is a plain file after it (a folder at <link>, there before or since,
# gets the link inside it, as with ln; the caller judges that; a folder is never removed here).
symlink() {
  MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" CYGWIN="${CYGWIN:+$CYGWIN }winsymlinks:nativestrict" ln -s "$1" "$2" || return 1
  if [ -L "$2" ] || [ -d "$2" ]; then return 0; fi
  rm -f "$2"; echo "ln -s made a copy, not a link: $2" >&2; return 1
}
# Legacy Claude Code entry point. Existing user files and unrelated links stay in place.
link_project_instructions() {
  local link="$1/$3" target lnerr lnrc
  target="$(project_instructions "$2")"
  # (a DRY=1 plan for a project folder that is not there yet, as scaffold --dry-run, is let through)
  if [ ! -f "$target" ] && { [ "${DRY:-0}" -ne 1 ] || [ -d "$2" ]; }; then echo "$target does not exist; nothing to link $3 to" >&2; return 1; fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$target" ]; then
      echo "$3 exists and is not a link to $target; leave it or remove it yourself" >&2
      return 1
    fi
  fi

  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    echo "skipped $(rel_core "$link")"; return 0
  fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$link")"; return 0; fi
  mkdir -p "$1" || return 1
  # (a directory that appeared at $link since the -e test would take the link inside itself: BSD and GNU ln -n
  # only cover a link to a directory, so look again right after and take our stray link out)
  lnerr="$(symlink "$target" "$link" 2>&1)"; lnrc=$?
  if [ -d "$link" ] && [ ! -L "$link" ]; then
    [ ! -L "$link/${target##*/}" ] || [ "$(readlink "$link/${target##*/}")" != "$target" ] || rm -f "$link/${target##*/}"
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
link_local_claude() { link_project_instructions "$1" "$2" CLAUDE.local.md; }

# Write paths as text, not imports or copies. An older Core may not have a root entry yet.
agents_entry_text() {
  local project="${1%/*}"
  printf '# Local agent entry point\n\nRead the private Core instructions before working on this project:\n\n'
  printf -- '- Core (if present): %s/AGENTS.md\n- Project: %s\n' "${project%/*}" "$1"
}

agents_entry_matches() {
  [ ! -L "$1" ] && [ -f "$1" ] && cmp -s "$1" <(agents_entry_text "$2")
}

# Existing relative and absolute links count only when they name this project's instruction file.
agents_link_target() {
  local dest
  # BSD readlink may omit its own line ending when the target already ends in a newline.
  dest="$(readlink -n "$1" && printf '.')" || return 1
  dest="${dest%.}"
  case "$dest" in *$'\n'*|*$'\r'*) return 1 ;; esac
  _host_path_r "$dest"; dest="$_HP"
  case "$dest" in /*) ;; *) dest="${1%/*}/$dest" ;; esac
  printf '%s/%s\n' "$(canon_dir "${dest%/*}")" "${dest##*/}"
}

# Identify the exact old entry so that a recheck before publishing can detect a change.
agents_entry_state() {
  local file="$1" target="$2" dest old="${2%/*}/CLAUDE.md"
  if [ -L "$file" ]; then
    [ ! -d "$file" ] || return 1
    dest="$(agents_link_target "$file")" || return 1
    [ "$dest" = "$target" ] || { [ "$dest" = "$old" ] && [ ! -e "$old" ] && [ ! -L "$old" ]; } || return 1
    readlink "$file"
  elif agents_entry_matches "$file" "$target"; then
    printf 'current\n'
  elif [ "$target" != "$old" ] && [ ! -e "$old" ] && [ ! -L "$old" ] && agents_entry_matches "$file" "$old"; then
    printf 'legacy entry\n'
  elif [ ! -e "$file" ]; then
    printf 'missing\n'
  else
    return 1
  fi
}

# Return 2 if Git does not ignore the entry, including when the old link or file is tracked.
# A dry run may plan the entry before scaffold creates its checkout or private project.
write_agents_entry() {
  local file="$1/AGENTS.md" target state tmp rc=1
  target="$(project_instructions "$2")"
  if [ -f "$2/CLAUDE.md" ] && { [ -e "$2/AGENTS.md" ] || [ -L "$2/AGENTS.md" ]; }; then
    echo "AGENTS.md exists in the Core at $2/AGENTS.md; resolve the two private instruction files first" >&2
    return 1
  fi
  if [ ! -f "$target" ] && { [ "${DRY:-0}" -ne 1 ] || [ -d "$2" ]; }; then return 1; fi
  case "$target" in *$'\n'*|*$'\r'*) echo 'Core instruction paths must be on one line' >&2; return 1 ;; esac
  if ! state="$(agents_entry_state "$file" "$target")"; then
    echo "$file exists and will stay in place; configure it yourself to read $target" >&2
    return 1
  fi
  if [ "${DRY:-0}" -ne 1 ]; then
    if GIT_LITERAL_PATHSPECS=0 git -C "$1" check-ignore -q -- AGENTS.md; then
      :
    elif [ "$?" -eq 1 ]; then
      echo "$file must be ignored by Git before CoreCrew can write it" >&2; return 2
    else
      return 1
    fi
  fi
  if [ "$state" = current ]; then echo "skipped $(rel_core "$file")"; return 0; fi
  if [ "${DRY:-0}" -eq 1 ]; then echo "would create $(rel_core "$file")"; return 0; fi
  tmp="$(mktemp -d "$1/.corecrew-entry.XXXXXX")" || return 1
  if agents_entry_text "$target" > "$tmp/AGENTS.md"; then
    if [ "$state" = missing ]; then
      # Use the checkout directory as the destination, so an AGENTS.md directory cannot take our file.
      mv -n "$tmp/AGENTS.md" "$1/" && agents_entry_matches "$file" "$target" && rc=0
    elif [ "$(agents_entry_state "$file" "$target")" = "$state" ]; then
      mv -f "$tmp/AGENTS.md" "$1/" && rc=0
    fi
  fi
  rm -f "$tmp/AGENTS.md"
  rmdir "$tmp"
  [ "$rc" -eq 0 ] || return 1
  echo "created $(rel_core "$file")"
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

# projects_upsert <name> <purpose> <entry> <purpose_set> — the name's PROJECTS.md line: when there is one, its entry
# (the text after the last " — ") becomes <entry>, and with <purpose_set> 1 the whole line becomes
# "- <name> — <purpose> — <entry>"; prints "updated PROJECTS.md entry". Else the line is added by projects_entry,
# silently. Written to a temp file and moved into place; exit 1 when the write fails (PROJECTS.md as it was).
# With DRY=1 nothing is written ("would update PROJECTS.md entry" for an update).
projects_upsert() {
  local f="$CORE_DIR/PROJECTS.md" tmp
  if [ -f "$f" ] && grep -q "^- $1 " "$f"; then
    if [ "${DRY:-0}" -eq 1 ]; then echo "would update PROJECTS.md entry"; return 0; fi
    tmp="$f.tmp.$$"
    if N="$1" E="$3" PU="$2" PS="$4" LC_ALL=C awk 'BEGIN { pre = "- " ENVIRON["N"] " "; sep = " — " }
        !done && index($0, pre) == 1 {
          s = $0; last = 0; off = 0
          while ((i = index(s, sep)) > 0) { last = off + i; off += i; s = substr(s, i + 1) }
          if (ENVIRON["PS"] == "1") $0 = "- " ENVIRON["N"] sep ENVIRON["PU"] sep ENVIRON["E"]
          else $0 = (last > 0 ? substr($0, 1, last - 1) : $0) sep ENVIRON["E"]
          done = 1 }
        { print }' "$f" > "$tmp" && mv "$tmp" "$f"; then
      echo "updated PROJECTS.md entry"
    else rm -f "$tmp"; return 1; fi
  else
    projects_entry "$1" "$2" "$3" >/dev/null
  fi
}
