#!/usr/bin/env bash
# Builds the end-to-end fixture <core_dir>/test-coredev/ (spec section 16): a tiny project with a
# planted bug, to try "/coredev:task fix: ..." on.
#   Core side: CLAUDE.md with "check: bash tests/run.sh", a wiki that passes wiki-check.sh (made
#              from the new-project templates), docs/knowledge/, a PROJECTS.md line.
#   code/:     its own git repo on main with add.sh (add <a> <b> prints the sum, except that a
#              wrong branch for an odd <b> prints the product: "add 2 3" prints 6, "add 2 2" is
#              right) and tests/run.sh (checks only "add 2 2" -> 4), one commit.
# The git hook shims are installed and the Core gets one commit, "Add test-coredev fixture".
# Usage: bash make-test-coredev.sh <core_dir>
# Output: "created ..." lines; the last line is the path of code/.
# Exit:   0 built; 1 a step failed (or git does not know who you are); 2 refused, nothing changed
#         (no argument, the Core is not set up, or <core_dir>/test-coredev already exists).
# Only test-coredev/ and its line in PROJECTS.md are written; the rest of the Core is left alone.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TPL="$ROOT_DIR/skills/new-project/templates"
. "$ROOT_DIR/scripts/lib.sh"

refuse() { echo "make-test-coredev: $1" >&2; exit 2; }
die() { echo "make-test-coredev: $1" >&2; exit 1; }

[ $# -eq 1 ] && [ -n "$1" ] || refuse "usage: make-test-coredev.sh <core_dir>"
CORE_DIR="$1"
load_settings
NAME="test-coredev"
P="$CORE_DIR/$NAME"
C="$P/code"
PURPOSE="Tiny fixture for the end-to-end check of coredev: adds two numbers."
DATE="$(date +%Y-%m-%d)"

{ core_ready && [ -d "$CORE_DIR/.git" ]; } || refuse "Core is not set up at $CORE_DIR (nothing was created)"
{ [ -e "$P" ] || [ -L "$P" ]; } && refuse "$P already exists (nothing was changed)"
if ! git -C "$CORE_DIR" var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! git -C "$CORE_DIR" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
  echo "Git does not know who you are yet, so the fixture cannot save its commits. Run:" >&2
  echo "  git config --global user.name \"Your Name\"" >&2
  echo "  git config --global user.email \"you@example.com\"" >&2
  echo "then run this again. Nothing was created." >&2
  exit 1
fi

# put_text <dest> — create dest from stdin; says "created <path in the Core>".
put_text() {
  mkdir -p "$(dirname "$1")" && cat > "$1" || return 1
  echo "created $(rel_core "$1")"
}

# --- Core side: the project docs from the new-project templates
put_project_docs "$TPL" "$P" || die "could not create the project docs"

# CLAUDE.md: the check line and the commands (the template leaves them to be filled in).
tmp="$P/CLAUDE.md.tmp.$$"
awk '
  /^check:/ { print "check: bash tests/run.sh"; next }
  /^- Build:/ { print "- Build: none (plain bash)"; next }
  /^- Test:/ { print "- Test: `bash tests/run.sh`"; next }
  /^- Run:/ { print "- Run: `bash add.sh <a> <b>`"; next }
  { print }' "$P/CLAUDE.md" > "$tmp" && mv "$tmp" "$P/CLAUDE.md" || die "could not write CLAUDE.md"

# One feature page that describes add.sh, and its line in the map (after the features/ line).
put_text "$P/docs/features/add.md" <<EOF || die "could not write docs/features/add.md"
---
title: Add
description: What add.sh does. Read before changing how two numbers are added.
status: active
files: [add.sh]
related: []
updated: $DATE
---

# Add

## Behavior
\`bash add.sh <a> <b>\` prints the sum of two whole numbers.

## Check
\`bash tests/run.sh\` in \`code/\` prints \`ALL TESTS PASSED\` when it holds.
EOF
tmp="$P/docs/INDEX.md.tmp.$$"
awk '{ print } /^- features\// { print "- [features/add.md](features/add.md) — what add.sh does." }' \
  "$P/docs/INDEX.md" > "$tmp" && mv "$tmp" "$P/docs/INDEX.md" || die "could not write docs/INDEX.md"

# --- code side: its own repo, one commit
mkdir -p "$C" || die "could not create $C"
git init -q "$C" && git -C "$C" symbolic-ref HEAD refs/heads/main || die "could not create the code repo"
echo "created $(rel_core "$C")/.git"
put_text "$C/add.sh" <<'EOF' || die "could not write add.sh"
#!/usr/bin/env bash
# add <a> <b> — prints the sum of two whole numbers.
a="${1:?usage: add.sh <a> <b>}"
b="${2:?usage: add.sh <a> <b>}"
if [ $((b % 2)) -eq 1 ]; then
  echo $((a * b))
else
  echo $((a + b))
fi
EOF
put_text "$C/tests/run.sh" <<'EOF' || die "could not write tests/run.sh"
#!/usr/bin/env bash
# Checks add 2 2 -> 4. Prints ALL TESTS PASSED on success; exits 1 otherwise.
cd "$(dirname "$0")/.." || exit 1
got="$(bash add.sh 2 2)"
if [ "$got" = "4" ]; then
  echo "ok: add 2 2 = 4"
  echo "ALL TESTS PASSED"
else
  echo "FAIL: add 2 2 printed '$got', expected 4"
  exit 1
fi
EOF
put "$TPL/code/gitignore-common" "$C/.gitignore" copy || die "could not write .gitignore"
git -C "$C" add -A && git -C "$C" commit -q -m "Initial commit" || die "could not make the first commit in $C"
echo "created $(rel_core "$C") commit: Initial commit"

# --- hooks (shims in code/ and in the Core)
RC=0
if [ -n "${COREDEV_TOOLS:-}" ]; then HOOK_ARGS=(--tools "$COREDEV_TOOLS"); else HOOK_ARGS=(); fi
if CORE_DIR="$CORE_DIR" bash "$ROOT_DIR/scripts/install-hooks.sh" "$P" ${HOOK_ARGS[@]+"${HOOK_ARGS[@]}"} >/dev/null; then
  echo "created git hook shims"
else
  echo "warning: git hooks were not installed; run: CORE_DIR=\"$CORE_DIR\" bash \"$ROOT_DIR/scripts/install-hooks.sh\" \"$P\"" >&2
  RC=1
fi

# --- PROJECTS.md line and the Core commit (only test-coredev/ and PROJECTS.md)
projects_entry "$NAME" "$PURPOSE" || die "could not write PROJECTS.md"
if git -C "$CORE_DIR" add -- "$NAME" PROJECTS.md && git -C "$CORE_DIR" commit -q -m "Add test-coredev fixture" -- "$NAME" PROJECTS.md >/dev/null 2>&1; then
  echo "created Core commit: Add test-coredev fixture"
else
  echo "warning: the Core commit failed; commit $NAME/ and PROJECTS.md in $CORE_DIR yourself" >&2
  RC=1
fi
echo "$C"
exit "$RC"
