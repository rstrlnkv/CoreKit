#!/usr/bin/env bash
# scripts/prepare.sh: what session-start does for hosts whose hooks may not run yet (Codex): tools copy, the
# CLAUDE.local.md / AGENTS.md links (also in a worktree outside the project), layout and git hook notes, the trust note.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR COREKIT_HOST
PREP="$SCRIPTS/prepare.sh"
assert_file "$PREP"
setup_core
bash "$SKILL/scripts/scaffold.sh" --name prep >/dev/null
P="$CORE_DIR/prep"; PR="$(dirname "$CORE_DIR")"; C="$PR/prep"
git -C "$C" commit -q --allow-empty -m init
mkdir -p "$SANDBOX/elsewhere"
VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json" | head -1)"
MARK="$XDG_CONFIG_HOME/corecrew/state/hooks-seen-codex"
# a sandbox profile is chosen (the codex_profile note is tested below), so the other Codex runs stay silent
mkdir -p "$CODEX_HOME"; CFG="$CODEX_HOME/config.toml"; printf 'default_permissions = "corecrew"\n' > "$CFG"
# run <host> [args] — stdout+stderr in OUT, exit code in RC
run() { local h="$1"; shift; OUT="$(COREKIT_HOST="$h" bash "$PREP" "$@" 2>&1)"; RC=$?; }

# --- first run (claude host): tools copy, both links; second run silent
rm -rf "$COREDEV_TOOLS" "$C/CLAUDE.local.md" "$C/AGENTS.md"
run claude --cwd "$C"
assert_eq "$RC" "0" "exit"
assert_file "$COREDEV_TOOLS/VERSION"; assert_file "$COREDEV_TOOLS/save"
assert_eq "$(readlink "$C/CLAUDE.local.md")" "$P/CLAUDE.md" "CLAUDE.local.md link"
assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "AGENTS.md link"
echo "$OUT" | grep -qF "linked CLAUDE.local.md to $P/CLAUDE.md" && pass || fail "link note missing: $OUT"
echo "$OUT" | grep -qF "Codex" && fail "trust note on the claude host: $OUT" || pass
run claude --cwd "$C"; assert_eq "$OUT" "" "second run is silent"
run claude --cwd "$SANDBOX/elsewhere"; assert_eq "$OUT" "" "outside a project: silent"
run claude; assert_eq "$RC" "0" "default cwd: exit"

# --- core.hooksPath set in the code repo: git runs other hooks, so the note names the folder and the chaining command
mkdir -p "$SANDBOX/myhooks"; git -C "$C" config core.hooksPath "$SANDBOX/myhooks"
run claude --cwd "$C"
echo "$OUT" | grep -qF "core.hooksPath" && pass || fail "hooksPath note missing: $OUT"
echo "$OUT" | grep -qF "$SANDBOX/myhooks" && pass || fail "hooksPath note names the folder: $OUT"
echo "$OUT" | grep -qF "install-hooks.sh\" \"$P\"" && pass || fail "hooksPath note names the chaining command: $OUT"
# an empty core.hooksPath: git runs no hooks at all, so the note says to unset it, then to install the shims
git -C "$C" config core.hooksPath ""
run claude --cwd "$C"
echo "$OUT" | grep -qF "git -C \"$C\" config --unset core.hooksPath" && pass || fail "empty hooksPath: the note says to unset it: $OUT"
echo "$OUT" | grep -qF "install-hooks.sh\" \"$P\"" && pass || fail "empty hooksPath: the note names install-hooks: $OUT"
echo "$OUT" | grep -qF "chain" && fail "empty hooksPath: chaining advice: $OUT" || pass
CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run claude --cwd "$C"
echo "$OUT" | grep -qF -- "--unset core.hooksPath" && pass || fail "ru empty hooksPath: the note says to unset it: $OUT"
echo "$OUT" | grep -qF "an empty value" && fail "ru empty hooksPath: English in the note: $OUT" || pass
git -C "$C" config --unset core.hooksPath
run claude --cwd "$C"; assert_eq "$OUT" "" "hooksPath unset: silent again"

# --- the trust note (codex host): no marker, older marker, current marker
run codex --cwd "$C"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "trust note missing: $OUT"
mkdir -p "$(dirname "$MARK")"; echo "0.0.1" > "$MARK"
run codex --cwd "$C"; echo "$OUT" | grep -qF "open /hooks" && pass || fail "older marker: trust note expected: $OUT"
echo "$VER" > "$MARK"
run codex --cwd "$C"; assert_eq "$OUT" "" "current marker: silent"
run codex --cwd "$SANDBOX/elsewhere"; assert_eq "$OUT" "" "current marker, outside a project: silent"
rm -f "$MARK"; run codex --cwd "$SANDBOX/elsewhere"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "trust note outside a project: $OUT"
assert_no_file "$MARK"   # prepare never writes the marker: only the hook can prove it ran
rm -rf "$COREDEV_TOOLS"; rm -f "$C/AGENTS.md"
OUT="$(COREKIT_HOST=codex bash "$PREP" --part host --cwd "$C" 2>&1)"
echo "$OUT" | grep -qF "/hooks" && pass || fail "--part host: $OUT"
# only that part ran: no tools copy made, no link made or named
[ ! -e "$COREDEV_TOOLS" ] && [ ! -L "$C/AGENTS.md" ] && ! echo "$OUT" | grep -qF "AGENTS.md" && pass || fail "--part host ran another part: $OUT"
run claude --cwd "$C"; assert_file "$COREDEV_TOOLS/VERSION"; assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "all parts again: the link is back"
# no marker path known (no settings folder), or no plugin version known (a plugin root with no manifest): the trust
# note. With no version, an absent marker must not count as current, with or without a marker path.
echo "$VER" > "$MARK"
OUT="$(env -u XDG_CONFIG_HOME -u CORECREW_CONFIG HOME="" COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "no marker path: trust note expected: $OUT"
OUT="$(CLAUDE_PLUGIN_ROOT="$SANDBOX/elsewhere" COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "no plugin version: trust note expected: $OUT"
rm -f "$MARK"
OUT="$(CLAUDE_PLUGIN_ROOT="$SANDBOX/elsewhere" COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "no plugin version, no marker: trust note expected: $OUT"
OUT="$(env -u XDG_CONFIG_HOME -u CORECREW_CONFIG HOME="" CLAUDE_PLUGIN_ROOT="$SANDBOX/elsewhere" COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "open /hooks" && pass || fail "no plugin version, no marker path: trust note expected: $OUT"
OUT="$(COREKIT_HOST=codex CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru bash "$PREP" --part host 2>&1)"
echo "$OUT" | grep -qF "Защита corecrew" && pass || fail "ru trust note: $OUT"

# --- the sandbox profile note (Codex only; config.toml is read as data, never written)
echo "$VER" > "$MARK"; CFGHASH="$(cksum < "$CFG")"
run codex --cwd "$C"; assert_eq "$OUT" "" "profile chosen: silent"
assert_eq "$(cksum < "$CFG")" "$CFGHASH" "config.toml untouched"
for body in '# default_permissions = "x"' 'default_permissions = ""' 'model = "o3"' ; do
  printf '%s\n' "$body" > "$CFG"; run codex --part host
  assert_eq "$(printf '%s\n' "$OUT" | grep -c 'codex-profile')" "1" "no profile ($body): the note once"
  echo "$OUT" | grep -qF "$PLUGIN/scripts/lib.sh" && echo "$OUT" | grep -qF "$CFG" && pass || fail "note names lib.sh and config.toml: $OUT"
  assert_eq "$(cat "$CFG")" "$body" "config.toml untouched ($body)"
done
# spellings of a chosen corecrew profile: silent (CRLF, tabs, no spaces, trailing comment, no final newline, single quotes, quoted key, BOM,
# the key after other top-level keys)
for body in 'default_permissions = "corecrew"\r\n' 'default_permissions="corecrew"\n' '  default_permissions\t=\t"corecrew"\n' \
  'default_permissions = "corecrew" # mine\n' 'default_permissions = "corecrew"' "default_permissions = 'corecrew'\n" '"default_permissions" = "corecrew"\n' \
  "'default_permissions' = 'corecrew'\n" '\xef\xbb\xbfdefault_permissions = "corecrew"\n' 'model = "o3"\ndefault_permissions = "corecrew"\n[profiles.x]\nmodel = "y"\n'; do
  printf "$body" > "$CFG"; run codex --part host; assert_eq "$OUT" "" "profile chosen ($body): silent"
done
# the BOM is matched byte for byte whatever the locale (a UTF-8 locale made awk miss it on CI); an unknown locale falls back to C
printf '\357\273\277default_permissions = "corecrew"\n' > "$CFG"
for loc in C C.UTF-8 en_US.UTF-8 POSIX; do
  OUT="$(LC_ALL="$loc" LANG="$loc" COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"; assert_eq "$OUT" "" "profile chosen after a BOM, LC_ALL=$loc: silent"
done
OUT="$(env -u LC_ALL LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 COREKIT_HOST=codex bash "$PREP" --part host 2>&1)"; assert_eq "$OUT" "" "profile chosen after a BOM, LANG=en_US.UTF-8: silent"
# another profile is the default, or the key is not at the top level, or it sits in a multi-line string: the corecrew profile is not the default
for body in 'default_permissions = "my profile"\n' 'default_permissions = ":workspace"\n' "default_permissions = 'other'\n" 'default_permissions = "corecrew2"\n' \
  '[profiles.x]\ndefault_permissions = "corecrew"\n' 'x = """\ndefault_permissions = "corecrew"\n"""\n' "x = '''\ndefault_permissions = 'corecrew'\n'''\n" \
  'default_permissions = corecrew\n' 'xdefault_permissions = "corecrew"\n' \
  'x = """\n\\"""\ndefault_permissions = "corecrew"\n"""\n' 'x = """a \\""" b\ndefault_permissions = "corecrew"\n' \
  "x = '''\n\"\"\"\ndefault_permissions = 'corecrew'\n'''\n" 'x = "a \\" b"\ndefault_permissions = "corecrew"\n'; do
  printf "$body" > "$CFG"; run codex --part host
  assert_eq "$(printf '%s\n' "$OUT" | grep -c 'codex-profile')" "1" "corecrew profile not the default or unsure ($body): the note once"
done
# a relative CODEX_HOME names no config path (and does not fall back to HOME): no note
mkdir -p "$SANDBOX/rel/cx"; n="$(cd "$SANDBOX/rel" && CODEX_HOME=cx COREKIT_HOST=codex bash "$PREP" --part host 2>&1 | grep -c codex-profile)"; assert_eq "$n" "0" "relative CODEX_HOME: no profile note"
rm -f "$CFG"; run codex --part host
echo "$OUT" | grep -qF "codex-profile" && pass || fail "no config.toml: note expected: $OUT"
assert_no_file "$CFG"
CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run codex --part host; echo "$OUT" | grep -qF "Профиль песочницы corecrew" && pass || fail "ru profile note: $OUT"
run claude --part host; assert_eq "$OUT" "" "claude host: no profile note"
printf 'default_permissions = "corecrew"\n' > "$CFG"

# --- a worktree outside the project gets both links; the main folder is left as it is
W="$SANDBOX/codex-home/worktrees/ab12/prep"
git -C "$C" worktree add -q "$W" -b b1 || fail "worktree add"
assert_no_file "$W/AGENTS.md"
run claude --cwd "$W/src-none"
assert_eq "$(readlink "$W/AGENTS.md")" "$P/CLAUDE.md" "worktree AGENTS.md link"
assert_eq "$(readlink "$W/CLAUDE.local.md")" "$P/CLAUDE.md" "worktree CLAUDE.local.md link"
run claude --cwd "$W"; assert_eq "$OUT" "" "worktree: second run silent"
# a Claude worktree under the main folder gets no links of its own (the main folder's are found above it)
CW="$C/.claude/worktrees/w1"; git -C "$C" worktree add -q "$CW" -b b2
run claude --cwd "$CW"; assert_no_file "$CW/AGENTS.md"; assert_no_file "$CW/CLAUDE.local.md"
# the same from the Core project folder: links belong to the main folder
rm -f "$C/AGENTS.md"; run claude --cwd "$P"; assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "link made from the Core project folder"

# --- failure path: a real file where a link should go is reported (CLAUDE.local.md) or left silent (AGENTS.md), never replaced
W2="$SANDBOX/codex-home/worktrees/cd34/prep"
git -C "$C" worktree add -q "$W2" -b b3
printf 'mine\n' > "$W2/CLAUDE.local.md"; printf 'mine too\n' > "$W2/AGENTS.md"
run claude --cwd "$W2"
assert_eq "$RC" "0" "refused link: exit 0"
echo "$OUT" | grep -qF "$W2/CLAUDE.local.md exists and is not a link" && pass || fail "refused link not reported: $OUT"
assert_eq "$(cat "$W2/CLAUDE.local.md")" "mine" "real CLAUDE.local.md kept"
assert_eq "$(cat "$W2/AGENTS.md")" "mine too" "real AGENTS.md kept"
[ ! -L "$W2/CLAUDE.local.md" ] && [ ! -L "$W2/AGENTS.md" ] && pass || fail "a real file was replaced by a link"
echo "$OUT" | grep -qF "AGENTS.md" && fail "a real AGENTS.md is named: $OUT" || pass
rm -f "$C/CLAUDE.local.md"; printf 'main mine\n' > "$C/CLAUDE.local.md"
run claude --cwd "$C"
echo "$OUT" | grep -qF "$C/CLAUDE.local.md exists and is not a link" && pass || fail "main: refused link not reported: $OUT"
assert_eq "$(cat "$C/CLAUDE.local.md")" "main mine" "real CLAUDE.local.md in the main folder kept"
rm -f "$C/CLAUDE.local.md"; ln -s "$P/CLAUDE.md" "$C/CLAUDE.local.md"

# --- failure path: both links missing and the code folder not writable: one line for each, exit 0, nothing created
# (skipped as root, who can write anyway); with the folder writable again a rerun makes both, and the next run is silent
rm -f "$C/CLAUDE.local.md" "$C/AGENTS.md"; chmod a-w "$C"
if [ ! -w "$C" ]; then
  run claude --cwd "$C"
  assert_eq "$RC" "0" "read-only code folder: exit 0"
  echo "$OUT" | grep -qF "could not create $C/CLAUDE.local.md" && pass || fail "read-only code folder: no CLAUDE.local.md line: $OUT"
  assert_eq "$(echo "$OUT" | grep -c 'AGENTS.md')" "1" "read-only code folder: one AGENTS.md line: $OUT"
  echo "$OUT" | grep -qF "could not create $C/AGENTS.md" && pass || fail "read-only code folder: no AGENTS.md line: $OUT"
  echo "$OUT" | grep -qF "ln -s \"$P/CLAUDE.md\" \"$C/AGENTS.md\"" && pass || fail "read-only code folder: no fix command: $OUT"
  [ ! -e "$C/CLAUDE.local.md" ] && [ ! -L "$C/CLAUDE.local.md" ] && [ ! -e "$C/AGENTS.md" ] && [ ! -L "$C/AGENTS.md" ] && pass \
    || fail "read-only code folder: a link was created"
  CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run claude --cwd "$C"
  echo "$OUT" | grep 'AGENTS.md' | grep -qF "could not" && fail "ru AGENTS.md line is English: $OUT" || pass
fi
chmod u+w "$C"
run claude --cwd "$C"
assert_eq "$(readlink "$C/CLAUDE.local.md")" "$P/CLAUDE.md" "rerun: CLAUDE.local.md link"
assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "rerun: AGENTS.md link"
run claude --cwd "$C"; assert_eq "$OUT" "" "after the rerun: silent"

# --- layout note and old git hooks (same texts as session-start)
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
run claude --cwd "$C"; echo "$OUT" | grep -qF "Layout note" && pass || fail "layout note: $OUT"
# a schema written with a leading zero is read as a decimal number: 08 is not older, no note and no shell error
printf 'schema: 08\n' > "$CORE_DIR/.coredev"
run claude --cwd "$C"; assert_eq "$OUT" "" "schema 08: silent"
printf 'schema: 01\n' > "$CORE_DIR/.coredev"
run claude --cwd "$C"; echo "$OUT" | grep -qF "Layout note" && pass || fail "schema 01: layout note: $OUT"
printf 'schema: 2\n' > "$CORE_DIR/.coredev"
mkdir -p "$C/.git/hooks"; printf '#!/bin/sh\n# new-project hook\n' > "$C/.git/hooks/pre-commit"
run claude --cwd "$C"; echo "$OUT" | grep -qF "Old git hooks" && fail "corecrew 1.0 still names an old hook: $OUT" || pass
rm -f "$C/.git/hooks/pre-commit"

# --- a failing sync is reported and the exit stays 0; the rest still runs
mkdir -p "$SANDBOX/foreign-tools"; : > "$SANDBOX/foreign-tools/mine.txt"
rm -f "$C/AGENTS.md"
OUT="$(COREKIT_HOST=claude COREDEV_TOOLS="$SANDBOX/foreign-tools" bash "$PREP" --cwd "$C" 2>&1)"; RC=$?
assert_eq "$RC" "0" "sync failure: exit 0"
echo "$OUT" | grep -qF "corecrew: tools not refreshed:" && pass || fail "sync_failed missing: $OUT"
assert_eq "$(ls "$SANDBOX/foreign-tools")" "mine.txt" "foreign tools folder untouched"
assert_eq "$(readlink "$C/AGENTS.md")" "$P/CLAUDE.md" "links still made after a failed sync"

# --- no usable HOME: no data folder, nothing written in the cwd or at /
rm -rf "$COREDEV_TOOLS"
mkdir -p "$SANDBOX/cwdempty"
for H in "" "relhome"; do
  OUT="$(cd "$SANDBOX/cwdempty" && env -u COREDEV_TOOLS -u CLAUDE_PLUGIN_DATA -u XDG_CONFIG_HOME -u CODEX_HOME -u CORECREW_CONFIG HOME="$H" CORE_DIR="$CORE_DIR" COREKIT_HOST=codex bash "$PREP" --cwd "$SANDBOX/elsewhere" 2>&1)"; RC=$?
  assert_eq "$RC" "0" "HOME='$H': exit 0"
  echo "$OUT" | grep -qF "codex-profile" && fail "HOME='$H': profile note names a config.toml that is not under a real home: $OUT" || pass
  assert_eq "$(ls -A "$SANDBOX/cwdempty")" "" "HOME='$H': nothing written in the cwd"
  [ ! -e "/.claude" ] && [ ! -e "/.codex" ] && [ ! -e "/.config" ] && pass || fail "HOME='$H': wrote at /"
  assert_no_file "$COREDEV_TOOLS"
  OUT="$(cd "$SANDBOX/cwdempty" && env -u COREDEV_TOOLS -u CLAUDE_PLUGIN_DATA -u XDG_CONFIG_HOME -u CODEX_HOME -u CORECREW_CONFIG HOME="$H" CORE_DIR="$CORE_DIR" COREKIT_HOST=codex bash "$PREP" --part tools 2>&1)"
  assert_eq "$OUT" "" "HOME='$H', --part tools: no data folder known, silent"
done

# --- host, tools_dir, hooks_marker_path; session-start writes the marker on Codex only
CP="$CODEX_HOME/plugins/cache/mart/corecrew/$VER"; mkdir -p "$(dirname "$CP")"; cp -R "$PLUGIN" "$CP"
assert_eq "$(. "$CP/scripts/lib.sh"; host)" "codex" "host: plugin under CODEX_HOME"
assert_eq "$(. "$SCRIPTS/lib.sh"; host)" "claude" "host: plugin elsewhere"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex host)" "codex" "host: COREKIT_HOST"
assert_eq "$(. "$CP/scripts/lib.sh"; COREKIT_HOST=claude host)" "claude" "host: COREKIT_HOST wins"
ln -s "$CODEX_HOME" "$SANDBOX/cx-link"
assert_eq "$(. "$CP/scripts/lib.sh"; CODEX_HOME="$SANDBOX/cx-link" host)" "codex" "host: CODEX_HOME given through a link"
assert_eq "$(. "$CP/scripts/lib.sh"; CODEX_HOME="$SANDBOX/elsewhere" host)" "claude" "host: plugin not under that CODEX_HOME"
assert_eq "$(. "$SCRIPTS/lib.sh"; tools_dir)" "$COREDEV_TOOLS" "tools_dir: COREDEV_TOOLS"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS; tools_dir)" "$CLAUDE_PLUGIN_DATA/tools" "tools_dir: CLAUDE_PLUGIN_DATA"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; tools_dir)" "$HOME/.claude/plugins/data/corecrew-corekit/tools" "tools_dir: claude default"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; COREKIT_HOST=codex tools_dir)" "$CODEX_HOME/plugins/data/corecrew-corekit/tools" "tools_dir: codex default"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; HOME=rel; tools_dir)" "" "tools_dir: relative HOME"
# the data folder follows the marketplace the plugin was installed from, read from the plugin root's path (Claude Code
# and Codex keep a plugin at plugins/cache/<marketplace>/corecrew/<version>; a marketplace clone lies under
# plugins/marketplaces/<marketplace>/); a checkout or any other shape falls back to corekit
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/.claude/plugins/cache/shop/corecrew/1.2.3)" "shop" "marketplace_name: Claude Code cache"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/.codex/plugins/cache/shop/corecrew/1.2.3)" "shop" "marketplace_name: Codex cache"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/.claude/plugins/marketplaces/shop/plugins/corecrew)" "shop" "marketplace_name: marketplace clone"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/Projects/CoreKit/plugins/corecrew)" "corekit" "marketplace_name: a checkout"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/.claude/plugins/cache/shop/other/1.2.3)" "corekit" "marketplace_name: another plugin's cache path"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /h/.claude/plugins/cache/shop)" "corekit" "marketplace_name: cache path without the plugin"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name "/h/.claude/plugins/cache/bad name/corecrew/1.2.3")" "corekit" "marketplace_name: a name with a space"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /x/plugins/cache/a/b/corecrew/1)" "corekit" "marketplace_name: a nested cache path"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /x/plugins/cache/../corecrew/1)" "corekit" "marketplace_name: .. is no marketplace"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name /x/plugins/cache/./corecrew/1)" "corekit" "marketplace_name: . is no marketplace"
assert_eq "$(. "$SCRIPTS/lib.sh"; marketplace_name)" "corekit" "marketplace_name: this checkout, no argument"
assert_eq "$(. "$CP/scripts/lib.sh"; marketplace_name)" "mart" "marketplace_name: the plugin under a cache path, no argument"
assert_eq "$(. "$SCRIPTS/lib.sh"; default_data_dir /h/.claude/plugins/cache/shop/corecrew/1.2.3)" "$HOME/.claude/plugins/data/corecrew-shop" "default_data_dir: claude"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex default_data_dir /h/.codex/plugins/cache/shop/corecrew/1.2.3)" "$CODEX_HOME/plugins/data/corecrew-shop" "default_data_dir: codex"
assert_eq "$(. "$SCRIPTS/lib.sh"; default_data_dir)" "$HOME/.claude/plugins/data/corecrew-corekit" "default_data_dir: this checkout"
assert_eq "$(. "$SCRIPTS/lib.sh"; HOME=rel default_data_dir /h/.claude/plugins/cache/shop/corecrew/1.2.3)" "" "default_data_dir: relative HOME"
assert_eq "$(. "$CP/scripts/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; tools_dir)" "$CODEX_HOME/plugins/data/corecrew-mart/tools" "tools_dir: codex default follows the cache marketplace"
# a tools copy whose .data-dir holds a relative path does not follow it (never a folder under the cwd): the host default
TC="$SANDBOX/tcopy"; cp -R "$SCRIPTS" "$TC"; echo "rel/data" > "$TC/.data-dir"
assert_eq "$(cd "$SANDBOX/elsewhere" && . "$TC/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; COREKIT_HOST=claude tools_dir)" "$HOME/.claude/plugins/data/corecrew-corekit/tools" "tools_dir: a relative .data-dir is not followed"
echo "$SANDBOX/dd/" > "$TC/.data-dir"
assert_eq "$(. "$TC/lib.sh"; unset COREDEV_TOOLS CLAUDE_PLUGIN_DATA; tools_dir)" "$SANDBOX/dd/tools" "tools_dir: an absolute .data-dir is followed"
# the version comes from the Codex manifest when the plugin root has no Claude Code one
mkdir -p "$SANDBOX/cxonly/.codex-plugin"; printf '{\n  "name": "corecrew",\n  "version": "9.8.7"\n}\n' > "$SANDBOX/cxonly/.codex-plugin/plugin.json"
assert_eq "$(. "$SCRIPTS/lib.sh"; plugin_version "$SANDBOX/cxonly")" "9.8.7" "plugin_version: only a Codex manifest"
assert_eq "$(. "$SCRIPTS/lib.sh"; plugin_version "$PLUGIN")" "$VER" "plugin_version: this plugin"
assert_eq "$(. "$SCRIPTS/lib.sh"; plugin_version "$SANDBOX/elsewhere")" "" "plugin_version: no manifest"
assert_eq "$(. "$SCRIPTS/lib.sh"; COREKIT_HOST=codex hooks_marker_path)" "$MARK" "hooks_marker_path"
assert_eq "$(. "$SCRIPTS/lib.sh"; unset XDG_CONFIG_HOME; HOME=""; COREKIT_HOST=codex hooks_marker_path)" "" "hooks_marker_path: no settings folder"
SS="{\"session_id\":\"s\",\"cwd\":\"$C\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
rm -f "$MARK"
printf '%s' "$SS" | COREKIT_HOST=claude CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_no_file "$MARK"
assert_eq "$(ls -A "$XDG_CONFIG_HOME/corecrew/state" 2>/dev/null | grep -c '^hooks-seen')" "0" "session-start on Claude Code writes no hooks-seen marker"
printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "$VER" "session-start writes the version on Codex"
touch -t 200001010000 "$MARK"; printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
[ -n "$(find "$MARK" -newermt 2001-01-01 2>/dev/null)" ] && fail "marker rewritten although current" || pass
echo "0.0.1" > "$MARK"; printf '%s' "$SS" | COREKIT_HOST=codex CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
assert_eq "$(cat "$MARK")" "$VER" "an older marker is replaced"
run codex --cwd "$C"; assert_eq "$OUT" "" "after session-start: no trust note"
finish
