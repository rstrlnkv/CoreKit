#!/usr/bin/env bash
# Keeps a stable copy of the plugin's scripts in the plugin's data folder, which survives
# plugin updates (the versioned plugin folder does not). Git hook shims run this copy.
# Usage: bash sync-tools.sh <plugin_root> <tools_dir>
# Prints "tools updated <version>" or "tools current <version>".
# <tools_dir>/VERSION holds the plugin version (line 1) and one checksum of the copied files (line 2).
# The copy is current when both match the plugin and the copy itself still has that checksum; a
# VERSION with only the version (older syncs) counts as stale. A non-empty <tools_dir> without a
# VERSION file, or a <tools_dir> that is not a folder, is not ours: exit 2, nothing is touched.
# A <tools_dir> named tools also gets <tools_dir>/.data-dir: its parent, the plugin's data folder (lib.sh tools_dir reads it).
# Runs at the same time take turns (a lock folder <tools_dir>.lock); one that cannot get it in about 10 s prints
# "tools busy <version>" and exits 0.
set -u
ROOT="${1:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${2:?usage: sync-tools.sh <plugin_root> <tools_dir>}"
T="${T%/}"
S="$ROOT/scripts"
MANIFEST="$ROOT/.claude-plugin/plugin.json"

[ -r "$MANIFEST" ] || { echo "corecrew: $MANIFEST not found; tools not updated." >&2; exit 1; }
# The version as lib-host.sh plugin_version reads it (the first line whose "version" holds a string), in one sed:
# this script runs at every session start, and sourcing lib.sh for one value costs more than the rest of a current run.
VER="$(sed -n '/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/{s//\1/p;q;}' "$MANIFEST" 2>/dev/null)"
[ -n "$VER" ] || { echo "corecrew: no version in $MANIFEST; tools not updated." >&2; exit 1; }

# The files we copy, relative to the scripts folder (names have no spaces): what save, undo-step and the git hook shims
# run, lib.sh with every part it sources (tests/test_tools.sh checks that against lib.sh), and git-hooks/*.
FILES="save undo-step _locate.sh install-hooks.sh lib.sh lib-paths.sh lib-settings.sh lib-layout.sh lib-host.sh lib-scaffold.sh
  lib-json.sh lib-codex-profile.sh lib-role-model.sh lib-tree-state.sh"
for f in $FILES; do
  [ -f "$S/$f" ] || { echo "corecrew: $S/$f not found; tools not updated." >&2; exit 1; }
done
[ -d "$S/git-hooks" ] || { echo "corecrew: $S/git-hooks not found; tools not updated." >&2; exit 1; }
for f in "$S"/git-hooks/*; do
  [ -f "$f" ] && FILES="$FILES git-hooks/${f##*/}"
done
# TP — the folder <tools_dir> is in (what dirname prints, without starting it).
case "$T" in */*) TP="${T%/*}"; [ -n "$TP" ] || TP=/ ;; *) TP=. ;; esac
# data_dir — the data folder of the copy (<data>/tools, the layout tools_dir uses), written into it as .data-dir, so a copy
# run by hand without CLAUDE_PLUGIN_DATA finds itself (lib.sh tools_dir); nothing for a tools folder with another name.
data_dir() {
  [ "${T##*/}" = tools ] || return 0
  (cd "$TP" 2>/dev/null && pwd -P)
}
# sum_of <dir> — one checksum over those files in <dir> (a missing file changes it too).
sum_of() {
  # shellcheck disable=SC2086
  (cd "$1" 2>/dev/null && cksum $FILES 2>/dev/null) | cksum | awk '{ print $1 " " $2 }'
}
SUM="$(sum_of "$S")"

# is_current — same version, same content, the copy is intact (a damaged or edited copy is rebuilt), and its .data-dir is right.
# VERSION is read with read -r and an empty IFS: each line exactly as written, as `sed -n 1p` and `sed -n 2p` print it.
is_current() {
  local v1="" v2=""
  [ -f "$T/VERSION" ] || return 1
  { IFS= read -r v1; IFS= read -r v2; } < "$T/VERSION" 2>/dev/null
  [ "$v1" = "$VER" ] && [ "$v2" = "$SUM" ] \
    && [ "$(sum_of "$T")" = "$SUM" ] && [ "$(cat "$T/.data-dir" 2>/dev/null)" = "$(data_dir)" ]
}
if is_current; then echo "tools current $VER"; exit 0; fi

# One swap at a time: several runs can start together (a session start and a skill's prepare). The lock is a folder
# next to the tools folder holding the owner's pid; a dead owner's lock is taken over. Up to 10 tries of one second,
# then a clean skip (the run that holds the lock is making the copy).
mkdir -p "$TP" || exit 1
LOCK="$T.lock"; got=0; tries=0
while [ "$tries" -lt 10 ]; do
  if mkdir "$LOCK" 2>/dev/null; then got=1; break; fi
  holder="$(cat "$LOCK/pid" 2>/dev/null)"
  # (no pid yet is a fresh lock for the first seconds, after that an owner that died before writing it)
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || { [ -z "$holder" ] && [ "$tries" -ge 3 ]; }; then
    # (an atomic rename: of several waiters that saw the same dead lock only one wins; the others find it gone)
    # (the lock may have changed hands between the read and the rename: another waiter took the dead one over and
    # made its own. Then the folder moved here holds another pid, or none yet, and goes back untouched.)
    if mv "$LOCK" "$LOCK.dead.$$" 2>/dev/null; then
      if [ "$(cat "$LOCK.dead.$$/pid" 2>/dev/null)" = "$holder" ]; then rm -rf "$LOCK.dead.$$"
      else mv "$LOCK.dead.$$" "$LOCK" 2>/dev/null || rm -rf "$LOCK.dead.$$"; fi
    fi
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
for f in $FILES; do
  cp -p "$S/$f" "$NEW/$f" || { rm -rf "$NEW"; echo "corecrew: copy of $S/$f failed; tools not updated." >&2; exit 1; }
done
# Executable regardless of how the plugin cache stored the modes.
chmod +x "$NEW/save" "$NEW/undo-step" "$NEW/install-hooks.sh" "$NEW"/git-hooks/* 2>/dev/null
chmod -x "$NEW/git-hooks/blocked-patterns" "$NEW/git-hooks/allowed-patterns" 2>/dev/null
D="$(data_dir)"
if [ -n "$D" ]; then printf '%s\n' "$D" > "$NEW/.data-dir" || { rm -rf "$NEW"; exit 1; }; fi
printf '%s\n%s\n' "$VER" "$(sum_of "$NEW")" > "$NEW/VERSION"
if [ -e "$T" ]; then mv "$T" "$OLD" || { rm -rf "$NEW"; exit 1; }; fi
if ! mv "$NEW" "$T"; then
  [ -e "$OLD" ] && mv "$OLD" "$T"
  rm -rf "$NEW"; echo "corecrew: could not replace $T." >&2; exit 1
fi
rm -rf "$OLD"
echo "tools updated $VER"
