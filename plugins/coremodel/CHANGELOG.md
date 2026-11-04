# Changelog

## 0.4.2 — 2026-11-04

- Fixed: a model and level CoreModel held survived `/clear`, `/resume` and a fork, so the new chat
  ran on the old pick (Fable included) with no label in the footer, and its first switch line
  named the wrong "was". A new chat now starts with nothing held, and a pick still on its way when
  it starts is dropped. A compacted chat keeps its hold.

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
