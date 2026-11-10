# Older formats

Projects made by older corecrew versions keep working; this file says how each older format is
brought up to date. The formats here are reported at session start. `<plugin>` and `<scripts>` are
the paths the skill resolved under Paths.

## Core without a schema
Made by corecrew 0.1.0-0.4.0.
Supported until corecrew 1.0.

The Core's `.coredev` has no `schema:` line, or a schema number lower than the plugin's. At session
start `prepare.sh` prints a layout note with the command to bring it up to date; relay it. That
command runs `setup-core.sh`, which puts the current `schema:` line first in `.coredev`, keeps its
other lines and adds only what is missing.
