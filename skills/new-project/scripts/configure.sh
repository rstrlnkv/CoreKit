#!/usr/bin/env bash
# Shows or saves the user's new-project settings.
# Usage: bash configure.sh --show
#        bash configure.sh [--projects-dir <abs path>] [--core-name <name>] [--app-id-prefix <com.example>]
set -u
. "$(dirname "$0")/../../../scripts/lib.sh"
load_config
SHOW=0; CHANGED=0
die() { echo "$*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --show) SHOW=1; shift ;;
    --projects-dir) PROJECTS_DIR="${2:-}"; CHANGED=1; shift 2 ;;
    --core-name) CORE_NAME="${2:-}"; CHANGED=1; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="${2:-}"; CHANGED=1; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
if [ $CHANGED -eq 1 ]; then
  case "$PROJECTS_DIR" in /*) ;; *) die "Projects folder must be an absolute path (e.g. $HOME/Projects)." ;; esac
  LC_ALL=C bash -c '[[ "$1" =~ ^[A-Za-z0-9._-]{1,100}$ ]]' _ "$CORE_NAME" \
    || die "Docs repository name may contain only Latin letters, digits, '.', '_' and '-'."
  [ -z "$APP_ID_PREFIX" ] || LC_ALL=C bash -c '[[ "$1" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]' _ "$APP_ID_PREFIX" \
    || die "App id prefix must be reverse-DNS in lowercase, e.g. com.yourname."
  mkdir -p "$(dirname "$NEW_PROJECT_CONFIG")"
  tmp="$NEW_PROJECT_CONFIG.tmp.$$"
  printf 'PROJECTS_DIR=%s\nCORE_NAME=%s\nAPP_ID_PREFIX=%s\n' "$PROJECTS_DIR" "$CORE_NAME" "$APP_ID_PREFIX" > "$tmp"
  mv "$tmp" "$NEW_PROJECT_CONFIG"
  echo "saved $NEW_PROJECT_CONFIG"
  CONFIGURED=yes; CORE_DIR="$PROJECTS_DIR/$CORE_NAME"
fi
if [ $SHOW -eq 1 ]; then
  printf 'configured=%s\nCONFIG_FILE=%s\nPROJECTS_DIR=%s\nCORE_NAME=%s\nCORE_DIR=%s\nAPP_ID_PREFIX=%s\n' \
    "$CONFIGURED" "$NEW_PROJECT_CONFIG" "$PROJECTS_DIR" "$CORE_NAME" "$CORE_DIR" "$APP_ID_PREFIX"
fi
[ $SHOW -eq 1 ] || [ $CHANGED -eq 1 ] || die "Usage: configure.sh --show | --projects-dir <path> --core-name <name> --app-id-prefix <prefix>"
