# Older formats

Projects made by older corecrew versions keep working; this file says how each older format is
brought up to date. A skill sends you to one section when it meets that format. `<plugin>` and
`<scripts>` are the paths the skill resolved under Paths.

## Wiki without types
A wiki from corecrew 0.6 has Markdown links, a hand-written map and its specs and plans in
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
An older `docs/brief.md` keeps the new-project stage as `stage: <v>` in its front matter. The wiki
allows exactly six front-matter fields, so the stage lives in the last section `## Progress`, as one
line `Stage: <v>`. Write that section as the last one and delete the field in the same edit, then run
`bash "<scripts>/wiki-check.sh" "<Core>/<name>"`. If `## Progress` already exists, only delete the field.

## Old layout
An older project keeps its code repo inside the Core, at `<Core>/<name>/code`. `lib.sh layout <name>`
prints `old` for it. `/corecrew:task adopt <path>` moves it beside the Core, to `<Projects>/<name>`
(`<plugin>/skills/task/references/adopt.md` has the steps).
