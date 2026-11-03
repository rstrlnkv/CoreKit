# Sourced by the skill's scripts. Reads user settings without executing the file.
# Config file: $NEW_PROJECT_CONFIG (default ~/.config/new-project/config), lines KEY=VALUE.
# Sets: PROJECTS_DIR, CORE_NAME, APP_ID_PREFIX, CONFIGURED (yes/no), CORE_DIR (unless already set).
NEW_PROJECT_CONFIG="${NEW_PROJECT_CONFIG:-$HOME/.config/new-project/config}"
load_config() {
  PROJECTS_DIR="$HOME/Projects"; CORE_NAME="Core"; APP_ID_PREFIX=""; CONFIGURED=no
  if [ -f "$NEW_PROJECT_CONFIG" ]; then
    CONFIGURED=yes
    while IFS= read -r line || [ -n "$line" ]; do
      key="${line%%=*}"; val="${line#*=}"
      case "$key" in
        PROJECTS_DIR) PROJECTS_DIR="$val" ;;
        CORE_NAME) CORE_NAME="$val" ;;
        APP_ID_PREFIX) APP_ID_PREFIX="$val" ;;
      esac
    done < "$NEW_PROJECT_CONFIG"
  fi
  CORE_DIR="${CORE_DIR:-$PROJECTS_DIR/$CORE_NAME}"
}
