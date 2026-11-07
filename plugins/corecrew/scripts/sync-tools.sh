#!/usr/bin/env bash
# Keeps a stable copy of the plugin's scripts in the plugin's data folder, which survives
# plugin updates (the versioned plugin folder does not). Git hook shims run this copy.
# Usage: bash sync-tools.sh <plugin_root> <tools_dir>
# Prints "tools updated <version>" or "tools current <version>".
# <tools_dir>/VERSION holds the plugin version (line 1) and one checksum of the copied files (line 2).
# The copy is current when both match the plugin and the copy itself still has that checksum; a
# VERSION with only the version (older syncs) counts as stale. A non-empty <tools_dir> without a
# VERSION file, or a <tools_dir> that is not a folder, is not ours: exit 2, nothing is touched.
# Runs at the same time take turns (a lock folder <tools_dir>.lock); one that cannot get it in about 10 s prints
# "tools busy <version>" and exits 0.
set -u
ROOT="${1:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${2:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${T%/}"
S="$ROOT/scripts"
MANIFEST="$ROOT/.claude-plugin/plugin.json"

[ -r "$MANIFEST" ] || { echo "corecrew: $MANIFEST not found; tools not updated." >&2; exit 1; }
VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)
[ -n "$VER" ] || { echo "corecrew: no version in $MANIFEST; tools not updated." >&2; exit 1; }
for f in save undo-step _locate.sh lib.sh install-hooks.sh; do
  [ -f "$S/$f" ] || { echo "corecrew: $S/$f not found; tools not updated." >&2; exit 1; }
done
[ -d "$S/git-hooks" ] || { echo "corecrew: $S/git-hooks not found; tools not updated." >&2; exit 1; }

# The files we copy, relative to the scripts folder (names have no spaces).
FILES="save undo-step _locate.sh lib.sh install-hooks.sh"
for f in "$S"/git-hooks/*; do
  [ -f "$f" ] && FILES="$FILES git-hooks/$(basename "$f")"
done
# sum_of <dir> — one checksum over those files in <dir> (a missing file changes it too).
sum_of() {
  # shellcheck disable=SC2086
  (cd "$1" 2>/dev/null && cksum $FILES 2>/dev/null) | cksum | awk '{ print $1 " " $2 }'
}
SUM="$(sum_of "$S")"

# is_current — same version, same content, and the copy is intact (a damaged or edited copy is rebuilt).
is_current() {
  [ -f "$T/VERSION" ] && [ "$(sed -n 1p "$T/VERSION")" = "$VER" ] && [ "$(sed -n 2p "$T/VERSION")" = "$SUM" ] \
    && [ "$(sum_of "$T")" = "$SUM" ]
}
if is_current; then echo "tools current $VER"; exit 0; fi

# One swap at a time: several runs can start together (a session start and a skill's prepare). The lock is a folder
# next to the tools folder holding the owner's pid; a dead owner's lock is taken over. Up to 10 tries of one second,
# then a clean skip (the run that holds the lock is making the copy).
mkdir -p "$(dirname "$T")" || exit 1
LOCK="$T.lock"; got=0; tries=0
while [ "$tries" -lt 10 ]; do
  if mkdir "$LOCK" 2>/dev/null; then got=1; break; fi
  holder="$(cat "$LOCK/pid" 2>/dev/null)"
  # (no pid yet is a fresh lock for the first seconds, after that an owner that died before writing it)
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || { [ -z "$holder" ] && [ "$tries" -ge 3 ]; }; then
    # (an atomic rename: of several waiters that saw the same dead lock only one wins; the others find it gone)
    if mv "$LOCK" "$LOCK.dead.$$" 2>/dev/null; then rm -rf "$LOCK.dead.$$"; fi
    tries=$((tries + 1)); continue
  fi
  tries=$((tries + 1)); sleep 1
done
if [ "$got" -ne 1 ]; then echo "tools busy $VER"; exit 0; fi
echo $$ > "$LOCK/pid"
NEW="$T.new.$$"; OLD="$T.old.$$"
trap 'rm -rf "$NEW" "$OLD" "$LOCK" "$LOCK.dead.$$"' EXIT
# (another run may have finished the same copy while this one waited)
if is_current; then echo "tools current $VER"; exit 0; fi

# Never replace a folder that is not ours.
if { [ -e "$T" ] || [ -L "$T" ]; } && [ ! -d "$T" ]; then
  echo "corecrew: $T is not a folder, so it is not a corecrew tools folder; it was not replaced. Move it away, then start a new session." >&2
  exit 2
fi
if [ -d "$T" ] && [ ! -f "$T/VERSION" ] && [ -n "$(ls -A "$T" 2>/dev/null)" ]; then
  echo "corecrew: $T is not a corecrew tools folder (it has files but no VERSION); it was not replaced. Move it away, then start a new session." >&2
  exit 2
fi

# Copy into a temp dir next to the target, then swap it in, so a half copy never stays.
rm -rf "$NEW" "$OLD"
mkdir -p "$NEW/git-hooks" || exit 1
for f in save undo-step _locate.sh lib.sh install-hooks.sh; do
  cp -p "$S/$f" "$NEW/$f" || { rm -rf "$NEW"; echo "corecrew: copy of $f failed; tools not updated." >&2; exit 1; }
done
for f in "$S"/git-hooks/*; do
  [ -f "$f" ] || continue
  cp -p "$f" "$NEW/git-hooks/" || { rm -rf "$NEW"; echo "corecrew: copy of $f failed; tools not updated." >&2; exit 1; }
done
# Executable regardless of how the plugin cache stored the modes.
chmod +x "$NEW/save" "$NEW/undo-step" "$NEW/install-hooks.sh" "$NEW"/git-hooks/* 2>/dev/null
chmod -x "$NEW/git-hooks/blocked-patterns" 2>/dev/null
printf '%s\n%s\n' "$VER" "$(sum_of "$NEW")" > "$NEW/VERSION"
if [ -e "$T" ]; then mv "$T" "$OLD" || { rm -rf "$NEW"; exit 1; }; fi
if ! mv "$NEW" "$T"; then
  [ -e "$OLD" ] && mv "$OLD" "$T"
  rm -rf "$NEW"; echo "corecrew: could not replace $T." >&2; exit 1
fi
rm -rf "$OLD"
echo "tools updated $VER"
