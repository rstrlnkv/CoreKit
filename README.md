# CoreKit

Claude Code skills for starting projects the same way every time.

## `new-project`

Say "new project" (or run `/corekit:new-project`) and Claude:

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

## Install

In Claude Code:
```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install corekit@corekit
```
Or manually: `git clone https://github.com/rstrlnkv/CoreKit && bash CoreKit/install.sh`
(copies the skill to `~/.claude/skills/`; then it runs as `/new-project`).

On first run the skill asks where to keep projects (default `~/Projects`), the name of the private
docs repo (default `Core`) and your app id prefix (e.g. `com.yourname`), and saves them to
`~/.config/new-project/config`. Change them any time:
`bash <skill>/scripts/configure.sh --projects-dir ~/dev --core-name Docs --app-id-prefix com.me`.

**Requirements:** macOS or Linux with bash, git, and the GitHub CLI (`gh`, logged in with
`gh auth login`). Stack tools (Flutter, Xcode, Node, Rust, uv) are checked when you pick a stack.

## Known limitations
- Auto-triggering competes with other planning skills (e.g. Superpowers' brainstorming). Start it
  explicitly with `/corekit:new-project`, or add to `~/.claude/CLAUDE.md`:
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
