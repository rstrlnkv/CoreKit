#!/usr/bin/env bash
# Moves an existing project (a git repo folder) into the Core layout: internal files to
# <Core>/<name>/, the repo to <Core>/<name>/code (spec section 11).
# Usage: bash adopt.sh --from <folder> [--name <name>] [--public-docs "<paths>"]
#                      [--check "<command>"] [--purpose "<text>"] [--dry-run]
# Env:   CORE_DIR overrides the plugin option core_dir (see lib.sh).
#
# Refusals (exit 2, one line on stderr, nothing changed; all checked before any change):
#   not a git repo | uncommitted changes | already inside Core | Core is inside the folder
#   invalid project name '<n>' (use --name) | target exists: <path> | Core is not set up
#   not found: <path>                  a --public-docs path that is not in the repo
#   symlink: <path> -> <target>; replace it with a file first   (a tracked file to be copied)
#   submodule: <path>; adopt cannot move it                     (a tracked gitlink to be copied)
#   different disk: move the folder next to Core first          (the move must be a rename;
#       also "different disk: could not compare disks; ..." when df gives no usable answer)
#   git does not know your name and email (...)
# Only files git tracks are copied and removed; ignored files stay in <Core>/<n>/code untouched.
# Exit 1 (nothing deleted; the message says where the files are): a failed mv after the commit.
# Steps: copy CLAUDE.md, AGENTS.md, docs/ and .claude/ (not settings.local.json, not worktrees/, not
# --public-docs paths) into a temp folder in the Core; add the wiki map and the pages the
# new-project templates have that are missing, the check: line and public-docs: line; give
# copied pages that lack wiki front matter the missing fields. Then one commit in the repo
# "Move internal Claude files to Core" (git rm of the copied files, plus the corecrew ignore lines of
# the new-project .gitignore template that the repo's .gitignore lacks, appended at its end: user lines
# are never changed or removed; skipped when there is neither; if it fails, the files and .gitignore
# come back and nothing else was touched). Then the temp folder becomes
# <Core>/<name>/, the repo folder is moved with mv to <Core>/<name>/code, linked worktrees under
# .claude/worktrees are repaired, git hook shims are installed, PROJECTS.md gets its line, and the Core gets one commit "Adopt <name>".
# --dry-run prints the plan and changes nothing. The last line is "open: <Core>/<name>/code".
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT_DIR/skills/new-project/templates"
. "$ROOT_DIR/scripts/lib.sh"
export GIT_LITERAL_PATHSPECS=1   # file names are never patterns

usage() {
  echo 'usage: adopt.sh --from <folder> [--name <n>] [--public-docs "<paths>"] [--check "<command>"] [--purpose "<text>"] [--dry-run]' >&2
  exit 2
}
refuse() { printf '%s\n' "$1" >&2; exit 2; }

FROM=""; NAME=""; PUBLIC=""; CHECK=""; PURPOSE="Adopted existing project"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || usage; FROM="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || usage; NAME="$2"; shift 2 ;;
    --public-docs) [ $# -ge 2 ] || usage; PUBLIC="$2"; shift 2 ;;
    --check) [ $# -ge 2 ] || usage; CHECK="$2"; shift 2 ;;
    --purpose) [ $# -ge 2 ] || usage; PURPOSE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$FROM" ] || usage
# One line each in CLAUDE.md, PROJECTS.md and sed replacements: no line breaks.
CHECK="$(printf '%s' "$CHECK" | tr '\r\n' '  ')"
PURPOSE="$(printf '%s' "$PURPOSE" | tr '\r\n' '  ' | tr -s ' ')"
PUBLIC="$(printf '%s' "$PUBLIC" | tr '\r\n' '  ')"
load_settings

# --- Refusals. Read-only; order as listed in the header.
{ [ -d "$FROM" ] && [ -d "$FROM/.git" ]; } || refuse "not a git repo"
FROM="$(cd -P "$FROM" && pwd)"
git -C "$FROM" rev-parse --verify -q HEAD >/dev/null 2>&1 || refuse "not a git repo"
[ -z "$(git -C "$FROM" status --porcelain 2>&1)" ] || refuse "uncommitted changes"
case "$FROM/" in "$CORE_DIR"/*) refuse "already inside Core" ;; esac
case "$CORE_DIR/" in "$FROM"/*) refuse "Core is inside the folder" ;; esac
[ -n "$NAME" ] || NAME="$(basename "$FROM")"
valid_project_name "$NAME" || refuse "invalid project name '$NAME' (use --name)"
P="$CORE_DIR/$NAME"
{ [ ! -e "$P" ] && [ ! -L "$P" ]; } || refuse "target exists: $P"
{ core_ready && [ -d "$CORE_DIR/.git" ]; } || refuse "Core is not set up"

# --- What goes where (read-only).
# public_path <file> — exit 0 when the repo-relative file is under a --public-docs path.
PUB_LIST=""
set -f
for t in $(printf '%s' "$PUBLIC" | tr ',' ' '); do
  t="${t#./}"; while [ "${t%/}" != "$t" ]; do t="${t%/}"; done
  [ -z "$t" ] || PUB_LIST="$PUB_LIST$t
"
done
set +f
public_path() {
  local t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$1" in "$t"|"$t"/*) return 0 ;; esac
  done <<< "$PUB_LIST"
  return 1
}
# kind <file> — "stay" (settings.local.json, worktrees/), "public" or "copy"
kind() {
  case "$1" in
    .claude/settings.local.json|.claude/worktrees|.claude/worktrees/*) echo stay ;;
    *) if public_path "$1"; then echo public; else echo copy; fi ;;
  esac
}

# A --public-docs path must exist in the repo.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  { [ -e "$FROM/$t" ] || [ -L "$FROM/$t" ]; } || refuse "not found: $t"
done <<< "$PUB_LIST"

# Only files git tracks are copied and removed; ignored and untracked files stay in code/ as
# they are (so nothing private ends up in the Core's git).
TRACKED="$(git -C "$FROM" -c core.quotepath=false ls-files -- CLAUDE.md AGENTS.md docs .claude)"
COPY=""; PUBKEEP=""; NCOPY=0; NPUB=0; NSTAY=0
REMOVE=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$(kind "$f")" in
    copy) COPY="$COPY$f
"; NCOPY=$((NCOPY + 1)); REMOVE[${#REMOVE[@]}]="$f" ;;
    public) PUBKEEP="$PUBKEEP$f
"; NPUB=$((NPUB + 1)) ;;
    stay) NSTAY=$((NSTAY + 1)) ;;
  esac
done <<< "$TRACKED"

# The corecrew ignore lines the repo's .gitignore lacks (internal Claude files and .env, from the
# new-project template), so local Claude files (.claude/settings.local.json, .claude/worktrees/) never
# end up in a `save`. When .env.* is added, its exceptions are added after it again (the last match
# wins in .gitignore). A .gitignore that is a symlink or not a file is left alone, with a warning.
GI="$FROM/.gitignore"; GI_ADD=""; GI_SKIP=0; GI_N=0
if [ -L "$GI" ] || { [ -e "$GI" ] && [ ! -f "$GI" ]; }; then
  GI_SKIP=1
elif [ -r "$TPL/code/gitignore-common" ]; then
  gi_has() { [ -f "$GI" ] && tr -d '\r' < "$GI" | grep -qxF -- "$1"; }
  envstar=0
  while IFS= read -r l; do
    l="${l%$'\r'}"
    case "$l" in CLAUDE*|AGENTS.md|.claude/*|docs/superpowers/*|.env*|'!.env'*) ;; *) continue ;; esac
    case "$l" in
      '!'*) if [ "$envstar" -eq 0 ] && gi_has "$l"; then continue; fi ;;
      *) if gi_has "$l"; then continue; fi ;;
    esac
    [ "$l" = '.env.*' ] && envstar=1
    GI_ADD="$GI_ADD$l
"; GI_N=$((GI_N + 1))
  done < "$TPL/code/gitignore-common"
fi

# Symlinks and submodules (gitlinks) cannot be moved faithfully: refuse if a file that would be
# copied is one.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  f="${line#*$'\t'}"
  [ "$(kind "$f")" = copy ] || continue
  case "$line" in
    120000*) refuse "symlink: $f -> $(readlink "$FROM/$f"); replace it with a file first" ;;
    160000*) refuse "submodule: $f; adopt cannot move it" ;;
  esac
done <<< "$(git -C "$FROM" -c core.quotepath=false ls-files -s -- CLAUDE.md AGENTS.md docs .claude \
  | awk -F'\t' '$1 ~ /^(120000|160000) / { print substr($1, 1, 6) "\t" substr($0, index($0, "\t") + 1) }')"

# The move must be a rename: the folder (and its parent) and the Core must share a file system.
mount_of() { df -P "$1" 2>/dev/null | sed -n '2s/^[^ ]* *[0-9]* *[0-9]* *[0-9]* *[0-9]*% *//p'; }
M_CORE="$(mount_of "$CORE_DIR")"; M_FROM="$(mount_of "$FROM")"; M_PAR="$(mount_of "$(dirname "$FROM")")"
# An empty answer (df failed or printed something unparseable) is a refusal: fail closed.
{ [ -n "$M_CORE" ] && [ -n "$M_FROM" ] && [ -n "$M_PAR" ]; } \
  || refuse "different disk: could not compare disks; move the folder next to Core first"
{ [ "$M_FROM" = "$M_CORE" ] && [ "$M_PAR" = "$M_CORE" ]; } \
  || refuse "different disk: move the folder next to Core first"

# Git needs an identity for the commits: refuse now rather than half way.
ident_ok() { git -C "$1" var GIT_AUTHOR_IDENT >/dev/null 2>&1 && git -C "$1" var GIT_COMMITTER_IDENT >/dev/null 2>&1; }
if [ "${#REMOVE[@]}" -gt 0 ] || [ -n "$GI_ADD" ]; then
  ident_ok "$FROM" || refuse "git does not know your name and email (git config --global user.name / user.email)"
fi
ident_ok "$CORE_DIR" || refuse "git does not know your name and email (git config --global user.name / user.email)"

# --- Dry run: the plan.
show() {  # show <heading> <newline-separated list> — at most 15 entries
  local n=0 f
  [ -n "$2" ] || return 0
  echo "$1"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    if [ "$n" -le 15 ]; then echo "  $f"; fi
  done <<< "$2"
  [ "$n" -le 15 ] || echo "  ... and $((n - 15)) more"
}
if [ "$DRY" -eq 1 ]; then
  echo "Plan: adopt $FROM as '$NAME'"
  show "copy to $P/:" "$COPY"
  if [ "${#REMOVE[@]}" -gt 0 ]; then
    echo "remove from the repo in one commit \"Move internal Claude files to Core\": ${#REMOVE[@]} file(s) (the copied ones that git tracks)"
  elif [ -n "$GI_ADD" ]; then
    echo "one repo commit \"Move internal Claude files to Core\" with only the ignore lines below (git tracks none of the copied files)"
  else
    echo "no repo commit: git tracks none of the copied files"
  fi
  show "add to code/.gitignore (in the same commit):" "$GI_ADD"
  [ "$GI_SKIP" -eq 0 ] || echo "warning: .gitignore is not a plain file; add the corecrew ignore lines to it yourself"
  show "stays in code (public docs):" "$PUBKEEP"
  IGN="$(cd "$FROM" && for t in CLAUDE.md AGENTS.md docs .claude; do
    { [ -e "$t" ] || [ -L "$t" ]; } && find "$t" -path .claude/worktrees -prune -o \( -type f -o -type l \) -print
  done | LC_ALL=C sort | LC_ALL=C comm -23 - <(printf '%s\n' "$TRACKED" | LC_ALL=C sort))"
  show "stays in code (ignored by git):" "$IGN"
  [ "$NSTAY" -eq 0 ] || echo "stays in code (local settings and worktrees): $NSTAY tracked file(s)"
  CRE=""
  while IFS='|' read -r a b; do
    [ "$a" != mkdir ] || { [ -d "$FROM/$b" ] || CRE="$CRE$b/
"; continue; }
    printf '%s\n' "$COPY" | grep -qxF -- "$b" || CRE="$CRE$b
"
  done <<< "$(project_docs_manifest)"
  show "create in $P/ (missing pages from the new-project templates):" "$CRE"
  echo "add to $P/: the check: line$([ -n "$PUB_LIST" ] && echo ', the public-docs: line'), front matter fields missing on copied pages, map lines for pages the map lacks"
  echo "move: $FROM -> $P/code"
  echo "then: install git hook shims, add the PROJECTS.md line, commit \"Adopt $NAME\" in the Core"
  echo "dry run: nothing was changed"
  exit 0
fi

# --- Real run. Stage everything in a temp folder inside the Core (same disk), so a failure
# before the repo commit leaves nothing but a folder we remove ourselves. After the repo commit the
# staged copy holds the only copy of the internal files: from then on nothing is ever deleted
# (the trap only removes the temp folder while it is empty).
COMMITTED=0
TMP="$(mktemp -d "$CORE_DIR/.adopt.XXXXXX")" || { echo "adopt: cannot create a temp folder in $CORE_DIR" >&2; exit 1; }
cleanup() { if [ "$COMMITTED" -eq 0 ]; then rm -rf "$TMP"; else rmdir "$TMP" 2>/dev/null; fi; }
trap cleanup EXIT
STAGE="$TMP/p"
mkdir "$STAGE" || exit 1
DATE="$(date +%Y-%m-%d)"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$STAGE/$(dirname "$f")" && cp -pP "$FROM/$f" "$STAGE/$f" \
    || { echo "adopt: could not copy $f" >&2; exit 1; }
done <<< "$COPY"

# set_line <file> <key> <value> — replace the first "key:" line, else append "key: value".
set_line() {
  local tmp="$1.tmp.$$"
  KEY="$2" VAL="$3" awk 'BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"]; done = 0 }
    !done && (index($0, k ":") == 1) { print k ": " v; done = 1; next }
    { print }
    END { if (!done) print k ": " v }' "$1" > "$tmp" && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

# Missing wiki pages and the map (from the new-project templates); CLAUDE.md if there was none.
CR="$(put_project_docs "$TPL" "$STAGE")" || exit 1
CREATED="$(printf '%s\n' "$CR" | sed -n 's|^created \.adopt\.[^/]*/p/||p')"
if [ -n "$CHECK" ]; then set_line "$STAGE/CLAUDE.md" check "$CHECK" || exit 1
elif ! grep -q '^check:' "$STAGE/CLAUDE.md"; then set_line "$STAGE/CLAUDE.md" check "<set after scaffolding>" || exit 1
fi
[ -z "$PUB_LIST" ] || set_line "$STAGE/CLAUDE.md" public-docs "$PUBLIC" || exit 1

# fm_value <file> <key> — a front matter value without quotes.
fm_value() {
  awk -v k="$2" 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { exit }
    f && index($0, k ":") == 1 { v = substr($0, length(k) + 2); gsub(/^[ \t]+|[ \t\r]+$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit }' "$1"
}
# fix_frontmatter <file> <updated> — add the wiki front matter fields the page lacks. Nothing
# is invented: the title is the page's first "# " heading (else the file name), updated is the
# date of its last commit, description is an explicit TODO, status draft, files and related empty.
fix_frontmatter() {
  local f="$1" up="$2" title tmp="$1.adopt.$$"
  title="$(awk '/^# / { sub(/^# +/, ""); print; exit }' "$f" | tr -d '"\\\r')"
  [ -n "$title" ] || title="$(basename "$f" .md)"
  if [ "$(head -1 "$f" | tr -d '\r')" = "---" ]; then
    sed -n '2,$p' "$f" | grep -q '^---[[:space:]]*$' || return 0   # unclosed: leave it, wiki-check reports it
    awk -v T="$title" -v U="$up" '
      BEGIN { n = split("title description status files related updated", K, " ")
        d["title"] = "\"" T "\""; d["description"] = "\"TODO: describe this page.\""
        d["status"] = "draft"; d["files"] = "[]"; d["related"] = "[]"; d["updated"] = U }
      NR == 1 { print; infm = 1; next }
      infm && /^---[ \t\r]*$/ { for (i = 1; i <= n; i++) if (!(K[i] in has)) print K[i] ": " d[K[i]]
        infm = 0; print; next }
      infm { if (match($0, /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/)) {
          key = substr($0, 1, RLENGTH); sub(/[ \t]*:$/, "", key)
          val = substr($0, RLENGTH + 1); gsub(/^[ \t]+|[ \t\r]+$/, "", val); has[key] = 1
          if ((key == "title" || key == "description" || key == "status" || key == "updated") \
              && (val == "" || val == "\"\"" || val == "\047\047")) { print key ": " d[key]; next } }
        print; next }
      { print }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    { printf -- '---\ntitle: "%s"\ndescription: "TODO: describe this page."\nstatus: draft\nfiles: []\nrelated: []\nupdated: %s\n---\n\n' "$title" "$up"
      cat "$f"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$f"
}

# Copied pages that wiki-check says lack front matter fields; pages the map does not link.
W="$(bash "$ROOT_DIR/scripts/wiki-check.sh" "$STAGE" 2>/dev/null)"
while IFS= read -r pg; do
  [ -n "$pg" ] || continue
  up="$(git -C "$FROM" log -1 --format=%cd --date=short -- "docs/$pg" 2>/dev/null)"
  fix_frontmatter "$STAGE/docs/$pg" "${up:-$DATE}" || { echo "adopt: could not fix front matter of $pg" >&2; exit 1; }
done <<< "$(printf '%s\n' "$W" | sed -n 's/^wiki-check: \(.*\): missing front matter field .*$/\1/p' | LC_ALL=C sort -u)"
W="$(bash "$ROOT_DIR/scripts/wiki-check.sh" "$STAGE" 2>/dev/null)"
while IFS= read -r pg; do
  [ -n "$pg" ] || continue
  title="$(fm_value "$STAGE/docs/$pg" title)"; [ -n "$title" ] || title="$pg"
  desc="$(fm_value "$STAGE/docs/$pg" description)"
  case "$desc" in ""|">"|"|"|">-"|"|-") desc="TODO: describe this page." ;; esac
  target="$pg"; case "$pg" in *" "*) target="<$pg>" ;; esac
  [ -z "$(tail -c1 "$STAGE/docs/INDEX.md")" ] || printf '\n' >> "$STAGE/docs/INDEX.md"
  printf -- '- [%s](%s) — %s\n' "$title" "$target" "$desc" >> "$STAGE/docs/INDEX.md" || exit 1
done <<< "$(printf '%s\n' "$W" | sed -n 's/^wiki-check: \(.*\): not in INDEX\.md$/\1/p')"

# The repo commit. If it fails the files and .gitignore come back; nothing else was touched.
[ "$GI_SKIP" -eq 0 ] || echo "warning: .gitignore is not a plain file; add the corecrew ignore lines to it yourself" >&2
GI_NEW=0
if [ -n "$GI_ADD" ]; then
  if [ -e "$GI" ]; then cp -p "$GI" "$TMP/gitignore.orig" || { echo "adopt: could not back up .gitignore" >&2; exit 1; }
  else GI_NEW=1; fi
  { { [ ! -s "$GI" ] || [ -z "$(tail -c1 "$GI")" ] || printf '\n'; }
    printf '# corecrew: internal Claude files and secrets stay out of this repo\n%s' "$GI_ADD"; } >> "$GI" \
    || { if [ "$GI_NEW" -eq 1 ]; then rm -f "$GI"; else cp -p "$TMP/gitignore.orig" "$GI"; fi
         echo "adopt: could not write $GI" >&2; exit 1; }
fi
if [ "${#REMOVE[@]}" -gt 0 ] || [ -n "$GI_ADD" ]; then
  if ! { { [ "${#REMOVE[@]}" -eq 0 ] || git -C "$FROM" rm -q -- "${REMOVE[@]}"; } \
         && { [ -z "$GI_ADD" ] || git -C "$FROM" add -- .gitignore; } \
         && git -C "$FROM" commit -q -m "Move internal Claude files to Core"; } >/dev/null 2>&1; then
    if [ "${#REMOVE[@]}" -gt 0 ]; then
      git -C "$FROM" reset -q -- "${REMOVE[@]}" >/dev/null 2>&1
      git -C "$FROM" checkout -q -- "${REMOVE[@]}" >/dev/null 2>&1
    fi
    if [ -n "$GI_ADD" ]; then
      git -C "$FROM" reset -q -- .gitignore >/dev/null 2>&1
      if [ "$GI_NEW" -eq 1 ]; then rm -f "$GI"; else cp -p "$TMP/gitignore.orig" "$GI"; fi
    fi
    refuse "could not commit in $FROM (nothing was changed)"
  fi
  COMMITTED=1
  rm -f "$TMP/gitignore.orig"
fi
# The move (a rename: same file system, checked above). If it fails nothing is deleted or moved
# back; the output says where everything is.
if ! mv "$STAGE" "$P"; then
  echo "adopt: could not create $P. Your project is still at $FROM." >&2
  [ "$COMMITTED" -eq 0 ] || echo "adopt: the internal files are in $STAGE and the repo has the commit 'Move internal Claude files to Core' (to undo it: git -C \"$FROM\" revert HEAD)." >&2
  exit 1
fi
if ! mv "$FROM" "$P/code"; then
  echo "adopt: could not move $FROM to $P/code. Nothing was deleted." >&2
  echo "adopt: your project is still at $FROM; the internal files are copied to $P." >&2
  [ "$COMMITTED" -eq 0 ] || echo "adopt: the repo has the commit 'Move internal Claude files to Core' (to undo it: git -C \"$FROM\" revert HEAD)." >&2
  exit 1
fi

# From here the project is in place; problems are reported, not undone.
echo "copied ${NCOPY} file(s) to $P/"
if [ "$COMMITTED" -eq 1 ]; then
  [ "${#REMOVE[@]}" -eq 0 ] || echo "removed ${#REMOVE[@]} file(s) from the repo (commit: Move internal Claude files to Core)"
  [ -z "$GI_ADD" ] || echo "added $GI_N ignore line(s) to .gitignore (commit: Move internal Claude files to Core)"
else echo "no repo commit: git tracks none of the copied files"; fi
[ -z "$CREATED" ] || { echo "created:"; printf '%s\n' "$CREATED" | sed 's/^/  /'; }
echo "old: $FROM"
echo "new: $P/code"
# Linked worktrees under .claude/worktrees moved with the repo: point them and the repo at each other.
WT=()
for w in "$P/code/.claude/worktrees"/*; do
  [ -f "$w/.git" ] && WT[${#WT[@]}]="$w"
done
if [ -d "$P/code/.git/worktrees" ]; then
  if [ "${#WT[@]}" -gt 0 ]; then git -C "$P/code" worktree repair "${WT[@]}" >/dev/null 2>&1
  else git -C "$P/code" worktree repair >/dev/null 2>&1; fi \
    || echo "warning: could not repair git worktrees after the move; run: git -C \"$P/code\" worktree repair <worktree folder>" >&2
fi
if ! CORE_DIR="$CORE_DIR" bash "$ROOT_DIR/scripts/install-hooks.sh" "$P"; then
  echo "warning: git hooks were not installed; run: CORE_DIR=\"$CORE_DIR\" bash \"$ROOT_DIR/scripts/install-hooks.sh\" \"$P\"" >&2
fi
projects_entry "$NAME" "$PURPOSE" >/dev/null || echo "warning: could not write PROJECTS.md" >&2
if git -C "$CORE_DIR" add -- "$NAME" PROJECTS.md && git -C "$CORE_DIR" commit -q -m "Adopt $NAME" -- "$NAME" PROJECTS.md >/dev/null 2>&1; then
  echo "Core commit: Adopt $NAME"
else
  echo "warning: the Core commit failed; commit $NAME/ and PROJECTS.md in $CORE_DIR yourself" >&2
fi
WOUT="$(bash "$ROOT_DIR/scripts/wiki-check.sh" "$P" 2>&1)"
if [ -n "$WOUT" ]; then echo "the wiki has problems to fix:"; printf '%s\n' "$WOUT"; else echo "wiki: green"; fi
echo "open: $P/code"
exit 0
