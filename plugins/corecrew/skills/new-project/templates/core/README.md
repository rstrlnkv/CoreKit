# Internal project documentation

Private repository. It holds CLAUDE.md and docs/ for every project, plus your standards and
knowledge. Only your data lives here; the commands (`save`, `undo-step`, hooks) come from the
`corecrew` plugin.
Each project's code lives in its own repository in the folder next to this one
(`../<Name>/`, a folder whose lower-case name is the project name: `../my-app/` or `../My-App/`
for the project `my-app`), so internal files never get into it.

Layout: `<project>/{CLAUDE.md, docs/}` here; the code repository is `../<Name>/`.
Its `CLAUDE.local.md` and `AGENTS.md` are gitignored symlinks to the project's `CLAUDE.md` here.
Each project's `docs/` is an Obsidian vault; `docs/INDEX.md` is generated, never edited by hand.
Start your agent in the code folder, `../<Name>/`: Claude Code as is, or Codex with
`codex --add-dir "<Core>"` (the path of this folder), so it may also write here.
Shared: `standards/` (your standards), `knowledge/` (lessons for all projects),
`session-rules.md` (optional: your rules, shown at every session start),
`.coredev` (layout version and settings).
Project list: [PROJECTS.md](PROJECTS.md).
