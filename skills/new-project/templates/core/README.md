# Internal project documentation

Private repository. It holds CLAUDE.md, docs/ and Claude rules for every project, plus your
standards and knowledge. Only your data lives here; the commands (`save`, `undo-step`, hooks)
come from the `coredev` plugin.
Each project's code lives in a nested `code/` folder with its own repository,
so internal files never get into it.

Layout: `<project-name>/{CLAUDE.md, docs/, .claude/rules/, code/}`.
`code/` is a separate repository and is ignored here.
Launch Claude Code in `<project-name>/code/`.
Shared: `standards/` (your standards), `knowledge/` (lessons for all projects),
`.coredev` (layout version and settings).
Project list: [PROJECTS.md](PROJECTS.md).
