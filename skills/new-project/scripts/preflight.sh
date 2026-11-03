#!/usr/bin/env bash
# Checks tools and paths before creating a project.
# Usage: bash preflight.sh [--name <name>]   Env: CORE_DIR overrides the plugin option core_dir
# Prints "OK|WARN|FAIL <check> [hint]" lines; exits 1 if any FAIL.
. "$(dirname "$0")/../../../scripts/lib.sh"
load_settings
NAME=""; [ "${1:-}" = "--name" ] && NAME="${2:-}"
rc=0
ok()   { echo "OK $*"; }
warn() { echo "WARN $*"; }
bad()  { echo "FAIL $*"; rc=1; }

command -v git >/dev/null 2>&1 && ok "git" || bad "git — install Xcode Command Line Tools: xcode-select --install"

HAVE_GH=0; GH_AUTH_OK=0
if command -v gh >/dev/null 2>&1; then
  HAVE_GH=1; ok "gh"
  if gh auth status >/dev/null 2>&1; then ok "gh-auth"; GH_AUTH_OK=1
  else bad "gh-auth — run: gh auth login"; fi
else
  bad "gh — install the GitHub CLI: brew install gh, then: gh auth login"
fi

non_ascii() { printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; }
non_ascii "$HOME" && warn "home-path — '$HOME' has non-Latin characters; Android/Flutter builds may fail" || ok "home-path"
non_ascii "$CORE_DIR" && warn "core-path — '$CORE_DIR' has non-Latin characters; Android/Flutter builds may fail" || ok "core-path"

if [ -n "$NAME" ]; then
  if [ -e "$CORE_DIR/$NAME" ]; then bad "name-local — folder $CORE_DIR/$NAME already exists"
  else ok "name-local"; fi
  if [ $GH_AUTH_OK -eq 1 ]; then
    if gh repo view "$NAME" >/dev/null 2>&1; then bad "name-github — a GitHub repository '$NAME' already exists"
    else ok "name-github"; fi
  else
    warn "name-github — cannot check GitHub until gh is installed and logged in"
  fi
fi
exit $rc
