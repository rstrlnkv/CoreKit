#!/usr/bin/env bash
# The code checkout contains paths to the private instructions, not their contents.
. "$(dirname "$0")/lib.sh"
new_sandbox
export CORE_DIR="$SANDBOX/Custom location/Private Rules"
setup_core
P="$CORE_DIR/entry-app"; C="${CORE_DIR%/*}/entry-app"; A="$C/AGENTS.md"
SC="$SKILL/scripts/scaffold.sh"
assert_exit 0 bash "$SC" --name entry-app --dry-run
assert_no_file "$A"
assert_exit 0 bash "$SC" --name entry-app
assert_file "$CORE_DIR/AGENTS.md"
assert_file "$A"
[ ! -L "$A" ] && pass || fail "scaffold made a symlink"
assert_contains "$A" "$CORE_DIR/AGENTS.md"
assert_contains "$A" "$P/AGENTS.md"
assert_not_contains "$A" 'PRIVATE SENTINEL'
git -C "$C" check-ignore -q -- AGENTS.md && pass || fail "entry file is not ignored"
cp "$A" "$SANDBOX/expected"
assert_exit 0 bash "$SC" --name entry-app
cmp -s "$A" "$SANDBOX/expected" && pass || fail "scaffold rerun changed the file"
locate_core() { env -u CORE_DIR -u CLAUDE_PLUGIN_OPTION_CORE_DIR bash -c '
  cd "$1" && . "$2/lib.sh" && . "$2/_locate.sh" && locate && printf "%s\n" "$CORE"
' _ "$1" "$SCRIPTS"; }
assert_exit 0 locate_core "$C"
assert_eq "$OUT" "$CORE_DIR" 'save and undo can still locate an unconfigured non-default Core'
ALT="${CORE_DIR%/*}/Core"
assert_exit 0 bash "$SCRIPTS/setup-core.sh" "$ALT"
mkdir -p "$HOME" "$ALT/entry-app"
ln -s "${CORE_DIR%/*}" "$HOME/Projects"
printf 'Other project\n' > "$ALT/entry-app/CLAUDE.md"
assert_exit 0 locate_core "$C"
assert_eq "$OUT" "$CORE_DIR" 'the generated entry wins over the same name in the default Core'
ln -s "$ALT/entry-app/CLAUDE.md" "$C/CLAUDE.local.md"
assert_exit 0 locate_core "$C"
assert_eq "$OUT" "$CORE_DIR" 'the generated entry wins over an unrelated legacy link'
assert_exit 0 locate_core "$ALT/entry-app"
assert_eq "$OUT" "$ALT" 'an explicitly opened Core project keeps its own Core'
rm "$C/CLAUDE.local.md"

git -C "$CORE_DIR" ls-files --error-unmatch -- AGENTS.md >/dev/null && pass || fail 'Core root instructions are not tracked'
mv "$CORE_DIR/AGENTS.md" "$SANDBOX/root-rules"
assert_exit 0 bash "$SCRIPTS/lib.sh" core-paths entry-app
printf '%s\n' "$OUT" | tr ' ' '\n' | grep -qx AGENTS.md && pass || fail 'save and clean-tree checks omit deleted Core root instructions'
mv "$SANDBOX/root-rules" "$CORE_DIR/AGENTS.md"

prepare() { bash "$SCRIPTS/prepare.sh" --cwd "$C" --part project; }
rm "$A"; ln -s '../Private Rules/entry-app/AGENTS.md' "$A"
printf '\nPRIVATE SENTINEL\n' >> "$P/AGENTS.md"
assert_exit 0 prepare
[ ! -L "$A" ] && pass || fail "prepare kept the old managed relative symlink"
cmp -s "$A" "$SANDBOX/expected" && pass || fail "prepare did not write the same pointer as scaffold"
assert_not_contains "$A" 'PRIVATE SENTINEL'
assert_contains "$P/AGENTS.md" 'PRIVATE SENTINEL'
assert_exit 0 prepare
assert_eq "$OUT" '' 'prepare rerun is silent'
cp "$C/.gitignore" "$SANDBOX/gitignore"
printf '\n!/AGENTS.md\n' >> "$C/.gitignore"
assert_exit 0 prepare
case "$OUT" in *'must be ignored by Git'*) pass ;; *) fail 'prepare was silent after the ignore rule stopped applying' ;; esac
cmp -s "$A" "$SANDBOX/expected" && pass || fail 'prepare changed the unignored entry'
mv "$SANDBOX/gitignore" "$C/.gitignore"

rm "$A"; printf 'User instructions\n' > "$A"
assert_exit 0 prepare
assert_contains "$A" 'User instructions'
rm "$A"; ln -s "$SANDBOX/missing" "$A"
assert_exit 0 prepare
assert_eq "$(readlink "$A")" "$SANDBOX/missing" 'unrelated dangling link stays'
rm "$A"; ln -s "$P/AGENTS.md"$'\n' "$A"
assert_exit 0 prepare
assert_eq "$(readlink -n "$A"; printf '.')" "$P/AGENTS.md"$'\n.' 'link whose target ends in a newline stays'
rm "$A"; ln -s "$P/AGENTS.md" "$A"
mkdir "$SANDBOX/bin"
printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/bin/mv"
chmod +x "$SANDBOX/bin/mv"
assert_exit 0 env PATH="$SANDBOX/bin:$PATH" bash "$SCRIPTS/prepare.sh" --cwd "$C" --part project
assert_contains "$P/AGENTS.md" 'PRIVATE SENTINEL'
assert_eq "$(readlink "$A")" "$P/AGENTS.md" 'publish failure leaves the old link intact'
git -C "$C" add -f -- AGENTS.md
assert_exit 0 prepare
assert_eq "$(readlink "$A")" "$P/AGENTS.md" 'tracked link stays even with an ignore rule'
finish
