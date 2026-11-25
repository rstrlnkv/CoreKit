# coremodel

A Claude Code plugin that picks the model and the effort level each prompt needs, before Claude starts on it; in Codex it can ask you to choose the model and effort for a task (see [Codex](#codex)).

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
CoreModel                             Auto ▾
╭──────────────────────────────────────────╮
│ CoreModel's pick                         │
│ Opus · High                  [ ↺ Reset ] │
│ ──────────────────────────────────────── │
│ In Claude: Sonnet · Medium               │
╰──────────────────────────────────────────╯
Model
[ Haiku ]  [ Sonnet ]  [ ● Opus ]  [ Fable ]
Effort
▬▬▬▬▬▬▬▬ ▬▬▬▬▬▬▬▬ ▬▬▬▬▬▬▬▬ ▭▭▭▭▭▭▭▭ ▭▭▭▭▭▭▭▭
Low  Medium  ● High  Extra high  Max
────────────────────────────────────────────
This session                     unchanged 2
Model                Effort
Sonnet ▬▬▬▬▬▬▬▬ 3    High   ▬▬▬▬▬▬▬▬ 4
Opus   ▬▬▬▬▬    2    Medium ▬▬▬▬     2
```

- The top line is the mode list. The card under it shows **CoreModel's pick** with **Reset** and,
  below, what you chose in Claude; when CoreModel holds nothing, it shows **In Claude** alone.
- The selected model carries **●**, so the selection does not rest on colour alone. The effort is a
  scale of five segments across the block, filled up to the current level; under it the levels are
  buttons by name, the current one marked with **●**.
- A **Model** or **Effort** button holds your pick at once, Fable, Extra high and Max included: your
  own press is your yes. A model pressed mid-chat first shows the cost question. **Reset** lets go
  of what coremodel set.
- **This session** counts the models and the efforts apart, the most used first, with bars to scale.
- The pane adapts to its width: in a wide pane the card and the controls, and the two session
  groups, stand side by side; in a narrow one they stack. Button rows wrap, so nothing is hidden.
- A warning is one short line: a model the account refused (with `/coremodel recheck`), or a
  classifier that keeps failing (details in `claude --debug`).

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

To add a language: copy `hooks/locales/ru.ts` to `hooks/locales/<code>.ts` and translate the values and `hostNames` (the Claude Code `language` values that choose it under `auto`); add the table to `LOCALES` in `hooks/policy.ts`, which `settingLang` and `hostLang` read; add `<code>` to `Lang` in `types/index.d.ts` and to the `language` options in `.claude-plugin/plugin.json` (a test checks the options against the locale files). The Codex hook asks the agent to use the user's language.

### Cost

One short classifier call per prompt you type (at most 120 output tokens), through your own
Claude Code account; it adds about 1 to 3 seconds before Claude starts. When the call has not
answered in 3 seconds a second one is sent and the first answer is used; after 8 seconds the prompt
goes on unchanged. Slash commands and messages that come neither from the prompt box nor from Remote
Control (the phone or the web) are never checked. Errors go to Claude Code's debug log (`claude
--debug`) and never block the prompt.

## Codex

Install with `codex plugin marketplace add rstrlnkv/CoreKit` and `codex plugin add coremodel@corekit`. Enable routing in `~/.config/coremodel/settings` (under `$XDG_CONFIG_HOME` when set, or the path named by `COREMODEL_CONFIG`).

```text
codex_mode: ask
codex_pick_model: on
```

| Setting | Effect |
|---|---|
| `codex_mode: ask` | Ask when the recommendation differs from the current settings. Choose from all visible models first, then from the efforts available for the chosen model. The choices identify the current and recommended values. |
| `codex_mode: auto` | Use the recommended settings without asking for a selection. Recommendations can raise or lower the model, including mid-chat. |
| `codex_mode: off` | Skip the classifier and the questions. |
| `codex_pick_model: off` | In either active mode, evaluate effort for the current model. Skip the model question. The default is `on`. |

Existing enabled `codex_hint` and `codex_confirm` configurations use ask mode. A previously disabled installation stays off. The legacy CoreCrew setting `coremodel_mode: on` can still enable ask mode when CoreModel has no explicit mode or hint setting.

Matching settings and approvals pass without a question. When the model already fits but Codex omits its current effort, ask mode asks only about effort. Closing either question cancels the task and discards a partial choice.

**Codex Desktop and CLI hooks.** The hook passes selection instructions to the agent. Clients with a question tool can present buttons. Text questions provide the fallback. In these clients the hook cannot apply new settings to the submitted turn. After selection, follow the supplied `/model` command and resend the original prompt. Auto mode uses the same manual fallback. A hook cannot write into the host's composer or restore settings changed through `/model`. Use the original prompt text to edit a cancelled task, and restore your previous settings after the task if needed.

- A prompt that is only a greeting, thanks, an approval or "go on" ("привет", "да, давай", "ok, go
  ahead", at most 8 words, the list is `codex/replies.txt`) gets no call and no hint. "Да, и ещё
  проверь расчёты" brings new work, so it is checked.
- The classifier uses visible model entries it recognizes in Codex's current cache format
  (`$CODEX_HOME/models_cache.json`). For recommendations it considers one model per tier. The model question also includes visible models outside these tiers. Sol and Astra prefer GPT-6.2
  when visible and fall back to their visible predecessors, GPT-6.1 Sol and GPT-6 Astra. If the
  file is missing or unreadable, the hint offers those two predecessors and GPT-6 Luna. Edited
  or truncated cache files can be misread. If the chosen model lacks the requested effort,
  the hint uses the highest listed effort below it, when available.
- Codex shows “CoreModel: Choosing a model and reasoning effort” while it runs. The nested call takes about 8 seconds; it
  runs with `--ignore-user-config` and low reasoning effort (or an available level when low is missing), so it does not load your config, MCP
  servers or other plugins' hooks (your login still works). It waits at most 20 seconds
  (`COREMODEL_HINT_TIMEOUT`); any failure is silent and the prompt goes on. The classifier starts in a new empty temporary folder for each call. The hook removes it after use. The nested call also
  ignores the `model_provider` of your Codex config, so it always goes to OpenAI with your Codex
  login, whatever provider your config names; without an OpenAI login (Bedrock, a gateway, a local
  model) leave the hint off, because it gives no hint and can hold each checked prompt for up to
  20 seconds.
- Codex asks you to trust the hooks the first time, and again after each update: review and enable
  both (`UserPromptSubmit` and `Stop`) in `/hooks`. Without the `Stop` hook the hint still works, but
  the classifier is told that Codex's previous reply is unknown.

What goes to the classifier, once per checked prompt: the classifier text of `codex/classifier.txt`,
your prompt (past 4000 bytes, its first and last 2000 bytes), and one of three things in place of
Codex's previous reply:

- for a prompt of at most 8 words ("почини", "the second one"), the last 600 bytes of Codex's
  previous reply in the same chat, blanks folded;
- for such a prompt with no saved reply (the first prompt, a chat started before the hint was on,
  or the `Stop` hook not trusted), the note that the reply is unknown;
- for a longer prompt, the note that the reply is not included.

The `Stop` hook keeps those 600 bytes in `~/.local/state/coremodel/codex-replies/<session id>`
(`$XDG_STATE_HOME` when set; the folder is readable only by you) until your next prompt in that chat,
which removes the file whether or not it was sent. A reply at least a day old is discarded before use.
The manual fallback stores a checksum of the submitted prompt under the same state root in `coremodel/codex-offered/<session id>`. The next identical submission in the same chat within ten minutes can pass once without classification. The hook cannot see when you dismiss a question, so resending the identical text after cancellation can also use this retry.
Each `Stop` also removes expired replies from other chats. Nothing is kept while the hint is off.

### Standalone terminal client

With a CoreKit checkout, Python 3 and a signed-in Codex CLI, run `python3 /path/to/CoreKit/clients/coremodel/client.py` from your project directory. The client starts a new chat. When a change is recommended, select the model and then its effort at the text prompts. Cancelling either selection lets you edit the original task. Add `--auto` to apply the recommendation without questions. The client sets the pair before it starts the turn and sends the task once. A manual choice applies to that task only. If the catalog lists no effort levels for your selected model, the client offers its catalog default. If Codex supplies neither the original effort nor a restorable default, the client gives you the manual command before sending the task. End the chat with Ctrl+D.

In Windows PowerShell with the Python launcher, run:

```powershell
py -3 "C:\path to\CoreKit\clients\coremodel\client.py"
```

Put Git for Windows and the native Codex CLI on PATH. The client locates Bash through the Git installation or Git Bash utilities on PATH and supports both `codex.exe` and the npm `codex.cmd` launcher. To end input in the Windows console, press Ctrl+Z, then Enter. Codex plugin hooks also require the `bash` command on PATH to resolve to Git Bash.

## Requirements

- **OS:** whatever Claude Code runs on; the plugin is a TypeScript module with no native code.
- **Claude Code** 2.1.309 or newer: it names models by alias in its hooks.
- **Network.** In Claude Code the classifier call uses your Claude Code account to reach Anthropic.
  If you enable the Codex hint, it sends each checked prompt to OpenAI with
  `codex exec`. The hint needs `bash` and the `codex` CLI.
- **Permissions:** it asks for none beyond the plugin hooks. It puts the pick on this chat's requests only and never writes your model or effort setting.
- **Changes outside its own folder:** none in Claude Code; its log lines go to Claude Code's debug log. In Codex, with the hint on, the hook can store a retry checksum and the end of Codex's last reply waits in `~/.local/state/coremodel/codex-replies/` until your next prompt (see [Codex](#codex)).

## Uninstall

`claude plugin uninstall coremodel@corekit` (or `/plugin` → Installed → coremodel → Uninstall). Your
model and effort settings were never changed, so nothing needs undoing. In Codex: `codex plugin remove coremodel@corekit`. For Codex, remove any
`codex_mode`, `codex_pick_model`, `codex_hint` or `codex_confirm` lines from `~/.config/coremodel/settings` if you added it, and the folder
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
