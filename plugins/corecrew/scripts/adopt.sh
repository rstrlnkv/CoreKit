#!/usr/bin/env bash
# Brings an existing project (a git repo folder) into the corecrew layout:
# internal files go to <Core>/<name>/, the repo stays where it is, in
# <Projects>/<Name> (<Projects> = the Core's parent folder, <name> = <Name> in lower case). Only a project
# still in the old layout (a repo at <Core>/<name>/code) is moved, to <Projects>/<name>.
# Usage: bash adopt.sh --from <folder> [--name <name>] [--public-docs "<paths>"]
#                      [--check "<command>"] [--purpose "<text>"] [--dry-run]
# Env:   CORE_DIR overrides the plugin option core_dir (see lib.sh).
#
# Refusals (exit 2, one line on stderr, nothing changed; all checked before any change, in this order):
#   not a git repo | uncommitted changes | no Core (empty Core path) | already inside Core | Core is inside the folder
#   not in <Projects>: move the folder to <Projects>/<Name> first   (not a direct child of <Projects>,
#       and not an old-layout <Core>/<name>/code)
#   old layout: only --purpose and --dry-run apply                  (--name, --public-docs, --check)
#   invalid project name '<n>' (rename the folder)                (old layout: without the hint)
#   name '<n>' does not match the folder '<Name>': rename the folder to <Projects>/<n> first
#       (--name must be the folder name in lower case: the link to the Core is by name only)
#   target exists: <path>        <Core>/<name> (new layout) or a <Projects> folder named <name> in any
#                                letter case (old layout)
#   two folders differ only in case: <A>, <B>
#   leftover staged copy of <name>: <Core>/.adopt.<name>.XXXXXX (...)   (new layout: an earlier adopt stopped after
#       staging; the line says how to recover: revert the repo commit, named by its hash, unless there is none or
#       it is reverted already; remove the folder; rerun)
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
# Exit 1 (nothing deleted; the message says where the files are): a failed mv after the repo commit. The staged
# copy stays in <Core>/.adopt.<name>.XXXXXX; a rerun refuses (leftover staged copy) until it is recovered.
# Exit 1 (nothing changed; the stderr lines say why): a step before the repo commit fails (the temp folder,
# a copy, a rule file, the fold, wiki-migrate on the staged copy, .gitignore, .worktreeinclude).
# Steps (new layout): copy CLAUDE.md, AGENTS.md, docs/ and .claude/ (not settings.local.json, not
# worktrees/, not --public-docs paths) into a temp folder in the Core; add the pages the new-project
# templates have that are missing, the check: line and public-docs: line; fold each tracked
# .claude/rules/<f>.md into CLAUDE.md as "### <f>" under "## Rules" (the heading is added at the end when
# missing; "Applies to: <paths>" from its paths: front matter, the front matter itself dropped, its
# headings moved three levels down); other tracked .claude/ files are kept in <Core>/<name>/.claude/,
# where they no longer load (the plan and the report list them); convert the copied wiki with
# wiki-migrate.sh (typed front matter, wikilinks, docs/superpowers/{specs,plans} moved, the Obsidian
# files, INDEX.md generated; updated dates from the repo; its warning: lines are printed). Then one
# commit in the repo "Move internal Claude files to Core" (git rm of
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
# Then wiki-migrate.sh converts <Core>/<name>/docs in place (its failure is a warning: line; the
# change goes into the "Adopt <name>" commit).
# Warnings (plan and report): tracked CLAUDE.md / AGENTS.md / CLAUDE.local.md files that stay in the repo
# (nested ones, public ones), which corecrew's hooks block changing or adding after adopt.
# Both: CLAUDE.local.md and AGENTS.md in the code folder become links to <Core>/<name>/CLAUDE.md
# (AGENTS.md is not linked while <Core>/<name>/AGENTS.md exists: a warning: line asks to fold it);
# .claude/settings.local.json is created from the template when missing (else left as is, with a
# warning: line naming the additionalDirectories entry to add when it lacks it); git hook shims are
# installed; PROJECTS.md gets (or has updated) its line "- <name> — <purpose> — <Name>/"; the Core gets
# one commit "Adopt <name>".
# --dry-run prints the plan and changes nothing. The last line is "open: <code folder>".
#
# The run is a sequence of phases, each a function below, called in order by the main at the end of
# the file: preconditions (the refusals; read-only), plan (what goes where; read-only), print_plan
# (--dry-run), stage (the copies, in a temp folder in the Core), commit_repo, move_into_place,
# finish (links, hooks, PROJECTS.md, the Core commit, the report). The rule readers are
# scripts/rule-block.awk and scripts/fold-rules.awk.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT_DIR/templates"
. "$ROOT_DIR/scripts/lib.sh"
export GIT_LITERAL_PATHSPECS=1   # file names are never patterns

usage() {
  echo 'usage: adopt.sh --from <folder> [--name <n>] [--public-docs "<paths>"] [--check "<command>"] [--purpose "<text>"] [--dry-run]' >&2
  exit 2
}
refuse() { printf '%s\n' "$1" >&2; exit 2; }
# The lines printed in more than one place.
IDENT_MSG="git does not know your name and email (git config --global user.name / user.email)"
GI_SKIP_MSG="warning: .gitignore is not a plain file; add the corecrew ignore lines to it yourself"
NO_COMMIT_MSG="no repo commit: git tracks none of the internal files"

# parse_args <args...> — the options into FROM, NAME, PUBLIC, CHECK, PURPOSE, PURPOSE_SET and DRY.
parse_args() {
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
}

# --- Helpers of the phases.
# public_path <file> — exit 0 when the repo-relative file is under a --public-docs path ($PUB_LIST).
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
# gi_has <line> — the repo's .gitignore ($GI) has the line.
gi_has() { [ -f "$GI" ] && tr -d '\r' < "$GI" | grep -qxF -- "$1"; }
# mount_of <path> — the mount point of the file system the path is on ("" when df gives no answer).
mount_of() { df -P "$1" 2>/dev/null | sed -n '2s/^[^ ]* *[0-9]* *[0-9]* *[0-9]* *[0-9]*% *//p'; }
# ident_ok <repo> — git knows a name and email for commits there.
ident_ok() { git -C "$1" var GIT_AUTHOR_IDENT >/dev/null 2>&1 && git -C "$1" var GIT_COMMITTER_IDENT >/dev/null 2>&1; }
# show <heading> <newline-separated list> — the heading and at most 15 entries, then a count.
show() {
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
# set_line <file> <key> <value> — replace the first "key:" line, else append "key: value".
set_line() {
  local tmp="$1.tmp.$$"
  KEY="$2" VAL="$3" awk 'BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"]; done = 0 }
    !done && (index($0, k ":") == 1) { print k ": " v; done = 1; next }
    { print }
    END { if (!done) print k ": " v }' "$1" > "$tmp" && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}
# rule_block <rule file> <label> — the rule as a CLAUDE.md subsection: "### <label>", then
# "Applies to: <paths, comma-separated>" when its front matter has paths: (a list, an inline [..] list
# or one value), then the body without the front matter, its headings three levels down (at most ######).
rule_block() {
  local fm=0
  if [ "$(head -1 "$1" | tr -d '\r')" = "---" ] && sed -n '2,$p' "$1" | grep -q '^---[[:space:]]*$'; then fm=1; fi
  awk -v L="$2" -v FM="$fm" -f "$ROOT_DIR/scripts/rule-block.awk" "$1"
}
# fold_rules <CLAUDE.md> <block file> — put the block at the end of the "## Rules" section (before the
# next "## " heading outside a code fence), or at the end under a new "## Rules" heading.
fold_rules() {
  local tmp="$1.rules.$$"
  awk -v BF="$2" -f "$ROOT_DIR/scripts/fold-rules.awk" "$1" > "$tmp" \
    && mv "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}
# cleanup — the trap of stage: the temp folder goes while nothing was committed; after the repo commit
# only its leftovers go (the staged copy is the only copy of the internal files).
cleanup() { if [ "$COMMITTED" -eq 0 ]; then rm -rf "$TMP"; else rm -f "$TMP/rules.md"; rmdir "$TMP" 2>/dev/null; fi; }
# read_rules <base dir> <shown prefix> — the rule blocks of $RULES (paths relative to <base dir>) into
# $TMP/rules.md, in list order; an unreadable file is "adopt: could not read <shown prefix><file>", exit 1.
read_rules() {
  local f lab
  : > "$TMP/rules.md" || exit 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    lab="${f#.claude/rules/}"; lab="${lab%.md}"
    rule_block "$1/$f" "$lab" >> "$TMP/rules.md" || { echo "adopt: could not read $2$f" >&2; exit 1; }
  done <<< "$RULES"
}

# --- Phase: preconditions. Read-only; the refusals, in the order the header lists them. Sets FROM
# (canonical), OLD, OLDNAME, NAME, BASE, P (the Core project folder), K (the code folder) and LOC.
preconditions() {
  { [ -d "$FROM" ] && [ -d "$FROM/.git" ]; } || refuse "not a git repo"
  FROM="$(canon_dir "$FROM")"   # symlinks resolved, letter case as on disk (not as typed)
  git -C "$FROM" rev-parse --verify -q HEAD >/dev/null 2>&1 || refuse "not a git repo"
  [ -z "$(git -C "$FROM" status --porcelain 2>&1)" ] || refuse "uncommitted changes"
  # The old layout: exactly <Core>/<name>/code of a project folder in the Core. Anything else in the Core
  # is refused.
  [ -n "$CORE_DIR" ] || refuse "adopt: no Core: set core_dir, CORE_DIR or HOME first"
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
    [ -n "$NAME" ] || NAME="$(lc "$BASE")"
    valid_project_name "$NAME" || refuse "invalid project name '$NAME' (rename the folder)"
    [ "$(lc "$BASE")" = "$NAME" ] || refuse "name '$NAME' does not match the folder '$BASE': rename the folder to $PROJECTS_DIR/$NAME first"
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
    # A staged copy left by an earlier adopt of this project (its move into the Core failed, or the run was
    # killed): another run would stage the template pages over the user's lost ones. Names carry no glob
    # characters (valid_project_name), and .adopt.<name>.* never matches another project's folder. The recovery
    # names the repo commit by its hash (the user may have committed since); a revert of it ("This reverts
    # commit <hash>") means only the leftover is left to remove.
    for d in "$CORE_DIR/.adopt.$NAME".*/p; do
      [ -d "$d" ] || continue
      d="${d%/p}"
      mc="$(git -C "$FROM" log -1 --format=%H --grep='^Move internal Claude files to Core$' 2>/dev/null)"
      if [ -z "$mc" ]; then
        refuse "leftover staged copy of $NAME: $d (an earlier adopt stopped before its repo commit); remove $d and run adopt again"
      elif [ -n "$(git -C "$FROM" log -1 --format=%H -F --grep="This reverts commit $mc" 2>/dev/null)" ]; then
        refuse "leftover staged copy of $NAME: $d (an earlier adopt stopped; its repo commit is undone); remove $d and run adopt again"
      fi
      refuse "leftover staged copy of $NAME: $d (an earlier adopt stopped); undo its repo commit with git -C \"$FROM\" revert --no-edit $mc, then remove $d and run adopt again"
    done
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
}

# --- Phase: plan. Read-only: what goes where, and the last refusals that need that list. Sets PUB_LIST,
# TRACKED, COPY, PUBKEEP, RULES, KEPT, REMOVE, the counts, the .gitignore and .worktreeinclude additions
# (GI, GI_ADD, GI_SKIP, GI_N, WTI, WTI_ADD), the warnings (NEST, NNEST, NEST_WARN, STALE, STALE_WARN,
# SL_STATE, SL_WARN).
plan() {
  PUB_LIST=""
  set -f
  for t in $(printf '%s' "$PUBLIC" | tr ',' ' '); do
    t="${t#./}"; while [ "${t%/}" != "$t" ]; do t="${t%/}"; done
    [ -z "$t" ] || PUB_LIST="$PUB_LIST$t
"
  done
  set +f

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
  COPY=""; PUBKEEP=""; RULES=""; KEPT=""; NCOPY=0; NSTAY=0; NRULES=0
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
" ;;
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
    M_FROM="$(mount_of "$FROM")"; M_PROJ="$(mount_of "$PROJECTS_DIR")"
    # An empty answer (df failed or printed something unparseable) is a refusal: fail closed.
    { [ -n "$M_FROM" ] && [ -n "$M_PROJ" ]; } \
      || refuse "different disk: could not compare the disks of $CORE_DIR and $PROJECTS_DIR"
    [ "$M_FROM" = "$M_PROJ" ] || refuse "different disk: $CORE_DIR and $PROJECTS_DIR are on different disks; put the Core on the same disk as $PROJECTS_DIR first"
  fi

  # Git needs an identity for the commits: refuse now rather than half way.
  if [ "${#REMOVE[@]}" -gt 0 ] || [ -n "$GI_ADD" ] || [ "$WTI_ADD" -eq 1 ]; then
    ident_ok "$FROM" || refuse "$IDENT_MSG"
  fi
  ident_ok "$CORE_DIR" || refuse "$IDENT_MSG"

  # settings.local.json in the code folder: created when missing; else it should name <Core>/<name>.
  SL_REL=".claude/settings.local.json"; SL_STATE=create
  if [ -e "$FROM/$SL_REL" ] || [ -L "$FROM/$SL_REL" ]; then
    if [ -f "$FROM/$SL_REL" ] && grep -qF -- "\"$P\"" "$FROM/$SL_REL"; then SL_STATE=ok; else SL_STATE=warn; fi
  fi
  SL_WARN="warning: $K/$SL_REL exists and was left as is; add \"$P\" to permissions.additionalDirectories in it"
}

# --- Phase: print_plan (--dry-run). The plan on stdout; nothing is changed.
print_plan() {
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
    echo "$NO_COMMIT_MSG"
  fi
  show "add to .gitignore (in the same commit):" "$GI_ADD"
  [ "$WTI_ADD" -eq 0 ] || echo "add .worktreeinclude (in the same commit; it lists .claude/settings.local.json for new worktrees)"
  [ "$GI_SKIP" -eq 0 ] || echo "$GI_SKIP_MSG"
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
    echo "add to $P/: the check: line$([ -n "$PUB_LIST" ] && echo ', the public-docs: line'), then the wiki converted by wiki-migrate.sh (front matter, wikilinks, Obsidian files, generated INDEX.md)"
  fi
  echo "link: $K/CLAUDE.local.md -> $P/CLAUDE.md"
  case "$SL_STATE" in
    create) echo "create: $K/$SL_REL (permissions.additionalDirectories: $P)" ;;
    warn) echo "$SL_WARN" ;;
  esac
  echo "then: $([ "$OLD" -eq 1 ] && echo 'repair git worktrees, convert the wiki with wiki-migrate.sh, ')install git hook shims, set the PROJECTS.md line to \"$(basename "$K")/\", commit \"Adopt $NAME\" in the Core"
  echo "dry run: nothing was changed"
}

# --- Phase: stage. New layout: everything is staged in a temp folder inside the Core (same disk), so a
# failure before the repo commit leaves nothing but a folder we remove ourselves. After the repo commit
# the staged copy holds the only copy of the internal files: from then on nothing is ever deleted
# (the trap only removes the temp folder while it is empty). Old layout: only the rule blocks are read.
# Sets TMP, STAGE, COMMITTED, CREATED, MIG.
stage() {
  COMMITTED=0
  TMP="$(mktemp -d "$CORE_DIR/.adopt.$NAME.XXXXXX")" || { echo "adopt: cannot create a temp folder in $CORE_DIR" >&2; exit 1; }
  trap cleanup EXIT
  STAGE="$TMP/p"
  # shellcheck disable=SC2034  # render() in lib.sh fills the templates with it
  DATE="$(date +%Y-%m-%d)"
  CREATED=""
  MIG=""

  if [ "$OLD" -eq 0 ]; then
    mkdir "$STAGE" || exit 1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      mkdir -p "$STAGE/$(dirname "$f")" && cp -pP "$FROM/$f" "$STAGE/$f" \
        || { echo "adopt: could not copy $f" >&2; exit 1; }
    done <<< "$COPY"

    # Missing wiki pages and vault files (from the new-project templates); CLAUDE.md if there was none.
    CR="$(put_project_docs "$TPL" "$STAGE")" || exit 1
    CREATED="$(printf '%s\n' "$CR" | sed -n 's|^created \.adopt\.[^/]*/p/||p')"
    if [ -n "$CHECK" ]; then set_line "$STAGE/CLAUDE.md" check "$CHECK" || exit 1
    elif ! grep -q '^check:' "$STAGE/CLAUDE.md"; then set_line "$STAGE/CLAUDE.md" check "<set after scaffolding>" || exit 1
    fi
    [ -z "$PUB_LIST" ] || set_line "$STAGE/CLAUDE.md" public-docs "$PUBLIC" || exit 1

    # Tracked rule files become subsections of the Rules section (rule files in the Core would not load).
    if [ -n "$RULES" ]; then
      read_rules "$FROM" ""
      fold_rules "$STAGE/CLAUDE.md" "$TMP/rules.md" || { echo "adopt: could not fold the rules into CLAUDE.md" >&2; exit 1; }
      rm -f "$TMP/rules.md"
    fi

    # The wiki in the current format (front matter, wikilinks, Obsidian files, generated INDEX); dates
    # from the repo the pages came from. It runs through a link named as the project (the INDEX title is
    # the folder name). Its warnings are printed after the move.
    ln -s p "$TMP/$NAME" || exit 1
    MIG="$(WIKI_MIGRATE_DATES="$FROM" bash "$ROOT_DIR/scripts/wiki-migrate.sh" "$TMP/$NAME")" || exit 1
    rm -f "$TMP/$NAME"
  elif [ -n "$RULES" ]; then
    # Old layout: the rule blocks are read now (nothing changed yet); they are folded after the move.
    read_rules "$P" "$P/"
  fi
}

# restore_gi — .gitignore as it was before commit_repo: removed when adopt created it, else the backup copied back.
restore_gi() { if [ "$GI_NEW" -eq 1 ]; then rm -f "$GI"; else cp -p "$TMP/gitignore.orig" "$GI"; fi; }

# --- Phase: commit_repo. The repo commit. If it fails the files and .gitignore come back; nothing else
# was touched. Sets COMMITTED and GI_NEW.
commit_repo() {
  [ "$GI_SKIP" -eq 0 ] || echo "$GI_SKIP_MSG" >&2
  GI_NEW=0
  if [ -n "$GI_ADD" ]; then
    if [ -e "$GI" ]; then cp -p "$GI" "$TMP/gitignore.orig" || { echo "adopt: could not back up .gitignore" >&2; exit 1; }
    else GI_NEW=1; fi
    { { [ ! -s "$GI" ] || [ -z "$(tail -c1 "$GI")" ] || printf '\n'; }
      printf '# corecrew: internal Claude files and secrets stay out of this repo\n%s' "$GI_ADD"; } >> "$GI" \
      || { restore_gi; echo "adopt: could not write $GI" >&2; exit 1; }
  fi
  if [ "$WTI_ADD" -eq 1 ]; then
    cp "$TPL/code/worktreeinclude" "$WTI" || { rm -f "$WTI"; [ -z "$GI_ADD" ] || restore_gi
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
        restore_gi
      fi
      if [ "$WTI_ADD" -eq 1 ]; then git -C "$FROM" reset -q -- .worktreeinclude >/dev/null 2>&1; rm -f "$WTI"; fi
      refuse "could not commit in $FROM (nothing was changed)"
    fi
    COMMITTED=1
    rm -f "$TMP/gitignore.orig"
  fi
}

# --- Phase: move_into_place. New layout: the staged copy becomes <Core>/<name>/ (a rename in the Core).
# Old layout: the repo folder moves to <Projects>/<name> (a rename: same file system, checked in plan).
# If the move fails nothing is deleted; the output says where everything is.
move_into_place() {
  UNDO="(to undo it: git -C \"$FROM\" revert HEAD)"
  if [ "$OLD" -eq 0 ]; then
    if ! mv "$STAGE" "$P"; then
      echo "adopt: could not create $P. Your project is still at $FROM." >&2
      [ "$COMMITTED" -eq 0 ] || echo "adopt: the internal files are in $STAGE and the repo has the commit 'Move internal Claude files to Core' $UNDO." >&2
      exit 1
    fi
  else
    if { [ -e "$K" ] || [ -L "$K" ]; } || ! mv "$FROM" "$K"; then
      echo "adopt: could not move $FROM to $K. Nothing was deleted; your project is still at $FROM." >&2
      [ "$COMMITTED" -eq 0 ] || echo "adopt: the repo has the commit 'Move internal Claude files to Core' $UNDO." >&2
      exit 1
    fi
  fi
}

# --- Phase: finish. From here the project is in place; problems are reported, not undone: the report,
# the old layout's fold and wiki conversion, the links, settings.local.json, the git hook shims, the
# PROJECTS.md line, the Core commit, a wiki check.
finish() {
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
  # The wiki in the current format: converted in the staged copy (new layout), here after the move (old).
  if [ "$OLD" -eq 1 ]; then
    MIG="$(bash "$ROOT_DIR/scripts/wiki-migrate.sh" "$P")" \
      || echo "warning: the wiki in $P/docs was not converted; run: bash \"$ROOT_DIR/scripts/wiki-migrate.sh\" \"$P\"" >&2
  fi
  printf '%s\n' "$MIG" | grep -E '^(moved|warning:) '
  show "kept in Core, no longer loaded:" "$KEPT"
  if [ "$COMMITTED" -eq 1 ]; then
    [ "${#REMOVE[@]}" -eq 0 ] || echo "removed ${#REMOVE[@]} file(s) from the repo (commit: Move internal Claude files to Core)"
    [ -z "$GI_ADD" ] || echo "added $GI_N ignore line(s) to .gitignore (commit: Move internal Claude files to Core)"
    [ "$WTI_ADD" -eq 0 ] || echo "added .worktreeinclude (commit: Move internal Claude files to Core)"
  else echo "$NO_COMMIT_MSG"; fi
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
  link_agents "$K" "$P" || echo "warning: $K/AGENTS.md was not linked; fold $P/AGENTS.md into CLAUDE.md if it exists, then make AGENTS.md a link to $P/CLAUDE.md" >&2
  case "$SL_STATE" in
    create) put "$TPL/code/settings.local.json.tmpl" "$K/$SL_REL" \
              || echo "warning: could not create $K/$SL_REL; add \"$P\" to permissions.additionalDirectories in it" >&2 ;;
    ok) echo "skipped $(rel_core "$K/$SL_REL")" ;;
    warn) echo "$SL_WARN" >&2 ;;
  esac
  # Exit 4: core.hooksPath sends git to another hooks folder (husky, lefthook, a global setting);
  # install-hooks has already said how to chain the hooks, and a rerun would exit 4 again.
  IH_RC=0; CORE_DIR="$CORE_DIR" bash "$ROOT_DIR/scripts/install-hooks.sh" "$P" || IH_RC=$?
  case "$IH_RC" in
    0|4) ;;
    *) echo "warning: git hooks were not installed; run: CORE_DIR=\"$CORE_DIR\" bash \"$ROOT_DIR/scripts/install-hooks.sh\" \"$P\"" >&2 ;;
  esac
  # The PROJECTS.md line: an existing one (the old layout's "<name>/code/") gets the new entry (and the
  # --purpose text when given), else one is added.
  projects_upsert "$NAME" "$PURPOSE" "$(basename "$K")/" "$PURPOSE_SET" || echo "warning: could not write PROJECTS.md" >&2
  if git -C "$CORE_DIR" add -- "$NAME" PROJECTS.md && git -C "$CORE_DIR" commit -q -m "Adopt $NAME" -- "$NAME" PROJECTS.md >/dev/null 2>&1; then
    echo "Core commit: Adopt $NAME"
  else
    echo "warning: the Core commit failed; commit $NAME/ and PROJECTS.md in $CORE_DIR yourself" >&2
  fi
  WOUT="$(bash "$ROOT_DIR/scripts/wiki-check.sh" "$P" 2>&1)"
  if [ -n "$WOUT" ]; then echo "the wiki has problems to fix:"; printf '%s\n' "$WOUT"; else echo "wiki: green"; fi
  echo "start a new session in $K so CLAUDE.local.md loads"
  echo "open: $K"
}

# --- Main: the phases in order.
parse_args "$@"
load_settings
preconditions
plan
if [ "$DRY" -eq 1 ]; then print_plan; exit 0; fi
stage
commit_repo
move_into_place
finish
exit 0
