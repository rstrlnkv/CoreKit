#!/usr/bin/env bash
# sync-tools.sh keeps a stable copy of the plugin's scripts in the data folder.
source "$(dirname "$0")/lib.sh"
new_sandbox
SYNC="$SCRIPTS/sync-tools.sh"
T="$SANDBOX/data/tools"
assert_exit 0 bash "$SYNC" "$ROOT" "$T"
assert_eq "$OUT" "tools updated 0.2.0" "first sync output"
for f in save undo-step _locate.sh lib.sh install-hooks.sh \
         git-hooks/pre-commit-code git-hooks/pre-push-code git-hooks/pre-push-core git-hooks/blocked-patterns; do
  assert_file "$T/$f"
done
assert_eq "$(cat "$T/VERSION")" "0.2.0" "VERSION file"
for f in save undo-step install-hooks.sh git-hooks/pre-commit-code git-hooks/pre-push-code git-hooks/pre-push-core; do
  [ -x "$T/$f" ] && pass || fail "not executable: $T/$f"
done
assert_eq "$(ls "$SANDBOX/data" | tr '\n' ' ')" "tools " "no temp dir left behind"

# second run: current, nothing rewritten
echo marker > "$T/marker"
assert_exit 0 bash "$SYNC" "$ROOT" "$T"
assert_eq "$OUT" "tools current 0.2.0" "second sync output"
assert_file "$T/marker"

# a damaged copy is healed: same VERSION, but a file is gone -> updated and restored
for f in git-hooks/blocked-patterns git-hooks/pre-push-core _locate.sh lib.sh install-hooks.sh undo-step; do
  rm -f "$T/$f"
  assert_exit 0 bash "$SYNC" "$ROOT" "$T"
  assert_eq "$OUT" "tools updated 0.2.0" "sync after deleting $f"
  assert_file "$T/$f"
done
assert_exit 0 bash "$SYNC" "$ROOT" "$T"
assert_eq "$OUT" "tools current 0.2.0" "intact copy is current again"
echo marker > "$T/marker"

# a different VERSION triggers an update that replaces the folder
echo 0.1.0 > "$T/VERSION"
assert_exit 0 bash "$SYNC" "$ROOT" "$T"
assert_eq "$OUT" "tools updated 0.2.0" "version change output"
assert_eq "$(cat "$T/VERSION")" "0.2.0"
assert_no_file "$T/marker"

# a tools dir whose path has a space
T2="$SANDBOX/my data/tools dir"
assert_exit 0 bash "$SYNC" "$ROOT" "$T2"
assert_file "$T2/save"; assert_file "$T2/git-hooks/blocked-patterns"

# the synced save runs standalone (reads _locate.sh next to itself)
(cd "$SANDBOX" && bash "$T2/save" 2>&1 | grep -q 'Usage') && pass || fail "synced save does not run"

# a broken plugin root fails loudly and leaves the target alone
assert_exit 1 bash "$SYNC" "$SANDBOX/nope" "$T"
assert_eq "$(cat "$T/VERSION")" "0.2.0" "target untouched after failure"
finish
