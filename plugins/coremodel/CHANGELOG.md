# Changelog

All notable changes to `coremodel` are listed here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/). Older entries are shortened; the commit log has the
full detail.

## [Unreleased]

### Fixed

- When only the model is held, the pane's "your default" names only the model, as `/coremodel`
  does (it also named the effort, which was not held).

## [0.8.0] - 2026-11-09

### Changed

- `language: auto` follows Claude Code's `language` setting, no longer the text of the prompt: a
  Cyrillic prompt (a Ukrainian one, say) no longer turns the words Russian. A language stored by
  0.7.0 is ignored. To keep Russian, set the plugin's `language` to `ru` or Claude Code's
  `"language": "russian"` in settings.json.

## [0.7.0] - 2026-11-08

Needs Claude Code 2.1.309 or newer (models are named by alias). Codex: the hook changed, so Codex
keeps it off until you trust it again in `/hooks`. The hint is also off until you set
`codex_hint: on` (see the README).

### Added

- `/coremodel undo` takes back the last silent switch, also after the line above the prompt is gone.
- A `language` setting (`auto`, `en`, `ru`). The words live in per-locale tables
  (`hooks/locales/`); `auto` keeps the last prompt's language across a reload.
- A toast and a pane line when the classifier fails twice in a row; a pick that works clears them.
- VS Code: a silent switch is told in a toast that names `/coremodel undo`.
- Codex: the hint reads its own settings file (`codex_hint: on` in `~/.config/coremodel/settings`)
  and shows a status message while it runs.

### Changed

- `auto` is the default mode. It asks only before Fable, Extra high, Max and a stronger model
  mid-chat.
- `suggest` no longer opens dialogs: the prompt runs as it is, and a line above the prompt offers
  the pick (Switch, Keep).
- The line above the prompt shows only after a silent switch. The footer button carries the state
  (`CoreModel · Opus · High`, `CoreModel · off`).
- The pane puts the mode and the state first, marks the selection with ●, says "Effort" everywhere
  and sums the session in one line.
- The mid-chat cost question names the lasting price per reply first, then the one-off re-read.
- Models are named by alias (`opus`, `sonnet[1m]`), so new versions and Bedrock, Vertex or gateway
  ids work.
- Codex: the hint is off until turned on, stays silent when the current model fits, and makes no
  call on the strongest model. The Codex manifest has its own description.
- Log lines go to Claude Code's debug log (`claude --debug`).
- A one-sentence description; the icon moved to `assets/icon.png`.

### Removed

- The log file `~/.claude/mods-logs/coremodel.log`.
- `/coremodel probe` from the command hint and the README (it writes to the debug log only).
- The suffix on the working line and the drawing of the session counts in the pane.

### Fixed

- In `auto`, a current model the plugin did not know (a newer id, a gateway name) was replaced on
  the first prompt by an older pinned id. It is now left alone.
- Classifier failures were invisible: the pane said "No picks yet".
- The pane's captions take the width of the longest caption in the active language, so the
  Russian rows line up.
- `/coremodel recheck` names the "Pick the model" setting instead of the raw key `pickModel`.
- `/coremodel panel` where no app can show the pane says so in a plain sentence instead of an
  internal reason; the reason goes to the debug log.

## [0.6.0] - 2026-11-08

### Added

- A hint in Codex. Codex hooks cannot switch the model, so a `UserPromptSubmit` hook asks
  `gpt-6-luna` which model and effort the prompt needs and adds one line ("switch with /model").
  It is about one small call per prompt, at most 20 seconds, and silent on any failure;
  `coremodel_mode: off` in the corecrew settings file turns it off. The Claude Code module is unchanged.

### Changed

- The hint is also shown to you as a `systemMessage`; `additionalContext` reaches only the model.

### Fixed

- The Codex hint no longer runs out of its 20 s limit: the nested `codex exec` runs with
  `--ignore-user-config` and low reasoning effort (about 8 s instead of 13 s), so it no longer
  loads your config, MCP servers or other plugins' hooks.

## [0.5.2] - 2026-11-06

### Changed

- The classifier picks the effort and the model more accurately, Haiku most of all. Its prompt
  keeps the two choices apart (effort follows the price of a mistake, the model follows how hard
  the thinking is), says when "keep" is right, sends a crash log that asks why to high effort on
  Opus, and shows eight short examples.
- Measured on labelled prompts, each asked three times: Haiku went from 143 of 165 right levels
  (55 prompts) to 180 of 180 (the same 55 and 5 new ones), with none off by two rungs; Sonnet from
  162 of 165 to 178 of 180.
- `tests/quality.sh` (manual, real model calls) reads its prompts from `tests/quality-cases.txt`,
  in a tuning set and a held-out set.

## [0.5.1] - 2026-11-05

### Fixed

- A pick that names a model you cannot use is no longer dropped: the nearest model you can use takes
  its place (the one below first, so Opus for Fable), and you are told why.

## [0.5.0] - 2026-11-05

### Added

- The models are chosen with four switches, **Allow Haiku**, **Allow Sonnet**, **Allow Opus** and
  **Allow Fable**, all on by default. With every switch off CoreModel picks the effort only.
- `/coremodel recheck` says when every switch is off.

### Removed

- The text setting `models` is no longer read: if you narrowed it, untick the models again.
  Its typo warning is gone with it.

## [0.4.17] - 2026-11-05

### Changed

- `/coremodel recheck` says the same in both languages and says so when the account's model list
  could not be used.

### Fixed

- The "not available" note offers `/coremodel recheck` instead of sending you to the `models` setting.

## [0.4.16] - 2026-11-05

### Added

- The models an account can use are read from the `/config` Model row before every pick: a model
  your plan lacks is never picked or offered, and one that becomes available is offered with no restart.
- `/coremodel recheck` reads the list again at once.

## [0.4.15] - 2026-11-05

### Added

- `/coremodel probe` lists the rows of `/config` with their choices (read only).

## [0.4.14] - 2026-11-05

### Added

- An icon file for the plugin listing (sliders). No manifest named it yet.

## [0.4.13] - 2026-11-05

### Changed

- Cleanup with no change in behaviour.

## [0.4.12] - 2026-11-05

### Changed

- Questions ask about the model first, then the effort, each with the recommended choice first.
  A level typed under Other counts.
- `/coremodel` names the model as well as the level ("Now in the chat: Opus · High"), and its
  replies follow the language of the last prompt.
- The working line says "checking model and effort…".

### Fixed

- The StopFailure and SessionStart hooks handle their errors; `claude plugin validate` no longer lists them.

## [0.4.11] - 2026-11-05

### Changed

- The Russian texts were read through once: level names in quotes, clearer counters, no mixed labels.

### Fixed

- The Russian mode names said the opposite of what the modes do; they are now «Спрашивать» (Ask)
  and «Автоматически» (Automatically).
- The `/coremodel` mode question in a Russian chat offers the Russian mode names.

## [0.4.10] - 2026-11-05

### Changed

- The pane has more even spacing, and the session drawing has larger text.

## [0.4.9] - 2026-11-05

### Changed

- While a model or level is held, the footer shows the pair "Opus • High".

### Fixed

- The session counts follow what was applied, not what the classifier asked for.
- On the desktop the pane draws with only "Left as it was" to show, and its rules take the pane's width.

## [0.4.8] - 2026-11-05

### Changed

- On the desktop the section rule is drawn at the pane's own width.

## [0.4.7] - 2026-11-05

### Changed

- The levels bar in the session drawing has its own caption and a legend that no longer overlaps it.

### Fixed

- On the desktop the section rules are no longer cut off.

## [0.4.6] - 2026-11-05

### Added

- On the desktop (and VS Code, mobile) the session counts are one drawing with a text alternative;
  the terminal keeps the text bars.

## [0.4.5] - 2026-11-05

### Added

- A thin rule separates the blocks of the pane.

### Changed

- The pane is tighter, and the session counts are scaled bars.

## [0.4.4] - 2026-11-05

### Added

- A **CoreModel** button in the footer opens and closes the pane without interrupting a running turn.

### Fixed

- Races found by a read-only audit: a pick for a prompt that can no longer be the next turn is
  dropped; a prompt sent before `/clear`, `/resume` or a fork keeps its pick; a request with no
  effort is not asked about a level; a pane press made while the classifier runs wins over the
  late pick; `model_not_found` from a subagent no longer drops the main chat's model; a failed
  classifier call is retried once.

## [0.4.3] - 2026-11-05

### Added

- A word in the `models` setting that names no model is shown in the pane and logged once.

### Changed

- A question about Fable, Extra high or Max lists **Keep** first.
- A long prompt goes to the classifier as its first and last 2000 characters.
- The mid-chat model question names the reason and the one-time cost in dollars.

### Fixed

- `/coremodel` replies no longer repeat "CoreModel" and speak of the model and the level.

## [0.4.2] - 2026-11-04

### Fixed

- A held model and level no longer survive `/clear`, `/resume` and a fork.
- The classifier call no longer hangs on a chat's first prompt: a second call starts after 3 s
  and the wait is 8 s at most.

## [0.4.1] - 2026-11-04

### Changed

- The pane is redrawn: what the chat runs at on top, model and level buttons, **Back to the menu's
  choice**, the mode buttons, the last pick with its reason, and this session's counts.

## [0.4.0] - 2026-11-04

### Added

- Picks the model too (Haiku, Sonnet, Opus or Fable), independently of the effort. Mid-chat it only
  moves to a stronger model, always with a question that names the cost. Fable always asks.
- Settings `models` and `pickModel`.
- A model your plan does not include is dropped for the session after the first failed turn.

### Changed

- Renamed from `coreeffort` to `coremodel`. The command is `/coremodel`, the log is
  `~/.claude/mods-logs/coremodel.log`; a mode set with `/coreeffort` may need to be set again.
- Two short questions instead of one: the model, then the effort.

## [0.3.0] - 2026-11-04

### Added

- A pane, `/coreeffort panel`: modes, levels, the last pick and why, this session's counts.
- After a silent switch in auto, a "Back to …" button above the prompt.
- Each switch leaves a mark in the chat, and the working line names a held level.

### Changed

- `/coreeffort` with no argument asks which mode to use.

## [0.2.1] - 2026-11-04

### Changed

- Plugin lists show the name as CoreEffort (`displayName`).

## [0.2.0] - 2026-11-04

### Changed

- Renamed from `effort-picker` to `coreeffort`. The command is `/coreeffort`.

## [0.1.0] - 2026-11-04

### Added

- First version: picks the effort level for each main-chat prompt, with the modes suggest, auto
  and off, and asks before any switch to xhigh or max.
