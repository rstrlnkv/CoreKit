# Migrating to coredev 0.2

For an existing user of the `corekit` plugin (0.1.x). The plugin is now called `coredev`; the
marketplace and the repository stay `corekit`. Do the steps in order, once per machine.
`<Core>` is your Core folder (default `~/Projects/Core`); `<plugin>` is the installed plugin
folder (see step 5).

### Step 1. Update the marketplace and install `coredev`

In Claude Code:
```
/plugin marketplace update corekit
/plugin install coredev@corekit
```
The marketplace maps the old name `corekit` to `coredev`, but a git-hosted marketplace still
needs this one explicit install. Claude Code then asks for the three settings (step 2) and
installs the `feature-dev` dependency from `claude-plugins-official`.

> claude.ai-synced install: see below

TODO (filled in after the live check): what to do when `corekit` reached Claude Code through
claude.ai sync, so that the old and the new plugin do not run side by side.

### Step 2. Set the three settings

`/plugin` → Installed → coredev → Configure options:

| Key | Values | Owner's choice |
|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` (the default) |
| `attribution` | `allow` / `forbid` | `forbid` |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` (the default) |

### Step 3. Remove the old manual skill copy

Versions 0.1.x were installed by `install.sh`, which copied the skill to
`~/.claude/skills/new-project` and put a `.corekit` marker file in it. Check, then remove only
a folder that has the marker:
```bash
ls -a ~/.claude/skills/new-project        # look for .corekit
rm -r ~/.claude/skills/new-project        # only if .corekit is there
```
A folder without the marker is yours; leave it alone.

### Step 4. Remove the `Stop` hook from each existing project

The plugin ships the Stop hook now. In every project, open
`<Core>/<project>/code/.claude/settings.local.json` and delete the whole `"hooks"` block, so that
only the permissions stay:
```json
{
  "permissions": {
    "additionalDirectories": ["<Core>/<project>"]
  }
}
```
Do not forget the comma before `"hooks"` when you delete it. Without this step Claude is
reminded twice, once by the old hook (`<Core>/bin/stop-remind.sh`) and once by the plugin.

### Step 5. Re-install the git hooks as shims

Old hook files in `code/.git/hooks` and in the Core repo are full copies and go stale. Replace
them with shims that run the plugin's current scripts. For each project:
```bash
bash "<plugin>/scripts/install-hooks.sh" <Core>/<project>
```
`<plugin>` is the folder of the installed plugin version:
`~/.claude/plugins/cache/corekit/coredev/<version>/` (for example `.../coredev/0.2.0/`; the
root moves to `$CLAUDE_CODE_PLUGIN_CACHE_DIR` if you set that variable). Another way to find it:
use the folder printed at session start, or ask Claude where the `coredev` plugin is installed.
The script also refreshes the plugin tools copy in the plugin data folder. It is safe to run
again; it prints what it did.

### Step 6. Move personal rules, turn on auto-update

- Move your personal rules (the ones you keep for every project) into
  `<Core>/session-rules.md`.
- Auto-update is off by default for third-party marketplaces: `/plugin` → Marketplaces →
  corekit → Enable auto-update. Updates arrive only when the plugin's `version` changes.

### Step 7. Restart Claude Code

Quit and start `claude` again. In a project's `code/` folder, check that `/coredev:new-project`
is listed and that a finished working step produces the reminder to run `save`.

## What stays as it was

`<Core>/bin/` and `<Core>/hooks/` copies written by 0.1.x are your files. They keep working but
are no longer updated, and the plugin no longer writes there. You can delete them once all
projects went through steps 4 and 5.

## claude.ai-synced install

TODO (filled in after the live check): exact steps, as observed in Claude Code.
