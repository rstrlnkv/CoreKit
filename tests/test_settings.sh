#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
LIB="$SCRIPTS/lib.sh"
new_sandbox; unset CORE_DIR CLAUDE_PLUGIN_OPTION_CORE_DIR CLAUDE_PLUGIN_OPTION_ATTRIBUTION CLAUDE_PLUGIN_OPTION_MODEL_PROFILE
export HOME="$SANDBOX/home"; mkdir -p "$HOME"

# settings <VAR> — load_settings in a clean shell (sees this script's environment), print one variable
settings() { bash -c '. "$1"; load_settings; eval "printf %s \"\$$2\""' _ "$LIB" "$1"; }
# profile / prefix — the two values no script reads from a variable, through the CLI (stderr is not part of the value)
profile() { local o; o="$(bash "$LIB" settings model_profile 2>/dev/null)"; printf %s "${o#model_profile: }"; }
prefix() { bash "$LIB" get app-id-prefix; }
real() { (cd -P "$1" && pwd); }
RS="$(real "$SANDBOX")"   # canonical sandbox (macOS: /var -> /private/var)
RH="$(real "$HOME")"

# defaults
assert_eq "$(settings CORE_DIR)" "$RH/Projects/Core" "default CORE_DIR"
assert_eq "$(settings CORE_NAME)" "Core" "default CORE_NAME"
assert_eq "$(settings ATTRIBUTION)" "allow" "default ATTRIBUTION"
assert_eq "$(profile)" "balanced" "default model_profile"
assert_eq "$(prefix)" "" "default app-id-prefix"

# plugin options
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid settings ATTRIBUTION)" "forbid"
assert_eq "$(CLAUDE_PLUGIN_OPTION_MODEL_PROFILE=strong profile)" "strong"

# CORE_DIR: env wins over the plugin option; option used when env is unset or empty
assert_eq "$(CORE_DIR="$SANDBOX/env" CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$RS/env" "env wins"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$RS/opt" "option used"
assert_eq "$(CORE_DIR= CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$RS/opt" "option used when env empty"
assert_eq "$(CORE_DIR="$SANDBOX/x/Docs" settings CORE_NAME)" "Docs" "CORE_NAME is basename"

# an unsubstituted ${user_config.*} placeholder counts as unset (plugin not configured)
assert_eq "$(CORE_DIR='${user_config.core_dir}' settings CORE_DIR)" "$RH/Projects/Core" "literal placeholder -> default"
assert_eq "$(CORE_DIR='${user_config.core_dir}' CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$RS/opt" "literal placeholder -> option"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR='${user_config.core_dir}' settings CORE_DIR)" "$RH/Projects/Core" "literal in the option -> default"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION='${user_config.attribution}' settings ATTRIBUTION)" "allow" "literal attribution -> default"
assert_eq "$(CLAUDE_PLUGIN_OPTION_MODEL_PROFILE='${user_config.model_profile}' profile)" "balanced" "literal model_profile -> default"
# ... and gives no warning: an unconfigured plugin is not a mistake of the person. Beside it, a really invalid option does warn.
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR='${user_config.core_dir}' CLAUDE_PLUGIN_OPTION_ATTRIBUTION='${user_config.attribution}' CLAUDE_PLUGIN_OPTION_MODEL_PROFILE='${user_config.model_profile}' bash "$LIB" settings core_dir attribution model_profile 2>&1 >/dev/null)" \
  "" "an unsubstituted option gives no warning"
err="$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=maybe bash "$LIB" settings attribution 2>&1 >/dev/null)"
case "$err" in *'attribution "maybe"'*'is not valid'*) pass ;; *) fail "an invalid option gives a warning: $err" ;; esac

# ~ expansion and trailing slash
assert_eq "$(CORE_DIR='~/x' settings CORE_DIR)" "$RH/x" "~/x"
assert_eq "$(CORE_DIR='~/x/' settings CORE_DIR)" "$RH/x" "~/x/"
assert_eq "$(CORE_DIR='~' settings CORE_DIR)" "$RH" "~ alone"
assert_eq "$(CORE_DIR="$SANDBOX/y///" settings CORE_DIR)" "$RS/y" "trailing slashes"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR='~/o' settings CORE_DIR)" "$RH/o" "~ in the option"

# a symlinked directory resolves to its target
mkdir -p "$SANDBOX/target"; ln -s "$SANDBOX/target" "$SANDBOX/link"
assert_eq "$(CORE_DIR="$SANDBOX/link" settings CORE_DIR)" "$(real "$SANDBOX/target")" "symlink"

# a missing dir under a symlinked parent has the same form before and after it is created
mkdir -p "$SANDBOX/realp"; ln -s "$SANDBOX/realp" "$SANDBOX/linkp"
before=$(CORE_DIR="$SANDBOX/linkp/a/b/Core" settings CORE_DIR)
assert_eq "$before" "$RS/realp/a/b/Core" "missing dir under symlink is canonical"
mkdir -p "$SANDBOX/linkp/a/b/Core"
assert_eq "$(CORE_DIR="$SANDBOX/linkp/a/b/Core" settings CORE_DIR)" "$before" "same string after mkdir"
assert_eq "$(CORE_DIR="$SANDBOX/linkp/zz/" settings CORE_DIR)" "$RS/realp/zz" "missing, trailing slash"

# spaces and Cyrillic round-trip, missing and existing
SP="$SANDBOX/My Projects/Ядро"
assert_eq "$(CORE_DIR="$SP" settings CORE_DIR)" "$RS/My Projects/Ядро" "space+Cyrillic (missing)"
assert_eq "$(CORE_DIR="$SP" settings CORE_NAME)" "Ядро" "CORE_NAME Cyrillic"
mkdir -p "$SP"
assert_eq "$(CORE_DIR="$SP" settings CORE_DIR)" "$(real "$SP")" "space+Cyrillic (existing)"

# .coredev: set, load, set twice keeps one line, other lines survive
export CORE_DIR="$SANDBOX/Projects/Core"
assert_exit 0 bash -c '. "$1"; load_settings; coredev_set app-id-prefix com.test' _ "$LIB"
assert_file "$CORE_DIR/.coredev"
assert_eq "$(prefix)" "com.test"
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
bash -c '. "$1"; load_settings; coredev_set app-id-prefix com.one; coredev_set app-id-prefix com.two' _ "$LIB"
assert_eq "$(grep -c '^app-id-prefix:' "$CORE_DIR/.coredev")" "1" "one app-id-prefix line"
assert_eq "$(prefix)" "com.two"
assert_contains "$CORE_DIR/.coredev" "schema: 1"
assert_eq "$(bash -c '. "$1"; load_settings; coredev_get schema' _ "$LIB")" "1" "coredev_get"
assert_eq "$(bash -c '. "$1"; load_settings; coredev_get nothing' _ "$LIB")" "" "coredev_get missing key"
# CLI entry: bash lib.sh get|set <key> [value]
assert_exit 0 bash "$LIB" set app-id-prefix com.cli
assert_eq "$(prefix)" "com.cli" "CLI get"
# a .coredev with CRLF line ends: the value comes back without the CR, and the next line is its own key
printf 'app-id-prefix: com.crlf\r\nschema: 7\r\n' > "$CORE_DIR/.coredev"
assert_eq "$(prefix | od -c | tr -s ' ' | tr '\n' ' ')" "$(printf 'com.crlf\n' | od -c | tr -s ' ' | tr '\n' ' ')" "CRLF .coredev: the value has no CR"
assert_eq "$(bash "$LIB" get schema)" "7" "CRLF .coredev: the line after it"
printf 'schema: 1\napp-id-prefix: com.cli\n' > "$CORE_DIR/.coredev"

# invalid app id prefix is refused and the file is unchanged
before=$(cat "$CORE_DIR/.coredev")
assert_exit 2 bash "$LIB" set app-id-prefix "Com Test"
assert_exit 2 bash "$LIB" set app-id-prefix 'x$(y)'
assert_eq "$(cat "$CORE_DIR/.coredev")" "$before" ".coredev changed by invalid input"

# the settings file is read, never executed
printf 'app-id-prefix: $(touch %s/pwned)\n' "$SANDBOX" > "$CORE_DIR/.coredev"
assert_eq "$(prefix)" "\$(touch $SANDBOX/pwned)" "literal value via CLI"
assert_no_file "$SANDBOX/pwned"

# canon_dir of the filesystem root
assert_eq "$(bash -c '. "$1"; canon_dir /' _ "$LIB")" "/" "canon_dir /"
assert_eq "$(bash -c '. "$1"; canon_dir //' _ "$LIB")" "/" "canon_dir //"
assert_eq "$(bash -c '. "$1"; canon_dir /nonexistent-zz' _ "$LIB")" "/nonexistent-zz" "canon_dir below /"

# core_ready: true only when .coredev has a "schema: <n>" line
ready() { CORE_DIR="$1" bash -c '. "$1"; core_ready' _ "$LIB"; }
RD="$SANDBOX/ready"; mkdir -p "$RD"
ready "$RD" && fail "ready without .coredev" || pass
printf 'app-id-prefix: com.x\n' > "$RD/.coredev"
ready "$RD" && fail "ready with prefix only" || pass
printf 'schema: x\n' > "$RD/.coredev"
ready "$RD" && fail "ready with schema: x" || pass
printf 'schema:\n' > "$RD/.coredev"
ready "$RD" && fail "ready with empty schema" || pass
printf 'app-id-prefix: com.x\nschema: 1\n' > "$RD/.coredev"
ready "$RD" && pass || fail "not ready with schema: 1 on line 2"
printf 'schema: 12\r\n' > "$RD/.coredev"
ready "$RD" && pass || fail "not ready with CRLF schema line"
# CLI form
CORE_DIR="$RD" bash "$LIB" ready && pass || fail "CLI ready should exit 0"
printf 'x: y\n' > "$RD/.coredev"
CORE_DIR="$RD" bash "$LIB" ready && fail "CLI ready should exit 1" || pass
# the unset CORE_DIR in a sourced shell does not make a bogus path ready
CORE_DIR= bash -c '. "$1"; core_ready' _ "$LIB" && fail "ready with empty CORE_DIR" || pass

# core-dir prints the absolute Core path
assert_eq "$(CORE_DIR="$RD" bash "$LIB" core-dir)" "$RD" "core-dir prints CORE_DIR"
assert_eq "$(CORE_DIR='${user_config.core_dir}' HOME="$SANDBOX/h" bash "$LIB" core-dir)" "$SANDBOX/h/Projects/Core" "core-dir ignores an unsubstituted placeholder"
assert_eq "$(CORE_DIR='~/xx' HOME="$SANDBOX/h" bash "$LIB" core-dir)" "$SANDBOX/h/xx" "core-dir expands ~"

# schema: the plugin's layout schema number lives in lib.sh and setup-core.sh writes it
SCH="$(bash "$LIB" schema)"
case "$SCH" in ""|*[!0-9]*) fail "lib.sh schema is not a number: '$SCH'" ;; *) pass ;; esac
assert_eq "$(CORE_DIR="$RD" bash "$LIB" schema)" "$SCH" "schema does not depend on the Core"
assert_eq "$(bash "$LIB" schema | wc -l | tr -d ' ')" "1" "schema prints one line"
assert_contains "$LIB" 'COREDEV_SCHEMA='
assert_contains "$LIB" 'schema) printf'
SC="$SANDBOX/schemacore"; CORE_DIR="$SC" bash "$SCRIPTS/setup-core.sh" "$SC" >/dev/null
assert_eq "$(CORE_DIR="$SC" bash "$LIB" get schema)" "$SCH" "setup-core writes the plugin schema"
assert_contains "$SCRIPTS/setup-core.sh" 'schema: $COREDEV_SCHEMA'
assert_not_contains "$SCRIPTS/setup-core.sh" 'echo "schema: 1"'

# scaffold uses the plugin option when CORE_DIR is unset
unset CORE_DIR
mkdir -p "$SANDBOX/optcore"; CORE_DIR="$SANDBOX/optcore" setup_core
CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/optcore" bash "$SKILL/scripts/scaffold.sh" --name opt-app >/dev/null
assert_file "$SANDBOX/optcore/opt-app/CLAUDE.md"
assert_contains "$SANDBOX/optcore/opt-app/CLAUDE.md" "optcore"

# --- settings file: ~/.config/corecrew/settings (or $CORECREW_CONFIG), "key: value" lines, never executed
unset CORE_DIR CLAUDE_PLUGIN_OPTION_UI_LANGUAGE CORECREW_CONFIG
SF="$SANDBOX/xdg/corecrew/settings"; mkdir -p "$SANDBOX/xdg/corecrew"
sfw() { printf '%b' "$1" > "$SF"; }
rm -f "$SF"
assert_eq "$(settings UI_LANGUAGE)" "en" "default UI_LANGUAGE"
assert_eq "$(bash "$LIB" setting-path)" "$SANDBOX/xdg/corecrew/settings" "setting-path from XDG_CONFIG_HOME"
assert_eq "$(env -u XDG_CONFIG_HOME bash "$LIB" setting-path)" "$HOME/.config/corecrew/settings" "setting-path default"
assert_eq "$(XDG_CONFIG_HOME=rel bash "$LIB" setting-path)" "$HOME/.config/corecrew/settings" "relative XDG_CONFIG_HOME ignored"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/c.txt" bash "$LIB" setting-path)" "$SANDBOX/c.txt" "setting-path from CORECREW_CONFIG"
sfw 'core_dir: ~/FromFile\nattribution: forbid\nmodel_profile: strong\nui_language: ru\n'
assert_eq "$(settings CORE_DIR)" "$RH/FromFile" "file core_dir"
assert_eq "$(settings ATTRIBUTION)" "forbid" "file attribution"
assert_eq "$(profile)" "strong" "file model_profile"
assert_eq "$(settings UI_LANGUAGE)" "ru" "file ui_language"
# format: quotes, spaces, comments, blanks, CRLF, unknown key, duplicates, leading blanks
sfw '# comment\n\n  core_dir: "'"$SANDBOX"'/My Core"\r\nbogus: 1\nattribution: '"'forbid'"'\nattribution: allow\n   model_profile:   economy  \n'
assert_eq "$(settings CORE_DIR)" "$SANDBOX/My Core" "quoted core_dir with a space, CRLF"
assert_eq "$(settings ATTRIBUTION)" "forbid" "single quotes, first occurrence wins"
assert_eq "$(profile)" "economy" "leading blanks and trimmed value"
# precedence: option > file; env CORE_DIR > option; placeholder falls through
sfw 'core_dir: '"$SANDBOX"'/file\nattribution: forbid\n'
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$SANDBOX/opt" "option beats file"
assert_eq "$(CORE_DIR="$SANDBOX/env" CLAUDE_PLUGIN_OPTION_CORE_DIR="$SANDBOX/opt" settings CORE_DIR)" "$SANDBOX/env" "env beats both"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR='${user_config.core_dir}' settings CORE_DIR)" "$SANDBOX/file" "placeholder option falls to file"
assert_eq "$(CORE_DIR='${user_config.core_dir}' settings CORE_DIR)" "$SANDBOX/file" "placeholder env falls to file"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=allow settings ATTRIBUTION)" "allow" "option beats file (attribution)"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION='${user_config.attribution}' settings ATTRIBUTION)" "forbid" "placeholder attribution falls to file"
# CORECREW_CONFIG, missing, empty, a directory
printf 'attribution: forbid\n' > "$SANDBOX/other"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/other" settings ATTRIBUTION)" "forbid" "CORECREW_CONFIG file"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/none" settings ATTRIBUTION)" "allow" "missing CORECREW_CONFIG file -> default"
: > "$SANDBOX/empty"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/empty" settings ATTRIBUTION)" "allow" "empty file -> default"
assert_eq "$(CORECREW_CONFIG="$SANDBOX" settings ATTRIBUTION)" "allow" "directory as CORECREW_CONFIG -> default"
# never executed
sfw 'core_dir: $(touch '"$SANDBOX"'/pwned)\nx; touch '"$SANDBOX"'/pwned2\nui_language: `touch '"$SANDBOX"'/pwned3`\n'
settings CORE_DIR >/dev/null 2>&1; settings UI_LANGUAGE >/dev/null 2>&1
assert_no_file "$SANDBOX/pwned"; assert_no_file "$SANDBOX/pwned2"; assert_no_file "$SANDBOX/pwned3"
# a relative core_dir is never made <cwd>/Core: it is ignored and the next source (or the default) is used
mkdir -p "$SANDBOX/cwd/Core"
for bad in Core ./Core '~bob/x' '$HOME/x' ../Core; do
  sfw "core_dir: $bad\n"
  assert_eq "$(cd "$SANDBOX/cwd" && settings CORE_DIR)" "$RH/Projects/Core" "file core_dir '$bad' ignored"
  assert_eq "$(cd "$SANDBOX/cwd" && CLAUDE_PLUGIN_OPTION_CORE_DIR="$bad" settings CORE_DIR)" "$RH/Projects/Core" "option core_dir '$bad' ignored"
  assert_eq "$(cd "$SANDBOX/cwd" && CORE_DIR="$bad" settings CORE_DIR)" "$RH/Projects/Core" "env core_dir '$bad' ignored"
done
sfw 'core_dir: '"$SANDBOX"'/file\n'
assert_eq "$(cd "$SANDBOX/cwd" && CLAUDE_PLUGIN_OPTION_CORE_DIR=Core settings CORE_DIR)" "$SANDBOX/file" "invalid option falls to the file"
# core-dir CLI: stdout is the path only; one stderr line for an invalid value
sfw 'core_dir: Core\n'
OUTO="$(cd "$SANDBOX/cwd" && bash "$LIB" core-dir 2>"$SANDBOX/err")"
assert_eq "$OUTO" "$RH/Projects/Core" "core-dir stdout with an invalid core_dir"
assert_eq "$(wc -l < "$SANDBOX/err" | tr -d ' ')" "1" "core-dir: one warning line"
assert_contains "$SANDBOX/err" '"Core"'; assert_contains "$SANDBOX/err" 'absolute'
sfw 'core_dir: ~/ok\n'
bash "$LIB" core-dir >/dev/null 2>"$SANDBOX/err"; assert_eq "$(cat "$SANDBOX/err")" "" "valid value: no stderr"
sfw 'attribution: forbbid\n'
assert_eq "$(settings ATTRIBUTION)" "allow" "invalid attribution -> allow"
bash "$LIB" core-dir >/dev/null 2>"$SANDBOX/err"; assert_contains "$SANDBOX/err" 'attribution'
# lib.sh settings
sfw 'core_dir: ~/S\nattribution: forbid\nmodel_profile: strong\nui_language: ru\n'
assert_eq "$(bash "$LIB" settings)" "core_dir: $RH/S
attribution: forbid
model_profile: strong
ui_language: ru" "settings prints four lines"
assert_eq "$(bash "$LIB" settings attribution model_profile)" "attribution: forbid
model_profile: strong" "settings with key names"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=allow bash "$LIB" settings attribution=forbid)" "attribution: forbid" "argument beats ambient option"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION=allow bash "$LIB" settings attribution=allow)" "attribution: allow" "argument allow"
assert_eq "$(bash "$LIB" settings 'attribution=${user_config.attribution}' 'model_profile=${user_config.model_profile}')" "attribution: forbid
model_profile: strong" "placeholder arguments fall to the file"
assert_eq "$(bash "$LIB" settings attribution=forbbid 2>/dev/null)" "attribution: forbid" "invalid argument falls to the file"
assert_exit 2 bash "$LIB" settings nosuchkey
# --- tester pass: odd settings-file shapes (pinned behaviour)
sfw 'core_dir: '"$SANDBOX"'/nonl'; printf '%s' "core_dir: $SANDBOX/nonl" > "$SF"
assert_eq "$(settings CORE_DIR)" "$RS/nonl" "last line without a trailing newline is read"
sfw 'core_dir:\t'"$SANDBOX"'/tab\n'
assert_eq "$(settings CORE_DIR)" "$RS/tab" "tab before the value is trimmed"
sfw 'core_dir: ~\n'
assert_eq "$(settings CORE_DIR)" "$RH" "core_dir: ~ alone is HOME"
sfw 'core_dir: ~/\n'
assert_eq "$(settings CORE_DIR)" "$RH" "core_dir: ~/ is HOME"
sfw 'core_dir: /\n'
assert_eq "$(settings CORE_DIR)" "/" "core_dir: / is the root, not an empty string"
sfw 'core_dir : '"$SANDBOX"'/spaced\nattribution : forbid\n'
assert_eq "$(settings CORE_DIR)" "$RS/spaced" "blanks before the colon: the line is the key"
assert_eq "$(settings ATTRIBUTION)" "forbid" "blanks before the colon: attribution"
printf '\xef\xbb\xbfattribution: forbid\n' > "$SF"
assert_eq "$(settings ATTRIBUTION)" "forbid" "a UTF-8 BOM at the start of the file is skipped"
sfw 'core_dir: '"$SANDBOX"'/first\ncore_dir: '"$SANDBOX"'/second\n'
assert_eq "$(settings CORE_DIR)" "$RS/first" "first occurrence of a key wins"
sfw 'core_dir_x: '"$SANDBOX"'/other\nxcore_dir: '"$SANDBOX"'/other\n'
assert_eq "$(settings CORE_DIR)" "$RH/Projects/Core" "a key that only starts or ends like core_dir is not core_dir"
sfw 'core_dir_x: '"$SANDBOX"'/bad\nxcore_dir: '"$SANDBOX"'/bad\ncore_dir: '"$SANDBOX"'/good\n'
assert_eq "$(settings CORE_DIR)" "$RS/good" "lookalike keys before the real one are skipped"
sfw 'attribution: Forbid\n'
assert_eq "$(settings ATTRIBUTION)" "allow" "values are case-sensitive: Forbid is invalid"
sfw 'core_dir: "\n'
assert_eq "$(settings CORE_DIR)" "$RH/Projects/Core" "a lone quote is a value, not a path: ignored"
# symlinked settings file is followed
printf 'attribution: forbid\n' > "$SANDBOX/real-settings"; ln -sf "$SANDBOX/real-settings" "$SANDBOX/link-settings"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/link-settings" settings ATTRIBUTION)" "forbid" "symlinked settings file is read"
ln -sf "$SANDBOX/dangling-target" "$SANDBOX/dangling"
assert_eq "$(CORECREW_CONFIG="$SANDBOX/dangling" settings ATTRIBUTION)" "allow" "dangling symlink -> default, no crash"
# warning wording: where to fix it and what is used instead, by source
sfw 'attribution: yes\nmodel_profile: fast\n'
ERRW="$(bash "$LIB" settings 2>&1 >/dev/null)"
case "$ERRW" in *'attribution "yes" (settings file)'*'allow or forbid'*"$SF"*'Using "allow"'*) pass ;; *) fail "attribution warning: $ERRW" ;; esac
case "$ERRW" in *'economy, balanced or strong'*'Using "balanced"'*) pass ;; *) fail "model_profile warning: $ERRW" ;; esac
case "$ERRW" in *absolute*) fail "enum warning mentions a path: $ERRW" ;; *) pass ;; esac
ERRW="$(CORE_DIR=rel bash "$LIB" core-dir 2>&1 >/dev/null)"
case "$ERRW" in *'environment variable CORE_DIR'*'Unset or correct the CORE_DIR variable'*'Using ~/Projects/Core'*) pass ;; *) fail "env warning: $ERRW" ;; esac
ERRW="$(CLAUDE_PLUGIN_OPTION_CORE_DIR=rel bash "$LIB" core-dir 2>&1 >/dev/null)"
case "$ERRW" in *"plugin option"*"options in Claude Code"*) pass ;; *) fail "option warning: $ERRW" ;; esac
# one text per warning: the CLI prints the texts of hooks/messages.sh, in English whatever ui_language says
assert_eq "$(cat "$SCRIPTS/lib.sh" "$SCRIPTS/lib-settings.sh" | grep -c 'is not valid')" "0" "no warning text outside hooks/messages.sh"
sfw 'attribution: yes\nui_language: ru\n'
ERRW="$(bash "$LIB" settings attribution 2>&1 >/dev/null)"
case "$ERRW" in 'corecrew: attribution "yes" (settings file) is not valid: use allow or forbid.'*) pass ;; *) fail "CLI warning with ui_language ru: $ERRW" ;; esac
# a lib.sh without hooks/messages.sh beside it (the tools copy) prints no warning; stdout and the exit code stay
mkdir -p "$SANDBOX/nomsg/scripts"; cp "$SCRIPTS"/lib*.sh "$SANDBOX/nomsg/scripts/"
OUTO="$(CORE_DIR=rel bash "$SANDBOX/nomsg/scripts/lib.sh" core-dir 2>"$SANDBOX/err")"; RCO=$?
assert_eq "$RCO" "0" "no messages.sh: core-dir exit"; assert_eq "$OUTO" "$RH/Projects/Core" "no messages.sh: core-dir stdout"
assert_eq "$(cat "$SANDBOX/err")" "" "no messages.sh: no warning"
OUTO="$(bash "$SANDBOX/nomsg/scripts/lib.sh" settings attribution 2>"$SANDBOX/err")"; RCO=$?
assert_eq "$RCO$OUTO" "0attribution: allow" "no messages.sh: settings exit and stdout"
assert_eq "$(cat "$SANDBOX/err")" "" "no messages.sh: settings prints no warning"
sfw ''
# unreadable file: defaults (skipped as root, which reads anything)
printf 'attribution: forbid\n' > "$SANDBOX/unread"; chmod 000 "$SANDBOX/unread"
if [ ! -r "$SANDBOX/unread" ]; then
  assert_eq "$(CORECREW_CONFIG="$SANDBOX/unread" settings ATTRIBUTION)" "allow" "unreadable settings file -> default"
  assert_eq "$(CORECREW_CONFIG="$SANDBOX/unread" bash "$LIB" settings attribution 2>&1 >/dev/null | wc -l | tr -d ' ')" "1" "unreadable file: one warning line"
  case "$(CORECREW_CONFIG="$SANDBOX/unread" bash "$LIB" core-dir 2>&1 >/dev/null)" in *"$SANDBOX/unread cannot be read"*) pass ;; *) fail "unreadable file warning" ;; esac
fi
chmod 600 "$SANDBOX/unread"
# a relative XDG_CONFIG_HOME is not read, even when <cwd>/corecrew/settings exists
mkdir -p "$SANDBOX/cwd2/rel/corecrew"; printf 'attribution: forbid\n' > "$SANDBOX/cwd2/rel/corecrew/settings"; rm -f "$HOME/.config/corecrew/settings"
assert_eq "$(cd "$SANDBOX/cwd2" && XDG_CONFIG_HOME=rel settings ATTRIBUTION)" "allow" "relative XDG_CONFIG_HOME: file under cwd not read"
# a valid file path beats an invalid plugin option, whatever the option says
sfw 'core_dir: '"$SANDBOX"'/winner\n'
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR=Core settings CORE_DIR)" "$RS/winner" "option 'Core' + valid file: the file wins"
assert_eq "$(CLAUDE_PLUGIN_OPTION_CORE_DIR=Core bash "$LIB" core-dir 2>&1 >/dev/null | grep -c 'plugin option')" "1" "option 'Core' is named in the warning"
# a relative env CORE_DIR (as _locate.sh could pass) never survives load_settings
sfw ''
assert_eq "$(cd "$SANDBOX/cwd" && CORE_DIR=. settings CORE_DIR)" "$RH/Projects/Core" "CORE_DIR=. is ignored"
# zsh runs the task skill's Start line with literal placeholders
if command -v zsh >/dev/null 2>&1; then
  sfw 'attribution: forbid\nmodel_profile: strong\n'
  assert_eq "$(zsh -c 'bash "$1" settings attribution='"'"'${user_config.attribution}'"'"' model_profile='"'"'${user_config.model_profile}'"'"'' _ "$LIB")" "attribution: forbid
model_profile: strong" "zsh: literal placeholders fall to the file"
else
  skip zsh-placeholders "zsh not on PATH"
fi

# --- load_settings (every hook, save, undo-step and adopt run it) starts no program and no subshell but canon_dir's
# one `cd -P` for each of the two paths; a settings file adds three: its size, twice, and the awk that reads it
subs() { bash -c '. "$1"; PS4=+; set -x; load_settings' _ "$LIB" 2>&1 | awk '/^\+\+/ && prev !~ /^\+\+/ {s++} {prev=$0} END{print s+0}'; }
rm -f "$SF"
assert_eq "$(subs)" "2" "load_settings, no settings file: command substitutions"
# shellcheck disable=SC1090
assert_eq "$( ( . "$LIB"; count_execs load_settings; printf '%s:%s' "$EXECS" "$(tr '\n' ' ' < "$EXEC_LOG")" ) )" "0:" \
  "load_settings, no settings file: programs started"
sfw 'attribution: forbid\n'
assert_eq "$(subs)" "5" "load_settings with a settings file: command substitutions"
# trailing newlines are dropped where $(...) dropped them: an option value, a settings file path, a Core path, HOME
sq() { bash -c '. "$1"; load_settings; printf "[%s]" "${!2}"' _ "$LIB" "$1"; }
assert_eq "$(CORECREW_CONFIG="$SF
" sq ATTRIBUTION)" "[forbid]" "a settings file path that ends in a newline"
rm -f "$SF"
assert_eq "$(CLAUDE_PLUGIN_OPTION_ATTRIBUTION="forbid
" CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="ru

" sq ATTRIBUTION; sq UI_LANGUAGE)" "[forbid][en]" "an option value that ends in a newline"
assert_eq "$(CLAUDE_PLUGIN_OPTION_UI_LANGUAGE="ru

" sq UI_LANGUAGE)" "[ru]" "a ui_language option that ends in newlines"
mkdir -p "$SANDBOX/nl
"
assert_eq "$(CORE_DIR="$SANDBOX/nl
/y
" sq CORE_DIR; CORE_DIR="$SANDBOX/nl
/y
" sq PROJECTS_DIR; CORE_DIR="$SANDBOX/nl
/y
" sq CORE_NAME)" "[$RS/nl/y][$RS/nl][y]" "a Core path whose folder name ends in a newline"
assert_eq "$(HOME="$HOME
" CORE_DIR='~' sq CORE_DIR)" "[$RH]" "a HOME that ends in a newline"
assert_eq "$(CORE_DIR=/ sq CORE_NAME; CORE_DIR=/ sq PROJECTS_DIR; CORE_DIR=//x sq PROJECTS_DIR)" "[/][/][/]" "the root as the Core and beside it"
# no writable folder at all, the temp folder included (a read-only Codex sandbox; bash 3.2 writes a here-string to a
# temp file): the settings file is still read and an ignored value is still named. macOS only (sandbox-exec).
NOWRITE='(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))'
if command -v sandbox-exec >/dev/null 2>&1 && [ "$(sandbox-exec -p "$NOWRITE" sh -c ': > "$1" || echo denied' _ "$SANDBOX/nw-probe" 2>/dev/null)" = denied ]; then
  sfw 'core_dir: '"$SANDBOX"'/rofile\nmodel_profile: strong\nattribution: maybe\n'
  assert_eq "$(sandbox-exec -p "$NOWRITE" bash "$LIB" settings core_dir model_profile attribution 2>/dev/null)" \
    "core_dir: $SANDBOX/rofile
model_profile: strong
attribution: allow" "nothing writable: the settings file is read"
  err="$(sandbox-exec -p "$NOWRITE" bash "$LIB" core-dir 2>&1 >/dev/null)"
  case "$err" in *'attribution "maybe"'*'is not valid'*) pass ;; *) fail "nothing writable: no settings warning: $err" ;; esac
  case "$err" in *"here document"*|*"temp file"*) fail "nothing writable: a raw bash error: $err" ;; *) pass ;; esac
  assert_eq "$(sandbox-exec -p "$NOWRITE" bash "$LIB" core-dir 2>/dev/null)" "$SANDBOX/rofile" "nothing writable: core-dir from the file"
else
  skip nothing-writable "no usable sandbox-exec (macOS only)"
fi
# a large settings file under the 64 KB limit with the keys on its last lines: the lookup is linear, so a hook (15 s)
# does not time out. The bound is on the CPU time of the run, which a loaded machine does not stretch.
awk -v d="$RS/sf-large" 'BEGIN { for (i = 0; i < 1150; i++) printf "key%05d: value-%05d-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", i, i
  print "attribution: forbid"; print "model_profile: strong"; print "ui_language: ru"; print "core_dir: " d }' > "$SF"
[ "$(wc -c < "$SF" | tr -d ' ')" -gt 55000 ] && [ "$(wc -c < "$SF" | tr -d ' ')" -le 65536 ] && pass || fail "the large settings file is not between 55 KB and 64 KB"
for loc in C en_US.UTF-8; do
  out="$SANDBOX/sf-large.out"
  cpu="$( { TIMEFORMAT=%U; time LC_ALL="$loc" /bin/bash "$LIB" settings core_dir attribution model_profile ui_language > "$out" 2>/dev/null; } 2>&1 )"
  assert_eq "$(cat "$out")" "core_dir: $RS/sf-large
attribution: forbid
model_profile: strong
ui_language: ru" "large settings file, keys last ($loc)"
  cpu="${cpu%%[.,]*}"
  case "$cpu" in ''|*[!0-9]*) fail "large settings file ($loc): no CPU time measured: $cpu" ;;
    *) [ "$cpu" -lt 3 ] && pass || fail "large settings file ($loc): the lookup took ${cpu}s of CPU time (limit 3)" ;; esac
done
# a value keeps its glob characters and inner blanks, and the caller's noglob state survives a lookup
mkdir -p "$SANDBOX/globdir"; : > "$SANDBOX/globdir/a1"; : > "$SANDBOX/globdir/a2"
sfw 'first: x\nglobby:   '"$SANDBOX"'/globdir/a*   [b]  ?\nempty:\nlast: z\n'
assert_eq "$(cd "$SANDBOX/globdir" && bash -c '. "$1"; load_settings; _sf_get globby' _ "$LIB")" "$SANDBOX/globdir/a*   [b]  ?" "a value with glob characters is data"
assert_eq "$(bash -c '. "$1"; load_settings; _sf_get_r empty; echo "rc=$? [$_SF_V]"; _sf_get_r nokey; echo "rc=$? [$_SF_V]"; _sf_get_r las; echo "rc=$?"' _ "$LIB")" "rc=0 []
rc=1 []
rc=1" "an empty value is found, a missing key and a key prefix are not"
assert_eq "$(bash -c '. "$1"; load_settings; _sf_get_r last; case $- in *f*) echo off ;; *) echo on ;; esac; set -f; _sf_get_r last; case $- in *f*) echo off ;; *) echo on ;; esac; IFS=:; _sf_get_r last; printf "%s" "$IFS"' _ "$LIB")" "on
off
:" "a lookup leaves globbing and IFS as the caller set them"
# load_settings and resolve_setting return 0 when a key, the settings file or .coredev is missing: a caller may run
# under set -e (as on 2104bfb)
rm -f "$SF"; mkdir -p "$SANDBOX/core-nofacts"; printf 'schema: 2\n' > "$SANDBOX/core-nofacts/.coredev"
for cd_ in "$SANDBOX/nocore" "$SANDBOX/core-nofacts"; do
  assert_eq "$(CORE_DIR="$cd_" bash -ec '. "$1"; load_settings; echo ok' _ "$LIB" 2>&1)" "ok" "load_settings under set -e, no settings file ($cd_)"
  assert_eq "$(CORE_DIR="$cd_" bash -c '. "$1"; load_settings; echo "rc=$?"' _ "$LIB" 2>&1)" "rc=0" "load_settings exit code ($cd_)"
done
assert_eq "$(bash -ec '. "$1"; resolve_setting attribution; echo " ok"' _ "$LIB" 2>&1)" "allow ok" "resolve_setting under set -e, no settings file"
sfw 'attribution: forbid\n'
assert_eq "$(CORE_DIR="$SANDBOX/nocore" bash -ec '. "$1"; load_settings; echo "ok $ATTRIBUTION"' _ "$LIB" 2>&1)" "ok forbid" \
  "load_settings under set -e, a settings file without most keys"
assert_eq "$(bash -ec '. "$1"; resolve_setting model_profile; echo " ok"' _ "$LIB" 2>&1)" "balanced ok" "resolve_setting under set -e, key not in the file"
rm -f "$SF"
finish
