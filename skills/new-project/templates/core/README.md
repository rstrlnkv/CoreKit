# Internal project documentation

Private repository. It holds CLAUDE.md and docs/ for every project, plus your standards and
knowledge. Only your data lives here; the commands (`save`, `undo-step`, hooks) come from the
`corecrew` plugin.
Each project's code lives in its own repository in the folder next to this one
(`<project-name>/` beside the Core), so internal files never get into it.

Layout: `<project-name>/{CLAUDE.md, docs/}` here; the code repository is `../<project-name>/`.
Its `CLAUDE.local.md` is a gitignored symlink to the project's `CLAUDE.md` here.
Launch Claude Code in the code folder, `../<project-name>/`.
Shared: `standards/` (your standards), `knowledge/` (lessons for all projects),
`.coredev` (layout version and settings).
Project list: [PROJECTS.md](PROJECTS.md).
