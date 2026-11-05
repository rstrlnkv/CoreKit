# Changelog

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
