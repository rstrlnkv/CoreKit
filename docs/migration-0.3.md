# Migrating to corecrew 0.3

For a user of `coredev` 0.2.x. The plugin is now called `corecrew` (brand CoreCrew), and the
second plugin `effort-picker` is now `coreeffort` (CoreEffort). The marketplace and the
repository stay `corekit`. If you come from 0.1.x (`corekit`), do
[migration-0.2.md](migration-0.2.md) first.
`<Core>` is your Core folder (default `~/Projects/Core`). It needs no change: `<Core>/.coredev`
keeps its name.

### Step 1. Update the marketplace and install the new names

In Claude Code:
```
/plugin marketplace update corekit
/plugin install corecrew@corekit
```
If you used `effort-picker`:
```
/plugin install coreeffort@corekit
```
The marketplace maps the old names to the new ones, but a git-hosted marketplace still needs
this one explicit install. Then check in a terminal:
```bash
claude plugin list
```
If `coredev@corekit` or `effort-picker@corekit` is still listed, remove it:
```bash
claude plugin uninstall coredev@corekit
claude plugin uninstall effort-picker@corekit
```

### Step 2. Set the settings again

Settings belong to a plugin name, so the new plugins start with the defaults.
`/plugin` → Installed → corecrew → Configure options: `core_dir`, `attribution`,
`model_profile`, `ui_language`. For coreeffort: `mode`, `classifier`.

### Step 3. Re-install the git hooks

The plugin data folder is now `~/.claude/plugins/data/corecrew-corekit`. The 0.2.x hook shims
still run the old copy in `coredev-corekit`, which no longer updates. A session start in a
project names these hooks. For each project (pick the newest `<version>` from
`ls ~/.claude/plugins/cache/corekit/corecrew/`):
```bash
bash "$HOME/.claude/plugins/cache/corekit/corecrew/<version>/scripts/install-hooks.sh" "$HOME/Projects/Core/<project>"
```
After every project is done, you can delete `~/.claude/plugins/data/coredev-corekit`.

### Step 4. Use the new names

Commands are `/corecrew:new-project`, `/corecrew:task`, `/corecrew:new-standard`; agents are
`corecrew:<role>`; the effort command is `/coreeffort`. Update any of your own notes or
`~/.claude/CLAUDE.md` lines that name `coredev` or `effort-picker`.

### Step 5. Restart Claude Code

Quit and start `claude` again. In a project's `code/` folder, check that `/corecrew:task` is
listed and that the session start shows no note about old git hooks.
