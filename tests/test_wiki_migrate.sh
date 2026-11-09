#!/usr/bin/env bash
# wiki-migrate.sh: converts a 0.6-format wiki (fixture tests/fixtures/wiki-old) to the 0.7 format
# (expected result: tests/fixtures/wiki-old.expected, byte for byte; its docs/wiki.base, docs/.obsidian/app.json
# and docs/.obsidian/.gitignore come from the new-project templates, copied below).
#
# Contract the tests pin:
#   stdout, one line per changed file, in this order, then the warnings:
#     1. pages in LC_ALL=C order of their final docs-relative path (wiki-pages.sh order), one line each:
#          "moved docs/superpowers/specs/a.md -> docs/specs/a.md"   a page moved out of superpowers/
#                                                                   (converted too; no second line)
#          "updated docs/<page>"                                    a converted page
#        a page that needs no change prints nothing and is not rewritten (not even its mtime matters
#        here: its bytes stay).
#     2. "created docs/wiki.base", "created docs/.obsidian/app.json", "created docs/.obsidian/.gitignore"
#        ("skipped <path>" when present)
#     3. the wiki-index.sh line ("updated docs/INDEX.md" / "created ..." / "skipped ...")
#     4. warnings in page order: "warning: <page name>: set type" | "description over 80 chars" |
#        "status <v>" | "anchor #<anchor> dropped" (a page's own warnings in that order)
#   Nothing on stderr when it succeeds. A failure prints one line on stderr and changes nothing.
#   Page conversion: title dropped; fields in the order type status description files related
#   updated; type from the folder; related and body Markdown links between wiki pages -> wikilinks;
#   "docs/<page>.md § Heading" at the end of a line -> [[page#Heading]]; fences and `inline code` and
#   pages under knowledge/ stay as they are. A related: path may be docs-relative or docs/-prefixed.
#   updated for a page without one = date of the last commit of its file (for a moved page: of the
#   path it came from) in the enclosing git repo, else today.
#   A "docs/x.md § H" followed by one . , ; : or ) takes the heading H when "H." is not a heading, the
#   punctuation stays after the link. A page without a final newline keeps none.
#   A mid-line reference converts by the longest heading prefix of the rest of the line ("docs/x.md § Layers
#   for the details." -> "[[x#Layers]] for the details."); no heading matches -> line unchanged and
#   "warning: <page>: reference to <x> § <rest of the line after §> not converted". The form
#   `docs/x.md` § H (path in backticks, heading outside) converts like the plain form.
#   A multi-line description (">" or empty value with indented lines) is kept line for line.
#   updated: is read from the front matter only (a body line "updated: x" does not count); an empty
#   updated: gets the commit date like a missing one. "[a|b](page.md)" never becomes [[page|a|b]].
#   The swap is signal-safe: after TERM at the swap docs/ is back with its content (or the script printed
#   where the original is); a failing second mv rolls back, exit 1.
#   Rulings (coordinator): a backtick span whose WHOLE content is one reference `docs/x.md § H` becomes
#   [[x#H]] (backticks dropped); any other span or fence content stays byte-identical.
#   A brief's stage: field moves into a last body section "## Progress" with one line "Stage: <v>" (unless
#   the body already has ## Progress, the value is multi-line, or the body ends in an open code fence: then
#   the field stays and is warned). Any other field outside the six
#   is kept after the six, in original order, with "warning: <name>: extra front matter field <k>".
#   [t](page.md#anchor): anchor = exact heading of that page -> [[page#anchor]] (when t is the name);
#   otherwise [[page|t]] ([[page]] when t is the name) and "warning: <page>: anchor #<anchor> dropped".
source "$(dirname "$0")/lib.sh"
WM="$SCRIPTS/wiki-migrate.sh"
WC="$SCRIPTS/wiki-check.sh"
WI="$SCRIPTS/wiki-index.sh"
# Work on copies of the fixtures, outside the per-section sandboxes.
FXT="$(mktemp -d "${TMPDIR:-/tmp}/wm-fixtures.XXXXXX")"; at_exit 'rm -rf "$FXT"'
copy_fixture wiki-old "$FXT/wiki-old"; copy_fixture wiki-old.expected "$FXT/wiki-old.expected"
FXO="$FXT/wiki-old"
FXE="$FXT/wiki-old.expected"
# The vault files wiki-migrate creates are the templates' own (one source, not a copy in the fixture).
mkdir -p "$FXE/docs/.obsidian"
cp "$PLUGIN/templates/docs/wiki.base" "$FXE/docs/wiki.base"
cp "$PLUGIN/templates/docs/obsidian-app.json" "$FXE/docs/.obsidian/app.json"
cp "$PLUGIN/templates/docs/obsidian-gitignore" "$FXE/docs/.obsidian/.gitignore"
# Those vault files are listed twice: in project_docs_manifest (lib-scaffold.sh, what new-project and adopt
# create) and in wiki-migrate.sh's `for pair` list. The two lists name the same files.
vault_manifest="$( (. "$SCRIPTS/lib-scaffold.sh"; project_docs_manifest) | grep -E '^docs/(wiki\.base|obsidian-)')"
vault_migrate="$(sed -n 's/^for pair in \(.*\); do$/\1/p' "$WM" | grep -oE '"[^"]*"' | tr -d '"' | sed 's#^#docs/#; s#|#|docs/#')"
[ -n "$vault_migrate" ] && pass || fail "no 'for pair in' list in wiki-migrate.sh"
assert_eq "$vault_migrate" "$vault_manifest" "wiki-migrate's vault files match project_docs_manifest"

WANT_OUT="updated docs/architecture.md
updated docs/brief.md
updated docs/decisions/001-stack.md
updated docs/features/login.md
updated docs/features/refs.md
updated docs/features/sign in.md
updated docs/glossary.md
updated docs/notes/n.md
moved docs/superpowers/plans/b.md -> docs/plans/b.md
moved docs/superpowers/specs/a.md -> docs/specs/a.md
created docs/wiki.base
created docs/.obsidian/app.json
created docs/.obsidian/.gitignore
updated docs/INDEX.md
warning: login: description over 80 chars
warning: login: anchor #Missing dropped
warning: refs: description is not one line
warning: refs: reference to architecture § Nope at all not converted
warning: sign in: anchor #Nope dropped
warning: n: set type
warning: n: status wip"
WANT_CHECK="wiki-check: features/login.md: description over 80 chars
wiki-check: features/refs.md: description not one line
wiki-check: notes/n.md: missing front matter field type
wiki-check: notes/n.md: bad status: wip"

# mkproj <root> — copy the 0.6 fixture to <root>/wiki-old (the project folder; the INDEX title uses
# its name). Sets P.
mkproj() { mkdir -p "$1"; cp -R "$FXO" "$1/wiki-old"; P="$1/wiki-old"; }
# gitify <core dir> — make <core dir> a git repo holding the project with fixed commit dates:
# 2026-02-03 for every file but docs/glossary.md, which arrives on 2026-03-04.
gitify() {
  local core="$1" nm="${2:-wiki-old}"
  git init -q "$core" && git -C "$core" symbolic-ref HEAD refs/heads/main || return 1
  mv "$core/$nm/docs/glossary.md" "$SANDBOX/glossary.hold" || return 1
  git -C "$core" add -A
  GIT_AUTHOR_DATE="2026-02-03T12:00:00 +0000" GIT_COMMITTER_DATE="2026-02-03T12:00:00 +0000" git -C "$core" commit -q -m one || return 1
  mv "$SANDBOX/glossary.hold" "$core/$nm/docs/glossary.md"
  git -C "$core" add -A
  GIT_AUTHOR_DATE="2026-03-04T12:00:00 +0000" GIT_COMMITTER_DATE="2026-03-04T12:00:00 +0000" git -C "$core" commit -q -m two
}
# run <project> [args] — stdout in OUT, stderr in ERR, exit code in RC
run() { local p="$1"; shift; OUT="$(bash "$WM" "$p" "$@" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"; }
same_tree() { # <dir> <expected dir> <label>
  local a b; a="$(tree_sum "$1")"; b="$(tree_sum "$2")"
  if [ "$a" = "$b" ]; then pass; else fail "$3: tree differs from $2:$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20)"; fi
}

# --- usage: exit 2, one line on stderr
new_sandbox
run ""; assert_eq "$RC" "2" "no argument"
bash "$WM" >/dev/null 2>&1; assert_eq "$?" "2" "no argument (really none)"
run "$SANDBOX/no-such-dir"; assert_eq "$RC" "2" "missing folder"
mkdir -p "$SANDBOX/nodocs"; run "$SANDBOX/nodocs"; assert_eq "$RC" "2" "folder without docs/"
mkproj "$SANDBOX/u"; run "$P" --bogus; assert_eq "$RC" "2" "unknown option"
same_tree "$P" "$FXO" "usage errors changed the project"

# --- the migration, in a git repo (the dates are the commit dates)
new_sandbox
CORE="$SANDBOX/core"; mkproj "$CORE"; gitify "$CORE" || fail "could not build the git fixture"
before="$(snap_tree "$P")"
run "$P" --dry-run
assert_eq "$RC" "0" "dry-run exit"
assert_eq "$(snap_tree "$P")" "$before" "--dry-run changed the project"
echo "$OUT" | grep -qF "docs/brief.md" && pass || fail "--dry-run output does not name docs/brief.md: $OUT"
echo "$OUT" | grep -qxF "warning: n: set type" && pass || fail "--dry-run output lacks the warnings: $OUT"
assert_eq "$(git -C "$CORE" status --porcelain)" "" "--dry-run dirtied the repo"

run "$P"
assert_eq "$RC" "0" "exit"
assert_eq "$OUT" "$WANT_OUT" "stdout"
assert_eq "$ERR" "" "stderr"
same_tree "$P" "$FXE" "migrated tree"
assert_no_file "$P/docs/superpowers/specs/a.md"; assert_no_file "$P/docs/superpowers/plans/b.md"
assert_file "$P/docs/knowledge/k.md"
ls -A "$SANDBOX/core/wiki-old" | grep -q 'migrate\|stage\|\.new\|\.old\|\.tmp' && fail "leftover next to docs: $(ls -A "$P")" || pass
bash "$WI" "$P" --check >/dev/null 2>&1 && pass || fail "INDEX is stale after the migration"
OUT2="$(bash "$WC" "$P" 2>&1)"; RC2=$?
assert_eq "$RC2" "1" "wiki-check exit"
assert_eq "$OUT2" "$WANT_CHECK" "wiki-check lists only the warned pages' problems"
# a trailing . , ; : or ) after an old reference stays after the link, no warning; no final newline stays none
assert_contains "$P/docs/features/login.md" "Also see [[architecture#Layers]]."
assert_eq "$(tail -c 1 "$P/docs/notes/n.md" | od -An -c | tr -d ' ')" "]" "n.md got a final newline"
# an unchanged page is not rewritten
assert_eq "$(cat "$P/docs/features/export.md")" "$(cat "$FXO/docs/features/export.md")" "already-new page"

# second run: nothing changes
after1="$(snap_tree "$P")"
run "$P"
assert_eq "$RC" "0" "second run exit"
assert_eq "$(snap_tree "$P")" "$after1" "second run changed the project"
echo "$OUT" | grep -qE '^(moved|updated|created) ' && fail "second run reports changes: $OUT" || pass
# the anchor links are converted by now, so their "anchor dropped" warnings do not repeat
assert_eq "$(printf '%s\n' "$OUT" | grep '^warning:')" "$(printf '%s\n' "$WANT_OUT" | grep '^warning:' | grep -v 'anchor #')" "second run warnings"
run "$P" --dry-run; assert_eq "$RC" "0" "second --dry-run exit"
assert_eq "$(snap_tree "$P")" "$after1" "second --dry-run changed the project"

# --- fields outside the six: stage: of a brief moves to ## Progress, anything else stays and is warned about
# mkpage <file> <front matter lines...> — one page: front matter from the arguments, body "# T", "", "Text."
mkpage() { local f="$1"; shift; mkdir -p "$(dirname "$f")"; { echo '---'; printf '%s\n' "$@"; printf -- '---\n\n# T\n\nText.\n'; } > "$f"; }
# (a) a non-brief page with tags: x
new_sandbox
mkdir -p "$SANDBOX/xa/p"
mkpage "$SANDBOX/xa/p/docs/features/x.md" 'title: X' 'tags: x' 'description: D.' 'status: active' 'files: []' 'related: []' 'updated: 2026-01-01'
run "$SANDBOX/xa/p"
assert_eq "$RC" "0" "extra field: exit"
assert_eq "$(sed -n '2,9p' "$SANDBOX/xa/p/docs/features/x.md")" "type: feature
status: active
description: D.
files: []
related: []
updated: 2026-01-01
tags: x
---" "extra field tags: stays after the six"
printf '%s\n' "$OUT" | grep -qxF "warning: x: extra front matter field tags" && pass || fail "no extra-field warning for tags: $OUT"
OUT2="$(bash "$WC" "$SANDBOX/xa/p" 2>&1)"
printf '%s\n' "$OUT2" | grep -qxF "wiki-check: features/x.md: unknown front matter field tags" && pass || fail "wiki-check does not report tags: $OUT2"
# (b) a brief that already has ## Progress keeps its stage: field and gets the warning
new_sandbox
mkdir -p "$SANDBOX/xb/p"
mkpage "$SANDBOX/xb/p/docs/brief.md" 'title: Brief' 'type: brief' 'status: active' 'description: D.' 'stage: decided' 'files: []' 'related: []' 'updated: 2026-01-01'
printf '\n## Progress\nStage: interviewed\n' >> "$SANDBOX/xb/p/docs/brief.md"
run "$SANDBOX/xb/p"
assert_eq "$RC" "0" "stage + ## Progress: exit"
assert_contains "$SANDBOX/xb/p/docs/brief.md" "stage: decided"
assert_eq "$(grep -c '^## Progress' "$SANDBOX/xb/p/docs/brief.md")" "1" "stage + ## Progress: sections"
assert_eq "$(grep -c '^Stage: ' "$SANDBOX/xb/p/docs/brief.md")" "1" "stage + ## Progress: Stage lines"
assert_eq "$(sed -n '2,8p' "$SANDBOX/xb/p/docs/brief.md" | tail -1)" "stage: decided" "stage: follows the six"
printf '%s\n' "$OUT" | grep -qxF "warning: brief: extra front matter field stage" && pass || fail "no warning for the kept stage: $OUT"
# (e) a multi-line stage: keeps its continuation lines, is warned about, gets no ## Progress
new_sandbox
mkdir -p "$SANDBOX/xe/p/docs"
printf -- '---\ntype: brief\nstatus: active\ndescription: D.\nstage: |\n  line one\n  line two\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# T\n' > "$SANDBOX/xe/p/docs/brief.md"
run "$SANDBOX/xe/p"
assert_eq "$RC" "0" "multi-line stage: exit"
assert_eq "$(sed -n '8,10p' "$SANDBOX/xe/p/docs/brief.md")" "stage: |
  line one
  line two" "multi-line stage kept with its lines"
grep -q '^## Progress' "$SANDBOX/xe/p/docs/brief.md" && fail "multi-line stage: Progress added" || pass
printf '%s\n' "$OUT" | grep -qxF "warning: brief: extra front matter field stage" && pass || fail "no warning for multi-line stage: $OUT"
# (f) a body that ends inside an open code fence: stage stays, warned, nothing appended
new_sandbox
mkdir -p "$SANDBOX/xf/p/docs"
printf -- '---\ntype: brief\nstatus: active\ndescription: D.\nstage: decided\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# T\n\n```\ncode\n' > "$SANDBOX/xf/p/docs/brief.md"
run "$SANDBOX/xf/p"
assert_eq "$RC" "0" "open fence: exit"
assert_contains "$SANDBOX/xf/p/docs/brief.md" "stage: decided"
grep -q '^## Progress' "$SANDBOX/xf/p/docs/brief.md" && fail "open fence: Progress added" || pass
printf '%s\n' "$OUT" | grep -qxF "warning: brief: extra front matter field stage" && pass || fail "no warning for stage in open fence: $OUT"
# (c) a brief with stage: and no final newline keeps none; the second run changes nothing
new_sandbox
mkdir -p "$SANDBOX/xc/p/docs"
printf -- '---\ntitle: Brief\ntype: brief\nstatus: active\ndescription: D.\nstage: interviewed\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# Brief\n\nText.' > "$SANDBOX/xc/p/docs/brief.md"
run "$SANDBOX/xc/p"
assert_eq "$RC" "0" "stage no final newline: exit"
assert_eq "$(tail -c 1 "$SANDBOX/xc/p/docs/brief.md" | od -An -c | tr -d ' ')" "d" "stage page: the final newline appeared (or Progress is missing)"
assert_eq "$(tail -n 4 "$SANDBOX/xc/p/docs/brief.md")" "Text.

## Progress
Stage: interviewed" "Progress section at the end"
grep -q '^stage:' "$SANDBOX/xc/p/docs/brief.md" && fail "stage: left in the front matter" || pass
after_c="$(snap_tree "$SANDBOX/xc/p")"
run "$SANDBOX/xc/p"
assert_eq "$RC" "0" "stage: second run exit"
printf '%s\n' "$OUT" | grep -q '^updated ' && fail "second run reports updates: $OUT" || pass
assert_eq "$(snap_tree "$SANDBOX/xc/p")" "$after_c" "second run changed the project"
# (d) a dry run changes no files
new_sandbox
mkdir -p "$SANDBOX/xd/p/docs/features"
mkpage "$SANDBOX/xd/p/docs/brief.md" 'title: Brief' 'type: brief' 'status: active' 'description: D.' 'stage: interviewed' 'files: []' 'related: []' 'updated: 2026-01-01'
mkpage "$SANDBOX/xd/p/docs/features/x.md" 'title: X' 'tags: x' 'description: D.' 'status: active' 'files: []' 'related: []' 'updated: 2026-01-01'
before_d="$(snap_tree "$SANDBOX/xd/p")"
run "$SANDBOX/xd/p" --dry-run
assert_eq "$RC" "0" "extra fields dry run: exit"
assert_eq "$(snap_tree "$SANDBOX/xd/p")" "$before_d" "extra fields dry run changed files"
printf '%s\n' "$OUT" | grep -qxF "warning: x: extra front matter field tags" && pass || fail "dry run: no warning for tags: $OUT"

# --- outside git: updated = today
new_sandbox
TODAY="$(date +%F)"
mkproj "$SANDBOX/plain"
EXP="$SANDBOX/exp"; cp -R "$FXE" "$EXP"
(cd "$EXP" && grep -rlE '2026-02-03|2026-03-04' .) | while IFS= read -r f; do
  sed -e "s/2026-02-03/$TODAY/" -e "s/2026-03-04/$TODAY/" "$EXP/$f" > "$EXP/$f.t" && mv "$EXP/$f.t" "$EXP/$f"
done
run "$P"
assert_eq "$RC" "0" "exit (no git)"
assert_eq "$OUT" "$WANT_OUT" "stdout (no git)"
same_tree "$P" "$EXP" "migrated tree (no git, updated = today)"

# --- an empty wiki: only the Obsidian files and the INDEX
new_sandbox
mkdir -p "$SANDBOX/e/empty/docs"
run "$SANDBOX/e/empty"
assert_eq "$RC" "0" "empty wiki exit"
assert_eq "$OUT" "created docs/wiki.base
created docs/.obsidian/app.json
created docs/.obsidian/.gitignore
created docs/INDEX.md" "empty wiki stdout"
bash "$WC" "$SANDBOX/e/empty" >/dev/null 2>&1 && pass || fail "empty wiki not green: $(bash "$WC" "$SANDBOX/e/empty" 2>&1)"
# an Obsidian file the owner changed is kept
printf '{"mine": true}\n' > "$SANDBOX/e/empty/docs/.obsidian/app.json"
run "$SANDBOX/e/empty"
assert_eq "$(cat "$SANDBOX/e/empty/docs/.obsidian/app.json")" '{"mine": true}' "own app.json overwritten"
echo "$OUT" | grep -qxF "skipped docs/.obsidian/app.json" && pass || fail "no 'skipped' line for app.json: $OUT"

# --- an unclosed front matter is not rewritten
new_sandbox
mkproj "$SANDBOX/c"
printf -- '---\ntitle: Broken\ndescription: No closing line.\n\n# Broken\n\n[brief](../brief.md)\n' > "$P/docs/features/broken.md"
cp "$P/docs/features/broken.md" "$SANDBOX/broken.orig"
run "$P"
case "$RC" in 0|1) pass ;; *) fail "unclosed front matter: exit $RC (want 0 or 1): $ERR" ;; esac
cmp -s "$P/docs/features/broken.md" "$SANDBOX/broken.orig" && pass || fail "unclosed front matter page was rewritten: $(cat "$P/docs/features/broken.md")"

# --- failure path: a step fails, the project is exactly as it was (files, folders, repo status)
fails() { # <label> — expects RC=1, one non-empty stderr, project unchanged; the repo stays clean
  assert_eq "$RC" "1" "$1: exit"
  [ -n "$ERR" ] && pass || fail "$1: nothing on stderr"
  assert_eq "$(snap_tree "$P")" "$before" "$1: project changed"
  assert_eq "$(git -C "$CORE" status --porcelain)" "$cstat" "$1: repo status changed"
  echo "$OUT" | grep -qE '^(moved|updated|created) ' && fail "$1: reported changes on stdout: $OUT" || pass
}
# a target of a move exists: docs/specs/ read-only and holding a.md
new_sandbox
CORE="$SANDBOX/core"; mkproj "$CORE"; gitify "$CORE"
mkdir "$P/docs/specs"; printf '# Mine\n' > "$P/docs/specs/a.md"; chmod 555 "$P/docs/specs"
before="$(snap_tree "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
run "$P"; fails "specs/a.md exists (read-only dir)"
chmod 755 "$P/docs/specs"
# the same with a writable plans/ holding b.md
rm -rf "$P/docs/specs"; mkdir "$P/docs/plans"; printf '# Mine\n' > "$P/docs/plans/b.md"
before="$(snap_tree "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
run "$P"; fails "plans/b.md exists"
assert_eq "$(cat "$P/docs/plans/b.md")" "# Mine" "the existing plan was overwritten"
rm -rf "$P/docs/plans"
if [ "$(id -u)" != 0 ]; then
  # the temp folder cannot be created (mktemp in the read-only project folder fails first)
  before="$(snap_tree "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
  chmod 555 "$P"
  run "$P"; chmod 755 "$P"; fails "read-only project folder"
  # a page cannot be read
  chmod 000 "$P/docs/features/login.md"
  run "$P"; chmod 644 "$P/docs/features/login.md"; fails "unreadable page"
  same_tree "$P" "$FXO" "after the failures the project is the fixture"
else
  skip "permission failures" "running as root"
fi

# --- multi-line description, pipe in a link text, empty updated: (git history: 2026-05-06)
new_sandbox
SC="$SANDBOX/sc"; mkdir -p "$SC/small/docs/features"
printf -- '---\ntype: brief\nstatus: active\ndescription: The brief.\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# Brief\n' > "$SC/small/docs/brief.md"
printf -- '---\ntitle: X\ndescription:\n  Indented one\n  and two.\nstatus: draft\nupdated:\n---\n\n# X\n\nPipe [a|b](../brief.md) here.\nupdated: x\n' > "$SC/small/docs/features/x.md"
git init -q "$SC" && git -C "$SC" add -A
GIT_AUTHOR_DATE="2026-05-06T12:00:00 +0000" GIT_COMMITTER_DATE="2026-05-06T12:00:00 +0000" git -C "$SC" commit -q -m one
run "$SC/small"
assert_eq "$RC" "0" "small project exit"
X="$SC/small/docs/features/x.md"
assert_eq "$(grep -A2 '^description:$' "$X")" "description:
  Indented one
  and two." "empty description with indented lines was changed"
assert_eq "$(grep -c '^updated:' "$X")" "2" "updated: lines (front matter + the body line)"
assert_eq "$(sed -n '1,/^---$/p;' "$X" | grep '^updated:')" "updated: 2026-05-06" "empty updated: gets the commit date"
assert_contains "$X" "updated: x"
grep -qF '[[brief|a|b]]' "$X" && fail "broken alias [[brief|a|b]]: $(cat "$X")" || pass
grep -q '\[\[brief' "$X" && pass || fail "pipe link was not converted at all: $(cat "$X")"

# --- the swap is signal-safe and rolls back. A PATH stub for mv acts at the swap (the plugin is copied so
# the stub is the only difference).
if [ "$(id -u)" != 0 ]; then
  new_sandbox
  cp -R "$PLUGIN" "$SANDBOX/plug"; mkdir "$SANDBOX/stub"
  REALMV="$(command -v mv)"
  # TERM after the first move of docs/ (docs/ is already in the temp folder then)
  cat > "$SANDBOX/stub/mv" <<STUB
#!/bin/bash
case "\$1" in
  */docs) if [ ! -e "$SANDBOX/term.done" ]; then : > "$SANDBOX/term.done"; "$REALMV" "\$@"; kill -TERM \$PPID; sleep 1; exit 0; fi ;;
esac
exec "$REALMV" "\$@"
STUB
  chmod +x "$SANDBOX/stub/mv"
  mkproj "$SANDBOX/sig"; before="$(tree_sum "$P")"; want_docs="$(tree_sum "$P/docs")"
  OUT="$(PATH="$SANDBOX/stub:$PATH" bash "$SANDBOX/plug/scripts/wiki-migrate.sh" "$P" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"
  [ -e "$SANDBOX/term.done" ] && pass || fail "the mv stub never saw the swap (nothing to test)"
  if [ -d "$P/docs" ] && [ "$(tree_sum "$P")" = "$before" ]; then pass
  else
    # docs/ is gone or changed: the script must have printed where the original is, and it must be whole
    saved="$(printf '%s\n' "$ERR" | sed -n 's/.* in \(\/[^ ]*\)$/\1/p' | head -1)"
    if [ -n "$saved" ] && [ -d "$saved" ] && [ "$(tree_sum "$saved")" = "$want_docs" ]; then pass
    else fail "TERM at the swap lost docs/: rc=$RC err=$ERR; project now: $(ls -A "$P")"; fi
  fi
  # the second move fails: docs/ is put back, exit 1
  cat > "$SANDBOX/stub/mv" <<STUB
#!/bin/bash
case "\$2" in
  */docs) case "\$1" in */old) ;; *) exit 1 ;; esac ;;
esac
exec "$REALMV" "\$@"
STUB
  mkproj "$SANDBOX/rb"; before="$(snap_tree "$P")"
  OUT="$(PATH="$SANDBOX/stub:$PATH" bash "$SANDBOX/plug/scripts/wiki-migrate.sh" "$P" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"
  assert_eq "$RC" "1" "second mv fails: exit"
  [ -n "$ERR" ] && pass || fail "second mv fails: nothing on stderr"
  assert_eq "$(snap_tree "$P")" "$before" "second mv fails: docs/ not restored"
else
  skip "mv-stub tests" "running as root"
fi

# --- a project folder named "old": the staging copy must not collide with the script's own "old" folder
new_sandbox
mkdir -p "$SANDBOX/core"; cp -R "$FXO" "$SANDBOX/core/old"; P="$SANDBOX/core/old"
gitify "$SANDBOX/core" old || fail "could not build the git fixture for old"
run "$P"
assert_eq "$RC" "0" "project named old: exit"
assert_eq "$ERR" "" "project named old: stderr"
diff -r -x INDEX.md "$P/docs" "$FXE/docs" >/dev/null 2>&1 && pass || fail "project named old: pages differ from the expected tree"
bash "$WI" "$P" --check >/dev/null 2>&1 && pass || fail "project named old: INDEX stale"

# --- C1: a symlink inside docs/ is refused before anything is copied, in a dry run and a real run
# (a plain docs/superpowers migrates: the main test above)
new_sandbox
mkproj "$SANDBOX/ln"; EXT="$SANDBOX/ext"; mkdir "$EXT"
mv "$P/docs/superpowers" "$EXT/superpowers"; ln -s "$EXT/superpowers" "$P/docs/superpowers"
ext_before="$(tree_sum "$EXT")"; docs_before="$(snap_tree "$P")"
[ -n "$(find "$EXT/superpowers" -type f)" ] && pass || fail "the link target holds no files (nothing to test)"
for m in --dry-run ""; do
  run "$P" $m
  assert_eq "$RC" "1" "superpowers link ${m:-real}: exit"
  assert_eq "$ERR" "wiki-migrate: docs/superpowers is a symlink; nothing was changed" "superpowers link ${m:-real}: message"
  assert_eq "$(tree_sum "$EXT")" "$ext_before" "superpowers link ${m:-real}: the link target changed"
  assert_eq "$(snap_tree "$P")" "$docs_before" "superpowers link ${m:-real}: the project changed"
  assert_eq "$OUT" "" "superpowers link ${m:-real}: stdout"
done
# the other folders, each a link to an outside folder
for l in superpowers/specs superpowers/plans specs plans .obsidian; do
  q="$SANDBOX/l-$(echo "$l" | tr '/.' '__')"; mkproj "$q"; X="$q-target"; mkdir -p "$X"
  if [ -d "$P/docs/$l" ]; then mv "$P/docs/$l" "$X/t"; else mkdir "$X/t"; printf 'x\n' > "$X/t/keep.md"; fi
  ln -s "$X/t" "$P/docs/$l"; xb="$(tree_sum "$X")"; pb="$(snap_tree "$P")"
  run "$P" --dry-run
  assert_eq "$RC" "1" "docs/$l link: exit"
  assert_eq "$ERR" "wiki-migrate: docs/$l is a symlink; nothing was changed" "docs/$l link: message"
  assert_eq "$(tree_sum "$X")" "$xb" "docs/$l link: target changed"
  assert_eq "$(snap_tree "$P")" "$pb" "docs/$l link: project changed"
done

# --- I2: 0.6 lines in CLAUDE.md are reported (dry run and real run), never edited
new_sandbox
mkproj "$SANDBOX/cm"
printf '# x\n\n- A new page gets a map line in `docs/INDEX.md`.\n- Put specs and plans in `docs/superpowers/`.\ncheck: true\n' > "$P/CLAUDE.md"
cp "$P/CLAUDE.md" "$SANDBOX/cm.orig"
WANT_CM="warning: CLAUDE.md:3: still says map line; update it by hand
warning: CLAUDE.md:4: still says docs/superpowers; update it by hand"
for m in --dry-run ""; do
  run "$P" $m
  assert_eq "$RC" "0" "CLAUDE.md ${m:-real}: exit"
  assert_eq "$(printf '%s\n' "$OUT" | grep '^warning: CLAUDE.md')" "$WANT_CM" "CLAUDE.md ${m:-real}: warnings"
  cmp -s "$P/CLAUDE.md" "$SANDBOX/cm.orig" && pass || fail "CLAUDE.md ${m:-real}: CLAUDE.md was edited"
done
# a CLAUDE.md made from the current template: no warning
mkproj "$SANDBOX/cm7"; cp "$PLUGIN/templates/CLAUDE.md.tmpl" "$P/CLAUDE.md"
run "$P" --dry-run
printf '%s\n' "$OUT" | grep -q '^warning: CLAUDE.md' && fail "a 0.7 CLAUDE.md is warned about: $(printf '%s\n' "$OUT" | grep CLAUDE.md)" || pass

# --- I3: a folded or literal description is warned about; ">" mid-text is not
new_sandbox
mkproj "$SANDBOX/fold"
i=0
for v in '>' '|' '>-' '|-'; do
  i=$((i + 1))
  printf -- '---\ntype: feature\nstatus: active\ndescription: %s\n  Folded text.\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# F\n' "$v" > "$P/docs/features/f$i.md"
done
printf -- '---\ntype: feature\nstatus: active\ndescription: a > b\nfiles: []\nrelated: []\nupdated: 2026-01-01\n---\n\n# F\n' > "$P/docs/features/f5.md"
run "$P" --dry-run
assert_eq "$RC" "0" "folded description: exit"
assert_eq "$(printf '%s\n' "$OUT" | grep 'not one line')" "warning: f1: description is not one line
warning: f2: description is not one line
warning: f3: description is not one line
warning: f4: description is not one line
warning: refs: description is not one line" "folded description warnings (refs.md of the fixture is one too)"

# --- M2: a leftover staging folder from a killed run is named and kept; the run goes on
new_sandbox
mkproj "$SANDBOX/lo"; mkdir "$P/.wiki-migrate.AbC123"; printf 'x\n' > "$P/.wiki-migrate.AbC123/f"
run "$P"
assert_eq "$RC" "0" "leftover: exit"
printf '%s\n' "$OUT" | grep -qxF "warning: leftover $P/.wiki-migrate.AbC123 from an interrupted run; check and remove it by hand" && pass || fail "leftover not named: $OUT"
assert_file "$P/.wiki-migrate.AbC123/f"
assert_file "$P/docs/specs/a.md"; assert_no_file "$P/docs/superpowers/specs/a.md"

# --- a wiki whose pages get no type still migrates (wiki-index does not refuse there)
new_sandbox
mkdir -p "$SANDBOX/ut/p/docs"; printf '# Notes\n' > "$SANDBOX/ut/p/docs/notes.md"
run "$SANDBOX/ut/p"
assert_eq "$RC" "0" "untyped wiki: exit"
assert_eq "$ERR" "" "untyped wiki: stderr"
printf '%s\n' "$OUT" | grep -qxF "warning: notes: set type" && pass || fail "untyped wiki: no set type warning: $OUT"
assert_file "$SANDBOX/ut/p/docs/INDEX.md"

# --- the converter is one awk program in scripts/wiki-migrate.awk, loaded from the script's own folder; a plugin
# copy without it stops before the swap with nothing changed
assert_file "$SCRIPTS/wiki-migrate.awk"
grep -qF '/wiki-migrate.awk' "$WM" && pass || fail "wiki-migrate.sh does not load wiki-migrate.awk from its own folder"
new_sandbox
mkproj "$SANDBOX/na"; before="$(tree_sum "$P")"
cp -R "$PLUGIN" "$SANDBOX/plugin-copy"; rm -f "$SANDBOX/plugin-copy/scripts/wiki-migrate.awk"
OUT="$(bash "$SANDBOX/plugin-copy/scripts/wiki-migrate.sh" "$P" 2>"$SANDBOX/err")"; RC=$?
assert_eq "$RC" "1" "no wiki-migrate.awk: exit"
assert_contains "$SANDBOX/err" "nothing was changed"
assert_eq "$(tree_sum "$P")" "$before" "no wiki-migrate.awk: the project changed"

finish
