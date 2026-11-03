# Migrating to coredev 0.2

For an existing user of the `corekit` plugin (0.1.x). The plugin is now called `coredev`; the
marketplace and the repository stay `corekit`. Do the steps in order. Steps 1, 2, 3, 6 and 7
are done once per machine; steps 4 and 5 are done for each existing project.
`<Core>` is your Core folder (default `~/Projects/Core`).

### Step 1. Update the marketplace and install `coredev`

In Claude Code:
```
/plugin marketplace update corekit
/plugin install coredev@corekit
```
The marketplace maps the old name `corekit` to `coredev`, but a git-hosted marketplace still
needs this one explicit install. Claude Code then asks for the three settings (step 2).

`/coredev:task` also needs the `feature-dev` plugin. If you do not have it (not from claude.ai
either), install it: `/plugin install feature-dev@claude-plugins-official`.

If `corekit` reached Claude Code through claude.ai sync, the old plugin is still there and both
`corekit:new-project` and `coredev:new-project` load. In a terminal, check:
```bash
claude plugin list
```
If the list shows `corekit@synced`, switch it off:
```bash
claude plugin disable corekit@synced
```
(or remove `corekit` from the plugins of your claude.ai account).

### Step 2. Set the three settings

`/plugin` → Installed → coredev → Configure options:

| Key | Values | Recommended |
|---|---|---|
| `core_dir` | a folder | `~/Projects/Core` (the default) |
| `attribution` | `allow` / `forbid` | `allow`; the repo owner uses `forbid` |
| `model_profile` | `economy` / `balanced` / `strong` | `balanced` (the default) |

### Step 3. Remove the old manual skill copy

Versions 0.1.x were installed by `install.sh`, which copied the skill to
`~/.claude/skills/new-project` and put a `.corekit` marker file in it. This removes the folder
only when the marker is there:
```bash
[ -f ~/.claude/skills/new-project/.corekit ] && rm -r ~/.claude/skills/new-project && echo removed || echo "left alone (no marker)"
```
A folder without the marker is yours; leave it alone.

### Step 4. Remove the `Stop` hook from each existing project

The plugin ships the Stop hook now. In every project, open
`<Core>/<project>/code/.claude/settings.local.json`. Delete the whole `"hooks": { ... }` entry
(from `"hooks"` to its closing `}`), and delete the comma after the `"permissions"` block that
stood before it. Keep any other content of the file. The result:
```json
{
  "permissions": {
    "additionalDirectories": ["<Core>/<project>"]
  }
}
```
Check that the file is still valid JSON:
```bash
python3 -m json.tool <Core>/<project>/code/.claude/settings.local.json >/dev/null && echo ok
```
Without this step Claude is reminded twice, once by the old hook (`<Core>/bin/stop-remind.sh`)
and once by the plugin.

### Step 5. Re-install the git hooks as shims

Old hook files in `code/.git/hooks` and in the Core repo are full copies and go stale. Replace
them with shims that run the plugin's current scripts. The plugin is installed in
`~/.claude/plugins/cache/corekit/coredev/<version>/` (the root moves if you set
`CLAUDE_CODE_PLUGIN_CACHE_DIR`). First see which versions are there and pick the newest:
```bash
ls ~/.claude/plugins/cache/corekit/coredev/
```
Then, for each project (replace `<version>` and `<project>`):
```bash
bash "$HOME/.claude/plugins/cache/corekit/coredev/<version>/scripts/install-hooks.sh" "$HOME/Projects/Core/<project>"
```
If your Core is not in `~/Projects/Core`, use its real path instead. The script also refreshes the
plugin tools copy in the plugin data folder. It is safe to run again; it prints what it did.

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
