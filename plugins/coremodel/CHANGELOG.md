# Changelog

## 0.5.2 — 2026-11-06

- **The classifier picks the effort and the model more accurately**, Haiku most of all. Its prompt now:
  - keeps the two choices apart: effort follows the price of a mistake and how unclear the way is, the
    model follows how hard the thinking is (a trade-off question with a short answer gets a strong model
    at low effort; a deploy by a checklist gets high effort on Sonnet);
  - says when "keep" is right: an approval, an answer to Claude's question or a picked option, even a big
    one. A question the person asks, the first prompt of a chat that asks for work, and "почини" after
    Claude only described a bug are new work, never keep (Haiku answered keep to "что делает git
    rebase --onto?" and to "накидай идей");
  - sends a crash log or stack trace that asks why to high effort on Opus;
  - shows eight short examples and asks for the reason before the level and the model.
- Measured on labelled prompts, each asked three times. Before, on 55 prompts: Haiku 143 of 165 right
  levels (21 off by two rungs or more) and 157 of 165 right models; Sonnet 162 and 159 of 165. After, on
  those 55 and 5 more written after the tuning: Haiku 180 and 178 of 180, none off by two rungs; Sonnet
  178 and 176 of 180, where 2 of its misses were calls that gave no answer.
- `tests/quality.sh` (manual, real model calls) reads the prompts from `tests/quality-cases.txt`, with
  Claude's last reply where it matters, in a tuning set and a held-out set; it asks each prompt `RUNS`
  times through a bare `claude -p` (no tools, settings or plugins), counts misses of two rungs or more
  apart, and cuts a call that hangs after 60 s.

## 0.5.1 — 2026-11-05

- A pick that names a model you cannot use (your account lacks it, or its switch is off) is no longer
  dropped: the nearest model you can use takes its place, the one below first (Opus for Fable), else
  the one above. You are told: the reason reads "Fable is not available, Opus instead" ("Fable
  недоступна, вместо неё Opus") in the question, the switch line, the transcript mark and the pane's
  last pick. When the stand-in is the model the chat already runs on, nothing changes.

## 0.5.0 — 2026-11-05

- **The models are chosen with switches.** The text setting `models` (comma-separated, typo-prone) is
  replaced by four on/off settings, **Allow Haiku**, **Allow Sonnet**, **Allow Opus** and **Allow
  Fable**, all on by default. A manifest cannot offer a multi-choice list (`options` and `multiple`
  exclude each other), and one switch per model is the documented way to get tick boxes. The old
  `models` value is no longer read: if you narrowed it, untick the models again. With every switch
  off CoreModel picks the effort only.
- The typo warning for `models` (pane and log) is gone, since a switch cannot be misspelled.
- `/coremodel recheck` says when every switch is off.

## 0.4.17 — 2026-11-05

After an independent review of 0.4.16:

- The "not available" note no longer sends you to the `models` setting (the account's list handles
  that now); it offers `/coremodel recheck`.
- `/coremodel recheck` says the same in both languages ("Models CoreModel may pick: …"), and says so
  when the account's list could not be used, when the list and the `models` setting share no model, and
  when `pickModel` is off. Its text lives with the others in `texts()`. The status reply and the command
  description name `recheck`.
- Tests: an unreadable settings list, the intersection of the list and `models`, an empty result.

## 0.4.16 — 2026-11-05

- The models an account can use are read from the `/config` Model row (the list `/model` shows), before
  every pick and at a new session: Fable on a plan without it is never picked or offered, and a model
  that becomes available later is offered from the next pick with no restart. If the row cannot be
  read, nothing is filtered. `models` stays as a limit on top.
- `/coremodel recheck` reads the list again at once and brings back a model dropped after
  `model_not_found`.

## 0.4.15 — 2026-11-05

- `/coremodel probe` lists the rows of `/config` with their choices (read only, nothing written). It
  is a probe: it shows whether Claude Code lists the models an account can use, so the plugin could
  drop the unavailable ones by itself instead of waiting for a `model_not_found` error.

## 0.4.14 — 2026-11-05

- An icon for the plugin listing (sliders); no change in behaviour.

## 0.4.13 — 2026-11-05

- Cleanup, no change in behaviour: dead exports, a text only the tests used, unused cache-read
  prices and two tests of a config-row path the plugin no longer has.

## 0.4.12 — 2026-11-05

- Questions: the model first, then the effort, each with the recommended choice first (before, a
  Fable, Extra high or Max question put Keep first). When both are asked, the effort question ends
  with "← Back to the model". A level typed under Other ("max", "Максимальное") counts. The
  platform allows a plugin one question per dialog, and a hook may not wait long on buttons of its
  own, so the two stay separate questions.
- `/coremodel` names the model as well as the level ("Now in the chat: Opus · High"), as the
  README said, and with `pickModel: off` the level only.
- `/coremodel` replies (status, mode set, off, on, pane) follow the language of the last prompt;
  before, they were English in a Russian chat.
- The working line says "checking model and effort…" (the effort alone with `pickModel: off`).
- The two classic hooks (StopFailure, SessionStart) have a `.catch`, as the mods docs ask of
  gating hooks; `claude plugin validate` no longer lists them.
- Texts: the README and the spec say Remote Control prompts are checked like the prompt box;
  "as CoreEffort did" is gone from the settings text; stale comments fixed.

## 0.4.11 — 2026-11-05

Russian texts, read through once.

- Mode names: "Подсказывать" said the opposite of what suggest does; it is now "Спрашивать"
  (asks before every switch), and "Сам" is "Автоматически" (not to be mistaken for the app's own
  "Авто" label in the footer).
- The `/coremodel` mode question offered the English words auto / suggest / off in a Russian chat;
  it now offers the mode names and says "Чат работает на уровне".
- The auto hints name the levels in quotes («Очень высокое», «Максимальное») instead of bending
  them mid-sentence.
- "Уровень не меняли: n" became "Без изменений: n" (it also counts model questions left alone).
- The models-setting warning reads "неизвестные названия … (допустимы …)".
- Removed the unused "Усилие High" label that mixed Russian and English.

## 0.4.10 — 2026-11-05

- Pane: every section keeps its caption one step (`xs`) apart from the buttons or text under it,
  and a hint stands apart from the buttons above it.
- Session drawing: larger text (14 px rows, 12 px legend) and more room between the rows.

## 0.4.9 — 2026-11-05

- The session counts follow what was applied, not what the classifier asked for: a model or level
  the person declined (or a prompt left as it was) is no longer counted, and the last pick shows
  only the applied model.
- Footer: while a model or level is held, the label beside the CoreModel button is the pair
  "Opus • High" (was "Effort High" for a level alone); a part not held is what the chat last showed,
  and there is no model part when pickModel is off. The button stays "CoreModel".
- Desktop: with only "Left as it was" to show, the pane no longer fails to draw (an empty
  drawing was refused).
- Desktop: the section rule has no fixed width, so it can take the pane's.

## 0.4.8 — 2026-11-05

- Desktop: the section rule is a drawing of the pane's own width (304 px), as the session drawing
  is; the 1000 px one drew nothing. It has a text alternative, "separator".

## 0.4.7 — 2026-11-05

- Desktop: the section rules are a one-pixel drawing across the whole pane (the text rule was cut
  off with "…"); the terminal keeps a shorter text rule.
- The levels bar in the session drawing has its own caption on the left and a legend under it
  that no longer overlaps the bar.
- "Release" sits one gap below the level buttons instead of touching them.

## 0.4.6 — 2026-11-05

- On the desktop (and VS Code, mobile) the session counts are one drawing: a share bar per model
  and one stacked bar for the levels, with a text alternative. The terminal keeps the text bars.
  The drawing is an image that cannot read the theme, so it uses a neutral track and mid-grey text.

## 0.4.5 — 2026-11-05

The pane is tighter and easier to scan.

- Buttons of a row sit close together (`xs` gap) and sections are closer (`sm`); the Model and
  Level captions are separate sections, so a caption no longer touches the row above.
- A thin rule separates the Model, Mode, Last pick and Session blocks.
- Session counts are bars, scaled to the most used model and the most used level.

## 0.4.4 — 2026-11-05

Races and edges found by a read-only audit.

- A **CoreModel** button in the footer opens and closes the pane without a chat command, so a
  running turn is not interrupted (`/coremodel panel` still does the same).
- A prompt waiting for its pick is dropped when it can no longer be the next turn's: the submit was
  refused, the turn ended before its first request (Esc), or another kind of prompt took the turn.
  A prompt queued behind a running turn still keeps its pick.
- A prompt sent before the engine's SessionStart for /clear, /resume or a fork keeps its pick; the
  switch rows of the old chat are cleared with it (a module reload keeps them).
- A request with no effort (a model without it) is no longer asked about a level, and no
  "Effort: High" is shown for something never put on the request.
- A pane press (level, model, Release) or Back made while the classifier or a question runs is
  newer than the pick: the late pick is dropped instead of overriding it.
- `model_not_found` from a subagent no longer drops the main chat's held model.
- A classifier call that fails outright (a 529, a throw) before 3 s is tried once more at once; a
  failed hedge timer no longer fires the second call early.
- An answer whose reason contains `}` is readable.
- The "not available" note names the `models` setting only when the setting lists the model.

## 0.4.3 — 2026-11-05

- A question about Fable, Extra high or Max lists **Keep** first: a question can pop up while the
  next message is being typed, and the Enter that sends it takes the first option.
- A long prompt (over 4000 characters) goes to the classifier as its first and last 2000
  characters, not only the head: the error or the question of a pasted log is usually at the end.
- The mid-chat model question names the reason and the one-time cost in dollars ("Switch to Opus
  (many files)? The chat is read again once: ≈ 40k tokens, about $0.20 at API prices"). The
  "~500 ordinary replies" figure and "replies are cheap again" are gone: the first scared more than
  it told, the second is false for Opus and Fable.
- A word in the `models` setting that names no model ("hauki") is shown in the pane and written to
  the log once per session.
- The pane shows the menu's level at once after **Back to the menu's choice**, and marks the last
  pick "not applied" when you kept what you had.
- `/coremodel` replies no longer repeat "CoreModel" after the engine's own prefix and speak of the
  model and level, not only the level; the setting descriptions say the same. "an Extra high
  effort task".

## 0.4.2 — 2026-11-04

- Fixed: a model and level CoreModel held survived `/clear`, `/resume` and a fork, so the new chat
  ran on the old pick (Fable included) with no label in the footer, and its first switch line
  named the wrong "was". A new chat now starts with nothing held, and a pick still on its way when
  it starts is dropped. A compacted chat keeps its hold.
- Fixed: the classifier call often hung on a chat's first prompt, and the prompt then waited 10
  seconds for nothing. A second call now starts when the first has not answered in 3 seconds, the
  first answer of the two is used, and the wait is 8 seconds at most. The log says "timed out
  after 8 s" for a real timeout instead of "aborted".

## 0.4.1 — 2026-11-04

- The pane is redrawn. On top is what the chat runs at ("Opus · High"), with "held by CoreModel"
  and the menu's own choice under it; the current model and level are highlighted buttons; **Back
  to the menu's choice** (was Release) lets go of a hold. The mode buttons read Suggest / Auto /
  Off (in Russian after a Russian prompt), with one line on what the mode does. The last pick shows
  its why on its own line; this session's counts show as short bars.

## 0.4.0 — 2026-11-04

- Renamed from `coreeffort` to `coremodel` (brand CoreModel). The command is `/coremodel`, the log
  is `~/.claude/mods-logs/coremodel.log`. The marketplace replaces an installed coreeffort. A mode
  set with `/coreeffort` may not carry over; if so, set it again with `/coremodel auto` or
  `/coremodel suggest`.
- Picks the model too: Haiku, Sonnet, Opus or Fable, independently of the effort. The model changes
  freely on the chat's first prompt; later only to a stronger model, always with a question that
  names the token cost of re-reading the chat. Fable always asks.
- Two short questions instead of one: the model, then the effort. "Switch, and auto-adjust from
  now" left the question; set auto in the pane or with `/coremodel auto`.
- The switch line, marks, footer, working line and pane show the pair "Opus · High"; the pane has
  a row of model buttons; Back undoes both parts a silent switch changed.
- New settings `models` and `pickModel`.
- A model your plan does not include is dropped for the session after the first failed turn.

## 0.3.0 — 2026-11-04

- A CoreEffort pane: `/coreeffort panel`. Mode buttons, the real level and the menu's level, the
  last pick and why, this session's counts, Release, and level buttons that hold a level at once.
- After a silent switch in auto, the line above the prompt has a "Back to …" button (key `1`).
- Each switch leaves a ↑ or ↓ mark in the chat.
- While a level is held, the working line names it.
- `/coreeffort` with no argument asks which mode to use.

## 0.2.1 — 2026-11-04

- Plugin lists show the name as CoreEffort (`displayName`), not "Coreeffort".

## 0.2.0 — 2026-11-04

- Renamed from `effort-picker` to `coreeffort` (brand CoreEffort). The command is `/coreeffort`,
  the log is `~/.claude/mods-logs/coreeffort.log`. A mode set with the old command may not carry
  over; if so, set it again with `/coreeffort auto` or `/coreeffort suggest`.

## 0.1.0 — 2026-11-04

- First version: picks the effort level for each main-chat prompt, modes suggest, auto and off,
  asks before any switch to xhigh or max.
