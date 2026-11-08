# Changelog

All notable changes to `corecrew` are listed here. The other two plugins keep their own:
[coremodel](plugins/coremodel/CHANGELOG.md) and [coreopinion](plugins/coreopinion/CHANGELOG.md).

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the
versions follow [Semantic Versioning](https://semver.org/). Older entries are shortened; the
commit log has the full detail.

## [Unreleased]

### Added

- `reference/codex-host.md`: one Codex reference for all four skills (skill folder, settings,
  `--add-dir`, approval outside the sandbox, chat questions, subagents).
- A Codex model per crew role from the settings file: `codex_model` and `codex_model_<role>`
  (`<model>`, `<model> <effort>` or `inherit`).
- `ship` tags `<plugin>-v<version>` (or `v<version>`) after the push and publishes a GitHub
  release, each after a yes.
- `task`'s architect and explorer steps run without the feature-dev plugin, on Claude Code's
  built-in Plan and Explore agents.
- A README for corecrew itself, with settings, uninstall steps and a glossary.

### Changed

- The Bash guard's shell-patch refusal runs only in Codex, where `apply_patch` can be run from the
  shell. In Codex a wildcard counts only in command position; heredoc bodies and redirect targets
  are data, and the message names what matched.
- `one-suite` holds a test run only while another run works in the same project folder or
  worktree, for at most 120 s (was: any run on the machine, 480 s).
- `ship` ships into the repo's default branch (origin/HEAD, else `init.defaultBranch`, else it
  asks) instead of `main`.
- Codex subagent steps work with both multi-agent tool sets (v1 and v2) and stop with a plain
  message when Codex has no subagents.
- Hook messages name skills `$corecrew:<skill>` in Codex.
- Crew agents reply in English; the orchestrator talks to you in your language.
- new-project's preflight warns, not fails, without `gh` (only the GitHub stage needs it), and its
  install hints link the official pages for every system.
- `release` offers Keep a Changelog 1.1.0 when a project has no versioning standard.
- The Paths section of every skill is one short block; migration notes for 0.6 wikis, the old
  brief stage field and the old layout moved to `reference/older-formats.md`.
- Step-Ids are `<time>-<NN>-<random>`.
- Plugin icons moved to `assets/icon.png` and are named in every manifest.

### Removed

- `ship`'s check of the global git config around the tests.

### Fixed

- `undo-step` reset the whole Core on a conflict and deleted other projects' staged files, swept
  unrelated staged files into its commit, and left a step's shared Core files (`knowledge/`) in
  place. It now touches only the paths the step changed.
- Two projects that saved in the same second could share a Step-Id, so `undo-step <id>` undid
  both.
- `install-hooks.sh` wrote shims to `.git/hooks` when `core.hooksPath` (husky, lefthook, a global
  setting) made git ignore them, and said the hooks were installed. It now writes nothing there,
  explains how to chain corecrew's checks, and `save` still saves.
- `one-suite` never held a run in a folder whose name has non-ASCII letters.
- `ship` ran `task`'s Start by step numbers that had moved; steps are referred to by name.

### Security

- `codex-profile` emits the documented `:workspace_roots` and `"deny"` instead of legacy aliases,
  names current flags instead of `--full-auto`, and also denies `*.ppk`, `*.keytab`, `.s3cfg` and
  `.gnupg/**`.

## [0.8.0] - 2026-11-08

Codex support: `corecrew` (and `coremodel` 0.6.0) install and run in the Codex CLI; the steps are
in the README. `coreopinion` stays Claude Code only. In Claude Code there is nothing to do: your
plugin options still win over the new settings file. In Codex, trust the hooks again in `/hooks`
after each update.

### Added

- A Codex manifest (`.codex-plugin/plugin.json`) beside the Claude Code one; the shared fields must match.
- The `/corecrew:task` chain in Codex: each role runs as a Codex subagent with the model and effort
  from `model_profile`. Codex subagents cannot be made read-only, so the read-only steps are
  checked (the working tree before and after), not enforced. Codex is told to add the Core with
  `codex --add-dir` when it cannot write there.
- An optional Codex sandbox profile for secrets: `lib.sh codex-profile` prints a fragment for
  `~/.codex/config.toml` that keeps `.env*`, keys, credentials and `~/.ssh` unreadable. It is a
  default, not a hard boundary (`--sandbox`, `--full-auto` and `-c sandbox_mode=...` switch it
  off), and corecrew never writes that file.
- A settings file, `~/.config/corecrew/settings` (or the path in `CORECREW_CONFIG`), with
  `key: value` lines for `core_dir`, `attribution`, `model_profile` and `ui_language`, for hosts
  without an options screen. Per key the order is: `CORE_DIR` (for `core_dir`), plugin option,
  file, default. `lib.sh settings` and `lib.sh setting-path` print them.
- The guards understand Codex's `apply_patch` tool: `guard-code` blocks an internal file as an
  added, updated or moved file; `guard-secrets` blocks `.env` and `~/.ssh` as a written file or a
  move source. A patch that names more than 100 files is refused.
- Git worktrees outside the projects folder (Codex keeps them elsewhere) are recognised, so the
  guards, one-suite and the save reminder work there. A worktree counts only when its main folder
  knows it and is the project's own code folder.
- `scripts/prepare.sh` makes the tool copy and the `CLAUDE.local.md` and `AGENTS.md` links without
  waiting for the session-start hook; the skills run it first.
- `agents/openai.yaml` keeps `task`, `ship` and `new-standard` out of Codex's implicit skill
  choice, as `disable-model-invocation` does in Claude Code.

### Changed

- In Codex, `save` asks for approval to leave the sandbox (it keeps `.git` read-only); in
  non-interactive `codex exec` the task stops with `Commit: stopped — Codex sandbox keeps .git
  read-only` and the files stay uncommitted.
- A wrong `attribution` or `model_profile`, or a relative `core_dir` such as `Core` (which used to
  become `<current folder>/Core`), is ignored with a warning at session start, and the next source
  is used. An unknown `ui_language` falls back to `en` silently.
- With an empty or relative `HOME` there is no default Core, and the plugin writes nothing under
  such a `HOME`.
- The skills find their own folder (`lib.sh plugin-root`) instead of relying on
  `${CLAUDE_SKILL_DIR}`, which Codex does not expand.
- Messages for a patch that cannot be judged show the offending line and say what to do.

### Fixed

- `save` stops with a clear message and a non-zero exit when git cannot write `.git`, instead of
  printing `nothing to save`.
- Several `prepare.sh` or `sync-tools.sh` runs at once no longer report false problems or leave
  temporary folders behind.
- A settings file with a very long line no longer makes a hook run past its timeout; a file over
  64 KB is not read (one warning, defaults used).
- An empty Core path gives plain messages in `session-start`, `setup-core.sh`, `adopt.sh` and
  `lib.sh core-paths`.
- A relative `CORECREW_CONFIG` is ignored, like a relative `XDG_CONFIG_HOME`.

### Security

- A TAB or CR inside a patch path is removed before the path is judged, as Codex does; before,
  `do<TAB>cs/a.md` or `.e<TAB>nv` passed both guards.
- When the patch reader is missing or fails, both guards refuse the patch instead of letting
  part of it through.
- Both guards refuse a patch handed to the shell (`apply_patch` run through Bash): that form
  cannot be checked. This is a best-effort rule with documented ways past it, not a boundary.

## [0.7.2] - 2026-11-06

### Changed

- `wiki-check` reports front matter fields beyond the six allowed ones; `wiki-migrate` moves a
  brief's one-line stage into `## Progress` and warns about other extra fields.

### Fixed

- The `new-project` resume stage lives in a `## Progress` section of the brief (`Stage: <stage>`)
  instead of a `stage:` front matter field, which the wiki rules do not allow.

## [0.7.1] - 2026-11-06

### Changed

- The Core README template names the code folder `../<Name>/` and lists the `AGENTS.md` link, the
  generated `docs/INDEX.md`, the Obsidian vaults and the optional `session-rules.md`. An existing
  Core README is never changed.

### Fixed

- The Core pre-push hook asks GitHub up to three times, 2 s apart, whether the Core repository is
  private, so one network timeout no longer blocks a push. A "not private" answer still blocks at once.

## [0.7.0] - 2026-11-06

### Added

- The wiki index `docs/INDEX.md` is generated from the pages' front matter (`wiki-index.sh`);
  `wiki-check.sh` reports it when it is out of date.
- Every project's `docs/` is one Obsidian vault: scaffold adds `wiki.base` and `.obsidian/`.
- `wiki-check.sh` checks the new format (front matter fields, wikilink targets, the generated INDEX).
- An `AGENTS.md` link in the code folder next to `CLAUDE.local.md`. Note for coreopinion users:
  it exposes the private `CLAUDE.md` to Codex in that folder, so a second opinion can send its
  content to OpenAI.
- `scripts/wiki-migrate.sh` converts a 0.6 wiki to the new format; `adopt` runs it too. The first
  `/corecrew:task` on a 0.6 project offers it, shows a dry run first and converts only on your ok.

### Changed

- Front matter: `type` replaces `title`; page references are wikilinks (`[[page#Heading]]`). Specs
  and plans live in `docs/specs/` and `docs/plans/` (before: `docs/superpowers/`).

## [0.6.6] - 2026-11-05

### Fixed

- The one-suite hook no longer lets several test runs through when many waiters find the same
  stale turn at the same instant: the takeover runs under a short lock.

## [0.6.5] - 2026-11-05

### Added

- `/corecrew:ship [patch|minor|major|<version>]` releases the current branch through the release
  path of `/corecrew:task`, then, after your explicit yes, fast-forwards `main` and pushes it.
  It never forces.

## [0.6.4] - 2026-11-05

### Added

- Icon files for the three plugins, with SVG sources in `docs/icons/`. No manifest named them yet,
  so plugin listings did not show them.

## [0.6.3] - 2026-11-05

### Changed

- The one-suite hook names its known limits in its header. No behaviour change.
- Repo paths named in the READMEs must exist (a test checks it).

## [0.6.2] - 2026-11-05

### Security

- The read-only checkers' rule, after a second opinion: any `cd` ends relative writes; `git push`,
  global git config, `--git-dir`/`--work-tree` and `git worktree add` are refused even into a temp
  folder; `cp`/`mv` into a folder, `sed` with a `w` command or `-f`, and grouped curl options are judged.

## [0.6.1] - 2026-11-05

### Changed

- The six agents' descriptions are 120 characters at most, which saves context in every session.
- Trigger evals for `new-project` in `plugins/corecrew/evals/` (`claude plugin eval`).

### Security

- The read-only checkers' rule, after an independent review: it follows `cd`, looks into `$(...)`
  and backticks, and refuses `find -delete`/`-exec`, `xargs rm`, `sort -o`, downloads, unpacking,
  `ln`, more git changes, and any command it cannot read whole. Some reads it wrongly refused now
  pass (`git tag -l`, `git stash list`, `git worktree list`).

## [0.6.0] - 2026-11-05

### Added

- The read-only checkers (designer, localizer, security, verifier) can change nothing but the temp
  folders: a hook refuses their Bash writes, removals, in-place edits and git changes.

### Changed

- The plugin lives in `plugins/corecrew/` of the repo; an install copies only the plugin. The name,
  the settings and the data folder stay the same.

## [0.5.3] - 2026-11-05

### Changed

- The session-start hook also runs when a session is forked.
- `tests/run.sh` names a test file that was skipped instead of hiding it.

### Fixed

- A quick re-run of a test suite no longer waits about 10 s: the one-suite grace is 3 s.

## [0.5.2] - 2026-11-05

### Changed

- README: the Claude Code versions needed and a short "What the hooks do" section.

### Fixed

- The one-time "Core not set up" hint is shown to the person, not only handed to the model.

### Security

- Both guards judge the command line handed to `bash -c`, `sh -c`, `zsh -c` and `eval`.
  Interpreters (`python -c`, `node -e`), `find -exec`, `git show REV:.env`, `dd` and
  `curl -F @file` are still not seen; the README says so.

## [0.5.1] - 2026-11-05

### Fixed

- `zip a.zip src -x .env` is no longer blocked.
- A `core_dir` that is a symlink: the code folders next to the link are recognised.
- one-suite sees `echo $((1<<3)); swift test` as a test run.

### Security

- guard-secrets judges a secret name written with quotes or a backslash (`.e'n'v`) and blocks globs
  that can match `.env` or `.ssh`.
- Both guards skip wrapper options that take a value (`timeout 5 cat .env`, `sudo -u root cat .env`).
- With `HOME` unset, `~/.ssh` is still protected.
- guard-code blocks a file written directly under `.claude/worktrees/`.

## [0.5.0] - 2026-11-04

### Added

- New projects keep their code beside the Core, in `<Projects>/<Name>`; private files stay in
  `<Core>/<name>/`. Launch Claude Code in the code folder.
- Session start makes and repairs `CLAUDE.local.md`, a gitignored link to `<Core>/<name>/CLAUDE.md`,
  and never overwrites a real file.

### Changed

- `/corecrew:task adopt` keeps the repo where it is and moves only old-layout `<Core>/<name>/code`
  folders. In such a project `/corecrew:task` asks you to run adopt first.
- `guard-code` guards the code folder beside the Core.
- Core schema 2: a schema 1 Core gets one layout note at session start.

### Removed

- The `.claude/rules/` template: project rules live in `CLAUDE.md`.

## [0.4.0] - 2026-11-04

### Changed

- `AGENTS.md` is an internal file like `CLAUDE.md`: `guard-code` and the git hooks keep it out of the
  code repo, and `adopt` moves it to `<Core>/<name>/`. A code repo that already tracks it must move
  it by hand: copy it to the Core, `git rm AGENTS.md`, add it to `.gitignore`, commit.

## [0.3.1] - 2026-11-04

### Changed

- Plugin lists show the name as CoreCrew (`displayName`). Commands keep their lowercase names.

## [0.3.0] - 2026-11-04

### Changed

- The plugin is now `corecrew`; the marketplace and repo stay `corekit`. Commands are
  `/corecrew:...`. The marketplace moves `coredev` and `corekit` installs to `corecrew`.
  Steps: [docs/migration-0.3.md](docs/migration-0.3.md).
- The plugin data folder is now `corecrew-corekit`; `install-hooks.sh` replaces the 0.2 git hook shims.

## [0.2.1] - 2026-11-04

### Added

- The `ui_language` setting (`en`, `ru`): the language of the hook messages.

## [0.2.0] - 2026-11-03

### Added

- `/coredev:task <task>` runs a task with a crew of six agents and ends with a report and one commit;
  `release` and `adopt` paths.
- `/coredev:new-standard` helps you write your own standards into the Core.
- Plugin settings: `core_dir`, `attribution`, `model_profile`.
- Five hooks: session start, one test suite at a time, the code guard, the secrets guard and the save reminder.
- Wiki rules and `wiki-check.sh`; knowledge files per project and for all projects.

### Changed

- The plugin is now `coredev`. Install and update with `claude plugin` commands.
- Git hooks in your repos are small shims that run the plugin's scripts from its data folder, so
  they stay current after an update.
- `feature-dev` is needed by `task` but is not a hard dependency.
- `.env.example`, `.env.sample` and `.env.template` are allowed everywhere.
- Upgrade steps from 0.1: [docs/migration-0.2.md](docs/migration-0.2.md).

### Removed

- `install.sh`: install with `/plugin install`.

### Fixed

- The release attribution check matches only trailer lines.
- A setting that is still the literal `${user_config.…}` counts as unset.

## [0.1.1] - 2026-11-03

### Changed

- The Stop hook reminds once per set of uncommitted changes and stays fast in large repos.
- The test suite passes on macOS bash 3.2 with BSD tools.

### Fixed

- `save` reinstalls the git hooks when one of them or `blocked-patterns` is missing.
- `install.sh` no longer replaces a skill it did not install.
- `scaffold.sh` joins a multi-line `--purpose` into one line.

## [0.1.0] - 2026-11-03

### Added

- First public release: the `new-project` skill (interview, stack and architecture analysis,
  scaffold, private docs repo, protective git hooks, `save` and `undo-step`), per-user settings,
  Claude Code plugin and marketplace manifests.
