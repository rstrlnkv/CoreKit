# Core — internal project documentation

Private repository. It holds CLAUDE.md, docs/ and Claude rules for every project.
Each project's code lives in a nested `code/` folder with its own repository,
so internal files never get into it.

Layout: `Core/<project-name>/{CLAUDE.md, docs/, .claude/rules/, code/}`.
`code/` is a separate repository and is ignored here.
Launch Claude Code in `Core/<project-name>/code/`.
Shared commands: `bin/save`, `bin/undo-step`.
Project list: [PROJECTS.md](PROJECTS.md).
