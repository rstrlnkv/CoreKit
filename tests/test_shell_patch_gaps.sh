#!/usr/bin/env bash
# Gaps found by mutating lib.sh shell_patch_refused (a copy with the find -exec rule removed stayed green):
# find's program-running primaries with the terminator in QUOTES. Quoted text is made opaque before the structure
# checks, so `';'` leaves no ; for the "no list" check: only the find rule refuses these.
# Each case is also run for real against a fake apply_patch (it appends a line to a log) to show that the fake starts.
source "$(dirname "$0")/lib.sh"
new_sandbox
. "$SCRIPTS/lib.sh"
SELF="$PLUGIN"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/w"; LOG="$SANDBOX/fake.log"
printf '#!/bin/sh\necho RAN >> "%s"\n' "$LOG" > "$SANDBOX/bin/apply_patch"; chmod +x "$SANDBOX/bin/apply_patch"; : > "$SANDBOX/w/f"
refused() { shell_patch_refused "$1" && pass || fail "$2: not refused: $1"; }
passes()  { shell_patch_refused "$1" && fail "$2: refused: $1" || pass; }
starts() { : > "$LOG"; ( cd "$SANDBOX/w" && PATH="$SANDBOX/bin:$PATH" bash -c "$1" </dev/null >/dev/null 2>&1 ); [ -s "$LOG" ] && pass || fail "$2: the fake did not start, so the case proves nothing: $1"; }
for c in "find . -exec apply_patch ';'" "find . -ok apply_patch ';'" "find . -execdir apply_patch ';'" "find . -okdir apply_patch ';'" \
         "find . -name f -exec apply_patch ';'" "find f -exec apply_patch \"+\""; do
  refused "$c" "find with a quoted terminator"
done
starts "find . -name f -exec apply_patch ';'" "find -exec ';'"
# twins that must pass: the same find reading only
passes "find . -name apply_patch -print" "find -name apply_patch"
passes "find . -iname 'apply_patch*'" "find -iname quoted glob"
finish
