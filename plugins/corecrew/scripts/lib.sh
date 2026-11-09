# Shared helpers for the plugin's scripts. Source it, or run it: bash lib.sh get|set <key> [value].
# User settings (core_dir, attribution, model_profile, ui_language) come, per key, from: the CORE_DIR
# env (core_dir only), the plugin option CLAUDE_PLUGIN_OPTION_<KEY> (Claude Code), the settings file
# ~/.config/corecrew/settings or $CORECREW_CONFIG (lines "key: value"; the only source in Codex), the
# default. Project facts live in <Core>/.coredev (lines "key: value"). Files are read, never executed.
# load_settings sets: CORE_DIR, CORE_NAME, PROJECTS_DIR, ATTRIBUTION, MODEL_PROFILE, UI_LANGUAGE,
# APP_ID_PREFIX, SETTINGS_WARN (records "key<TAB>value<TAB>source<TAB>value in effect" of values ignored as invalid;
# their texts are msg_settings_warning in hooks/messages.sh).
#
# The helpers live in parts next to this file, which it sources (callers source only lib.sh):
#   lib-paths.sh     expand_home canon_dir lc norm_path resolve_abs (and expand_home_r canon_dir_r, which set a variable)
#   lib-settings.sh  coredev_get coredev_set core_ready settings_file_path resolve_setting load_settings ...
#   lib-layout.sh    project_of worktree_of code_root_of code_dir_of layout_of valid_project_name
#   lib-host.sh      codex_home host tools_dir hooks_marker_path plugin_version
#   lib-scaffold.sh  rel_core render put mkdir_p git_init put_project_docs link_* projects_entry projects_upsert
#   lib-json.sh      json_str json_fields (the hook JSON readers; their awk program is inline, so file tools need no awk file)
# Three subcommands source their own file when run: lib-codex-profile.sh, lib-role-model.sh, lib-tree-state.sh.
# The guards' shell-patch check is scripts/shell-patch.sh and their shared code scripts/guard-lib.sh (neither is part of lib.sh). sync-tools.sh copies every part
# into the tools copy (save, undo-step and install-hooks source lib.sh there).

# The Core layout schema this plugin version writes and expects (the one place it is defined).
COREDEV_SCHEMA=2

# HOME unset (a stripped environment): the account's home folder, so ~ and ~/.ssh still mean something.
if [ -z "${HOME:-}" ]; then
  HOME="$(eval 'printf %s ~' 2>/dev/null)"
  case "${HOME:-}" in /*) ;; *) HOME="" ;; esac
fi

# The folder of this file, absolute, so the parts are found after the caller changes folder. CDPATH is ignored (a relative
# scripts/lib.sh must not lead cd to another scripts folder, nor make it print one).
_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || _LIB_DIR=""

# CLI plugin-root (the absolute plugin folder this script is in; exit 1 when it is not the corecrew plugin). It needs no
# part, so a lib.sh copied alone into a folder that is not a plugin still says so.
# A mix-up catch, not a security boundary: a script cannot vet itself, so a look-alike folder that carries its own copy of
# this script passes. The Paths text of the skills adds the Codex cache-location rule for the model.
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = plugin-root ]; then
  r="$(cd "$_LIB_DIR/.." && pwd -P)"
  m=""
  if [ -f "$r/.codex-plugin/plugin.json" ]; then m="$r/.codex-plugin/plugin.json"
  elif [ -f "$r/.claude-plugin/plugin.json" ]; then m="$r/.claude-plugin/plugin.json"; fi
  if [ -d "$r/skills" ] && [ -n "$m" ]; then
    grep -q '"name"[[:space:]]*:[[:space:]]*"corecrew"' "$m" || { echo "corecrew: not a corecrew plugin folder: $r" >&2; exit 1; }
    printf '%s\n' "$r"; exit 0
  fi
  echo "corecrew: not a plugin folder: $r" >&2; exit 1
fi

for _lib_part in "$_LIB_DIR/lib-paths.sh" "$_LIB_DIR/lib-settings.sh" "$_LIB_DIR/lib-layout.sh" "$_LIB_DIR/lib-host.sh" \
                 "$_LIB_DIR/lib-scaffold.sh" "$_LIB_DIR/lib-json.sh"; do
  # shellcheck disable=SC1090
  . "$_lib_part" || { echo "corecrew: $_lib_part is missing or broken" >&2; unset _lib_part; return 1 2>/dev/null || exit 1; }
done
unset _lib_part

# CLI: bash lib.sh get <key> | set <key> <value> | ready (exit 0 when core_ready) | core-dir (absolute path; warnings for ignored values on stderr)
#      | settings [key[=optionvalue] ...] (resolved user settings, one "key: value" line each)
#      | setting-path (the settings file path)
#      | plugin-root (the absolute plugin folder this script is in; exit 1 when it is not the corecrew plugin)
#      | codex-profile | host | role-model <host> <profile> <role> | core-writable <dir> | tree-state <dir>
#      | schema (the plugin's schema number) | core-paths <project> (the Core paths `save` commits for
#      the project, one line, space-separated; from _locate.sh next to this file)
#      | project-of <path> | code-root <path> | code-dir <name> | layout <name> (see project_of, code_root_of, code_dir_of, layout_of)
# shellcheck disable=SC2034  # SETTINGS_WARN and CLAUDE_PLUGIN_OPTION_* set here are read by the parts (lib-settings.sh)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # _warn_settings — the SETTINGS_WARN records as English lines (the texts of hooks/messages.sh). messages.sh is
  # sourced only here; where it is missing (the tools copy) nothing is printed and the exit code stays.
  _warn_settings() {
    local k v s e
    [ -n "$SETTINGS_WARN" ] || return 0
    # shellcheck disable=SC1091
    . "$_LIB_DIR/../hooks/messages.sh" 2>/dev/null || return 0
    while IFS=$'\t' read -r k v s e; do
      [ -n "$k" ] || continue
      UI_LANGUAGE=en msg_settings_warning "$k" "$v" "$s" "$e" "$(settings_file_path)"; printf '\n'
    done <<< "$SETTINGS_WARN"
    return 0
  }
  _ORIG_CORE_DIR="${CORE_DIR:-}"
  load_settings
  case "${1:-}" in
    get) [ $# -eq 2 ] || { echo "Usage: lib.sh get <key>" >&2; exit 2; }; coredev_get "$2" ;;
    set) [ $# -eq 3 ] || { echo "Usage: lib.sh set <key> <value>" >&2; exit 2; }; coredev_set "$2" "$3" ;;
    ready) core_ready ;;
    core-dir) [ -z "$CORE_DIR" ] || printf '%s\n' "$CORE_DIR"; _warn_settings >&2; [ -n "$CORE_DIR" ] ;;
    setting-path) settings_file_path; echo ;;
    settings)
      shift; keys=""; CORE_DIR="$_ORIG_CORE_DIR"; SETTINGS_WARN=""; _settings_file_check
      for a in "$@"; do
        k="${a%%=*}"; v=""; [ "$k" = "$a" ] || v="${a#*=}"
        case "$k" in
          core_dir) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_CORE_DIR="$v" ;;
          attribution) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_ATTRIBUTION="$v" ;;
          model_profile) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_MODEL_PROFILE="$v" ;;
          ui_language) [ "$k" = "$a" ] || CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="$v" ;;
          *) echo "Usage: lib.sh settings [core_dir|attribution|model_profile|ui_language[=value] ...]" >&2; exit 2 ;;
        esac
        keys="$keys $k"
      done
      [ -n "$keys" ] || keys="core_dir attribution model_profile ui_language"
      for k in $keys; do
        _resolve_setting "$k"
        if [ "$k" = core_dir ]; then _core_raw "$REPLY"; if [ -n "$CORE_RAW" ]; then printf 'core_dir: %s\n' "$(canon_dir "$CORE_RAW")"; else printf 'core_dir: \n'; fi
        else printf '%s: %s\n' "$k" "$REPLY"; fi
      done
      _warn_settings >&2 ;;
    codex-profile) . "$_LIB_DIR/lib-codex-profile.sh" || exit 1; codex_profile ;;
    host) host; echo ;;
    role-model) . "$_LIB_DIR/lib-role-model.sh" || exit 1; shift; role_model "$@" ;;
    core-writable)
      # Exit 0 when <dir> accepts a new file (a mktemp probe, removed at once; only the probe is removed).
      [ $# -eq 2 ] && case "$2" in /*) true ;; *) false ;; esac || { echo "Usage: lib.sh core-writable <absolute dir>" >&2; exit 2; }
      cw_probe="$(mktemp "$2/.corecrew-probe.XXXXXX" 2>/dev/null)" || {
        echo "corecrew: $2 is not writable from this session. Start Codex with: codex --add-dir \"$2\"" >&2; exit 1; }
      rm -f "$cw_probe" ;;
    tree-state) . "$_LIB_DIR/lib-tree-state.sh" || exit 1; shift; tree_state "$@" ;;
    schema) printf '%s\n' "$COREDEV_SCHEMA" ;;
    code-root) [ $# -eq 2 ] || { echo "Usage: lib.sh code-root <path>" >&2; exit 2; }; code_root_of "$2" ;;
    project-of) [ $# -eq 2 ] || { echo "Usage: lib.sh project-of <path>" >&2; exit 2; }; project_of "$2" ;;
    code-dir) [ $# -eq 2 ] || { echo "Usage: lib.sh code-dir <name>" >&2; exit 2; }; code_dir_of "$2" ;;
    layout) [ $# -eq 2 ] || { echo "Usage: lib.sh layout <name>" >&2; exit 2; }; layout_of "$2" ;;
    core-paths)
      [ $# -eq 2 ] && [ -n "$2" ] || { echo "Usage: lib.sh core-paths <project>" >&2; exit 2; }
      [ -n "$CORE_DIR" ] || { echo "lib.sh core-paths: no Core path" >&2; exit 1; }
      . "$_LIB_DIR/_locate.sh" || exit 1
      core_paths "$CORE_DIR" "$2" ;;
    *) echo "Usage: lib.sh get <key> | set <key> <value> | ready | core-dir | settings [key[=value] ...] | setting-path | plugin-root | codex-profile | host | role-model <host> <profile> <role> | core-writable <dir> | tree-state <dir> | schema | core-paths <project> | project-of <path> | code-root <path> | code-dir <name> | layout <name>" >&2; exit 2 ;;
  esac
fi
