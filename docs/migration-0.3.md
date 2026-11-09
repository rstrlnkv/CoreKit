# Upgrading to corecrew

For a user of `coredev` 0.2.x or of the `corekit` plugin 0.1.x. The plugin is now called `corecrew`
(brand CoreCrew), and the second plugin `effort-picker` is now `coremodel` (CoreModel; it was called
`coreeffort` for a short time). The marketplace and the repository stay `corekit`. Coming from
0.1.x (`corekit`), also do the steps of
[Coming from 0.1.x (corekit), also](#coming-from-01x-corekit-also) after Step 5.
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
/plugin install coremodel@corekit
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

Settings belong to a plugin name, so the new plugins start with the defaults. Set them in
`/plugin` → Installed → the plugin → Configure options:

- corecrew: `core_dir`, `attribution`, `model_profile`, `ui_language`.
- coremodel: `mode`, `language`, `classifier`, `useHaiku`, `useSonnet`, `useOpus`, `useFable`,
  `pickModel`. The older text setting with a list of models is no longer read: untick the models
  you do not want with the four Allow switches.

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
`corecrew:<role>`; the model and effort command is `/coremodel`. Update any of your own notes or
`~/.claude/CLAUDE.md` lines that name `coredev` or `effort-picker`.

### Step 5. Restart Claude Code

Quit and start `claude` again. In a project's code folder, check that `/corecrew:task` is
listed and that the session start shows no note about old git hooks.

## Coming from 0.1.x (corekit), also

Versions 0.1.x were the `corekit` plugin. Do these steps once, after Step 5.

1. Remove the old manual skill copy. 0.1.x was installed by `install.sh`, which copied the skill to
   `~/.claude/skills/new-project` and put a `.corekit` marker file in it. This removes the folder
   only when the marker is there:
   ```bash
   [ -f ~/.claude/skills/new-project/.corekit ] && rm -r ~/.claude/skills/new-project && echo removed || echo "left alone (no marker)"
   ```
   A folder without the marker is yours; leave it alone. If `claude plugin list` shows
   `corekit@synced` (the old plugin from claude.ai sync), run `claude plugin disable corekit@synced`.
2. Remove the `Stop` hook from each existing project. The plugin ships the Stop hook now. In every
   project, open `<Core>/<project>/code/.claude/settings.local.json`. Delete the whole
   `"hooks": { ... }` entry (from `"hooks"` to its closing `}`), and delete the comma after the
   `"permissions"` block that stood before it. Keep any other content of the file. The result:
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
3. Move personal rules and turn on auto-update.
   - Move your personal rules (the ones you keep for every project) into `<Core>/session-rules.md`,
     and commit it: `git -C <Core> add session-rules.md && git -C <Core> commit -m "Add session rules"`.
     `/corecrew:task` stops while a Core file it commits with a step has uncommitted changes.
   - Auto-update is off by default for third-party marketplaces: `/plugin` → Marketplaces →
     corekit → Enable auto-update. Updates arrive only when the plugin's `version` changes.

`<Core>/bin/` and `<Core>/hooks/` copies written by 0.1.x are your files. They keep working but
are no longer updated, and the plugin no longer writes there. You can delete them once every
project went through step 2 above and Step 3.
