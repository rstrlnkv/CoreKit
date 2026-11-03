# CoreKit

The `coredev` Claude Code plugin: develop every project the same way, and keep your standards
and lessons in one private repo of your own. It lives in the `corekit` marketplace.

## Install

In Claude Code:
```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coredev@corekit
```
Claude Code asks for the three settings below when the plugin is enabled. The plugin depends on
`feature-dev` from the official `claude-plugins-official` marketplace and installs it with itself.

**Requirements:** macOS or Linux with bash, git, and the GitHub CLI (`gh`, logged in with
`gh auth login`). Stack tools (Flutter, Xcode, Node, Rust, uv) are checked when you pick a stack.

## Commands

| Command | What it does |
|---|---|
| `/coredev:new-project` | Interview, stack and architecture analysis, project skeleton (below) |
| `/coredev:task <task>` | Runs a task through the crew of agents |
| `/coredev:new-standard` | Writes a new standard into your Core |

## Settings

Set when the plugin is enabled; change later in `/plugin` → Installed → coredev → Configure options.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` | Where your private Core repo lives |
| `attribution` | `allow` / `forbid` | `allow` | Whether Claude may add `Co-Authored-By` and "Generated with" lines to commits and pull requests |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` | Which models the crew uses per role |

## Updates

The plugin updates only when its `version` changes. Auto-update is off for third-party
marketplaces by default: turn it on in `/plugin` → Marketplaces → corekit → Enable auto-update,
or update by hand with `/plugin marketplace update corekit`.

If you used this plugin as `corekit`: the marketplace migrates the old name, but run
`/plugin install coredev@corekit` once.

## `new-project`

Say "new project" (or run `/coredev:new-project`) and Claude:

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
  PROJECTS.md, bin/, hooks/
  my-app/CLAUDE.md, docs/, .claude/rules/
  my-app/code/                the code — its own repo, can be public
```
Claude Code is launched in `my-app/code/`; it still reads `CLAUDE.md` and rules from the folder
above. Internal files never sit inside the code repo, so publishing the code cannot leak them.
Five safety layers: separate folders, `.gitignore`, pre-commit and pre-push hooks in the code
repo, and a Core pre-push hook that refuses to push unless the GitHub repo is private.

`bin/save "<message>"` commits code and docs together as one step; `bin/undo-step` reverts the
last step in both (with `git revert`, history kept). A Stop hook reminds Claude to save.

## Known limitations
- Auto-triggering competes with other planning skills (e.g. Superpowers' brainstorming). Start it
  explicitly with `/coredev:new-project`, or add to `~/.claude/CLAUDE.md`:
  `When I want to start a new project from scratch, use the new-project skill.`
- Windows is not supported yet (the scripts are bash).
- Copies of `bin/` and `hooks/` in your docs repo are not updated automatically when the plugin
  updates.

## Development
```bash
bash tests/run.sh        # 200+ checks, no network
```
Design spec: `docs/specs/` · implementation plan: `docs/plans/` · trigger evals: `evals/`.

## License
MIT — see [LICENSE](LICENSE).
