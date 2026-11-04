# CoreKit

The `corecrew` Claude Code plugin: develop every project the same way, and keep your standards
and lessons in one private repo of your own. It lives in the `corekit` marketplace.

## Install

You need Claude Code 2.1.271 or newer, git, and the GitHub CLI (`gh`, logged in with
`gh auth login`). Stack tools (Flutter, Xcode, Node, Rust, uv) are checked when you pick a stack.

### Mac (and Linux)

Open Terminal and run these three commands, one after another:
```
claude plugin marketplace add rstrlnkv/CoreKit
claude plugin install corecrew@corekit
claude plugin install feature-dev@claude-plugins-official
```
The first adds the `corekit` marketplace, the second installs this plugin, the third installs
`feature-dev`, which `/corecrew:task` needs (its `code-architect` and `code-explorer` agents).
Skip the third if you already have `feature-dev` from claude.ai. It is not a hard dependency, so
`corecrew` loads either way, and `/corecrew:task` tells you at start if it is missing.

Start `claude` (restart it if it was open). Then run `/corecrew:new-project`: on the first run
it shows what it will create, and after your "ok" sets up your private Core repo.

### Windows

1. Install [Git for Windows](https://git-scm.com/download/win). It is required: the plugin's
   hooks run in Git Bash. Full Windows support comes later, so expect rough edges.
2. Install the GitHub CLI and run `gh auth login`.
3. Run the same three `claude plugin ...` commands as on Mac, in PowerShell or in Git Bash.
4. Start `claude` and run `/corecrew:new-project`.

### Inside Claude Code

You can also type the same steps in a running Claude Code session. Claude Code then asks for
the plugin's settings when it is enabled:
```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install corecrew@corekit
/plugin install feature-dev@claude-plugins-official
```

### Settings

An install from the command line does not ask for the plugin's settings, so the defaults apply
until you set them. To change them, in Claude Code open `/plugin` → Installed → corecrew →
Configure options. `claude plugin configure corecrew@corekit` shows which settings are still
unset. You can also give a value at install time, for example
`claude plugin install corecrew@corekit --config attribution=forbid`, or
`claude plugin install corecrew@corekit --config ui_language=ru` for Russian hook messages.

## Update

The same commands on Mac and on Windows (PowerShell or Git Bash):
```
claude plugin marketplace update corekit
claude plugin update corecrew@corekit
```
Then restart Claude Code. An update never touches your Core, standards or knowledge files.

The plugin updates only when its `version` changes. Auto-update is off for third-party
marketplaces by default: turn it on in `/plugin` → Marketplaces → corekit → Enable auto-update.

If you used this plugin as `coredev` (0.2.x), follow [docs/migration-0.3.md](docs/migration-0.3.md).
If you come from 0.1.x (`corekit`), follow [docs/migration-0.2.md](docs/migration-0.2.md) first.

## Commands

| Command | What it does |
|---|---|
| `/corecrew:new-project` | Interview, stack and architecture analysis, project skeleton (below) |
| `/corecrew:task <task>` | Runs a task through the crew of agents |
| `/corecrew:new-standard` | Writes a new standard into your Core |

## Settings

Asked when the plugin is enabled from inside Claude Code (a command-line install keeps the defaults until you set them); change later in `/plugin` → Installed → corecrew → Configure options.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` | Where your private Core repo lives |
| `attribution` | `allow` / `forbid` | `allow` | Whether Claude may add `Co-Authored-By` and "Generated with" lines to commits and pull requests |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` | Which models the crew uses per role |
| `ui_language` | `en` / `ru` | `en` | Language of the messages the hooks show |

## `new-project`

Say "new project" (or run `/corecrew:new-project`) and Claude:

1. **Interviews you** — what the app does, for whom, platforms, v1 features, data, services,
   design, public or private code, definition of done (2–3 questions at a time, in your language).
2. **Analyses** platform constraints, compares 2–3 stacks with scores and a recommendation
   (Flutter, SwiftUI, Tauri, Vite, Python bot/CLI), verifies them against official docs, and
   sketches the architecture. You approve each part.
3. **Records decisions** in a small wiki (`docs/`, YAML front matter, ADRs) — in English.
4. **Scaffolds** the project with the stack's official generator and checks that it builds.
5. **Creates GitHub repos** — only after you approve each one.

### The layout
```
~/Projects/Core/              one PRIVATE repo with the internal docs of all your projects
  .coredev, PROJECTS.md, standards/, knowledge/
  my-app/CLAUDE.md, docs/, .claude/rules/
  my-app/code/                the code — its own repo, can be public
```
Claude Code is launched in `my-app/code/`; it still reads `CLAUDE.md` and rules from the folder
above. Internal files never sit inside the code repo, so publishing the code cannot leak them.
Five safety layers: separate folders, `.gitignore`, pre-commit and pre-push hooks in the code
repo, and a Core pre-push hook that refuses to push unless the GitHub repo is private.

Claude runs the plugin's `save` tool to commit code and docs together as one step, and `undo-step`
to revert the last step in both (with `git revert`, history kept). Nothing is copied into your
docs repo. The plugin's Stop hook reminds Claude to save when a step is left uncommitted.

## `coremodel` (a second plugin)

The `corekit` marketplace also holds `coremodel` (formerly `coreeffort`): before Claude starts on a
prompt it picks the model (Haiku, Sonnet, Opus, Fable) and the effort level the work needs, for
code and office work alike, and offers the switch (or makes it, in auto mode, always asking before
Fable, Extra high and Max, and naming the token cost of any model switch mid-chat). It needs Claude Code 2.1.287 or newer and
does not depend on `corecrew`:
```
/plugin install coremodel@corekit
```
Details: plugins/coremodel/README.md.

## `coreopinion` (a third plugin)

`coreopinion` lets Claude ask OpenAI's GPT, through the Codex CLI in a read-only sandbox, for a
second opinion or a review (`/coreopinion:second-opinion`), and shows GPT's answer next to
Claude's own assessment. Only Claude edits, after your yes. It needs the Codex CLI signed in with
a ChatGPT plan and does not depend on the other plugins:
```
/plugin install coreopinion@corekit
```
Details: plugins/coreopinion/README.md.

## Known limitations
- Auto-triggering competes with other planning skills (e.g. Superpowers' brainstorming). Start it
  explicitly with `/corecrew:new-project`, or add to `~/.claude/CLAUDE.md`:
  `When I want to start a new project from scratch, use the new-project skill.`
- Windows needs Git for Windows (the hooks run in Git Bash) and is not fully supported yet.
- `bin/` and `hooks/` copies that 0.1.x put in your docs repo are left as they are (they are
  your files); the plugin no longer writes there.

## Development
```bash
bash tests/run.sh        # 200+ checks, no network
```
Design spec: `docs/specs/` · implementation plan: `docs/plans/` · trigger evals: `evals/`.

## License
MIT — see [LICENSE](LICENSE).
