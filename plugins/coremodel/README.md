# coremodel

A Claude Code plugin that picks the model and the effort level each prompt needs, before Claude starts on it.

![platform](https://img.shields.io/badge/platform-Claude%20Code%202.1.287%2B-lightgrey) ![release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoremodel%2F.claude-plugin%2Fplugin.json&query=%24.version&label=release) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

## Install

Claude Code 2.1.287 or newer (`claude --version`; update with `claude update`). The plugin uses
Claude Code's early-access plugin API, which can change between releases. It is in the `corekit`
marketplace (formerly CoreEffort) and does not depend on `corecrew`.

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coremodel@corekit
```

Update: `claude plugin marketplace update corekit`, `claude plugin update coremodel@corekit`, then restart Claude Code.

## Features

| Feature | What it does |
|---|---|
| Model pick | Before Claude starts on a prompt, a short model call picks the model: Haiku, Sonnet, Opus or Fable |
| Effort pick | Picks the effort level independently: Low, Medium, High, Extra high or Max |
| Cost-aware switching | On the first prompt the model may change in either direction (`suggest` asks first, `auto` switches by itself, except to Fable); later it only offers a stronger model, always with a question that names the token cost |
| Modes | `suggest` (asks), `auto` (switches Low, Medium, High by itself; always asks before Extra high, Max and Fable), `off` |
| The pane | A footer button opens a pane with the current pair, Model, Level and Mode buttons, the last pick and session counts |
| Your menus stay put | The pick is put on the requests of this chat only; your model and effort settings are never written |
| Account-aware | Reads the models your account can use and never picks one it lacks |
| Commands and settings | `/coremodel` and its sub-commands; the settings are listed below |

The two picks are independent: a polite email is Haiku at Low, a contract risk review is Opus at
High, a whole app built alone is Fable at Extra high. Approvals such as "yes", "go on" or "да,
давай" (Russian for "yes, go ahead") keep both as they are.

### When the model changes, and what it costs

Claude re-reads the whole chat before every reply, and keeps what it has read in a cache that is
tied to one model. Reading from the cache is cheap; after a model switch the new model reads the
whole chat again at full price. So:

- On the **first prompt** of a chat the model may change in either direction: there is nothing to re-read.
  In `suggest` mode (the default) it still asks first, in `auto` mode it switches by itself, and a
  switch to Fable always asks.
- **Later** coremodel only offers a **stronger** model, always with a question that names the cost,
  for example "Switch to Opus (many files)? The chat is read again once: ≈ 100k tokens, about
  $0.50 at API prices". It never offers a weaker model mid-chat: the re-read would eat the saving.
- **Fable** always asks first.

### Modes

- **suggest** (the default): when a pick differs, Claude waits and asks, the model first, then the
  effort, each in its own short question with the recommended choice first ("Opus (recommended)",
  "Keep Sonnet", …). The effort question then ends with **← Back to the model**, to change the
  model answer; a level can also be typed.
- **auto**: switches the effort among Low, Medium and High by itself, up or down, and the model on
  the first prompt; says so in a line above the prompt, with a **Back to …** button (or the key
  `1`) that undoes what it switched. **It always asks before Extra high, Max or Fable**, and
  before any model switch mid-chat.
- **off**: does nothing.

Every switch also leaves a mark in the chat, such as "↑ Opus · High (was Sonnet · Medium) · why",
and while the plugin holds a model or level the working line names it ("Thinking… · Opus · High")
and the footer names the pair beside the CoreModel button ("Opus • High").

The texts are in Russian for a Russian prompt and in English otherwise.

### The pane

Open it without typing anything into the chat: press the **CoreModel** button in the footer
under the prompt (the slot where the mode labels sit, on the terminal and the desktop app); press
it again to close the pane. Nothing is sent to the model, so a running turn is not interrupted.
`/coremodel panel` opens it too. The pane sits beside the chat (above the prompt in a narrow
terminal); its keys and the close mark are the engine's own (Esc, ctrl+x x). There is no
shortcut of the plugin's own: the hooks API gives a plugin no keys of its own.

From top to bottom, the pane shows:

- **Now in the chat**: the model and level the chat really runs at, and, while the plugin holds
  something, "held by CoreModel" with the menu's own choice.
- **Model** and **Level** buttons, the current ones highlighted. A press holds your pick at
  once, Fable, Extra high and Max included: your own pick is your yes. A model pressed mid-chat
  first shows the cost question. **Back to the menu's choice** lets go of what the plugin holds.
- **Mode**: Suggest, Auto, Off, with a line on what the chosen mode does.
- **Last pick**: the pair, whether it was applied or you kept what you had, and the reason.
- **This session**: how often each model and level was picked, and how many prompts were left alone.

Button rows wrap, so nothing is hidden in a narrow pane.

### Your menus do not move

The plugin puts the chosen model and level on every request of this chat only. It never writes
your model or effort setting, so other chats and later sessions keep your own defaults. The menus
therefore keep showing your own settings; the footer shows **Opus • High** beside the CoreModel button, and
`/coremodel` prints what the chat really runs at. Choose a model with `/model` or move the effort
menu yourself, and the plugin lets go of that part; a new chat (`/clear`, `/resume`) or a new
session lets go of both.

**Which models are offered.** coremodel reads the list of models your account can use from the
Model row of `/config` (the same list `/model` shows), before every pick and at the start of a
session. A model that is not in it, such as Fable on a plan without it, is never picked or offered:
when the pick names it, the nearest model you can use takes its place (the one below it first, so
Opus for Fable), and the reason says so: "Fable is not available, Opus instead" in the question,
the switch line and the transcript. The same holds for a model you switched off.
When a model becomes available later, it is offered from the next pick: nothing is stored, so
nothing needs a restart. If the list cannot be read, nothing is filtered. `/coremodel recheck` reads
it again at once and also brings back a model that was dropped after an error.

If a model the plugin picked still fails (`model_not_found`), the turn fails once; coremodel then
stops using that model for the session and says so in the pane (`/coremodel recheck` undoes that).
The four **Allow Haiku / Sonnet / Opus / Fable** switches in the plugin settings (all on by default)
are a limit on top of the account's list: untick a model you never want, and coremodel never picks it.
They can only narrow the list, never add a model your account does not have. With every switch off
coremodel picks the effort only.

### Commands

- `/coremodel` asks which mode to use, showing the current mode and the real level; Esc changes
  nothing.
- `/coremodel recheck` reads the account's model list again and brings back models dropped after an error.
- `/coremodel probe` prints what `/config` offers (rows and their choices), to see whether the models
  your account can use are listed there; it changes nothing.
- `/coremodel panel` opens the pane (the footer button does the same without a chat command).
- `/coremodel auto`, `/coremodel suggest` set the mode for every session.
- `/coremodel off` and `/coremodel on` turn it off and back on.

### Settings

`/plugin` → Installed → coremodel → Configure options:

- `mode`: `suggest`, `auto` or `off` (default `suggest`). `/coremodel` wins over it.
- `classifier`: `sonnet` (default, the more accurate) or `haiku` (faster, cheaper).
- `useHaiku`, `useSonnet`, `useOpus`, `useFable` (titled **Allow …**, on by default): tick the models coremodel may pick. They narrow what your account lists, never add a model it does not have. (Before 0.5.0 this was one text setting `models`; it is no longer read.)
- `pickModel`: `on` (default) or `off`. With `off` it picks the effort level only and never changes the model.

### Cost

One short classifier call per prompt you type (at most 120 output tokens), through your own
Claude Code account; it adds about 1 to 3 seconds before Claude starts. When the call has not
answered in 3 seconds a second one is sent and the first answer is used; after 8 seconds the
prompt goes on unchanged. Slash commands and messages that come neither from the prompt box nor from Remote Control
(the phone or the web) are never checked. Errors are written to `~/.claude/mods-logs/coremodel.log` and never block the
prompt.

## Codex

In Codex the plugin gives a **hint only**: Codex hooks cannot switch the model or the effort. A `UserPromptSubmit` hook
(`codex/hint.sh`) asks `gpt-6-luna` (`codex exec`, read-only) which model and effort the prompt needs and, when they differ
from "keep", adds one line to the context, for example "this prompt needs gpt-6-astra at high effort; switch with /model if the
current one differs". You switch yourself with `/model`. Mapping: Haiku to `gpt-6-luna`, Sonnet to `gpt-6.1-sol`, Opus and Fable to `gpt-6-astra`.

- The hint shows as a system message (and reaches the model as context). The nested call takes about 8 seconds; it runs with `--ignore-user-config` and low reasoning effort, so it does not load your config, MCP servers or other plugins' hooks (your login still works).
- It costs about one `gpt-6-luna` call per prompt and waits at most 20 seconds (`COREMODEL_HINT_TIMEOUT`); any failure is silent and the prompt goes on.
- Turn it off with `coremodel_mode: off` in `~/.config/corecrew/settings`.
- Codex asks you to trust the hook the first time: review and enable it in `/hooks`.

## Requirements

- **OS:** whatever Claude Code runs on (terminal and desktop app); the plugin is a TypeScript module with no native code.
- **Claude Code** 2.1.287 or newer: its hooks run as a module.
- **Network:** no host of its own. In Claude Code the classifier call goes through your own Claude Code account, so it reaches the same Anthropic service Claude Code does. In Codex every prompt is sent a second time to OpenAI (`gpt-6-luna`) through `codex exec`; the Codex hint needs `bash` and the `codex` CLI.
- **Permissions:** it asks for none beyond the plugin hooks. It puts the pick on this chat's requests only and never writes your model or effort setting.
- **Changes outside its own folder:** errors are written to `~/.claude/mods-logs/coremodel.log` (the plugin never blocks a prompt on an error).
- **Known limitation:** it uses an early-access plugin API that can change between Claude Code releases.

## Build from source

```bash
bash tests/test_coremodel.sh                  # validate the manifest and module, run the plugin's tests
claude plugin test plugins/coremodel          # the plugin's own tests (needs the claude CLI)
claude plugin validate plugins/coremodel
bash plugins/coremodel/tests/quality.sh sonnet  # classifier quality on the real model (network, not part of the suite)
```
The sources are in `plugins/coremodel/hooks/`. Credits: the idea comes from Ben AI's "Effort Optimizer" mod. No code or text of it is reused.

## Licence

MIT — see [LICENSE](../../LICENSE).
