# Changelog

## 0.2.0 — 2026-11-03
- The plugin is now `coredev` (the marketplace and repo stay `corekit`). The marketplace
  `renames` map migrates old installs; run `/plugin install coredev@corekit` once.
  Commands are `/coredev:...`.
- Plugin settings (`userConfig`): `core_dir`, `attribution` (`allow`/`forbid`),
  `model_profile` (`economy`/`balanced`/`strong`).
- `feature-dev` (from `claude-plugins-official`, or from claude.ai) is needed by `/coredev:task`
  but is not declared as a hard dependency: a hard dependency stopped `coredev` from loading
  when `feature-dev` came from claude.ai sync or another marketplace. Install it with
  `/plugin install feature-dev@claude-plugins-official`; `task` checks for it at start.
- Settings: a value that is still the literal text `${user_config.…}` (plugin not configured)
  counts as unset, so scripts fall back to `CLAUDE_PLUGIN_OPTION_*` and then the defaults.
- Added `tests/test_manifest.sh`.
- Git hooks installed in repos are small shims that run the plugin's scripts from a stable
  copy in the plugin data folder (`sync-tools.sh`); the copy is refreshed on version change, so
  hooks no longer go stale after an update. `install-hooks.sh` fails with exit 1 when its hook
  sources are missing, and no longer copies `blocked-patterns` into `.git/hooks`.
- The Stop hook ships with the plugin (`hooks/hooks.json`, runs `hooks/stop-remind.sh`) and
  stays silent outside a Core project. New projects no longer get a `hooks` block in
  `code/.claude/settings.local.json`; existing projects must remove theirs (migration step 4).
- `install.sh` and its test are removed: install with `/plugin install coredev@corekit`.
  The README says the plugin needs Claude Code 2.1.271 or newer.
- The project `CLAUDE.md` template names `save` and `undo-step` as plugin tools that Claude
  runs, instead of `Core/bin/`.
- Added `docs/migration-0.2.md`: the seven steps for an existing 0.1.x user.

## 0.1.1 — 2026-11-03
- `save` reinstalls hooks when the code pre-push hook or `blocked-patterns` is missing
  (without the patterns file every commit was blocked and `save` never recovered).
- `install.sh` no longer replaces a same-named skill it did not install; installed folders
  get a `.corekit` marker, `--force` replaces anyway. A symlinked skill folder is left alone,
  and it refuses to install into the repo's own `skills/` (that deleted the source).
- Stop hook reminds once per set of uncommitted changes and tells Claude not to save while
  it waits for the user's answer. It notices edits in untracked files with non-ASCII names
  and in repos without commits, and stays fast with thousands of untracked files.
- `scaffold.sh` joins a multi-line `--purpose` into one line (PROJECTS.md entry was split).
- Test suite passes on macOS (bash 3.2, BSD utilities); new `tests/test_portability.sh`
  blocks bash 4 and GNU-only constructs. Added CLAUDE.md for contributors.
- Upgrade note: existing docs repos keep their old `Core/bin/` copies; copy the new `save`
  and `stop-remind.sh` from `skills/new-project/core-bin/` there to get the fixes.

## 0.1.0 — 2026-11-03
- First public release: `new-project` skill (interview, stack and architecture analysis,
  scaffold, private docs repo, protective git hooks, `save` / `undo-step`), per-user settings,
  Claude Code plugin and marketplace manifests.
