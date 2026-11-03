#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
CFG="$SKILL/scripts/configure.sh"
new_sandbox; unset CORE_DIR; export HOME="$SANDBOX/home"; mkdir -p "$HOME"
val() { echo "$OUT" | sed -n "s/^$1=//p"; }

# defaults when not configured
assert_exit 0 bash "$CFG" --show
assert_eq "$(val configured)" "no"; assert_eq "$(val PROJECTS_DIR)" "$HOME/Projects"
assert_eq "$(val CORE_NAME)" "Core"; assert_eq "$(val CORE_DIR)" "$HOME/Projects/Core"

# write and read back
assert_exit 0 bash "$CFG" --projects-dir "$SANDBOX/dev" --core-name Docs --app-id-prefix com.test
assert_file "$NEW_PROJECT_CONFIG"
assert_exit 0 bash "$CFG" --show
assert_eq "$(val configured)" "yes"; assert_eq "$(val CORE_DIR)" "$SANDBOX/dev/Docs"
assert_eq "$(val APP_ID_PREFIX)" "com.test"

# invalid values are refused and the file is unchanged
before=$(cat "$NEW_PROJECT_CONFIG")
assert_exit 2 bash "$CFG" --projects-dir relative/path
assert_exit 2 bash "$CFG" --core-name "my docs"
assert_exit 2 bash "$CFG" --app-id-prefix "Com Test"
assert_eq "$(cat "$NEW_PROJECT_CONFIG")" "$before" "config changed by invalid input"

# scaffold uses the config; CORE_DIR env still overrides
bash "$SKILL/scripts/scaffold.sh" --name cfg-app >/dev/null
assert_file "$SANDBOX/dev/Docs/cfg-app/CLAUDE.md"
assert_contains "$SANDBOX/dev/Docs/cfg-app/CLAUDE.md" "Docs"
CORE_DIR="$SANDBOX/override" bash "$SKILL/scripts/scaffold.sh" --name env-app >/dev/null
assert_file "$SANDBOX/override/env-app/CLAUDE.md"

# the config file is parsed, never executed
printf 'PROJECTS_DIR=$(touch %s/pwned)\n' "$SANDBOX" > "$NEW_PROJECT_CONFIG"
bash "$CFG" --show >/dev/null 2>&1
assert_no_file "$SANDBOX/pwned"
finish
