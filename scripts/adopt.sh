#!/usr/bin/env bash
# Brings an existing project (a git repo folder) into the corecrew layout (docs/specs/2026-11-04-project-
# layout-design.md, section 5.2): internal files go to <Core>/<name>/, the repo stays where it is, in
# <Projects>/<Name> (<Projects> = the Core's parent folder, <name> = <Name> in lower case). Only a project
# still in the old layout (a repo at <Core>/<name>/code) is moved, to <Projects>/<name>.
# Usage: bash adopt.sh --from <folder> [--name <name>] [--public-docs "<paths>"]
#                      [--check "<command>"] [--purpose "<text>"] [--dry-run]
# Env:   CORE_DIR overrides the plugin option core_dir (see lib.sh).
#
# Refusals (exit 2, one line on stderr, nothing changed; all checked before any change, in this order):
#   not a git repo | uncommitted changes | already inside Core | Core is inside the folder
#   not in <Projects>: move the folder to <Projects>/<Name> first   (not a direct child of <Projects>,
#       and not an old-layout <Core>/<name>/code)
#   old layout: only --purpose and --dry-run apply                  (--name, --public-docs, --check)
#   invalid project name '<n>' (rename the folder)                (old layout: without the hint)
#   name '<n>' does not match the folder '<Name>': rename the folder to <Projects>/<n> first
#       (--name must be the folder name in lower case: the link to the Core is by name only)
#   target exists: <path>        <Core>/<name> (new layout) or a <Projects> folder named <name> in any
#                                letter case (old layout)
#   two folders differ only in case: <A>, <B>
#   Core is not set up
#   CLAUDE.local.md exists in <folder>: move it away first (...)    (a file, or a link elsewhere)
#   not found: <path>                  a --public-docs path that is not in the repo
#   symlink: <path> -> <target>; replace it with a file first   (a tracked file to be copied)
#   submodule: <path>; adopt cannot move it                     (a tracked gitlink to be copied)
#   different disk: <Core> and <Projects> are on different disks; put the Core on the same disk as
#       <Projects> first        (old layout only: the move must be a rename; also "different disk: could
#       not compare the disks of <Core> and <Projects>" when df gives no usable answer)
#   git does not know your name and email (...)
# Only files git tracks are copied and removed; ignored files stay in the repo untouched.
# Exit 1 (nothing deleted; the message says where the files are): a failed mv after the repo commit.
# Steps (new layout): copy CLAUDE.md, AGENTS.md, docs/ and .claude/ (not settings.local.json, not
# worktrees/, not --public-docs paths) into a temp folder in the Core; add the wiki map and the pages the
# new-project templates have that are missing, the check: line and public-docs: line; fold each tracked
# .claude/rules/<f>.md into CLAUDE.md as "### <f>" under "## Rules" (the heading is added at the end when
# missing; "Applies to: <paths>" from its paths: front matter, the front matter itself dropped, its
# headings moved three levels down); other tracked .claude/ files are kept in <Core>/<name>/.claude/,
# where they no longer load (the plan and the report list them); give copied pages that lack wiki front
# matter the missing fields. Then one commit in the repo "Move internal Claude files to Core" (git rm of
# the copied and folded files, plus the corecrew ignore lines of the new-project .gitignore template that
# the repo's .gitignore lacks, appended at its end: user lines are never changed or removed; plus
# .worktreeinclude from the new-project template when the repo has none, so native worktrees get
# .claude/settings.local.json; an existing one is never edited; skipped when there is none of these; if it
# fails, the files, .gitignore and .worktreeinclude come back and nothing else was touched). Then the temp
# folder becomes <Core>/<name>/.
# Old layout: the internal files are in <Core>/<name>/ already; the repo commit holds only the missing
# ignore lines and .worktreeinclude; then the repo folder is moved with mv to <Projects>/<name> and linked
# worktrees under .claude/worktrees are repaired; each <Core>/<name>/.claude/rules/<f>.md is folded into
# <Core>/<name>/CLAUDE.md the same way (the rule files are kept; they no longer load); a warning: line
# names <Core>/<name>/CLAUDE.md when it still says ../docs/ or `code/` (it is not rewritten).
# Warnings (plan and report): tracked CLAUDE.md / AGENTS.md / CLAUDE.local.md files that stay in the repo
# (nested ones, public ones), which corecrew's hooks block changing or adding after adopt.
# Both: CLAUDE.local.md in the code folder becomes a link to <Core>/<name>/CLAUDE.md;
# .claude/settings.local.json is created from the template when missing (else left as is, with a
# warning: line naming the additionalDirectories entry to add when it lacks it); git hook shims are
# installed; PROJECTS.md gets (or has updated) its line "- <name> — <purpose> — <Name>/"; the Core gets
# one commit "Adopt <name>".
# --dry-run prints the plan and changes nothing. The last line is "open: <code folder>".
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

FROM=""; NAME=""; PUBLIC=""; CHECK=""; PURPOSE="Adopted existing project"; PURPOSE_SET=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || usage; FROM="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || usage; NAME="$2"; shift 2 ;;
    --public-docs) [ $# -ge 2 ] || usage; PUBLIC="$2"; shift 2 ;;
    --check) [ $# -ge 2 ] || usage; CHECK="$2"; shift 2 ;;
    --purpose) [ $# -ge 2 ] || usage; PURPOSE="$2"; PURPOSE_SET=1; shift 2 ;;
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
# The old layout: exactly <Core>/<name>/code of a project folder in the Core. Anything else in the Core
# is refused.
OLD=0; OLDNAME=""
case "$FROM/" in
  "$CORE_DIR"/*)
    rest="${FROM#"$CORE_DIR"/}"; OLDNAME="${rest%%/*}"
    case "$OLDNAME" in .*|standards|knowledge) OLDNAME="" ;; esac
    if [ -n "$OLDNAME" ] && [ "$rest" = "$OLDNAME/code" ] && [ -f "$CORE_DIR/$OLDNAME/CLAUDE.md" ]; then OLD=1
    else refuse "already inside Core"; fi ;;
esac
case "$CORE_DIR/" in "$FROM"/*) refuse "Core is inside the folder" ;; esac
BASE="$(basename "$FROM")"
if [ "$OLD" -eq 0 ]; then
  [ "$(dirname "$FROM")" = "$PROJECTS_DIR" ] || refuse "not in $PROJECTS_DIR: move the folder to $PROJECTS_DIR/$BASE first"
  if [ -n "$NAME" ]; then
    valid_project_name "$NAME" || refuse "invalid project name '$NAME' (rename the folder)"
    [ "$(lc "$BASE")" = "$NAME" ] || refuse "name '$NAME' does not match the folder '$BASE': rename the folder to $PROJECTS_DIR/$NAME first"
  else
    NAME="$(lc "$BASE")"
    valid_project_name "$NAME" || refuse "invalid project name '$NAME' (rename the folder)"
  fi
else
  { [ -z "$NAME" ] && [ -z "$PUBLIC" ] && [ -z "$CHECK" ]; } || refuse "old layout: only --purpose and --dry-run apply"
  NAME="$OLDNAME"
  valid_project_name "$NAME" || refuse "invalid project name '$NAME'"
fi
P="$CORE_DIR/$NAME"
if [ "$OLD" -eq 0 ]; then
  K="$FROM"   # the code folder: stays where it is
  { [ ! -e "$P" ] && [ ! -L "$P" ]; } || refuse "target exists: $P"
  CLASH="$(code_dir_of "$NAME" 2>&1 >/dev/null)"; [ $? -ne 3 ] || refuse "$CLASH"
else
  K="$PROJECTS_DIR/$NAME"   # the code folder after the move
  for d in "$PROJECTS_DIR"/*; do
    { [ -e "$d" ] || [ -L "$d" ]; } || continue
    [ "$(lc "$(basename "$d")")" = "$NAME" ] && refuse "target exists: $d"
  done
fi
{ core_ready && [ -d "$CORE_DIR/.git" ]; } || refuse "Core is not set up"
# CLAUDE.local.md becomes the link to the private CLAUDE.md: a file of the user's there is never replaced.
LOC="$FROM/CLAUDE.local.md"
if { [ -e "$LOC" ] || [ -L "$LOC" ]; } && ! { [ -L "$LOC" ] && [ "$(readlink "$LOC")" = "$P/CLAUDE.md" ]; }; then
  refuse "CLAUDE.local.md exists in $FROM: move it away first (adopt links that name to $P/CLAUDE.md)"
fi

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

# Only files git tracks are copied and removed; ignored and untracked files stay in the repo as
# they are (so nothing private ends up in the Core's git). The old layout copies nothing: its internal
# files are in the Core already.
TRACKED=""
[ "$OLD" -eq 1 ] || TRACKED="$(git -C "$FROM" -c core.quotepath=false ls-files -- CLAUDE.md AGENTS.md docs .claude)"
COPY=""; PUBKEEP=""; RULES=""; KEPT=""; NCOPY=0; NPUB=0; NSTAY=0; NRULES=0
REMOVE=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$(kind "$f")" in
    copy)
      REMOVE[${#REMOVE[@]}]="$f"
      case "$f" in
        .claude/rules/*.md) RULES="$RULES$f
"; NRULES=$((NRULES + 1)) ;;
        *) COPY="$COPY$f
"; NCOPY=$((NCOPY + 1))
           case "$f" in .claude/*) KEPT="$KEPT$f
" ;; esac ;;
      esac ;;
    public) PUBKEEP="$PUBKEEP$f
"; NPUB=$((NPUB + 1)) ;;
    stay) NSTAY=$((NSTAY + 1)) ;;
  esac
done <<< "$TRACKED"
# Old layout: .claude/ files already in the Core folder no longer load either. Its rule files (0.4 and
# older wrote .claude/rules/tests.md) are folded into CLAUDE.md like the new layout's; the files stay.
if [ "$OLD" -eq 1 ] && [ -d "$P/.claude" ]; then
  KEPT="$(cd "$P" && find .claude \( -type f -o -type l \) -print | LC_ALL=C sort)"
  if [ -d "$P/.claude/rules" ]; then
    RULES="$(cd "$P" && find .claude/rules -type f -name '*.md' -print | LC_ALL=C sort)"
    if [ -n "$RULES" ]; then
      KEPT="$(printf '%s\n' "$KEPT" | LC_ALL=C comm -23 - <(printf '%s\n' "$RULES"))"
      NRULES="$(printf '%s\n' "$RULES" | grep -c .)"
      RULES="$RULES
"
    fi
  fi
fi

# The corecrew ignore lines the repo's .gitignore lacks (internal Claude files and .env, from the
# new-project template), so local Claude files (CLAUDE.local.md, .claude/settings.local.json,
# .claude/worktrees/) never end up in a `save`. When .env.* is added, its exceptions are added after it
# again (the last match wins in .gitignore). A .gitignore that is a symlink or not a file is left alone,
# with a warning.
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

# .worktreeinclude (lists .claude/settings.local.json, so native worktrees get it): added when missing.
WTI="$FROM/.worktreeinclude"; WTI_ADD=0
{ [ -e "$WTI" ] || [ -L "$WTI" ]; } || { [ -r "$TPL/code/worktreeinclude" ] && WTI_ADD=1; }

# Tracked CLAUDE.md / AGENTS.md / CLAUDE.local.md files that stay in the repo (nested ones, or public
# ones): corecrew's ignore lines, git hook and guard block changing or adding them after adopt.
NEST=""; NNEST=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf '%s' "$COPY$RULES" | grep -qxF -- "$f" && continue   # moved to the Core: not a warning
  NEST="$NEST$f
"; NNEST=$((NNEST + 1))
done <<< "$(git -C "$FROM" -c core.quotepath=false ls-files | grep -E '(^|/)(CLAUDE(\.local)?|AGENTS)\.md$')"
NEST_WARN="warning: git tracks $NNEST CLAUDE.md / AGENTS.md file(s) that stay in the repo; after adopt, corecrew's hooks block changing or adding such files:"

# Old layout: a CLAUDE.md that still names paths relative to <Core>/<name>/code.
STALE=0
if [ "$OLD" -eq 1 ] && { grep -qF -- '../docs/' "$P/CLAUDE.md" || grep -qF -- '`code/`' "$P/CLAUDE.md"; }; then STALE=1; fi
STALE_WARN="warning: $P/CLAUDE.md still names ../docs/ or \`code/\` paths from the old layout; they now point to the wrong place: write them as $P/docs/... and the code folder $K"

# Symlinks and submodules (gitlinks) cannot be moved faithfully: refuse if a file that would be
# copied or folded is one.
if [ "$OLD" -eq 0 ]; then
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
fi

# Old layout: the move must be a rename, so the repo and <Projects> must share a file system.
if [ "$OLD" -eq 1 ]; then
  mount_of() { df -P "$1" 2>/dev/null | sed -n '2s/^[^ ]* *[0-9]* *[0-9]* *[0-9]* *[0-9]*% *//p'; }
  M_FROM="$(mount_of "$FROM")"; M_PROJ="$(mount_of "$PROJECTS_DIR")"
  # An empty answer (df failed or printed something unparseable) is a refusal: fail closed.
  { [ -n "$M_FROM" ] && [ -n "$M_PROJ" ]; } \
    || refuse "different disk: could not compare the disks of $CORE_DIR and $PROJECTS_DIR"
  [ "$M_FROM" = "$M_PROJ" ] || refuse "different disk: $CORE_DIR and $PROJECTS_DIR are on different disks; put the Core on the same disk as $PROJECTS_DIR first"
fi

# Git needs an identity for the commits: refuse now rather than half way.
ident_ok() { git -C "$1" var GIT_AUTHOR_IDENT >/dev/null 2>&1 && git -C "$1" var GIT_COMMITTER_IDENT >/dev/null 2>&1; }
if [ "${#REMOVE[@]}" -gt 0 ] || [ -n "$GI_ADD" ] || [ "$WTI_ADD" -eq 1 ]; then
  ident_ok "$FROM" || refuse "git does not know your name and email (git config --global user.name / user.email)"
fi
ident_ok "$CORE_DIR" || refuse "git does not know your name and email (git config --global user.name / user.email)"

# settings.local.json in the code folder: created when missing; else it should name <Core>/<name>.
SL_REL=".claude/settings.local.json"; SL_STATE=create
if [ -e "$FROM/$SL_REL" ] || [ -L "$FROM/$SL_REL" ]; then
  if [ -f "$FROM/$SL_REL" ] && grep -qF -- "\"$P\"" "$FROM/$SL_REL"; then SL_STATE=ok; else SL_STATE=warn; fi
fi
SL_WARN="warning: $K/$SL_REL exists and was left as is; add \"$P\" to permissions.additionalDirectories in it"

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
  if [ "$OLD" -eq 1 ]; then
    echo "Plan: adopt the old-layout project '$NAME' (its internal files are in $P/ already)"
    echo "move: $FROM -> $K"
  else
    echo "Plan: adopt $FROM as '$NAME' (the folder stays where it is)"
    show "copy to $P/:" "$COPY"
  fi
  show "fold into $P/CLAUDE.md under ## Rules:" "$RULES"
  show "kept in Core, no longer loaded:" "$KEPT"
  if [ "${#REMOVE[@]}" -gt 0 ]; then
    echo "remove from the repo in one commit \"Move internal Claude files to Core\": ${#REMOVE[@]} file(s) (the copied and folded ones that git tracks)"
  elif [ -n "$GI_ADD" ] || [ "$WTI_ADD" -eq 1 ]; then
    echo "one repo commit \"Move internal Claude files to Core\" with only the lines below (git tracks none of the internal files)"
  else
    echo "no repo commit: git tracks none of the internal files"
  fi
  show "add to .gitignore (in the same commit):" "$GI_ADD"
  [ "$WTI_ADD" -eq 0 ] || echo "add .worktreeinclude (in the same commit; it lists .claude/settings.local.json for new worktrees)"
  [ "$GI_SKIP" -eq 0 ] || echo "warning: .gitignore is not a plain file; add the corecrew ignore lines to it yourself"
  [ "$NNEST" -eq 0 ] || show "$NEST_WARN" "$NEST"
  [ "$STALE" -eq 0 ] || echo "$STALE_WARN"
  if [ "$OLD" -eq 0 ]; then
    show "stays in the repo (public docs):" "$PUBKEEP"
    IGN="$(cd "$FROM" && for t in CLAUDE.md AGENTS.md docs .claude; do
      { [ -e "$t" ] || [ -L "$t" ]; } && find "$t" -path .claude/worktrees -prune -o \( -type f -o -type l \) -print
    done | LC_ALL=C sort | LC_ALL=C comm -23 - <(printf '%s\n' "$TRACKED" | LC_ALL=C sort))"
    show "stays in the repo (ignored by git):" "$IGN"
    [ "$NSTAY" -eq 0 ] || echo "stays in the repo (local settings and worktrees): $NSTAY tracked file(s)"
    CRE=""
    while IFS='|' read -r a b; do
      [ "$a" != mkdir ] || { [ -d "$FROM/$b" ] || CRE="$CRE$b/
"; continue; }
      printf '%s\n' "$COPY" | grep -qxF -- "$b" || CRE="$CRE$b
"
    done <<< "$(project_docs_manifest)"
    show "create in $P/ (missing pages from the new-project templates):" "$CRE"
    echo "add to $P/: the check: line$([ -n "$PUB_LIST" ] && echo ', the public-docs: line'), front matter fields missing on copied pages, map lines for pages the map lacks"
  fi
  echo "link: $K/CLAUDE.local.md -> $P/CLAUDE.md"
  case "$SL_STATE" in
    create) echo "create: $K/$SL_REL (permissions.additionalDirectories: $P)" ;;
    warn) echo "$SL_WARN" ;;
  esac
  echo "then: $([ "$OLD" -eq 1 ] && echo 'repair git worktrees, ')install git hook shims, set the PROJECTS.md line to \"$(basename "$K")/\", commit \"Adopt $NAME\" in the Core"
  echo "dry run: nothing was changed"
  exit 0
fi

# --- Real run. New layout: stage everything in a temp folder inside the Core (same disk), so a failure
# before the repo commit leaves nothing but a folder we remove ourselves. After the repo commit the
# staged copy holds the only copy of the internal files: from then on nothing is ever deleted
# (the trap only removes the temp folder while it is empty).
COMMITTED=0
TMP="$(mktemp -d "$CORE_DIR/.adopt.XXXXXX")" || { echo "adopt: cannot create a temp folder in $CORE_DIR" >&2; exit 1; }
cleanup() { if [ "$COMMITTED" -eq 0 ]; then rm -rf "$TMP"; else rm -f "$TMP/rules.md"; rmdir "$TMP" 2>/dev/null; fi; }
trap cleanup EXIT
STAGE="$TMP/p"
DATE="$(date +%Y-%m-%d)"
CREATED=""

# set_line <file> <key> <value> — replace the first "key:" line, else append "key: value".
set_line() {
  local tmp="$1.tmp.$$"
  KEY="$2" VAL="$3" awk 'BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"]; done = 0 }
    !done && (index($0, k ":") == 1) { print k ": " v; done = 1; next }
    { print }
    END { if (!done) print k ": " v }' "$1" > "$tmp" && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

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

# rule_block <rule file> <label> — the rule as a CLAUDE.md subsection: "### <label>", then
# "Applies to: <paths, comma-separated>" when its front matter has paths: (a list, an inline [..] list
# or one value), then the body without the front matter, its headings three levels down (at most ######).
rule_block() {
  local fm=0
  if [ "$(head -1 "$1" | tr -d '\r')" = "---" ] && sed -n '2,$p' "$1" | grep -q '^---[[:space:]]*$'; then fm=1; fi
  awk -v L="$2" -v FM="$fm" -v SQ="'" '
    function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    function unq(s,   a) { s = trim(s); a = substr(s, 1, 1)
      if (length(s) >= 2 && (a == "\"" || a == SQ) && substr(s, length(s), 1) == a) s = substr(s, 2, length(s) - 2)
      return s }
    function add(s) { s = unq(s); if (s != "") PS = (PS == "" ? s : PS ", " s) }
    function inline(s,   i, c, q, d, cur) {
      s = trim(s); sub(/^\[/, "", s); sub(/\][ \t]*$/, "", s); q = ""; d = 0; cur = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; cur = cur c; continue }
        if (c == "\"" || c == SQ) { q = c; cur = cur c; continue }
        if (c == "{") d++
        if (c == "}") d--
        if (c == "," && d <= 0) { add(cur); cur = ""; continue }
        cur = cur c
      }
      add(cur)
    }
    { sub(/\r$/, "") }
    FM && NR == 1 { infm = 1; next }
    infm && /^---[ \t]*$/ { infm = 0; next }
    infm {
      if (inlist) { if ($0 ~ /^[ \t]*-/) { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); add(v); next } else inlist = 0 }
      if ($0 ~ /^paths[ \t]*:/) { v = $0; sub(/^paths[ \t]*:/, "", v); v = trim(v)
        if (v == "") inlist = 1; else if (v ~ /^\[/) inline(v); else add(v) }
      next
    }
    {
      if (!started && $0 ~ /^[ \t]*$/) next
      started = 1
      if ($0 ~ /^(```|~~~)/) fence = !fence
      if (!fence && match($0, /^#+ /)) {
        n = RLENGTH - 1
        if (n <= 6) { m = n + 3; if (m > 6) m = 6; h = ""; for (i = 0; i < m; i++) h = h "#"; $0 = h substr($0, RLENGTH) }
      }
      B[++nb] = $0
    }
    END {
      while (nb > 0 && B[nb] ~ /^[ \t]*$/) nb--
      print ""; print "### " L; print ""
      if (PS != "") { print "Applies to: " PS; print "" }
      for (i = 1; i <= nb; i++) print B[i]
    }' "$1"
}
# fold_rules <CLAUDE.md> <block file> — put the block at the end of the "## Rules" section (before the
# next "## " heading outside a code fence), or at the end under a new "## Rules" heading.
fold_rules() {
  local tmp="$1.rules.$$"
  # Blank lines are held back (nb) so the block, which starts with one, joins without a double gap.
  awk -v BF="$2" '
    function emit(   l) { while ((getline l < BF) > 0) print l; close(BF); done = 1 }
    function flush() { while (nb > 0) { print ""; nb-- } }
    {
      line = $0; sub(/\r$/, "", line)
      if (line ~ /^[ \t]*$/ && !fence) { nb++; next }
      if (!done && inr && !fence && line ~ /^## /) { nb = 0; emit(); print ""; inr = 0 }
      flush()
      if (line ~ /^(```|~~~)/) fence = !fence
      if (!done && !fence && line ~ /^## Rules[ \t]*$/) inr = 1
      print
    }
    END { if (!done) { nb = 0; if (!inr) { print ""; print "## Rules" }; emit() } else flush() }' "$1" > "$tmp" \
    && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

if [ "$OLD" -eq 0 ]; then
  mkdir "$STAGE" || exit 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$STAGE/$(dirname "$f")" && cp -pP "$FROM/$f" "$STAGE/$f" \
      || { echo "adopt: could not copy $f" >&2; exit 1; }
  done <<< "$COPY"

  # Missing wiki pages and the map (from the new-project templates); CLAUDE.md if there was none.
  CR="$(put_project_docs "$TPL" "$STAGE")" || exit 1
  CREATED="$(printf '%s\n' "$CR" | sed -n 's|^created \.adopt\.[^/]*/p/||p')"
  if [ -n "$CHECK" ]; then set_line "$STAGE/CLAUDE.md" check "$CHECK" || exit 1
  elif ! grep -q '^check:' "$STAGE/CLAUDE.md"; then set_line "$STAGE/CLAUDE.md" check "<set after scaffolding>" || exit 1
  fi
  [ -z "$PUB_LIST" ] || set_line "$STAGE/CLAUDE.md" public-docs "$PUBLIC" || exit 1

  # Tracked rule files become subsections of the Rules section (rule files in the Core would not load).
  if [ -n "$RULES" ]; then
    : > "$TMP/rules.md" || exit 1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      lab="${f#.claude/rules/}"; lab="${lab%.md}"
      rule_block "$FROM/$f" "$lab" >> "$TMP/rules.md" || { echo "adopt: could not read $f" >&2; exit 1; }
    done <<< "$RULES"
    fold_rules "$STAGE/CLAUDE.md" "$TMP/rules.md" || { echo "adopt: could not fold the rules into CLAUDE.md" >&2; exit 1; }
    rm -f "$TMP/rules.md"
  fi

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
elif [ -n "$RULES" ]; then
  # Old layout: the rule blocks are read now (nothing changed yet); they are folded after the move.
  : > "$TMP/rules.md" || exit 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    lab="${f#.claude/rules/}"; lab="${lab%.md}"
    rule_block "$P/$f" "$lab" >> "$TMP/rules.md" || { echo "adopt: could not read $P/$f" >&2; exit 1; }
  done <<< "$RULES"
fi

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
if [ "$WTI_ADD" -eq 1 ]; then
  cp "$TPL/code/worktreeinclude" "$WTI" || { rm -f "$WTI"
    if [ -n "$GI_ADD" ]; then if [ "$GI_NEW" -eq 1 ]; then rm -f "$GI"; else cp -p "$TMP/gitignore.orig" "$GI"; fi; fi
    echo "adopt: could not write $WTI" >&2; exit 1; }
fi
if [ "${#REMOVE[@]}" -gt 0 ] || [ -n "$GI_ADD" ] || [ "$WTI_ADD" -eq 1 ]; then
  if ! { { [ "${#REMOVE[@]}" -eq 0 ] || git -C "$FROM" rm -q -- "${REMOVE[@]}"; } \
         && { [ -z "$GI_ADD" ] || git -C "$FROM" add -- .gitignore; } \
         && { [ "$WTI_ADD" -eq 0 ] || git -C "$FROM" add -f -- .worktreeinclude; } \
         && git -C "$FROM" commit -q -m "Move internal Claude files to Core"; } >/dev/null 2>&1; then
    if [ "${#REMOVE[@]}" -gt 0 ]; then
      git -C "$FROM" reset -q -- "${REMOVE[@]}" >/dev/null 2>&1
      git -C "$FROM" checkout -q -- "${REMOVE[@]}" >/dev/null 2>&1
    fi
    if [ -n "$GI_ADD" ]; then
      git -C "$FROM" reset -q -- .gitignore >/dev/null 2>&1
      if [ "$GI_NEW" -eq 1 ]; then rm -f "$GI"; else cp -p "$TMP/gitignore.orig" "$GI"; fi
    fi
    if [ "$WTI_ADD" -eq 1 ]; then git -C "$FROM" reset -q -- .worktreeinclude >/dev/null 2>&1; rm -f "$WTI"; fi
    refuse "could not commit in $FROM (nothing was changed)"
  fi
  COMMITTED=1
  rm -f "$TMP/gitignore.orig"
fi
UNDO="(to undo it: git -C \"$FROM\" revert HEAD)"
if [ "$OLD" -eq 0 ]; then
  # The staged copy becomes <Core>/<name>/ (a rename in the Core). If it fails nothing is deleted;
  # the output says where everything is.
  if ! mv "$STAGE" "$P"; then
    echo "adopt: could not create $P. Your project is still at $FROM." >&2
    [ "$COMMITTED" -eq 0 ] || echo "adopt: the internal files are in $STAGE and the repo has the commit 'Move internal Claude files to Core' $UNDO." >&2
    exit 1
  fi
else
  # The move (a rename: same file system, checked above). If it fails nothing is deleted or moved back.
  if { [ -e "$K" ] || [ -L "$K" ]; } || ! mv "$FROM" "$K"; then
    echo "adopt: could not move $FROM to $K. Nothing was deleted; your project is still at $FROM." >&2
    [ "$COMMITTED" -eq 0 ] || echo "adopt: the repo has the commit 'Move internal Claude files to Core' $UNDO." >&2
    exit 1
  fi
fi

# From here the project is in place; problems are reported, not undone.
if [ "$OLD" -eq 0 ]; then
  echo "copied ${NCOPY} file(s) to $P/"
  [ "$NRULES" -eq 0 ] || echo "folded ${NRULES} rule file(s) into $P/CLAUDE.md (## Rules)"
elif [ "$NRULES" -gt 0 ]; then
  # Old layout: the rule files stay in <Core>/<name>/.claude/rules/; their text joins CLAUDE.md, which
  # goes into the "Adopt <name>" commit below.
  if fold_rules "$P/CLAUDE.md" "$TMP/rules.md"; then
    echo "folded ${NRULES} rule file(s) into $P/CLAUDE.md (## Rules)"
  else
    echo "warning: could not fold the rule files into $P/CLAUDE.md; they are in $P/.claude/rules/ and no longer load" >&2
  fi
  rm -f "$TMP/rules.md"
fi
show "kept in Core, no longer loaded:" "$KEPT"
if [ "$COMMITTED" -eq 1 ]; then
  [ "${#REMOVE[@]}" -eq 0 ] || echo "removed ${#REMOVE[@]} file(s) from the repo (commit: Move internal Claude files to Core)"
  [ -z "$GI_ADD" ] || echo "added $GI_N ignore line(s) to .gitignore (commit: Move internal Claude files to Core)"
  [ "$WTI_ADD" -eq 0 ] || echo "added .worktreeinclude (commit: Move internal Claude files to Core)"
else echo "no repo commit: git tracks none of the internal files"; fi
[ -z "$CREATED" ] || { echo "created:"; printf '%s\n' "$CREATED" | sed 's/^/  /'; }
if [ "$OLD" -eq 0 ]; then
  echo "folder unchanged: $K"
else
  echo "old: $FROM"
  echo "new: $K"
  # Linked worktrees under .claude/worktrees moved with the repo: point them and the repo at each other.
  WT=()
  for w in "$K/.claude/worktrees"/*; do
    [ -f "$w/.git" ] && WT[${#WT[@]}]="$w"
  done
  if [ -d "$K/.git/worktrees" ]; then
    if [ "${#WT[@]}" -gt 0 ]; then git -C "$K" worktree repair "${WT[@]}" >/dev/null 2>&1
    else git -C "$K" worktree repair >/dev/null 2>&1; fi \
      || echo "warning: could not repair git worktrees after the move; run: git -C \"$K\" worktree repair <worktree folder>" >&2
  fi
fi
[ "$NNEST" -eq 0 ] || show "$NEST_WARN" "$NEST" >&2
[ "$STALE" -eq 0 ] || echo "$STALE_WARN" >&2
link_local_claude "$K" "$P" || echo "warning: $K/CLAUDE.local.md was not linked; make it a link to $P/CLAUDE.md" >&2
case "$SL_STATE" in
  create) put "$TPL/code/settings.local.json.tmpl" "$K/$SL_REL" \
            || echo "warning: could not create $K/$SL_REL; add \"$P\" to permissions.additionalDirectories in it" >&2 ;;
  ok) echo "skipped $(rel_core "$K/$SL_REL")" ;;
  warn) echo "$SL_WARN" >&2 ;;
esac
if ! CORE_DIR="$CORE_DIR" bash "$ROOT_DIR/scripts/install-hooks.sh" "$P"; then
  echo "warning: git hooks were not installed; run: CORE_DIR=\"$CORE_DIR\" bash \"$ROOT_DIR/scripts/install-hooks.sh\" \"$P\"" >&2
fi
# The PROJECTS.md line: an existing one (the old layout's "<name>/code/") gets the new entry (and the
# --purpose text when given), else one is added.
ENTRY="$(basename "$K")/"
if [ -f "$CORE_DIR/PROJECTS.md" ] && grep -q "^- $NAME " "$CORE_DIR/PROJECTS.md"; then
  PT="$CORE_DIR/PROJECTS.md.adopt.$$"
  if N="$NAME" E="$ENTRY" PU="$PURPOSE" PS="$PURPOSE_SET" LC_ALL=C awk 'BEGIN { pre = "- " ENVIRON["N"] " "; sep = " — " }
      !done && index($0, pre) == 1 {
        s = $0; last = 0; off = 0
        while ((i = index(s, sep)) > 0) { last = off + i; off += i; s = substr(s, i + 1) }
        if (ENVIRON["PS"] == "1") $0 = "- " ENVIRON["N"] sep ENVIRON["PU"] sep ENVIRON["E"]
        else $0 = (last > 0 ? substr($0, 1, last - 1) : $0) sep ENVIRON["E"]
        done = 1 }
      { print }' "$CORE_DIR/PROJECTS.md" > "$PT" && mv "$PT" "$CORE_DIR/PROJECTS.md"; then
    echo "updated PROJECTS.md entry"
  else rm -f "$PT"; echo "warning: could not write PROJECTS.md" >&2; fi
else
  projects_entry "$NAME" "$PURPOSE" "$ENTRY" >/dev/null || echo "warning: could not write PROJECTS.md" >&2
fi
if git -C "$CORE_DIR" add -- "$NAME" PROJECTS.md && git -C "$CORE_DIR" commit -q -m "Adopt $NAME" -- "$NAME" PROJECTS.md >/dev/null 2>&1; then
  echo "Core commit: Adopt $NAME"
else
  echo "warning: the Core commit failed; commit $NAME/ and PROJECTS.md in $CORE_DIR yourself" >&2
fi
WOUT="$(bash "$ROOT_DIR/scripts/wiki-check.sh" "$P" 2>&1)"
if [ -n "$WOUT" ]; then echo "the wiki has problems to fix:"; printf '%s\n' "$WOUT"; else echo "wiki: green"; fi
echo "restart Claude Code in $K so CLAUDE.local.md loads"
echo "open: $K"
exit 0
