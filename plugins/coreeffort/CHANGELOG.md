# Changelog

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
