#!/usr/bin/env bash
# Checks tools and paths before creating a project (with --name: <Core>/<name> and a folder named
# <name> in any letter case beside the Core must both be free).
# Usage: bash preflight.sh [--name <name>]   Env: CORE_DIR overrides the plugin option core_dir
# Prints "OK|WARN|FAIL <check> [hint]" lines; exits 1 if any FAIL. gh is needed only at the GitHub stage, so a
# missing or logged-out gh is a WARN. Hints name the official install pages, not one system's package manager.
. "$(dirname "$0")/../../../scripts/lib.sh"
load_settings
NAME=""; [ "${1:-}" = "--name" ] && NAME="${2:-}"
rc=0
ok()   { echo "OK $*"; }
warn() { echo "WARN $*"; }
bad()  { echo "FAIL $*"; rc=1; }

command -v git >/dev/null 2>&1 && ok "git" || bad "git — install Git: https://git-scm.com/downloads (macOS: xcode-select --install)"

HAVE_GH=0; GH_AUTH_OK=0
if command -v gh >/dev/null 2>&1; then
  HAVE_GH=1; ok "gh"
  if gh auth status >/dev/null 2>&1; then ok "gh-auth"; GH_AUTH_OK=1
  else warn "gh-auth — needed to create the GitHub repos; run: gh auth login"; fi
else
  warn "gh — needed to create the GitHub repos; install the GitHub CLI (https://cli.github.com), then: gh auth login"
fi

non_ascii() { printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; }
non_ascii "$HOME" && warn "home-path — '$HOME' has non-Latin characters; Android/Flutter builds may fail" || ok "home-path"
non_ascii "$CORE_DIR" && warn "core-path — '$CORE_DIR' has non-Latin characters; Android/Flutter builds may fail" || ok "core-path"

if [ -n "$NAME" ]; then
  # Both places must be free: <Core>/<name> and, beside the Core, a folder whose lower-case name is <name>
  # (the code repo goes to <Projects>/<name>, and two names that differ only in case are one folder on most Mac disks).
  taken=""
  [ -e "$CORE_DIR/$NAME" ] && taken="$CORE_DIR/$NAME"
  if [ -z "$taken" ]; then
    for d in "$PROJECTS_DIR"/*; do
      { [ -e "$d" ] || [ -L "$d" ]; } || continue
      [ "$d" = "$CORE_DIR" ] && continue
      [ "$(lc "$(basename "$d")")" = "$NAME" ] && { taken="$d"; break; }
    done
  fi
  if [ -n "$taken" ]; then bad "name-local — folder $taken already exists"
  else ok "name-local"; fi
  if [ $GH_AUTH_OK -eq 1 ]; then
    if gh repo view "$NAME" >/dev/null 2>&1; then bad "name-github — a GitHub repository '$NAME' already exists"
    else ok "name-github"; fi
  else
    warn "name-github — cannot check GitHub until gh is installed and logged in"
  fi
fi
exit $rc
