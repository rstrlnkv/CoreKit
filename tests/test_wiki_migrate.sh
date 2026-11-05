#!/usr/bin/env bash
# wiki-migrate.sh: converts a 0.6-format wiki (fixture tests/fixtures/wiki-old) to the 0.7 format
# (expected result: tests/fixtures/wiki-old.expected, byte for byte).
#
# Contract the tests pin (docs/specs/2026-11-06-md-structure-design.md §4, §8; the task 5 brief):
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
#   Front matter fields outside the six (e.g. stage:) are kept after the six, in original order.
#   [t](page.md#anchor): anchor = exact heading of that page -> [[page#anchor]] (when t is the name);
#   otherwise [[page|t]] ([[page]] when t is the name) and "warning: <page>: anchor #<anchor> dropped".
source "$(dirname "$0")/lib.sh"
WM="$SCRIPTS/wiki-migrate.sh"
WC="$SCRIPTS/wiki-check.sh"
WI="$SCRIPTS/wiki-index.sh"
FXO="$ROOT/tests/fixtures/wiki-old"
FXE="$ROOT/tests/fixtures/wiki-old.expected"

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
warning: refs: reference to architecture § Nope at all not converted
warning: sign in: anchor #Nope dropped
warning: n: set type
warning: n: status wip"
WANT_CHECK="wiki-check: features/login.md: description over 80 chars
wiki-check: notes/n.md: missing front matter field type
wiki-check: notes/n.md: bad status: wip"

# mkproj <root> — copy the 0.6 fixture to <root>/wiki-old (the project folder; the INDEX title uses
# its name). Sets P.
mkproj() { mkdir -p "$1"; cp -R "$FXO" "$1/wiki-old"; P="$1/wiki-old"; }
# gitify <core dir> — make <core dir> a git repo holding the project with fixed commit dates:
# 2026-02-03 for every file but docs/glossary.md, which arrives on 2026-03-04.
gitify() {
  local core="$1"
  git init -q "$core" && git -C "$core" symbolic-ref HEAD refs/heads/main || return 1
  mv "$core/wiki-old/docs/glossary.md" "$SANDBOX/glossary.hold" || return 1
  git -C "$core" add -A
  GIT_AUTHOR_DATE="2026-02-03T12:00:00 +0000" GIT_COMMITTER_DATE="2026-02-03T12:00:00 +0000" git -C "$core" commit -q -m one || return 1
  mv "$SANDBOX/glossary.hold" "$core/wiki-old/docs/glossary.md"
  git -C "$core" add -A
  GIT_AUTHOR_DATE="2026-03-04T12:00:00 +0000" GIT_COMMITTER_DATE="2026-03-04T12:00:00 +0000" git -C "$core" commit -q -m two
}
# run <project> [args] — stdout in OUT, stderr in ERR, exit code in RC
run() { local p="$1"; shift; OUT="$(bash "$WM" "$p" "$@" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"; }
# snap_all <dir> — file checksums plus the list of every path (dirs included, .git left out)
snap_all() { tree_sum "$1" 2>/dev/null; (cd "$1" && find . -not -path '*/.git/*' -not -name .git | LC_ALL=C sort); }
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
before="$(snap_all "$P")"
run "$P" --dry-run
assert_eq "$RC" "0" "dry-run exit"
assert_eq "$(snap_all "$P")" "$before" "--dry-run changed the project"
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
after1="$(snap_all "$P")"
run "$P"
assert_eq "$RC" "0" "second run exit"
assert_eq "$(snap_all "$P")" "$after1" "second run changed the project"
echo "$OUT" | grep -qE '^(moved|updated|created) ' && fail "second run reports changes: $OUT" || pass
# the anchor links are converted by now, so their "anchor dropped" warnings do not repeat
assert_eq "$(printf '%s\n' "$OUT" | grep '^warning:')" "$(printf '%s\n' "$WANT_OUT" | grep '^warning:' | grep -v 'anchor #')" "second run warnings"
run "$P" --dry-run; assert_eq "$RC" "0" "second --dry-run exit"
assert_eq "$(snap_all "$P")" "$after1" "second --dry-run changed the project"

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
  assert_eq "$(snap_all "$P")" "$before" "$1: project changed"
  assert_eq "$(git -C "$CORE" status --porcelain)" "$cstat" "$1: repo status changed"
  echo "$OUT" | grep -qE '^(moved|updated|created) ' && fail "$1: reported changes on stdout: $OUT" || pass
}
# a target of a move exists: docs/specs/ read-only and holding a.md
new_sandbox
CORE="$SANDBOX/core"; mkproj "$CORE"; gitify "$CORE"
mkdir "$P/docs/specs"; printf '# Mine\n' > "$P/docs/specs/a.md"; chmod 555 "$P/docs/specs"
before="$(snap_all "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
run "$P"; fails "specs/a.md exists (read-only dir)"
chmod 755 "$P/docs/specs"
# the same with a writable plans/ holding b.md
rm -rf "$P/docs/specs"; mkdir "$P/docs/plans"; printf '# Mine\n' > "$P/docs/plans/b.md"
before="$(snap_all "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
run "$P"; fails "plans/b.md exists"
assert_eq "$(cat "$P/docs/plans/b.md")" "# Mine" "the existing plan was overwritten"
rm -rf "$P/docs/plans"
if [ "$(id -u)" != 0 ]; then
  # the temp folder cannot be created (mktemp in the read-only project folder fails first)
  before="$(snap_all "$P")"; cstat="$(git -C "$CORE" status --porcelain)"
  chmod 555 "$P"
  run "$P"; chmod 755 "$P"; fails "read-only project folder"
  # a page cannot be read
  chmod 000 "$P/docs/features/login.md"
  run "$P"; chmod 644 "$P/docs/features/login.md"; fails "unreadable page"
  same_tree "$P" "$FXO" "after the failures the project is the fixture"
else
  echo "  note: running as root, permission failures skipped"
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
  mkproj "$SANDBOX/rb"; before="$(snap_all "$P")"
  OUT="$(PATH="$SANDBOX/stub:$PATH" bash "$SANDBOX/plug/scripts/wiki-migrate.sh" "$P" 2>"$SANDBOX/err")"; RC=$?; ERR="$(cat "$SANDBOX/err")"
  assert_eq "$RC" "1" "second mv fails: exit"
  [ -n "$ERR" ] && pass || fail "second mv fails: nothing on stderr"
  assert_eq "$(snap_all "$P")" "$before" "second mv fails: docs/ not restored"
else
  echo "  note: running as root, mv-stub tests skipped"
fi

finish
