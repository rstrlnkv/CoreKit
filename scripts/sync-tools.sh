#!/usr/bin/env bash
# Keeps a stable copy of the plugin's scripts in the plugin's data folder, which survives
# plugin updates (the versioned plugin folder does not). Git hook shims run this copy.
# Usage: bash sync-tools.sh <plugin_root> <tools_dir>
# Prints "tools updated <version>" or "tools current <version>".
# <tools_dir>/VERSION holds the plugin version (line 1) and one checksum of the copied files (line 2).
# The copy is current when both match the plugin and the copy itself still has that checksum; a
# VERSION with only the version (older syncs) counts as stale. A non-empty <tools_dir> without a
# VERSION file, or a <tools_dir> that is not a folder, is not ours: exit 2, nothing is touched.
set -u
ROOT="${1:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${2:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${T%/}"
S="$ROOT/scripts"
MANIFEST="$ROOT/.claude-plugin/plugin.json"

[ -r "$MANIFEST" ] || { echo "coredev: $MANIFEST not found; tools not updated." >&2; exit 1; }
VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)
[ -n "$VER" ] || { echo "coredev: no version in $MANIFEST; tools not updated." >&2; exit 1; }
for f in save undo-step _locate.sh lib.sh install-hooks.sh; do
  [ -f "$S/$f" ] || { echo "coredev: $S/$f not found; tools not updated." >&2; exit 1; }
done
[ -d "$S/git-hooks" ] || { echo "coredev: $S/git-hooks not found; tools not updated." >&2; exit 1; }

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

# Current: same version, same content, and the copy is intact (a damaged or edited copy is rebuilt).
if [ -f "$T/VERSION" ] && [ "$(sed -n 1p "$T/VERSION")" = "$VER" ] && [ "$(sed -n 2p "$T/VERSION")" = "$SUM" ] \
   && [ "$(sum_of "$T")" = "$SUM" ]; then
  echo "tools current $VER"; exit 0
fi

# Never replace a folder that is not ours.
if { [ -e "$T" ] || [ -L "$T" ]; } && [ ! -d "$T" ]; then
  echo "coredev: $T is not a folder, so it is not a coredev tools folder; it was not replaced. Move it away, then start Claude Code again." >&2
  exit 2
fi
if [ -d "$T" ] && [ ! -f "$T/VERSION" ] && [ -n "$(ls -A "$T" 2>/dev/null)" ]; then
  echo "coredev: $T is not a coredev tools folder (it has files but no VERSION); it was not replaced. Move it away, then start Claude Code again." >&2
  exit 2
fi

# Copy into a temp dir next to the target, then swap it in, so a half copy never stays.
mkdir -p "$(dirname "$T")" || exit 1
NEW="$T.new.$$"; OLD="$T.old.$$"
rm -rf "$NEW" "$OLD"
mkdir -p "$NEW/git-hooks" || exit 1
for f in save undo-step _locate.sh lib.sh install-hooks.sh; do
  cp -p "$S/$f" "$NEW/$f" || { rm -rf "$NEW"; echo "coredev: copy of $f failed; tools not updated." >&2; exit 1; }
done
for f in "$S"/git-hooks/*; do
  [ -f "$f" ] || continue
  cp -p "$f" "$NEW/git-hooks/" || { rm -rf "$NEW"; echo "coredev: copy of $f failed; tools not updated." >&2; exit 1; }
done
# Executable regardless of how the plugin cache stored the modes.
chmod +x "$NEW/save" "$NEW/undo-step" "$NEW/install-hooks.sh" "$NEW"/git-hooks/* 2>/dev/null
chmod -x "$NEW/git-hooks/blocked-patterns" 2>/dev/null
printf '%s\n%s\n' "$VER" "$(sum_of "$NEW")" > "$NEW/VERSION"
if [ -e "$T" ]; then mv "$T" "$OLD" || { rm -rf "$NEW"; exit 1; }; fi
if ! mv "$NEW" "$T"; then
  [ -e "$OLD" ] && mv "$OLD" "$T"
  rm -rf "$NEW"; echo "coredev: could not replace $T." >&2; exit 1
fi
rm -rf "$OLD"
echo "tools updated $VER"
