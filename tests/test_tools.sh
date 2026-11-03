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
assert_eq "$(head -1 "$T/VERSION")" "0.2.0" "VERSION file: the version on line 1"
sed -n 2p "$T/VERSION" | grep -qE '^[0-9]+ [0-9]+$' && pass || fail "VERSION file: no content checksum on line 2: $(cat "$T/VERSION")"
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
assert_eq "$(head -1 "$T/VERSION")" "0.2.0"
assert_no_file "$T/marker"

# a tools dir whose path has a space
T2="$SANDBOX/my data/tools dir"
assert_exit 0 bash "$SYNC" "$ROOT" "$T2"
assert_file "$T2/save"; assert_file "$T2/git-hooks/blocked-patterns"

# the synced save runs standalone (reads _locate.sh next to itself)
(cd "$SANDBOX" && bash "$T2/save" 2>&1 | grep -q 'Usage') && pass || fail "synced save does not run"

# a broken plugin root fails loudly and leaves the target alone
assert_exit 1 bash "$SYNC" "$SANDBOX/nope" "$T"
assert_eq "$(head -1 "$T/VERSION")" "0.2.0" "target untouched after failure"

# Same version, changed content (a fix shipped without a version bump, or a --plugin-dir checkout):
# the copy is refreshed. A plugin root copied into the sandbox, so its scripts can change.
R="$SANDBOX/plugin"; mkdir -p "$R"; cp -R "$ROOT/.claude-plugin" "$ROOT/scripts" "$R/"
T3="$SANDBOX/data3/tools"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools current 0.2.0" "unchanged plugin: current"
printf '# changed\n' >> "$R/scripts/save"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated 0.2.0" "changed save, same version: updated"
assert_eq "$(tail -1 "$T3/save")" "# changed" "the changed save was copied"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools current 0.2.0" "current again after the refresh"
printf '# changed\n' >> "$R/scripts/git-hooks/blocked-patterns"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated 0.2.0" "changed git-hooks file, same version: updated"
# a copy edited in place (same version, same file set) is rebuilt too
printf 'echo tampered\n' >> "$T3/lib.sh"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated 0.2.0" "edited copy: updated"
assert_not_contains "$T3/lib.sh" "echo tampered"
# backward compatible: a VERSION from an older sync holds only the version -> stale, rebuilt
printf '0.2.0\n' > "$T3/VERSION"
assert_exit 0 bash "$SYNC" "$R" "$T3"
assert_eq "$OUT" "tools updated 0.2.0" "version-only VERSION: updated"
assert_eq "$(wc -l < "$T3/VERSION" | tr -d ' ')" "2" "VERSION rewritten with the checksum"

# A target folder that is not ours (non-empty, no VERSION) is never replaced: exit 2, nothing changed.
F="$SANDBOX/foreign"; mkdir -p "$F/sub"; echo mine > "$F/notes.txt"; echo x > "$F/sub/y"
before="$(tree_sum "$F")"
assert_exit 2 bash "$SYNC" "$ROOT" "$F"
echo "$OUT" | grep -qF "$F" && pass || fail "refusal does not name the folder: $OUT"
echo "$OUT" | grep -qi 'not replaced\|not a coredev' && pass || fail "refusal is not a plain message: $OUT"
assert_eq "$(tree_sum "$F")" "$before" "foreign folder changed"
assert_eq "$(ls -A "$SANDBOX" | grep -c 'foreign\.')" "0" "temp dir left next to the foreign folder"
# a file in place of the target: refused too
echo file > "$SANDBOX/tfile"
assert_exit 2 bash "$SYNC" "$ROOT" "$SANDBOX/tfile"
assert_eq "$(cat "$SANDBOX/tfile")" "file" "file target changed"
# an empty folder is fine (made by hand or by an earlier mkdir)
mkdir -p "$SANDBOX/empty/tools"
assert_exit 0 bash "$SYNC" "$ROOT" "$SANDBOX/empty/tools"
assert_file "$SANDBOX/empty/tools/save"
finish
