# CoreKit

A marketplace of Claude Code plugins: `corecrew` runs every project the same way, `coremodel` picks the model and effort per prompt, `coreopinion` asks GPT for a second opinion.

![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows%20Git%20Bash-lightgrey) ![corecrew](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcorecrew%2F.claude-plugin%2Fplugin.json&query=%24.version&label=corecrew) ![coremodel](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoremodel%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coremodel) ![coreopinion](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoreopinion%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coreopinion) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

## Install

You need Claude Code 2.1.271 or newer, git, and the GitHub CLI (`gh`, logged in with
`gh auth login`). Stack tools (Flutter, Xcode, Node, Rust, uv) are checked when you pick a stack.

### Mac and Linux

Open Terminal and run these three commands, one after another:
```
claude plugin marketplace add rstrlnkv/CoreKit
claude plugin install corecrew@corekit
claude plugin install feature-dev@claude-plugins-official
```
The first adds the `corekit` marketplace, the second installs `corecrew`, the third installs
`feature-dev`, which `/corecrew:task` needs (its `code-architect` and `code-explorer` agents).
Skip the third if you already have `feature-dev` from claude.ai. It is not a hard dependency, so
`corecrew` loads either way, and `/corecrew:task` tells you at start if it is missing.

Start `claude` (restart it if it was open). Then run `/corecrew:new-project`: on the first run
it shows what it will create, and after your "ok" sets up your private Core repo.

### Windows

1. Install [Git for Windows](https://git-scm.com/download/win). It is required: the plugin's
   hooks run in Git Bash. Full Windows support comes later, so expect rough edges.
2. Install the GitHub CLI and run `gh auth login`.
3. Run the same three `claude plugin ...` commands as on Mac and Linux, in PowerShell or in Git Bash.
4. Start `claude` and run `/corecrew:new-project`.

### Inside Claude Code

You can also type the same steps in a running Claude Code session. Claude Code then asks for
the plugin's settings when it is enabled:
```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install corecrew@corekit
/plugin install feature-dev@claude-plugins-official
```

### Plugin settings at install time

An install from the command line does not ask for the plugin's settings, so the defaults apply
until you set them. To change them, in Claude Code open `/plugin` → Installed → corecrew →
Configure options. `claude plugin configure corecrew@corekit` shows which settings are still
unset. You can also give a value at install time, for example
`claude plugin install corecrew@corekit --config attribution=forbid`, or
`claude plugin install corecrew@corekit --config ui_language=ru` for Russian hook messages.

### Update

The same commands on Mac, Linux and Windows (PowerShell or Git Bash):
```
claude plugin marketplace update corekit
claude plugin update corecrew@corekit
```
Then restart Claude Code. An update never touches your Core, standards or knowledge files.

`corecrew` updates only when its `version` changes. Auto-update is off for third-party
marketplaces by default: turn it on in `/plugin` → Marketplaces → corekit → Enable auto-update.

If you used `corecrew` as `coredev` (0.2.x), follow [docs/migration-0.3.md](docs/migration-0.3.md).
If you come from 0.1.x (`corekit`), follow [docs/migration-0.2.md](docs/migration-0.2.md) first.

### coremodel and coreopinion

The two smaller plugins install on their own and do not need `corecrew`:
```
/plugin install coremodel@corekit
/plugin install coreopinion@corekit
```
Run them after `/plugin marketplace add rstrlnkv/CoreKit` (above). Details are in [plugins/coremodel/README.md](plugins/coremodel/README.md) and [plugins/coreopinion/README.md](plugins/coreopinion/README.md).

## Features

| Feature | What it does |
|---|---|
| `corecrew` | Starts a project from an interview, runs tasks with a crew of agents, releases, and keeps your standards and lessons in one private repo of your own (the Core) |
| `coremodel` | Before Claude starts on a prompt, picks the model (Haiku, Sonnet, Opus, Fable) and the effort level the work needs; asks before Fable, Extra high and Max. Details: [plugins/coremodel/README.md](plugins/coremodel/README.md) |
| `coreopinion` | Asks OpenAI's GPT, through the Codex CLI with a narrow read-only permission profile, for a second opinion or a review (`/coreopinion:second-opinion`). Only Claude edits, after your yes. Details: [plugins/coreopinion/README.md](plugins/coreopinion/README.md) |

### Commands (corecrew)

| Command | What it does |
|---|---|
| `/corecrew:new-project` | Interview, stack and architecture analysis, project skeleton (below) |
| `/corecrew:task <task>` | Runs a task through the crew of agents |
| `/corecrew:task release <version>` | Prepares a release: version, changelog and the other release postconditions |
| `/corecrew:task adopt <folder>` | Brings an existing project into the Core layout |
| `/corecrew:ship [patch\|minor\|major\|<version>]` | Releases the current branch, then, after your yes, fast-forwards `main` to it and pushes |
| `/corecrew:new-standard` | Writes a new standard into your Core |

### Settings (corecrew)

Asked when the plugin is enabled from inside Claude Code (a command-line install keeps the defaults until you set them); change later in `/plugin` → Installed → corecrew → Configure options.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` | Where your private Core repo lives |
| `attribution` | `allow` / `forbid` | `allow` | Whether Claude may add `Co-Authored-By` and "Generated with" lines to commits and pull requests |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` | Which models the crew uses per role |
| `ui_language` | `en` / `ru` | `en` | Language of the messages the hooks show |

### `new-project` (corecrew)

Say "new project" (or run `/corecrew:new-project`) and Claude:

1. **Interviews you** — what the app does, for whom, platforms, v1 features, data, services,
   design, public or private code, definition of done (2–3 questions at a time, in your language).
2. **Analyses** platform constraints, compares 2–3 stacks with scores and a recommendation
   (Flutter, SwiftUI, Tauri, Vite, Python bot/CLI), verifies them against official docs, and
   sketches the architecture. You approve each part.
3. **Records decisions** in a small wiki (`docs/`: typed YAML front matter, `[[wikilinks]]`, a generated `INDEX.md`, ADRs; opens as an Obsidian vault) — in English.
4. **Scaffolds** the project with the stack's official generator and checks that it builds.
5. **Creates GitHub repos** — only after you approve each one.

#### The layout
```
~/Projects/Core/              one PRIVATE repo with the internal docs of all your projects
  .coredev, PROJECTS.md, standards/, knowledge/
  my-app/CLAUDE.md, docs/     private files of the project (<Core>/<name>/)
~/Projects/my-app/            the code (<Projects>/<name> in the docs) — its own repo, can be public
  CLAUDE.local.md, AGENTS.md  gitignored links to Core/my-app/CLAUDE.md
```
`<Projects>` is the folder that holds the Core. Launch Claude Code in the code folder
(`~/Projects/my-app`): it reads the private `CLAUDE.md` through the `CLAUDE.local.md` link, which
session start makes and repairs. Rules live in `CLAUDE.md`. Internal files never sit inside the
code repo, so publishing the code cannot leak them. Five safety layers: separate folders,
`.gitignore`, pre-commit and pre-push hooks in the code repo, and a Core pre-push hook that
refuses to push unless the GitHub repo is private. Projects made by 0.4 and older keep the code
in `<Core>/<name>/code/`: in such a project `/corecrew:task` stops and asks you to run
`/corecrew:task adopt <Core>/<name>/code` first, which moves it to the new layout.

Rules for every session can go into `<Core>/session-rules.md` (optional, yours): when that file
exists, session start prints it into the conversation.

Claude runs the `corecrew` `save` tool to commit code and docs together as one step, and `undo-step`
to revert the last step in both (with `git revert`, history kept). Nothing is copied into your
Core. The `corecrew` Stop hook reminds Claude to save when a step is left uncommitted.

#### What the hooks do

Except for the first item and the read-only checker rule in the code guard (which applies wherever the agent runs), these hooks work inside a Core project (the Core folder, or the code folder beside it) and nowhere else:

- **Session start** refreshes the `corecrew` tools, links `CLAUDE.local.md` and `AGENTS.md`, and prints the project, the docs index, the save and undo commands and your `session-rules.md`.
- **Secrets guard** refuses to read `.env`, `.env.*` (not `.env.example`) and `~/.ssh`, also through `bash -c`, `sh -c` and `eval`.
  For Bash it is a best-effort check, not a sandbox: it does not see `python -c`, `node -e`, `find -exec`, `git show REV:.env`, `dd` or `curl -F @.env`.
  Treat it as a seat belt against accidents, not as protection from a determined program.
- **Code guard** refuses to write `CLAUDE.md`, `AGENTS.md`, `docs/` and `.claude/` into the code folder, which may be public; they belong in the Core.
- **Read-only checkers**: the designer, localizer, security and verifier agents may change nothing but the temp folders. Their Bash writes, removals, in-place edits, links, downloads, unpacking and git changes are refused, wherever they run; a command the check cannot read whole is refused too.
  After a `cd` only absolute paths may be written (`/tmp/log`, not `log`). It reads the shell command, not the programs it starts: a build, `python -c` or `node -e` is not judged.
- **One suite at a time** holds a test run while another one runs on the machine, so two suites do not break each other.
- **Stop** reminds Claude to save a step that is left uncommitted.

Outside a Core project there are two exceptions: the session-start hook refreshes the plugin's tools and, once per machine, prints a hint that the Core is not set up; and the code guard still refuses the writes of a read-only checker agent. Every other hook exits at once and prints nothing.

## Requirements

### Systems and tools

- **OS:** macOS (Apple silicon and Intel) and Linux. Windows needs [Git for Windows](https://git-scm.com/download/win) (the hooks run in Git Bash) and is not fully supported yet. The scripts are portable bash (macOS bash 3.2).
- **Claude Code** 2.1.271 or later for `corecrew` and `coreopinion` (the plugin settings with a list of choices, `userConfig` with `options`, need it; an older client cannot load them). `coremodel` needs 2.1.287 or later (its hooks run as a module).
- **git** and the **GitHub CLI** (`gh auth login`) for `corecrew`. `feature-dev@claude-plugins-official` is used by `/corecrew:task` but is not a hard dependency.
- **The Codex CLI**, signed in with a ChatGPT plan (Plus or higher), for `coreopinion` only; see [plugins/coreopinion/README.md](plugins/coreopinion/README.md#requirements).

### Network

- `corecrew`: the GitHub API through `gh`, only when you approve a repo creation or a push (`gh repo create`, `git push`), and the Core pre-push hook asks `api.github.com` whether the Core repo is private. Stack generators you approve (Flutter, Node, Rust, uv) reach their own package hosts.
- `coremodel`: no host of its own; its classifier call goes through your Claude Code account.
- `coreopinion`: OpenAI, through the Codex CLI, with the files you confirmed (see [plugins/coreopinion/README.md](plugins/coreopinion/README.md)).

### Changes outside the repo

- `corecrew` keeps its tools in `~/.claude/plugins/data/corecrew-corekit/` (refreshed at session start), reads and writes your private Core (`~/Projects/Core` by default, the `core_dir` setting), writes `CLAUDE.local.md` and `AGENTS.md` links and git hooks (pre-commit, pre-push) into the code repos beside the Core, and adds ignore lines to a `.gitignore` when it adopts a project. It never overwrites or deletes your files.
- `coremodel` writes errors to `~/.claude/mods-logs/coremodel.log`.
- `coreopinion` writes a temp folder with the prompt and removes it at the end; it reads `codex` credentials only through the Codex CLI.
- Outside a Core project the `corecrew` session-start hook still refreshes the tools in that data folder and, once per machine, prints a "Core not set up" hint, and the code guard still refuses the writes of a read-only checker agent; every other hook exits at once and prints nothing.

### Known limitations

- Auto-triggering competes with other planning skills (e.g. Superpowers' brainstorming). Start it
  explicitly with `/corecrew:new-project`, or add to `~/.claude/CLAUDE.md`:
  `When I want to start a new project from scratch, use the new-project skill.`
- `bin/` and `hooks/` copies that 0.1.x put in your Core are left as they are (they are
  your files); `corecrew` no longer writes there.

## Build from source

```bash
bash tests/run.sh        # all tests, no network, prints ALL TESTS PASSED
claude plugin validate . # the marketplace; also plugins/corecrew, plugins/coremodel, plugins/coreopinion
```
Trigger evals (does a skill start when it should, and stay silent when it should not):
`plugins/corecrew/evals/` and `plugins/coreopinion/evals/`, run by hand with
`claude plugin eval plugins/corecrew --ablation none --no-publish` (real model calls, under a
dollar a plugin; not part of `tests/run.sh`). How the repo is laid out: [ARCHITECTURE.md](ARCHITECTURE.md). To report
a vulnerability: [SECURITY.md](SECURITY.md).

## Licence

MIT — see [LICENSE](LICENSE).
