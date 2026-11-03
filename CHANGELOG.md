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
- Added `/coredev:new-standard`: an interview, a research subagent and `scripts/check-standard.sh`
  help the user write their own standards into `<Core>/standards/`; the plugin ships none.
  `reference/knowledge.md` defines the knowledge files (`docs/knowledge/`, `<Core>/knowledge/`).
- Added `docs/migration-0.2.md`: the seven steps for an existing 0.1.x user.
- `/coredev:task adopt` adds the missing coredev ignore lines (`CLAUDE.md`, `.claude/`, `.env`, ...)
  to the repo's `.gitignore` in its "Move internal Claude files to Core" commit, so a local
  `.claude/settings.local.json` or a `.claude/worktrees/` worktree never blocks `save`.
- Added `/coredev:task <task>`: the orchestrator runs a task along one of four paths (`fix`,
  `full`, `question`, `batch`) and ends with a report with proof and one commit.
- `/coredev:task release <version>` runs seven checks (tests, wiki, version, changelog) and commits the release; it tags and pushes nothing.
- `/coredev:task adopt <folder>` (`scripts/adopt.sh`) moves an existing project into the Core
  layout, keeps its git history and adds the missing wiki pages.
- Six agents: `engineer`, `tester`, `security`, `verifier`, `localizer`, `designer`.
- Five hooks: `session-start` (refreshes the tools, shows the project context), `one-suite`
  (one test run at a time), `guard-code` (no internal files in `code/`), `guard-secrets`
  (no `.env`, no `~/.ssh`) and `stop-remind` (the save reminder).
- Wiki rules (`reference/wiki.md`) and `scripts/wiki-check.sh`; `new-project` and adopt create a
  wiki that passes the check.
- Knowledge: lessons per project (`docs/knowledge/`) and for all projects (`<Core>/knowledge/`),
  read by the agents before they work.
- Install and update with the `claude plugin` commands on Mac and Windows (README); Windows
  needs Git for Windows.
- Added the end-to-end fixture `tests/fixtures/make-test-coredev.sh` (a tiny project with a
  planted bug) and `tests/test_fixture.sh`.

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
