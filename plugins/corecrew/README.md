# CoreCrew

Run every project the same way. `corecrew` starts a new app from a short interview, runs each task
through a crew of agents (an engineer writes, a tester and read-only checkers review), and keeps
your standards, lessons and each project's internal docs in one private git repo of your own, the
Core. The code of each project lives in its own repo beside the Core, so publishing the code never
publishes your internal notes. It works in Claude Code and in the Codex CLI.

## Install

### Claude Code

Run these two commands in a terminal:

```bash
claude plugin marketplace add rstrlnkv/CoreKit
claude plugin install corecrew@corekit
```

The first adds the `corekit` marketplace, the second installs `corecrew`. Optional:
`claude plugin install feature-dev@claude-plugins-official` gives `/corecrew:task` deeper architect
and explorer agents (`code-architect`, `code-explorer`); without it, `task` uses Claude Code's
built-in Plan and Explore agents and says so once at the start.

Inside a running Claude Code session the same steps are:

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install corecrew@corekit
```

and, optionally, `/plugin install feature-dev@claude-plugins-official`.

Start `claude` again, then run `/corecrew:new-project`. On the first run it shows what it will
create and sets up your Core after your "ok".

Recommended: add the deny rules from [SECURITY.md](../../SECURITY.md#recommended-host-settings) to
your Claude Code settings. They keep `.env` files and `~/.ssh` away from Claude's file tools. That
is the boundary; corecrew's secrets guard only backs it up.

A command-line install does not ask for the [settings](#settings); the defaults apply until you
set them. Give a value at install time, for example
`claude plugin install corecrew@corekit --config ui_language=ru` for Russian hook messages, or
change them later in `/plugin` → Installed → corecrew → Configure options.

### Codex

```bash
codex plugin marketplace add rstrlnkv/CoreKit
codex plugin add corecrew@corekit
```

Then:

1. **Trust the hooks.** Start `codex`, open `/hooks`, review and enable the `corecrew` hooks. Until
   you do, corecrew's guards (project docs in code, secrets) stay off, and a plain Codex start does
   not warn you: only `new-project`, `task` and `ship` remind you when they run. Do it again after
   each update.
2. **Write the settings file.** Codex has no options screen; see [Settings](#settings).
3. **Give Codex your Core.** Codex writes only in the working folder and `--add-dir` folders, so
   start it as `codex --add-dir "<Core>"` (`~/Projects/Core` by default). For new-project, start it
   as `codex --add-dir "<Projects>"` (the folder that holds the Core): the Core may not exist yet,
   and the new code folder goes there. Every skill checks this and tells you the command.
4. **Name the skills.** Codex may pick `new-project` by itself. Name the others in your prompt
   (`$corecrew:task <task>`, `$corecrew:ship`, `$corecrew:new-standard`) or pick them from the
   skill list.
5. **Optional: the secrets profile.** See [SECURITY.md](../../SECURITY.md#recommended-host-settings).

What differs from Claude Code:

- The crew roles are role files that `/corecrew:task` hands to Codex subagents as text, with the
  model and effort from `model_profile`, or from `codex_model` / `codex_model_<role>` when set.
  `feature-dev` is not used.
- The crew needs Codex subagents (the `multi_agent` feature, on by default; `codex features list`
  shows it). In a session without the `spawn_agent` tool the chain stops and says so.
- Commits ask for your approval: the Codex sandbox keeps `.git` read-only, so `save` runs outside
  it after you approve. In non-interactive `codex exec` the whole chain still runs; only the commit
  stops, with `Commit: stopped — Codex sandbox keeps .git read-only`, and the files stay
  uncommitted.
- `gh`, pushes and project generators also run outside the sandbox after your approval: the
  sandbox has no network.
- Codex subagents cannot be made read-only, so the read-only steps are checked, not enforced: the
  chain compares `git status` before and after and stops on a change.

### Update

```bash
claude plugin marketplace update corekit
claude plugin update corecrew@corekit
```

In Codex: `codex plugin marketplace upgrade corekit`, then trust the hooks again in `/hooks`.
Then restart the host. An update never touches your Core, standards or knowledge files.
Auto-update is off for third-party marketplaces by default; turn it on in `/plugin` → Marketplaces
→ corekit → Enable auto-update.

Coming from `coredev` (0.2.x): follow [docs/migration-0.3.md](../../docs/migration-0.3.md). Coming
from 0.1.x: follow [docs/migration-0.2.md](../../docs/migration-0.2.md) first.

## Features

### Words used here

| Word | Meaning |
|---|---|
| **Core** | Your private git repo (`~/Projects/Core` by default) with your standards, lessons and each project's internal docs in `<Core>/<name>/`. |
| **Code folder** | The project's own repo beside the Core (`<Projects>/<name>`, where `<Projects>` is the folder that holds the Core). It may be public. |
| **Save** | One step committed: the code repo and the Core together, by the `save` tool. |
| **Undo** | The last saved step reverted in both repos with `git revert`, by the `undo-step` tool. History is kept. |

### Commands

| Command | What it does |
|---|---|
| `/corecrew:new-project` | Interview, stack and architecture analysis, project skeleton (below) |
| `/corecrew:task <task>` | Runs a task through the crew of agents and ends with a report and one commit |
| `/corecrew:task release <version>` | Prepares a release: version, changelog and the other release checks |
| `/corecrew:task adopt <folder>` | Brings an existing project into the Core layout |
| `/corecrew:ship [patch\|minor\|major\|<version>]` | Releases the current branch, then, after your yes, fast-forwards the default branch and pushes it; after a second yes, tags the version and publishes a GitHub release |
| `/corecrew:new-standard` | Helps you write a standard of your own into the Core |

### `new-project`

Say "new project" (or run `/corecrew:new-project`) and Claude:

1. **Interviews you**: what the app does, for whom, platforms, first features, data, services,
   design, public or private code, what "done" means. Two or three questions at a time, in your language.
2. **Analyses** platform limits, compares two or three stacks with a recommendation, checks them
   against official docs, and sketches the architecture. You approve each part.
3. **Records decisions** in a small wiki in English (`docs/`: front matter on every page,
   `[[wikilinks]]`, a generated `INDEX.md`, decision records; it opens as an Obsidian vault).
4. **Scaffolds** the project with the stack's official generator and checks that it builds.
5. **Creates GitHub repos**, only after you approve each one.

### The layout

```
~/Projects/Core/              your private Core repo
  .coredev, PROJECTS.md, standards/, knowledge/
  my-app/CLAUDE.md, docs/     the private files of one project (<Core>/<name>/)
~/Projects/my-app/            the code (<Projects>/<name>): its own repo, may be public
  CLAUDE.local.md, AGENTS.md  gitignored links to Core/my-app/CLAUDE.md
```

Start Claude Code in the code folder. It reads the private `CLAUDE.md` through the
`CLAUDE.local.md` link, which session start makes and repairs. Projects made by 0.4 and older keep
the code in `<Core>/<name>/code/`; there `/corecrew:task` asks you to run
`/corecrew:task adopt <Core>/<name>/code` first, which moves it to this layout.

Rules for every session can go into `<Core>/session-rules.md` (optional): when it exists, session
start prints it into the conversation, and the engineer agent reads it before it writes code (its
rules for code; the brief and the project's `CLAUDE.md` win where they differ).

### What the hooks do

Inside a Core project (the Core folder, or a code folder beside it):

- **Session start** refreshes the plugin's tools, links `CLAUDE.local.md` and `AGENTS.md`, and
  prints the project, the docs index, the save and undo commands and your `session-rules.md`.
- **Secrets guard** refuses to read `.env`, `.env.*` (not `.env.example`, `.env.sample` or
  `.env.template`) and `~/.ssh`. For Bash it is a best-effort check, not a sandbox;
  [SECURITY.md](../../SECURITY.md#known-limits-of-the-hooks) lists what it does not see.
- **Code guard** refuses to write `CLAUDE.md`, `AGENTS.md`, `docs/` and `.claude/` into the code
  folder; they belong in the Core. List docs that should stay public in the code folder on a
  `public-docs: <paths>` line of the project's `CLAUDE.md`. It judges the paths of the file tools,
  and reads Bash plainly for the common write commands (redirects, `tee`, `touch`, `mkdir`, `cp`,
  `mv`, `install`, `ln`, `git mv`, `sed -i`, `perl -i`); [SECURITY.md](../../SECURITY.md#known-limits-of-the-hooks)
  lists what it does not follow.
- **One suite at a time** holds a test run (up to 120 s) while another runs in the same project
  folder, so two runs do not break each other.
- **Stop** reminds Claude to save a step that is left uncommitted.

Outside a Core project, session start only refreshes the tools and, once per machine, says that the
Core is not set up. The read-only checker rule applies everywhere: the designer, localizer,
security and verifier agents may write nothing but temp folders. Every other hook exits at once.

The git hooks in the code repo (pre-commit, pre-push) refuse internal files in commits and pushes.
The Core's pre-push hook refuses to push unless the Core's GitHub repo is private.

### Settings

| Key | Values | Default | Meaning |
|---|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` | Where your Core lives |
| `attribution` | `allow` / `forbid` | `allow` | Whether Claude may add `Co-Authored-By` and "Generated with" lines to commits and pull requests |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` | Which models the crew uses per role |
| `ui_language` | `en` / `ru` | `en` | Language of the hook messages |
| `codex_model` | `<model> [<effort>]` or `inherit` | — | Codex only: the model (and effort) of every crew role, over `model_profile`; `inherit` leaves Codex's own default |
| `codex_model_<role>` | `<model> [<effort>]` or `inherit` | — | Codex only: the same for one role (`engineer`, `tester`, ...), over `codex_model` |
| `coremodel_mode` | see the [coremodel README](../coremodel/README.md#codex) | — | Read only by coremodel's Codex hint, from the settings file; corecrew ignores it |

In Claude Code the settings are plugin options (`/plugin` → Installed → corecrew → Configure
options). Without an options screen (Codex, or a command-line install) they live in
`~/.config/corecrew/settings`, or in the file named by `CORECREW_CONFIG`: one `key: value` per line,
`#` starts a comment. The file is read, never run.

```
core_dir: ~/Projects/Core
attribution: allow
model_profile: balanced
ui_language: en
```

Per key, the first valid value wins: the `CORE_DIR` environment variable (`core_dir` only), the
plugin option, the settings file, the default. `core_dir` must be absolute or start with `~`; a
relative value such as `Core` is ignored with a warning. A value that is not listed is ignored
the same way, except `ui_language`, which falls back to `en` silently.

## Requirements

- **OS:** macOS and Linux; CI runs the tests on both.
  Windows needs [Git for Windows](https://git-scm.com/download/win), because the hooks run in Git Bash; it is untested.
- **Claude Code** 2.1.271 or newer (its settings with a list of choices need it), or the **Codex CLI**.
- **git**, and the **GitHub CLI** `gh`, logged in with `gh auth login`. `gh` is used to create repos,
  to check that a new project's name is free, to check that the Core repo is private before a push,
  and to publish a GitHub release.
- **Stack tools** (Flutter, Xcode, Node, Rust, uv) only for the stack you pick; `new-project` checks them.

### What it runs and sends

- **Scripts:** portable bash scripts from the plugin (`scripts/`, `hooks/`), `git`, and `gh`.
- **Network:** GitHub, through `gh` and `git`. Read-only checks run without a prompt (in Codex,
  whose sandbox has no network, every network call asks first):
  `new-project` checks that `gh` is logged in (`gh auth status`) and that the project name is free
  on GitHub (`gh repo view <name>`); `/corecrew:ship` fetches tags from `origin` to check for a
  clash; the Core pre-push hook asks `api.github.com` whether the Core repo is private. Writes
  happen only after your yes: each repo creation, each push, and the tag and GitHub release of
  `/corecrew:ship`. Stack generators you approve reach their own package hosts. corecrew sends
  nothing anywhere else.

### Changes outside the repo

- The tools copy in the plugin's data folder: `~/.claude/plugins/data/corecrew-corekit/` (Claude
  Code) or `~/.codex/plugins/data/corecrew-corekit/` (Codex; under `$CODEX_HOME` when set), refreshed at session start. Git hooks
  run the scripts from there.
- Your Core (the `core_dir` setting): read and written.
- In each code repo beside the Core: the `CLAUDE.local.md` and `AGENTS.md` links, git hooks
  (pre-commit, pre-push), and ignore lines in `.gitignore` when a project is adopted. In the Core: a
  pre-push hook.
- The settings file `~/.config/corecrew/settings`, only if you create it.

corecrew never overwrites or deletes your files.

### Known limitations

- Auto-triggering competes with other planning skills. Start it with `/corecrew:new-project`, or
  add to `~/.claude/CLAUDE.md`: `When I want to start a new project from scratch, use the new-project skill.`
- `bin/` and `hooks/` copies that 0.1.x put into your Core stay where they are; corecrew no
  longer writes there.

## Uninstall

The git hooks in your repos are small shims that run the scripts from the plugin's data folder.
Uninstalling the plugin deletes that folder, and then every commit and push in those repos stops
with `corecrew: ... is missing`. So remove the shims first.

1. In the Core and in every code folder, remove the corecrew git hooks (only files marked as
   corecrew shims are removed):

   ```bash
   for h in pre-commit pre-push; do
     f="$(git rev-parse --path-format=absolute --git-path "hooks/$h")"
     grep -qE '# (corecrew|coredev) hook shim' "$f" 2>/dev/null && rm "$f"
   done
   ```

2. In every code folder, remove the two links (only if they are links):

   ```bash
   for l in CLAUDE.local.md AGENTS.md; do [ -L "$l" ] && rm "$l"; done
   ```

3. Uninstall the plugin:
   - Claude Code: `claude plugin uninstall corecrew@corekit`. It deletes
     `~/.claude/plugins/data/corecrew-corekit/` unless you pass `--keep-data`.
   - Codex: `codex plugin remove corecrew@corekit`, then delete the tools folder corecrew made,
     `~/.codex/plugins/data/corecrew-corekit/` (under `$CODEX_HOME` when you set it). Codex does
     not know this folder and leaves it.

4. Optional:
   - Delete `~/.config/corecrew/settings`. coremodel's Codex hint reads it too.
   - If you pasted the Codex secrets profile: remove `default_permissions = "corecrew"` and the
     `[permissions.corecrew...]` tables from `~/.codex/config.toml`.

What stays: your Core, your code repos and their history, and the ignore lines in `.gitignore`.
They are yours; corecrew never deletes them.

## Development

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the rules and the tests, and
[ARCHITECTURE.md](../../ARCHITECTURE.md) for how the plugin is built. Trigger evals are in
`evals/` and run by hand with `claude plugin eval plugins/corecrew --ablation none --no-publish`.

## Licence

MIT — see [LICENSE](../../LICENSE).
