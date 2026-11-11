# CoreCrew

Run every project the same way: start from an interview, work with a crew of agents, keep the docs in a private repo.

![platform](https://img.shields.io/badge/platform-Claude%20Code%202.1.271%2B%20%7C%20Codex%20CLI-lightgrey) ![release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcorecrew%2F.claude-plugin%2Fplugin.json&query=%24.version&label=release) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

`corecrew` starts a new app from a short interview, runs each task through a crew of agents (an
engineer writes, a tester and read-only checkers review), and keeps your standards, lessons and
each project's internal docs in one private git repo of your own, the Core. The code of each
project lives in its own repo beside the Core, so publishing the code never publishes your internal
notes. It works in Claude Code and in the Codex CLI.

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
   you do, corecrew's guards (project docs in code, secrets) stay off. The interactive `codex` asks
   at start to review new or changed hooks. `codex exec` and other non-interactive runs do not ask
   and skip the hooks silently, so `new-project`, `task` and `ship` remind you when they run. Do it
   again after each update.
2. **Write the settings file.** Codex has no options screen; see [Settings](#settings).
3. **Give Codex your Core.** Codex writes only in the working folder and `--add-dir` folders, so
   start it as `codex --add-dir "<Core>"` (`~/Projects/Core` by default). For new-project, start it
   as `codex --add-dir "<Projects>"` (the folder that holds the Core): the Core may not exist yet,
   and the new code folder goes there. Every skill checks this and tells you the command.
4. **Name the skills.** Codex may pick `new-project` and `bloat-audit` by itself. Name the others in your prompt
   (`$corecrew:task <task>`, `$corecrew:ship`, `$corecrew:new-standard`) or pick them from the
   skill list.
5. **Optional: the secrets profile.** See [SECURITY.md](../../SECURITY.md#recommended-host-settings).

What differs from Claude Code:

- The crew roles are role files that `/corecrew:task` hands to Codex subagents as text, with the
  model and effort from `model_profile`, or from `codex_model` / `codex_model_<role>` when set.
  `feature-dev` is not used.
- The crew needs Codex subagents. In a session without the `spawn_agent` tool the chain stops and
  says so.
- Commits ask for your approval: the Codex sandbox keeps `.git` read-only, so `save` runs outside
  it after you approve.
- A non-interactive run needs a sandbox that can write, with the Core added. In a folder Codex
  does not trust yet, a plain `codex exec` is a read-only session and stops at the Core check.
  Run `codex exec --sandbox workspace-write --add-dir "<Core>"`. With the corecrew secrets profile
  as your default, run `codex exec --add-dir "<Core>"` instead: `--sandbox` switches the profile off.
  Then the whole chain runs and only the commit stops, with
  `Commit: stopped — Codex sandbox keeps .git read-only`, and the files stay uncommitted.
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

Coming from `coredev` (0.2.x), `corekit` (0.1.x) or a project made by corecrew 0.4 or older: corecrew
1.0 no longer converts those. Install corecrew 0.15 first and follow the upgrade guide and the
0.15.0 notes of the tag `corecrew-v0.15.0`.

## Features

| Feature | What it does |
|---|---|
| [`new-project`](#new-project) | Interviews you, compares stacks, records the decisions in the Core and scaffolds the code repo |
| `task` | Runs a task through the crew of agents and ends with a report and one commit; also prepares a release and adopts an existing project |
| `ship` | Releases the current branch: pushes it after your yes, tags it and publishes a GitHub release after a second yes |
| `new-standard` | Helps you write a standard of your own into the Core |
| `bloat-audit` | Reads a whole repo and lists, ranked, what can be deleted, merged or replaced; changes nothing |
| [The guards](#what-the-hooks-do) | Hooks refuse to read secrets and to write internal files into the code folder; git hooks keep internal files out of commits and pushes |
| Save and undo | `save` commits one step in the code repo and the Core together; `undo-step` reverts the last one in both |
| [The settings](#settings) | The Core folder, attribution, the crew's models and the language of the hook messages |

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
| `/corecrew:ship [<part>] [patch\|minor\|major\|<version>]` | Releases the current branch (in a repo with several versioned parts, the one `<part>` you name; from the default branch it offers a release branch), then, after your yes, pushes the branch, waits for its CI checks, fast-forwards the default branch and pushes it; after a second yes, tags the version and publishes a GitHub release |
| `/corecrew:new-standard` | Helps you write a standard of your own into the Core |
| `/corecrew:bloat-audit` | Lists what the repo could lose: duplicates, hand-written standard library, one-user abstractions, unused settings, dead code |

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
the code in `<Core>/<name>/code/`, a layout this version no longer supports: session start says so,
and `save`, `undo-step` and `adopt` refuse such a project without changing it. Move it beside the
Core with corecrew 0.15 (`/corecrew:task adopt <Core>/<name>/code`) first.

Rules for every session can go into `<Core>/session-rules.md` (optional): when it exists, session
start prints it into the conversation, and the engineer agent reads it before it writes code (its
rules for code; the brief and the project's `CLAUDE.md` win where they differ).

### What the hooks do

Inside a Core project (the project's folder in the Core, `<Core>/<name>/`, or its code folder beside the Core):

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
  lists what it does not follow. In Codex both guards also refuse a patch handed to the shell
  (`apply_patch` run through Bash): it cannot be checked.
- **One suite at a time** holds a test run (up to 120 s) while another runs in the same project
  folder, so two runs do not break each other.
- **Stop** reminds the agent to save a step that is left uncommitted.

Outside a Core project, session start refreshes the tools, names a setting it had to ignore and,
once per machine, says that the Core is not set up. In Claude Code the read-only checker rule
applies everywhere: the designer, localizer, security and verifier agents may write nothing but
temp folders; it does not act for Codex subagents, which the chain checks instead. In Codex the
code guard also refuses, in any folder, a patch handed to the shell and a patch it cannot check
(more than 100 files, a missing reader, or an unreadable patch that names an internal path).
"Outside a Core project" means the session folder. The code guard judges the path written, so a
write into a project's code folder is refused from any session folder. The secrets guard, the
one-suite hook and the Stop reminder act only when the session folder is in a project.

The git hooks in the code repo (pre-commit, pre-push) refuse internal files in commits and pushes.
The Core's pre-push hook refuses to push unless the Core's GitHub repo is private.

### Settings

| Key | Values | Default | Meaning |
|---|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` | Where your Core lives |
| `attribution` | `allow` / `forbid` | `allow` | Whether corecrew's own commits (`save`) may carry `Co-Authored-By` and "Generated with" lines; `forbid` strips them. A plain `git commit` is governed by the host's own attribution setting |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` | Which models the crew uses per role |
| `ui_language` | `en` / `ru` | `en` | Language of the hook messages |
| `codex_model` | `<model> [<effort>]` or `inherit` | — | Codex only: the model (and effort) of every crew role, over `model_profile`; `inherit` leaves Codex's own default |
| `codex_model_<role>` | `<model> [<effort>]` or `inherit` | — | Codex only: the same for one role (`engineer`, `tester`, ...), over `codex_model` |
| `coremodel_mode` | see the [coremodel README](../coremodel/README.md#codex) | — | Read only by coremodel's Codex hint, from the settings file; corecrew ignores it |

`ui_language` covers only the messages of corecrew's own scripts: the hooks and the checks a skill
runs when it starts. It does not follow Claude Code's `language` setting. The skills talk to you in
your language whatever `ui_language` says (from your Claude settings or instructions, else the
language you write in). For Russian messages set `ui_language` to `ru`: at install time with
`--config ui_language=ru` ([Install](#claude-code)), in `/plugin` → Installed → corecrew →
Configure options, or in the settings file below. coremodel has a `language` setting of its own.

In Claude Code the settings are plugin options (`/plugin` → Installed → corecrew → Configure
options). Without an options screen (Codex, or a command-line install) they live in
`~/.config/corecrew/settings` (`$XDG_CONFIG_HOME/corecrew/settings` when that is set), or in the
file named by `CORECREW_CONFIG`: one `key: value` per line; a line that starts with `#` is a
comment (a `#` after a value is part of the value). The file is read, never run.

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

- **OS:** macOS and Linux; CI runs the tests on both. Any CPU architecture: the plugin is bash
  scripts with no native code.
  Windows needs [Git for Windows](https://git-scm.com/download/win), because the hooks run in Git Bash; it is untested.
- **Claude Code** 2.1.271 or newer (its settings with a list of choices need it), or the **Codex CLI** (tested with 0.166).
- **git**, and the **GitHub CLI** `gh`, logged in with `gh auth login`. `gh` is used to create repos,
  to check that a new project's name is free, to check that the Core repo is private before a push,
  and to publish a GitHub release.
- **Stack tools** (Flutter, Xcode, Node, Rust, uv) only for the stack you pick; `new-project` checks them.
- **Permissions:** the hooks refuse some reads and writes ([What the hooks do](#what-the-hooks-do)).
  `new-project` and `/corecrew:task adopt` write `.claude/settings.local.json` into the code folder
  with `permissions.additionalDirectories` set to the project's folder in the Core
  (`<Core>/<name>`), so Claude can reach the project's private files from the code folder. An
  existing file is left as it is; adopt then names the entry to add. corecrew's `.gitignore` lines
  keep the file out of commits.

### What it runs and sends

- **Scripts:** portable bash scripts from the plugin (`scripts/`, `hooks/`), `git`, and `gh`.
- **Network:** GitHub, through `gh` and `git`. Read-only checks run without a prompt (in Codex,
  whose sandbox has no network, every network call asks first):
  `new-project` checks that `gh` is logged in (`gh auth status`) and that the project name is free
  on GitHub (`gh repo view <name>`); `/corecrew:ship` fetches tags from `origin` to check for a
  clash and reads the CI runs of the branch it pushed (`gh run list`, `gh run watch`); the Core
  pre-push hook asks `api.github.com` whether the Core repo is private. Writes happen only after
  your yes: each repo creation, each push (the branch, then the default branch), and the tag and
  GitHub release of `/corecrew:ship`. Stack generators you approve reach their own package hosts. corecrew sends
  nothing anywhere else.

### Changes outside the repo

- The tools copy in the plugin's data folder: `~/.claude/plugins/data/corecrew-corekit/` (Claude
  Code) or `~/.codex/plugins/data/corecrew-corekit/` (Codex; under `$CODEX_HOME` when set), refreshed at session start. Git hooks
  run the scripts from there. Installed from a marketplace with another name, the folder is
  `corecrew-<marketplace>`.
- Your Core (the `core_dir` setting): read and written.
- In each code repo beside the Core: the `CLAUDE.local.md` and `AGENTS.md` links, git hooks
  (pre-commit, pre-push), and ignore lines in `.gitignore` when a project is adopted. In the Core: a
  pre-push hook. `/corecrew:task adopt` also moves the tracked `CLAUDE.md`, `AGENTS.md`, `docs/`
  and `.claude/` files into the Core and commits that in the repo ("Move internal Claude files to
  Core"), adding a `.worktreeinclude`; it shows the plan first.
- The settings file, only if you create it ([Settings](#settings) has its path).
- Small state files:
  - In Codex, a marker that the hooks ran: `state/hooks-seen-codex` beside the settings file
    (`~/.config/corecrew/state/hooks-seen-codex` by default). Session start writes the plugin
    version into it.
  - The turn folder of the one-suite hook: `one-suite/` in the plugin's data folder, or
    `$TMPDIR/corecrew-one-suite-<uid>` when the host names no data folder.
  - `.git/new-project-stop-remind` in a code repo: what the Stop reminder last reminded about.

Outside adopt, which moves those files into the Core, corecrew never overwrites or deletes your files.

### Known limitations

- Auto-triggering competes with other planning skills. Start it with `/corecrew:new-project`, or
  add to `~/.claude/CLAUDE.md`: `When I want to start a new project from scratch, use the new-project skill.`
- `bin/` and `hooks/` copies that 0.1.x put into your Core stay where they are; corecrew no
  longer writes there, and `save` no longer commits a change there. Delete them by hand.

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
   - Delete `~/.config/corecrew/` (the settings file and, in Codex, the `state/` marker).
     coremodel's Codex hint reads the settings file too.
   - Delete `.git/new-project-stop-remind` in a code repo, and a `corecrew-one-suite-<uid>` folder
     in your temp folder. Both are safe to delete.
   - If you pasted the Codex secrets profile: remove `default_permissions = "corecrew"` and the
     `[permissions.corecrew...]` tables from `~/.codex/config.toml`.

What stays: your Core, your code repos and their history, and the ignore lines in `.gitignore`.
They are yours; corecrew never deletes them.

## Development

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the rules and the tests, and
[ARCHITECTURE.md](../../ARCHITECTURE.md) for how the plugin is built. Trigger evals are in
`evals/corecrew/` at the repo root and run by hand with `bash scripts/eval.sh corecrew`.

## Licence

MIT — see [LICENSE](../../LICENSE).
