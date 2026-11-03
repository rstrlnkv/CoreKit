#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
LIB="$SCRIPTS/lib.sh"
new_sandbox; unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_ATTRIBUTION CLAUDE_PLUGIN_OPTION_MODEL_PROFILE
export HOME="$SANDBOX/home"; mkdir -p "$HOME"

# settings <VAR> — load_settings in a clean shell (sees this script's environment), print one variable
settings() { bash -c '. "$1"; load_settings; eval "printf %s \"\$$2\""' _ "$LIB" "$1"; }
real() { (cd -P "$1" && pwd); }

# defaults
assert_eq "$(settings CORE_DIR)" "$HOME/Projects/Core" "default CORE_DIR"
assert_eq "$(settings CORE_NAME)" "Core" "default CORE_NAME"
assert_eq "$(settings ATTRIBUTION)" "allow" "default ATTRIBUTION"
assert_eq "$(settings MODEL_PROFILE)" "balanced" "default MODEL_PROFILE"
assert_eq "$(settings APP_ID_PREFIX)" "" "default APP_ID_PREFIX"

# plugin options
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid settings ATTRIBUTION)" "forbid"
assert_eq "$(CLAUDE_PLUGIN_OPTION_MODEL_PROFILE=strong settings MODEL_PROFILE)" "strong"

# CORE_DIR: env wins over the plugin option; option used when env is unset or empty
assert_eq "$(CORE_DIR="$SANDBOX/env" CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$SANDBOX/env" "env wins"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$SANDBOX/opt" "option used"
assert_eq "$(CORE_DIR= CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$SANDBOX/opt" "option used when env empty"
assert_eq "$(CORE_DIR="$SANDBOX/x/Docs" settings CORE_NAME)" "Docs" "CORE_NAME is basename"

# ~ expansion and trailing slash
assert_eq "$(CORE_DIR='~/x' settings CORE_DIR)" "$HOME/x" "~/x"
assert_eq "$(CORE_DIR='~/x/' settings CORE_DIR)" "$HOME/x" "~/x/"
assert_eq "$(CORE_DIR='~' settings CORE_DIR)" "$(real "$HOME")" "~ alone"
assert_eq "$(CORE_DIR="$SANDBOX/y///" settings CORE_DIR)" "$SANDBOX/y" "trailing slashes"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR='~/o' settings CORE_DIR)" "$HOME/o" "~ in the option"

# a symlinked directory resolves to its target
mkdir -p "$SANDBOX/target"; ln -s "$SANDBOX/target" "$SANDBOX/link"
assert_eq "$(CORE_DIR="$SANDBOX/link" settings CORE_DIR)" "$(real "$SANDBOX/target")" "symlink"

# spaces and Cyrillic round-trip, missing and existing
SP="$SANDBOX/My Projects/Ядро"
assert_eq "$(CORE_DIR="$SP" settings CORE_DIR)" "$SP" "space+Cyrillic (missing)"
assert_eq "$(CORE_DIR="$SP" settings CORE_NAME)" "Ядро" "CORE_NAME Cyrillic"
mkdir -p "$SP"
assert_eq "$(CORE_DIR="$SP" settings CORE_DIR)" "$(real "$SP")" "space+Cyrillic (existing)"

# .coredev: set, load, set twice keeps one line, other lines survive
export CORE_DIR="$SANDBOX/Projects/Core"
assert_exit 0 bash -c '. "$1"; load_settings; coredev_set app-id-prefix com.test' _ "$LIB"
assert_file "$CORE_DIR/.coredev"
assert_eq "$(settings APP_ID_PREFIX)" "com.test"
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
bash -c '. "$1"; load_settings; coredev_set app-id-prefix com.one; coredev_set app-id-prefix com.two' _ "$LIB"
assert_eq "$(grep -c '^app-id-prefix:' "$CORE_DIR/.coredev")" "1" "one app-id-prefix line"
assert_eq "$(settings APP_ID_PREFIX)" "com.two"
assert_contains "$CORE_DIR/.coredev" "schema: 1"
assert_eq "$(bash -c '. "$1"; load_settings; coredev_get schema' _ "$LIB")" "1" "coredev_get"
assert_eq "$(bash -c '. "$1"; load_settings; coredev_get nothing' _ "$LIB")" "" "coredev_get missing key"
# CLI entry: bash lib.sh get|set <key> [value]
assert_exit 0 bash "$LIB" set app-id-prefix com.cli
assert_eq "$(bash "$LIB" get app-id-prefix)" "com.cli" "CLI get"
assert_eq "$(settings APP_ID_PREFIX)" "com.cli"

# invalid app id prefix is refused and the file is unchanged
before=$(cat "$CORE_DIR/.coredev")
assert_exit 2 bash "$LIB" set app-id-prefix "Com Test"
assert_exit 2 bash "$LIB" set app-id-prefix 'x$(y)'
assert_eq "$(cat "$CORE_DIR/.coredev")" "$before" ".coredev changed by invalid input"

# the settings file is read, never executed
printf 'app-id-prefix: $(touch %s/pwned)\n' "$SANDBOX" > "$CORE_DIR/.coredev"
assert_eq "$(settings APP_ID_PREFIX)" "\$(touch $SANDBOX/pwned)" "literal value"
assert_eq "$(bash "$LIB" get app-id-prefix)" "\$(touch $SANDBOX/pwned)" "literal value via CLI"
assert_no_file "$SANDBOX/pwned"

# scaffold uses the plugin option when CORE_DIR is unset
unset CORE_DIR
CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/optcore" bash "$SKILL/scripts/scaffold.sh" --name opt-app >/dev/null
assert_file "$SANDBOX/optcore/opt-app/CLAUDE.md"
assert_contains "$SANDBOX/optcore/opt-app/CLAUDE.md" "optcore"
finish
