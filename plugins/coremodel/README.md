# coremodel

A Claude Code plugin that picks the model and the effort level each prompt needs, before Claude starts on it; in Codex it gives an opt-in hint (see [Codex](#codex)).

![platform](https://img.shields.io/badge/platform-Claude%20Code%202.1.309%2B-lightgrey) ![release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoremodel%2F.claude-plugin%2Fplugin.json&query=%24.version&label=release) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

## Install

Claude Code 2.1.309 or newer (`claude --version`; update with `claude update`). The plugin is a
mod: it runs on Claude Code's mods API (from 2.1.287), which can still change between releases, and
which Anthropic or an administrator can switch off (`allowManagedModsOnly`, `disableAllHooks`). It is
in the `corekit` marketplace and does not depend on `corecrew`.

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coremodel@corekit
```

Update: `claude plugin marketplace update corekit`, `claude plugin update coremodel@corekit`, then restart Claude Code.
In Codex: `codex plugin marketplace upgrade corekit`, then trust the hook again in `/hooks` (see [Codex](#codex)).

## Features

| Feature | What it does |
|---|---|
| Model pick | Before Claude starts on a prompt, a short model call picks the model: Haiku, Sonnet, Opus or Fable |
| Effort pick | Picks the effort independently: Low, Medium, High, Extra high or Max |
| Quiet by default | `auto` switches by itself, with an undo, and asks only before the costly ones: Fable, Extra high, Max and a stronger model mid-chat |
| Cost-aware switching | Mid-chat it only offers a stronger model, with a question that names the lasting price per reply and the one-off re-read |
| Modes | `auto` (the default), `suggest` (never asks: offers the pick above the prompt), `off` |
| The pane | The footer button opens a pane with the mode, what the chat runs at, Model and Effort buttons and the session in one line |
| Your menus stay put | The pick is put on the requests of this chat only; your model and effort settings are never written |
| Account-aware | Reads the models your account can use and never picks one it lacks |
| Languages | English and Russian, by Claude Code's `language` setting or by coremodel's own; corecrew's `ui_language` does not change it (corecrew has its own) |

The two picks are independent: a polite email is Haiku at Low, a contract risk review is Opus at
High, a whole app built alone is Fable at Extra high. Approvals such as "yes", "go on" or "да,
давай" (Russian for "yes, go ahead") keep both as they are.

### When the model changes, and what it costs

Claude re-reads the whole chat before every reply, and keeps what it has read in a cache that is
tied to one model. Reading from the cache is cheap; after a model switch the new model reads the
whole chat again at full price. So:

- On the **first prompt** of a chat the model may change in either direction: there is nothing to
  re-read. `auto` switches by itself; a switch to Fable always asks.
- **Later** coremodel only offers a **stronger** model, always with a question that names the
  lasting price first, then the one-off cost: "Switch to Opus? From now on each reply costs about
  2× Sonnet. Switching also re-reads this chat once: ≈ 100k tokens, about $0.50 at API prices (on a
  subscription it counts toward your limits)." It never offers a weaker model mid-chat: the re-read
  would eat the saving.
- A model coremodel does not know (a gateway's own model name) is never switched or asked about.

Models are named by their alias (`opus`, `sonnet[1m]`): Claude Code resolves the newest version and
the id your provider uses (Anthropic, Bedrock, Vertex or a gateway).

### Modes

- **auto** (the default): switches the effort among Low, Medium and High by itself, up or down, and
  the model on the first prompt. A line above the prompt says what changed, with a **Back to …**
  button that undoes it: click it, or press ctrl+x tab and then `1`. `/coremodel undo` does the same
  later. **It asks first, in a short dialog before Claude starts, only before Fable, Extra high, Max
  and a stronger model mid-chat.** The model question comes first, then the effort; the effort
  question ends with **← Back to the model**, and a level can also be typed.
- **suggest**: never opens a dialog. The prompt runs as it is, and a line above the prompt offers
  the pick: "CoreModel suggests Opus · High · why" with **Switch** (`1`) and **Keep** (`2`). Switch
  holds the pick from the next request (a stronger model mid-chat still shows the cost question).
  The line goes after 15 seconds.
- **off**: does nothing.

Every applied switch also leaves a row in the chat, such as "↑ Opus · High (was Sonnet · Medium) ·
why". The footer button carries the state: **CoreModel · Opus · High** while coremodel sets the
model or effort for this chat, **CoreModel** when your own choice runs, **CoreModel · off** in mode
off.

When two classifier calls in a row fail (an API error, a timeout), coremodel says so once in a
toast and keeps a warning line in the pane until a pick works again; your prompts run unchanged.

**VS Code** draws neither the line above the prompt nor the footer button: there a silent switch is
told in a toast that names `/coremodel undo`, and `/coremodel` prints what the chat runs at.

### The pane

Open it without typing anything into the chat: press the **CoreModel** button in the footer under
the prompt; press it again to close the pane. Nothing is sent to the model, so a running turn is not
interrupted. `/coremodel panel` opens it too. Its keys and the close mark are Claude Code's own (Esc,
ctrl+x x).

```
CoreModel · Auto
[ ● Auto ]  [ Suggest ]  [ Off ]
Asks only before Fable, Extra high, Max and a stronger model mid-chat
────────────────────────────────────────
This chat     Opus · High
Set by CoreModel for this chat · your default: Sonnet · Medium
[ Use my default ]
Model         [ Haiku ]  [ Sonnet ]  [ ● Opus ]  [ Fable ]
Effort        [ Low ]  [ Medium ]  [ ● High ]  [ Extra high ]  [ Max ]
────────────────────────────────────────
This session  Sonnet 3 · Opus 2 · High 4 · unchanged 2
```

- The selected button carries **●**, so the selection does not rest on colour alone.
- A **Model** or **Effort** button holds your pick at once, Fable, Extra high and Max included: your
  own press is your yes. A model pressed mid-chat first shows the cost question. **Use my default**
  lets go of what coremodel set.
- **Last pick** shows only when it says something new: a pick you kept away, or one that differs
  from what the chat runs at.
- Button rows wrap, so nothing is hidden in a narrow pane.

### Your menus do not move

The plugin puts the chosen model and effort on every request of this chat only. It never writes
your model or effort setting, so other chats and later sessions keep your own defaults; the menus
keep showing them, and the footer button and `/coremodel` say what the chat really runs at. Choose
a model with `/model` or move the effort menu yourself, and the plugin lets go of that part; a new
chat (`/clear`, `/resume`) or a new session lets go of both.

**Which models are offered.** coremodel reads the list of models your account can use from the
Model row of `/config` (the same list `/model` shows), before every pick and at the start of a
session. A model that is not in it, such as Fable on a plan without it, is never picked or offered:
when the pick names it, the nearest model you can use takes its place (the one below it first, so
Opus for Fable), and the reason says so: "Fable is not available, Opus instead". The same holds for a
model you switched off. A model that becomes available later is offered from the next pick. If the
list cannot be read, nothing is filtered. `/coremodel recheck` reads it again at once and also brings
back a model that was dropped after an error.

If a model the plugin picked still fails (`model_not_found`), the turn fails once; coremodel then
stops using that model for the session and says so in the pane (`/coremodel recheck` undoes that).

### Commands

- `/coremodel` asks which mode to use, showing the current mode and what the chat runs at; Esc changes nothing.
- `/coremodel auto`, `/coremodel suggest` set the mode for every session; `/coremodel off` and `/coremodel on` turn it off and back on.
- `/coremodel undo` takes back the last silent switch; a part you changed since stays.
- `/coremodel panel` opens the pane (the footer button does the same without a chat command).
- `/coremodel recheck` reads the account's model list again and brings back models dropped after an error.

### Settings

`/plugin` → Installed → coremodel → Configure options:

| Setting | Values | What it does |
|---|---|---|
| `mode` | `auto` (default), `suggest`, `off` | The mode; `/coremodel` wins over it |
| `language` | `auto` (default), `en`, `ru` | The language of coremodel's words; `auto` follows Claude Code's `language` setting (`"language": "russian"` in settings.json gives Russian), anything else is English |
| `classifier` | `sonnet` (default), `haiku` | The model that reads each prompt: Sonnet is more accurate, Haiku faster and cheaper |
| `useHaiku`, `useSonnet`, `useOpus`, `useFable` | on (default) or off | **Allow …**: the models coremodel may pick; they narrow what your account lists, never add one. All off: the effort only |
| `pickModel` | `on` (default), `off` | `off`: pick the effort only, never the model |

To add a language: copy `hooks/locales/ru.ts` to `hooks/locales/<code>.ts` and translate the values and `hostNames` (the Claude Code `language` values that choose it under `auto`); add the table to `LOCALES` in `hooks/policy.ts`, which `settingLang` and `hostLang` read; add `<code>` to `Lang` in `types/index.d.ts` and to the `language` options in `.claude-plugin/plugin.json` (a test checks the options against the locale files). The Codex hint stays English.

### Cost

One short classifier call per prompt you type (at most 120 output tokens), through your own
Claude Code account; it adds about 1 to 3 seconds before Claude starts. When the call has not
answered in 3 seconds a second one is sent and the first answer is used; after 8 seconds the prompt
goes on unchanged. Slash commands and messages that come neither from the prompt box nor from Remote
Control (the phone or the web) are never checked. Errors go to Claude Code's debug log (`claude
--debug`) and never block the prompt.

## Codex

In Codex the plugin gives a **hint only**, and it is **off until you turn it on**: Codex hooks
cannot switch the model or the effort, and the hint sends every prompt to a model once more. A
`UserPromptSubmit` hook (`codex/hint.sh`) asks `gpt-6-luna` (`codex exec`, read-only) which model and
effort the prompt needs and adds one line, for example "this prompt needs gpt-6-astra at high effort;
switch with /model if the current one differs". Codex Desktop does not show that line in the chat, so
the hook also asks Codex to open its reply with the pick in your language, for example "CoreModel
рекомендует GPT-6 Astra · High", and then go on with your request. You switch yourself with `/model`. The hint names
`gpt-6-luna`, `gpt-6.1-sol` or `gpt-6-astra`, and judges the model and the effort separately: a hard
question with a short answer can get `gpt-6-astra` at low effort.

Install: `codex plugin marketplace add rstrlnkv/CoreKit`, then `codex plugin add coremodel@corekit`.

- Turn it on with `codex_hint: on` in `~/.config/coremodel/settings` (`$XDG_CONFIG_HOME/coremodel/settings`
  when that is set; `COREMODEL_CONFIG` names another file). Without that key, `coremodel_mode: on` in
  the corecrew settings file (`~/.config/corecrew/settings`) turns it on too; `codex_hint: off` wins.
- It stays silent when your current model is the one it would name or a stronger one; on
  `gpt-6-astra` it makes no call at all. The hint ranks only `gpt-6-luna`, `gpt-6.1-sol` and
  `gpt-6-astra`; on any other model it cannot compare and names its pick each time (except when the
  answer is "keep"). Codex does not tell hooks the current effort, so the hint names an effort but
  never compares it with yours.
- A prompt that is only a greeting, thanks, an approval or "go on" ("привет", "да, давай", "ok, go
  ahead", at most 8 words, the list is `codex/replies.txt`) gets no call and no hint. "Да, и ещё
  проверь расчёты" brings new work, so it is checked.
- When Codex's model catalog (`$CODEX_HOME/models_cache.json`) is readable, the hint offers only
  the models it lists and lowers an effort a model does not support to the highest one it does.
- Codex shows "coremodel: choosing a model" while it runs. The nested call takes about 8 seconds; it
  runs with `--ignore-user-config` and low reasoning effort, so it does not load your config, MCP
  servers or other plugins' hooks (your login still works). It waits at most 20 seconds
  (`COREMODEL_HINT_TIMEOUT`); any failure is silent and the prompt goes on. The nested call also
  ignores the `model_provider` of your Codex config, so it always goes to OpenAI with your Codex
  login, whatever provider your config names; without an OpenAI login (Bedrock, a gateway, a local
  model) leave the hint off, because it gives no hint and holds each prompt up to 20 seconds.
- Codex asks you to trust the hooks the first time, and again after each update: review and enable
  both (`UserPromptSubmit` and `Stop`) in `/hooks`. Without the `Stop` hook the hint still works, but
  the classifier is told that Codex's previous reply is unknown.

What goes to `gpt-6-luna`, once per checked prompt: the classifier text of `codex/classifier.txt`,
your prompt (past 4000 bytes, its first and last 2000 bytes), and one of three things in place of
Codex's previous reply:

- for a prompt of at most 8 words ("почини", "the second one"), the last 600 bytes of Codex's
  previous reply in the same chat, blanks folded;
- for such a prompt with no saved reply (the first prompt, a chat started before the hint was on,
  or the `Stop` hook not trusted), the note that the reply is unknown;
- for a longer prompt, the note that the reply is not included.

The `Stop` hook keeps those 600 bytes in `~/.local/state/coremodel/codex-replies/<session id>`
(`$XDG_STATE_HOME` when set; the folder is readable only by you) until your next prompt in that chat,
which removes the file whether or not it was sent; a file older than a day is removed by the next
`Stop`. Nothing is kept while the hint is off.

## Requirements

- **OS:** whatever Claude Code runs on; the plugin is a TypeScript module with no native code.
- **Claude Code** 2.1.309 or newer: it names models by alias in its hooks.
- **Network:** no host of its own. In Claude Code the classifier call goes through your own Claude Code account, so it reaches the same Anthropic service Claude Code does. In Codex, once you turn the hint on, every prompt is sent a second time to OpenAI (`gpt-6-luna`) through `codex exec`; the hint needs `bash` and the `codex` CLI.
- **Permissions:** it asks for none beyond the plugin hooks. It puts the pick on this chat's requests only and never writes your model or effort setting.
- **Changes outside its own folder:** none in Claude Code; its log lines go to Claude Code's debug log. In Codex, with the hint on, the end of Codex's last reply waits in `~/.local/state/coremodel/codex-replies/` until your next prompt (see [Codex](#codex)).

## Uninstall

`claude plugin uninstall coremodel@corekit` (or `/plugin` → Installed → coremodel → Uninstall). Your
model and effort settings were never changed, so nothing needs undoing. In Codex: `codex plugin remove coremodel@corekit`. For Codex, remove the
`codex_hint` line from `~/.config/coremodel/settings` if you added it, and the folder
`~/.local/state/coremodel/` if it is there.

## Development

```bash
bash tests/test_coremodel.sh                          # validate the manifest and module, run the module tests in tests/coremodel/
bash tests/test_coremodel_codex.sh                    # the Codex hint, against a fake codex
claude plugin validate plugins/coremodel
bash tests/coremodel/quality.sh sonnet                # classifier quality on the real model (network, not part of the suite)
```
The sources are in `plugins/coremodel/hooks/`. Credits: the idea comes from Ben AI's "Effort Optimizer" mod. No code or text of it is reused.

## Licence

MIT — see [LICENSE](../../LICENSE).
