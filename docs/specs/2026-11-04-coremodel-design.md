---
title: coremodel plugin — design spec
description: Requirements for CoreModel, the successor of CoreEffort (0.3.0) in the corekit marketplace. Besides the effort level it recommends one of the Anthropic models for each main-chat prompt, holds the pair on the chat's requests, and names the token cost of a model switch mid-chat. Read before changing plugins/coremodel/.
status: accepted
files: [plugins/coremodel/, .claude-plugin/marketplace.json, tests/test_coremodel.sh, README.md, CLAUDE.md]
related: [docs/specs/2026-11-04-effort-picker-design.md]
updated: 2026-11-04
---

# `coremodel` plugin — design spec

## 1. Goal

CoreEffort picks the effort level for each prompt. CoreModel picks the pair "model + effort":
cheap, fast models for small work, the strongest model where a hidden mistake is costly. It keeps
everything CoreEffort 0.3.0 does (spec docs/specs/2026-11-04-effort-picker-design.md, §4–§4.7);
this spec lists only what changes. Where the two disagree, this spec wins.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| M1 | Rename `coreeffort` to `coremodel` (brand CoreModel), version `0.4.0`; `renames` maps `coreeffort` and `effort-picker` to `coremodel`. | The owner's choice; same road as coredev → corecrew. A second plugin beside CoreEffort would fight it over the effort. |
| M2 | One classifier call per prompt returns level, model and why. | Same cost and delay as today; the classifier sees the whole task, so "Sonnet + high" is possible. |
| M3 | Model and effort are chosen independently and asked separately: two short questions, each only when its part changes. | The owner's choice. `$.ui.ask` takes one question with 2–4 options. |
| M4 | The model changes freely only on the chat's first prompt. Later: only to a stronger model, always with a question, in every mode. A weaker model is never offered mid-chat. | Prompt caches are model-scoped: a switch re-reads the whole chat at write price (§5). Going down rarely pays back. |
| M5 | A mid-chat model question names its token cost. | The owner's requirement: the person must see that a switch costs tokens. |
| M6 | Fable always asks, like `xhigh` and `max` (E6 of the CoreEffort spec). A model or level the person presses in the pane needs no further question. | Fable is the most expensive model; the person's own press is their yes. |
| M7 | The model is held like the effort: put on every main-chat request (`turn.step` rewrite of `model`); `/model` and the person's default are never written. | Same reasoning as CoreEffort §4.4. |

## 3. Models

Ladder, weakest to strongest, with the ids the plugin puts on requests and the prices it uses
for §5 (Anthropic API, $ per million input tokens; cache read multiplier):

| Model | Id | Input | Cache read |
|---|---|---|---|
| Haiku 5.5 | `claude-haiku-5-5` | 0.10 | 0.1× |
| Sonnet 5.5 | `claude-sonnet-5-5` | 2.00 | 0.05× |
| Opus 5.5 | `claude-opus-5-5` | 4.00 | 0.05× |
| Fable 5.1 | `claude-fable-5-1` | 10.00 | 0.025× |

Cache writes cost 1.25× input (5-minute TTL) on every model. Source: platform.claude.com prompt
caching page (multipliers, 5-minute default TTL, checked 2026-11-04); the model scope of caches
comes from Anthropic's API reference bundled with Claude Code ("caches are model-scoped"), the
public page does not state it. The table lives in one constant; a price change is a one-line edit.

## 4. Behaviour

### 4.1 The classifier
The answer becomes `{"level": "...", "model": "haiku|sonnet|opus|fable", "why": "..."}`. The
rules of CoreEffort §6 stay for `level`; a second ladder for `model`, stop at the first match:
- `haiku`: questions, explanations, mechanical edits, short texts, a command to run.
- `sonnet` (also when unsure): ordinary work with a clear path.
- `opus`: a hidden mistake is costly or the path is unclear; many files; analysis across sources.
- `fable`: long, critical work handed off to run alone, or an explicit request for the deepest work.

A missing `model`, an unknown word, or a model not in the setting `models` (§6) leaves the model
untouched; the level is handled as before. `keep` keeps both.

### 4.2 When each part may change
- **Effort:** as CoreEffort (§4.3 there): `suggest` asks, `auto` switches silently, `xhigh` and
  `max` always ask.
- **Model, first prompt of the chat** (no assistant message yet): `suggest` asks, `auto` switches
  silently, Fable always asks.
- **Model, later:** only when the pick is stronger than the model the chat runs at; always asks,
  with the cost line of §5. A weaker pick changes nothing.

### 4.3 The questions
Asked in this order, each only when needed; a dismissed question keeps that part.
1. Model (header `Модель` / `Model`): the picked model marked "(recommended)", "Keep <current>"
   (also for a current model outside `models`; "Keep the current model" when it is none of the
   four), then, on the first prompt only, up to two more models from `models`, nearest to the pick
   first. Mid-chat it offers the pick and Keep alone, and the text carries the cost line (M4, M5).
   The request's context suffix (`[1m]`) stays on a held model.
2. Effort (header `Усилие` / `Effort`): the picked level "(recommended)", "Keep <current>", then
   the neighbouring levels while they fit four options.
"Switch, and auto-adjust from now" leaves the questions; `auto` is set in the pane or with
`/coremodel auto`.

### 4.4 Applying and releasing
- The held pair `{ model, level, base }` goes on every main-chat request; `base` holds the
  request's own model and effort when the hold began (or the first request's, for a hold made
  before any request, as CoreEffort 0.3.0 does).
- The model part is released when the request's own model differs from `base.model` (the person
  used `/model`); the effort part as today. Each part releases on its own.
- A model without effort (`e.effort` absent) gets no effort; no error.
- Session start, `/coremodel off`, and Release in the pane drop both parts.
- Subagent requests, slash commands and non-composer prompts are never touched.

### 4.5 A model the account cannot use
When a request on a held model fails because the model is not available (the turn ends with an
error naming the model), the model hold is dropped for this session, the model is skipped in
later picks of this session, a log line is written, and the pane shows
"Модель <name> недоступна — уберите её из настройки models" / "<name> is not available — remove
it from the models setting". No retry on every request. How such a failure reaches a hook
(`turn.step` result, an error event) is checked in the plan before this part is built.
Checked 2026-11-04: Claude Code raises `classic.StopFailure` with `error: 'model_not_found'`; it
names no model, so the model held at that moment is the one dropped.

## 5. The cost line

Mid-chat model questions say why the model is suggested and what the switch costs, once, in the
prompt's language (changed in 0.4.2; the "~N ordinary replies" figure scared more than it told, and
"replies are cheap again" is false when the new model is Opus or Fable):
"Перейти на Opus (много файлов)? Чат один раз перечитается заново: ≈ 100 тыс. токенов, около
$0,50 по ценам API." / "Switch to Opus (many files)? The chat is read again once: ≈ 100k tokens,
about $0.50 at API prices."
- Tokens: `$.session.usage().context.tokens` (the last response's input tokens; free call).
- Dollars: `tokens × input(new) × 1.25 / 1e6` (one cache write on the new model). Example: 100k
  tokens to Opus: 100k × $4 × 1.25 / 1M = $0.50. Under a cent it reads "< $0.01".
- Unknown tokens: "Чат один раз перечитается заново, это стоит токенов." / "The chat is read
  again once, which costs tokens."
- Numbers are rounded: thousands as "тыс." / "k", dollars to the cent.

## 6. Settings

| Key | Options | Default |
|---|---|---|
| `mode` | `suggest`, `auto`, `off` | `suggest` |
| `classifier` | `haiku`, `sonnet` | `sonnet` |
| `models` | any of `haiku`, `sonnet`, `opus`, `fable`, comma-separated | all four |
| `pickModel` | `on`, `off` | `on`; `off` = CoreEffort behaviour (effort only) |

`/coremodel auto|suggest|off|on|panel` as `/coreeffort` today; `/coremodel` without an argument
asks the mode.

## 7. Interface

Everything of CoreEffort §4.7 stays, showing the pair; texts follow the prompt's language.
1. **Switch line** (15 s, after a silent switch): "✓ Opus · Высокое (было Sonnet · Среднее) · why
   [Вернуть]"; only the part that changed when one did. "Back" (key `1`) restores both parts the
   silent switch changed, and only those.
2. **Marks in the chat:** "↑ Opus · Высокое (было Sonnet · Среднее) · why"; the arrow follows the
   model, or the effort when the model did not change.
3. **Footer label:** "Opus · High"; one part when only one is held.
4. **Working line:** "Thinking… · Opus · Высокое" while anything is held.
5. **Pane "CoreModel"** (`/coremodel panel`), since 0.4.1 in sections spaced apart, top to bottom:
   - **Сейчас:** what the chat runs at, bold ("Opus · Высокое"; the level alone with `pickModel`
     off); "держит CoreModel · в меню: Sonnet · Среднее (ваше)" while anything is held (without
     the menu part until a request shows the menu); the "not available" line of §4.5; a row of
     model buttons (only `models`) and a row of level buttons, both wrapping, the current model and
     level highlighted (`variant: 'primary'`); while anything is held, a quiet button "Вернуть как
     в меню" (Release). A model button pressed mid-chat first asks the cost question of §5 (Esc
     cancels); a level button holds at once.
   - **Режим:** buttons Подсказывать / Сам / Выкл, the current one highlighted, and one line on
     what it does.
   - **Последний выбор:** "Последний выбор · Opus · Высокое", the why on the next line.
   - **За сессию:** a short bar and a count per model and per level, then "Уровень не меняли: n".

## 8. Layout

`plugins/coreeffort/` moves to `plugins/coremodel/` (git mv, history kept); `hooks/models.ts`
holds the table of §3 and the cost line of §5, with no `$` calls. `types/index.d.ts` declares the
state under `coremodel`. `tests/test_coreeffort.sh` becomes `tests/test_coremodel.sh`. The
marketplace entry, root README section, CLAUDE.md layout and `.gitignore` paths follow the move.

## 9. Testing

### 9.1 Unit tests (`claude plugin test`, model mocked)
- Parser: level + model, no model, unknown model, a model outside `models`, `keep`.
- First prompt: `auto` switches the model silently; `suggest` asks; Fable asks in both.
- Mid-chat: a stronger pick asks with the cost line; a weaker pick changes nothing; unknown
  tokens give the plain line.
- Questions: model only, effort only, both in order; a dismissed model question still asks the
  effort.
- Hold: the request carries the held model; `/model` (a new request model) releases only the
  model part; a model without effort gets none.
- Unavailable model: hold dropped, model skipped for the session, log line, pane line.
- `pickModel: off` behaves as CoreEffort 0.3.0 (its tests keep passing).
- UI on `terminal` and `desktop`: switch line with both parts, undo restoring both, marks, footer,
  working line, pane rows and the cost question from a model button.
- Cost line: the §5 example gives "~50"; rounding; Russian and English.

### 9.2 Classifier quality (manual)
`quality.sh` gets an expected model per prompt: typo fix → haiku; `git rebase --onto` question →
haiku; login 500 → opus; CSV export button → sonnet; payments refactor + migration → opus or
fable; habit tracker from scratch, work alone → fable; polite email → haiku or sonnet; 12-page
lease risks → opus; "да, давай" → keep.

### 9.3 Live
Terminal with `claude --plugin-dir plugins/coremodel`, then the desktop app after a marketplace
install: first-prompt switch, the mid-chat cost question, the pane, `/model` releasing the hold.

## 10. Release
- `plugins/coremodel/.claude-plugin/plugin.json` version `0.4.0`, `displayName` `CoreModel`.
- CHANGELOG entry (the plugin's own), including: the command is now `/coremodel`; a mode set with
  `/coreeffort` may not carry over, set it again.
- corecrew is not touched and not bumped.

## 11. Out of scope
- Choosing models for subagents or corecrew's agents.
- Learning from the person's past answers.
- Fast mode, 1-hour cache TTL, or any change to how Claude Code caches.
