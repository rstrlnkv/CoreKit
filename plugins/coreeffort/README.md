# coreeffort

A Claude Code plugin in the `corekit` marketplace. Before Claude starts on a prompt, a short model
call reads it and picks the effort level the work needs: Low, Medium, High, Extra high or Max. It
knows both kinds of work Claude Code gets: code in a repository (a typo is Low, a bug with an
unknown cause is High, a whole app built alone is Extra high) and office work (a polite rewrite is
Low, a contract risk review is High).

Approvals such as "yes", "go on" or "да, давай" keep the level as it is.

## Modes

- **suggest** (the default): when the pick differs from your level, Claude waits and asks:
  "Switch to High", "Switch, and auto-adjust from now", or "Keep Medium".
- **auto**: switches among Low, Medium and High by itself, up or down, and says so in a line
  above the prompt. **It always asks before Extra high or Max**: those are the long, costly runs.
- **off**: does nothing.

The texts are in Russian for a Russian prompt and in English otherwise.

## The effort menu does not move

The plugin puts the chosen level on every request of this chat only. It never writes your effort
setting, so other chats and later sessions keep your own default. The menu next to the model name
therefore keeps showing your own setting; the footer shows a label such as **Effort High**, and
`/coreeffort` prints the level the chat really runs at. Move the menu yourself, or start a new
session, and the plugin lets go of its level.

## Commands

- `/coreeffort` shows the mode and the real level.
- `/coreeffort auto`, `/coreeffort suggest` set the mode for every session.
- `/coreeffort off` and `/coreeffort on` turn it off and back on.

## Settings

`/plugin` → Installed → coreeffort → Configure options:

- `mode`: `suggest`, `auto` or `off` (default `suggest`). `/coreeffort` wins over it.
- `classifier`: `sonnet` (default, the more accurate) or `haiku` (faster, cheaper).

## Install

Claude Code 2.1.287 or newer (`claude --version`; update with `claude update`). The plugin uses
Claude Code's early-access plugin API, which can change between releases.

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coreeffort@corekit
```

## Cost

One short classifier call per prompt you type (at most 120 output tokens), through your own
Claude Code account; it adds about 1 to 3 seconds before Claude starts. Slash commands and
messages that do not come from the prompt box are never checked. Errors are written to
`~/.claude/mods-logs/coreeffort.log` and never block the prompt.

## Credits

The idea comes from Ben AI's "Effort Optimizer" mod. No code or text of it is reused.
