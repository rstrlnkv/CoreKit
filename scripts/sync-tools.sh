#!/usr/bin/env bash
# Keeps a stable copy of the plugin's scripts in the plugin's data folder, which survives
# plugin updates (the versioned plugin folder does not). Git hook shims run this copy.
# Usage: bash sync-tools.sh <plugin_root> <tools_dir>
# Prints "tools updated <version>" or "tools current <version>".
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

# Current: same version and every file we would copy is there (a damaged copy is rebuilt).
complete=1
[ -f "$T/VERSION" ] && [ "$(cat "$T/VERSION")" = "$VER" ] || complete=0
if [ $complete -eq 1 ]; then
  for f in save undo-step _locate.sh lib.sh install-hooks.sh; do
    [ -f "$T/$f" ] || { complete=0; break; }
  done
fi
if [ $complete -eq 1 ]; then
  for f in "$S"/git-hooks/*; do
    [ -f "$f" ] || continue
    [ -f "$T/git-hooks/$(basename "$f")" ] || { complete=0; break; }
  done
fi
if [ $complete -eq 1 ]; then
  echo "tools current $VER"; exit 0
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
printf '%s\n' "$VER" > "$NEW/VERSION"
if [ -e "$T" ]; then mv "$T" "$OLD" || { rm -rf "$NEW"; exit 1; }; fi
if ! mv "$NEW" "$T"; then
  [ -e "$OLD" ] && mv "$OLD" "$T"
  rm -rf "$NEW"; echo "coredev: could not replace $T." >&2; exit 1
fi
rm -rf "$OLD"
echo "tools updated $VER"
