# Older formats

Projects made by older corecrew versions keep working; this file says how each older format is
brought up to date. Most sections are reached from a skill, which sends you to one when it meets
that format; the last ones are reported at session start. `<plugin>` and `<scripts>` are the paths
the skill resolved under Paths.

## Old layout
Made by corecrew 0.1.0-0.4.0.
Supported until corecrew 1.0.

An older project keeps its code repo inside the Core, at `<Core>/<name>/code`. `lib.sh layout <name>`
prints `old` for it. `/corecrew:task adopt <path>` moves it beside the Core, to `<Projects>/<name>`
(`<plugin>/skills/task/references/adopt.md` has the steps).

## Core without a schema
Made by corecrew 0.1.0-0.4.0.
Supported until corecrew 1.0.

The Core's `.coredev` has no `schema:` line, or a schema number lower than the plugin's. At session
start `prepare.sh` prints a layout note with the command to bring it up to date; relay it. That
command runs `setup-core.sh`, which puts the current `schema:` line first in `.coredev`, keeps its
other lines and adds only what is missing.
