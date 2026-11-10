# Older formats

Projects made by older corecrew versions keep working; this file says how each older format is
brought up to date. Most sections are reached from a skill, which sends you to one when it meets
that format; the last ones are reported at session start. `<plugin>` and `<scripts>` are the paths
the skill resolved under Paths.

## Wiki without types
Made by corecrew 0.1.0-0.6.6.
Supported until corecrew 1.0 for the parts only such a wiki needs (`docs/superpowers/` and the
offer in a task chain); `adopt` keeps the general conversion.

A wiki from corecrew 0.6 and older has Markdown links, a hand-written map and its specs and plans in
`docs/superpowers/`. `wiki-index.sh` refuses it with `wiki-index: no page has a type; run wiki-migrate.sh first`.
`bash "<scripts>/wiki-migrate.sh" "<Core>/<project>" [--dry-run]` converts it: typed front matter,
wikilinks, specs and plans moved to `docs/specs/` and `docs/plans/`. A `warning:` line names what to
fix by hand (old `CLAUDE.md` lines too). It also moves a brief's one-line `stage:` field (see below).
`adopt` runs it by itself.

In a task chain (Start, **Wiki**):
1. Run `bash "<scripts>/wiki-migrate.sh" "<Core>/<project>" --dry-run`, show its output to the user
   and ask for an "ok".
2. On "ok" run it again without `--dry-run`, and commit it as its own step from the code root:
   `bash "<scripts>/save" "wiki: migrate to the 0.7 format"` (with attribution=forbid add
   `--no-attribution`). This needs the clean tree of Start, **Clean tree** (on `question`, check it
   now).
3. Without that "ok", stop the chain.

## Brief with a stage field
Made by corecrew 0.1.0-0.7.1.
Supported until corecrew 1.0.

An older `docs/brief.md` keeps the new-project stage as `stage: <v>` in its front matter. The wiki
allows exactly six front-matter fields, so the stage lives in the last section `## Progress`, as one
line `Stage: <v>`. Write that section as the last one and delete the field in the same edit, then run
`bash "<scripts>/wiki-check.sh" "<Core>/<name>"`. If `## Progress` already exists, only delete the field.

## Knowledge with sections
Made by corecrew 0.2.0-0.9.1.
Supported until corecrew 1.0.

A knowledge file from corecrew 0.9 and older has four sections (`## How proof is made here`,
`## Where things are`, `## What has broken here`, `## What you must not do here`) and may link
family files `<role>/<Family>.md`. Agents read it as it is. `task`
never restructures it: a new line goes at the end of `## What has broken here` of the role file.
The user may move the lines into one list by hand; the current form is
`<plugin>/reference/knowledge.md`.

## Old layout
Made by corecrew 0.1.0-0.4.0.
Supported until corecrew 1.0.

An older project keeps its code repo inside the Core, at `<Core>/<name>/code`. `lib.sh layout <name>`
prints `old` for it. `/corecrew:task adopt <path>` moves it beside the Core, to `<Projects>/<name>`
(`<plugin>/skills/task/references/adopt.md` has the steps).

## Core bin/ and hooks/ folders (0.1.x)
Made by corecrew 0.1.0-0.1.1.
Supported until corecrew 1.0.

corecrew 0.1.x put copies of `save`, `undo-step` and its git hooks into the Core, in `<Core>/bin/`
and `<Core>/hooks/`. corecrew no longer writes there or runs those copies; only a git hook from 0.1
still does, until it is replaced (next section). A Core that tracks the folders keeps them: `save`
still commits a change or a deletion there with the step, and the clean-tree check of a task chain
names them.

## Old git hooks
Made by corecrew 0.1.0-0.2.1.
Supported until corecrew 1.0.

Git hooks from corecrew 0.1 (a hook with the line `new-project hook`) and 0.2 (a shim with the line
`# coredev hook shim`, from when the plugin was called coredev) run a tools copy that is no longer
updated. `install-hooks.sh` calls these markers `OLD_MARK` and `OLD_SHIM`. At session start
`prepare.sh` names each such hook in a note with the command to replace them; relay it. That command
runs `install-hooks.sh`, which writes current shims over them and leaves a hook of the user's own
alone.

## Core without a schema
Made by corecrew 0.1.0-0.4.0.
Supported until corecrew 1.0.

The Core's `.coredev` has no `schema:` line, or a schema number lower than the plugin's. At session
start `prepare.sh` prints a layout note with the command to bring it up to date; relay it. That
command runs `setup-core.sh`, which puts the current `schema:` line first in `.coredev`, keeps its
other lines and adds only what is missing.
