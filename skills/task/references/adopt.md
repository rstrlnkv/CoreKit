# Adopt

`/corecrew:task adopt <folder>`: move an existing project into the Core layout
(`<Core>/<name>/` for internal docs, `<Core>/<name>/code/` for the repo). Start has already
resolved `<Core>`, checked that it is set up, and noted `<scripts>` (the plugin scripts folder).
No crew, no tester: only you and the script. Talk to the user in plain words; never run
`adopt.sh` before "ok".

1. **Inspect** `<folder>` (resolve it to an absolute path; `~` counts as home). Look at
   its name, `CLAUDE.md`, `AGENTS.md`, `docs/`, `.claude/` and the top level of the repo. Never open `.env`
   files or `~/.ssh`.
2. **Plan.** Run `CORE_DIR="<Core>" bash "<scripts>/adopt.sh" --from "<folder>" --dry-run`
   (add `--name <n>` when the folder name is not a valid project name: 3-40 lowercase Latin
   letters, digits and hyphens). A refusal (one line, exit 2) is final: explain it in plain
   words, say what to do about it, change nothing. Otherwise tell the user in plain words:
   the name; which files move to `<Core>/<name>/`; that git history stays and one commit
   "Move internal Claude files to Core" removes them from the repo and adds the corecrew ignore
   lines the repo's `.gitignore` lacks (listed under "add to code/.gitignore"; the user's own lines
   stay as they are), so local Claude files never reach a commit; that the folder itself is
   moved to `<Core>/<name>/code`, so the old path stops working; what gets created.
   If the plan lists `CLAUDE.md` or `.claude/` under "stays in code (ignored by git)", tell
   the user: the Core gets a template `CLAUDE.md`, and their own file stays in `code/`.
3. **Public docs.** Ask which docs, if any, stay in the repo for everyone to read (for
   example `docs/`, or one page). Those paths are not moved and are listed as `public-docs:`.
4. **Purpose.** Ask for one line on what the project is for; it goes on the `PROJECTS.md`
   line (`--purpose "<text>"`). Do not fill it in yourself.
5. **Check command.** Detect the likely one from the repo (`package.json` scripts,
   `Makefile`, `tests/run.sh`, `Cargo.toml`, `go.mod`, `pyproject.toml`, ...). Offer it and
   let the user confirm or change it. None found: leave it out; `task` asks later.
6. **Wait for "ok"** after showing the final plan (re-run `--dry-run` with the chosen
   `--public-docs` and `--check` if the answers changed it).
7. **Run** `CORE_DIR="<Core>" bash "<scripts>/adopt.sh" --from "<folder>" [--name <n>] [--public-docs "<paths>"] [--check "<command>"] --purpose "<text>"`.
   Relay every `warning:` line and every `WARN:` line (from the hook install) in plain words:
   a `WARN:` means a hook of the user's own was left in place, so the corecrew guard is not
   installed in that repo; say so. A non-zero exit: show its lines and stop (exit 1 means a
   move failed: nothing was deleted, and the lines say where the files are).
8. **Verify** with `bash "<scripts>/wiki-check.sh" "<Core>/<name>"`.
   Red: say which pages and why; the usual cause is a link or reference in an old page that
   no longer resolves. Pages the script gave new front matter hold `TODO` descriptions and
   `status: draft`: say they still need writing.
9. **Report** in plain words, with these lines:
   - `Path: adopt`
   - what moved (old and new path), the `check:` command or that it is not set yet
   - the wiki result
   - `Open Claude Code in: <Core>/<name>/code`, and tell the user to restart Claude Code there,
     because this session still runs in the old folder, which is gone. Claude Code's history
     for the old path does not move with it.
