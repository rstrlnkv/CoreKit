# Adopt

`/corecrew:task adopt <folder>`: bring an existing project into the corecrew layout. The repo
stays where it is, in `<Projects>/<Name>` (`<Projects>` is the folder that holds `<Core>`); its
internal files move to `<Core>/<name>/` (`<name>` is `<Name>` in lower case) and reach the
session through `CLAUDE.local.md`, a gitignored link to `<Core>/<name>/CLAUDE.md`. Only a project
still in the old layout (its repo at `<Core>/<name>/code`) is moved, to `<Projects>/<name>`.
Start has already resolved `<Core>`, checked that it is set up, and noted `<scripts>` (the plugin
scripts folder). No crew, no tester: only you and the script. Talk to the user in plain words;
never run `adopt.sh` before "ok".

1. **Inspect** `<folder>` (resolve it to an absolute path; `~` counts as home). Look at
   its name, `CLAUDE.md`, `AGENTS.md`, `docs/`, `.claude/` and the top level of the repo. Never open `.env`
   files or `~/.ssh`.
2. **Plan.** Run `CORE_DIR="<Core>" bash "<scripts>/adopt.sh" --from "<folder>" --dry-run`.
   A refusal (one line, exit 2) is final: explain it in plain words, say what to do about it,
   change nothing. The usual ones:
   - `not in <Projects>: move the folder to <Projects>/<Name> first`: the folder must sit directly
     in `<Projects>`; the user moves it there (adopt never moves a repo of the new layout).
   - `invalid project name` or `name ... does not match the folder`: the folder name, in lower
     case, must be 3-40 Latin letters, digits and hyphens; the user renames the folder.
   - `target exists: <path>`: that folder is taken; nothing is merged or overwritten.
   - `different disk` (old layout): the Core sits on another disk than `<Projects>`, so the code
     folder cannot be moved by a rename; the user puts the Core on the same disk first.
   - `CLAUDE.local.md exists`: the user moves their own file away first.

   Otherwise tell the user in plain words:
   - the name, and that the folder stays where it is (old layout: that it moves from
     `<Core>/<name>/code` to `<Projects>/<name>`, so the old path stops working);
   - which files go to `<Core>/<name>/` (under "copy to");
   - the rule files under "fold into ... under ## Rules": their text becomes a subsection of the
     Rules section of the private `CLAUDE.md` (with "Applies to: ..." for rules limited to some
     files), because rule files kept in the Core would not load; in the old layout these are the
     rule files already in `<Core>/<name>/.claude/rules/` (for example `tests.md`): they stay
     there, and their text joins the private `CLAUDE.md` in the "Adopt <name>" commit;
   - the files under "kept in Core, no longer loaded": they are kept in `<Core>/<name>/.claude/`
     but Claude Code no longer reads them (for example `settings.json` permissions or hooks,
     custom commands); if the user still needs one, it has to be set up again another way;
   - that git history stays and one commit "Move internal Claude files to Core" removes those
     files from the repo and adds the corecrew ignore lines the repo's `.gitignore` lacks (listed
     under "add to .gitignore"; the user's own lines stay as they are), so local Claude files never
     reach a commit, and, when the repo has none, a `.worktreeinclude` that copies
     `.claude/settings.local.json` into new worktrees (an existing one is left as is);
   - the `CLAUDE.local.md` link and `.claude/settings.local.json` (created, or a `warning:` line:
     the user's own file is left as is and needs the `additionalDirectories` entry it names);
   - what gets created.
   If the plan lists `CLAUDE.md` or `.claude/` under "stays in the repo (ignored by git)", tell
   the user: the Core gets a template `CLAUDE.md`, and their own file stays in the repo.
   If the plan has the `warning: git tracks N CLAUDE.md / AGENTS.md file(s) that stay in the repo`
   line, raise it before asking for "ok": those files (often test fixtures) stay in the repo, but
   after adopt corecrew's hooks and guard block changing them or adding new ones there, so the
   user decides whether that is acceptable, or renames them first.
   Old layout: a `warning: ... still names ../docs/ or `code/` paths` line means the private
   `CLAUDE.md` has paths that pointed from the old code folder; adopt does not rewrite them, so
   offer to fix them afterwards (as `<Core>/<name>/docs/...`).
3. **Public docs** (new layout only). Ask which docs, if any, stay in the repo for everyone to
   read (for example `docs/`, or one page). Those paths are not moved and are listed as `public-docs:`.
4. **Purpose.** Ask for one line on what the project is for; it goes on the `PROJECTS.md`
   line (`--purpose "<text>"`). Do not fill it in yourself. An old-layout project already has a
   line: ask only if the user wants to change it.
5. **Check command** (new layout only). Detect the likely one from the repo (`package.json` scripts,
   `Makefile`, `tests/run.sh`, `Cargo.toml`, `go.mod`, `pyproject.toml`, ...). Offer it and
   let the user confirm or change it. None found: leave it out; `task` asks later.
6. **Wait for "ok"** after showing the final plan (re-run `--dry-run` with the chosen
   `--public-docs` and `--check` if the answers changed it).
7. **Run** `CORE_DIR="<Core>" bash "<scripts>/adopt.sh" --from "<folder>" [--name <n>] [--public-docs "<paths>"] [--check "<command>"] --purpose "<text>"`
   (old layout: only `--purpose`).
   Relay every `warning:` line and every `WARN:` line (from the hook install) in plain words:
   a `WARN:` means a hook of the user's own was left in place, so the corecrew guard is not
   installed in that repo; say so. A non-zero exit: show its lines and stop (exit 1 means a
   step after the repo commit failed: nothing was deleted, and the lines say where the files are).
8. **Verify** with `bash "<scripts>/wiki-check.sh" "<Core>/<name>"`.
   Red: say which pages and why; the usual cause is a link or reference in an old page that
   no longer resolves. Pages the script gave new front matter hold `TODO` descriptions and
   `status: draft`: say they still need writing.
9. **Report** in plain words, with these lines:
   - `Path: adopt`
   - the code folder: unchanged (new layout), or the old and new path (old layout); the
     `check:` command or that it is not set yet
   - the rules folded into `CLAUDE.md`, and the files "kept in Core, no longer loaded"
   - the wiki result
   - `Open Claude Code in: <code folder>` (the script's last line, `open: ...`), and tell the
     user to restart Claude Code in that folder: the private `CLAUDE.md` loads through
     `CLAUDE.local.md` only in a new session. Old layout: this session still runs in the old
     folder, which is gone, and Claude Code's history for the old path does not move with it.
