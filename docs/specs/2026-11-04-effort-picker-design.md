---
title: effort-picker plugin — design spec
description: Requirements for effort-picker, a second plugin in the corekit marketplace that picks the effort level for each prompt of the main chat, for code and office work, and asks before any switch to xhigh or max. Read before changing it.
status: draft
files: [plugins/effort-picker/, .claude-plugin/marketplace.json, tests/test_effort_picker.sh, tests/test_manifest.sh, README.md]
related: [docs/specs/2026-11-03-coredev-design.md]
updated: 2026-11-04
---

# `effort-picker` plugin — design spec

## 1. Goal

Before Claude starts on a prompt in the main chat, a short model call reads the prompt and picks
the effort level the work needs: `low`, `medium`, `high`, `xhigh` or `max`, for code in a
repository and for office work (writing, documents, analysis) alike. The plugin then offers the
switch, or makes it, so cheap work runs cheap and hard work gets the care it needs.

Install: `/plugin install effort-picker@corekit`. One command: `/effort-picker`.

The idea comes from a third-party mod (Ben AI's "Effort Optimizer"), which ships with no license.
Nothing of it is copied: code, classifier rules and texts here are written from scratch.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| E1 | A separate plugin in the corekit marketplace, at `plugins/effort-picker/`; coredev is not changed. | Changing the effort of a request needs a function hooks module (early-access API, Claude Code 2.1.287+). coredev stays bash-only, keeps its minimum version and its claude.ai sync; an API change breaks only effort-picker. |
| E2 | Name `effort-picker`, command `/effort-picker`. | `/effort` is a built-in command. |
| E3 | Written from scratch; only the idea is reused. | The source mod has no license; CoreKit is public under MIT. |
| E4 | One classifier call per prompt, before the turn's first model request. | The first request must already run at the chosen level. |
| E5 | Default classifier model Haiku 5.5; Sonnet 5.5 by setting. Haiku stays the default only if it matches the expected level on all nine prompts of §7.2 where Sonnet does; otherwise the default is Sonnet. | Haiku is faster and cheaper; picking one of six answers is a small task. |
| E6 | Consent rule: the plugin never switches to `xhigh` or `max` without the person's yes, in any mode. In `auto` every other switch, up or down, is silent and announced after the fact (§4.5). | `xhigh` and `max` are the long, costly runs, so the person agrees to them; below that, `auto` must stay automatic to be worth having. |
| E7 | A failed classifier call (timeout, error, unreadable answer) leaves the level as it is; the prompt always goes on. | The plugin must never block work. |
| E8 | No `.claude-plugin/types/`, logs or personal data in the repo; nothing leaves the person's account but the classifier call through `$.model.complete`. | Same principle as coredev: a universal plugin with nothing personal. |

## 3. Layout

```
plugins/effort-picker/
  .claude-plugin/plugin.json   name, version, description, license, userConfig (§5), "types"
  hooks/hooks.json             { "modules": ["./register.tsx"] }
  hooks/register.tsx           hooks: session.start, prompt.submit, turn.step, command.run, ui.press, ui.render
  hooks/classifier.ts          the classifier prompt (§6) and the answer parser; no `$` calls
  hooks/policy.ts              the consent rule (E6) and the UI texts; no `$` calls
  types/index.d.ts             $.state contract: band, override
  tests/*.test.ts              run by `claude plugin test plugins/effort-picker`
  README.md                    what it does, install, settings, cost, the menu caveat (§4.5)
  CHANGELOG.md                 the plugin's own; the root CHANGELOG is coredev's
```
`.claude-plugin/marketplace.json` gets a second entry: `"name": "effort-picker"`,
`"source": "./plugins/effort-picker"`. coredev's entry (`"source": "./"`) stays; its installed copy
will contain the `plugins/` folder, which coredev never loads (checked in the plan, §7.3).

## 4. Behaviour

### 4.1 When it checks
- On `prompt.submit` from the composer or the bridge only; slash commands, empty prompts, and
  prompts from hooks, agents or automation are skipped.
- The pick runs at the turn's first main-chat model request (`turn.step`, `index === 0`, no
  `agentId`); subagent requests are never touched.
- A newer prompt makes a pending pick for an older one stale; a stale pick is dropped.

### 4.2 What it sends
The classifier gets the prompt (first 4000 characters), the last assistant reply (first 600
characters) and the current level. Model: per E5, effort `low`, at most 120 output tokens,
timeout 10 s.

### 4.3 Modes (setting `mode`, overridden by `/effort-picker`)
- `suggest` (default): when the pick differs from the current level, Claude waits and a question
  asks: "Switch to X" / "Switch, and auto-adjust from now" / "Keep Y". A dismissed question keeps
  the level.
- `auto`: a switch to `low`, `medium` or `high`, up or down, is applied silently and announced
  by the line of §4.5; a switch to `xhigh` or `max` asks the same question as `suggest` (E6).
- `off`: nothing runs.
- A `keep` answer, or a pick equal to the current level, changes nothing and asks nothing.

### 4.4 How the level is applied
1. Set the effort row of the config menu (`$.config.set`) when it exists, is not locked and has
   the level.
2. Otherwise hold the level: put it on every main-chat request (`turn.step` rewrite) and store it
   as `override`.
3. A held level is released when the person moves the menu (the request's own effort changes
   from the value seen when the hold started) or turns the plugin off.

### 4.5 What the person sees
- After a switch, a line above the prompt for 15 s: "Effort: High (was Medium) · <why>".
- While a level is held, a label "Effort High" in the footer slot beside the model menu: the
  menu itself keeps showing the person's own setting, which a chat cannot change.
- `/effort-picker` prints the mode and the level the chat really runs at.
- Interface texts are in Russian when the prompt is mostly Cyrillic, English otherwise; the
  classifier writes its `why` in the language of the prompt.
- A status line "checking effort…" while the classifier runs.

### 4.6 Errors
Every failure (classifier, config, UI) is caught, written to
`~/.claude/mods-logs/effort-picker.log` (last 20 KB kept) and the prompt goes on (E7).

## 5. Settings

`userConfig` in `plugin.json`:

| Key | Options | Default |
|---|---|---|
| `mode` | `suggest`, `auto`, `off` | `suggest` |
| `classifier` | `haiku`, `sonnet` | `sonnet` (E5: on 2026-11-04 Sonnet 9/9, Haiku 8/9, missing xhigh on the unattended app) |

`/effort-picker auto|suggest|off|on` changes the mode for every session and is kept in
`$.store`; it wins over the setting. `on` returns to the last mode that was not `off`.

## 6. Classifier rules

Stop at the first match:

1. `keep`: the prompt only approves, answers Claude's question, picks an option or says to go on.
2. `low`: quick, conversational or mechanical, easy to check, a mistake is cheap.
   Code: explain a snippet or error, rename, fix a typo, one-line change, run a command, a git
   step, a question about a tool. Office: brainstorm, quick rewrite, short translation, short
   summary, sorting, rough outline, simple question.
3. `medium` (also when unsure): normal work with a clear path. Code: a contained feature or a
   fix with a known cause in one or two files, tests for a given function, a small script, docs.
   Office: everyday writing, meeting summary, report in a set format, quick research.
4. `high`: a hidden mistake is costly or the path is unclear. Code: unknown-cause bug, failing or
   flaky tests, many files, refactoring, security, auth, payments, migrations, deploys,
   concurrency, deleting data, code review, performance, API or schema design. Office: numbers
   across sources, open-ended analysis, contract risk, fact-checking, long documents.
5. `xhigh`: long, hard and critical work handed off to run alone (all three). Code: a whole
   feature or app end to end, a large migration or rewrite, a multi-step plan unattended, a deep
   security audit. Office: a full research report, a long agreement before signing, a one-shot
   investor deck.
6. `max`: only when the prompt asks for the deepest work and says it is critical.

Plus: length is not difficulty; a short prompt can hide big work; prompts can be in any
language. Answer: JSON `{"level": "...", "why": "<12 words, in the prompt's language>"}`. The
parser takes the first JSON object, accepts `extra high` / `x-high` as `xhigh`, and treats
anything else as no answer (E7).

## 7. Testing

### 7.1 Unit tests (`claude plugin test`, model mocked, no network)
- Parser: each level, `keep`, `Extra high`, junk, missing JSON.
- Skips: slash command, empty prompt, non-composer origin, subagent request.
- `suggest`: question asked on a different pick; "Keep" leaves the level; dismiss leaves it.
- `auto`: switches among low, medium, high (both ways) silent with the announce line; → xhigh
  and → max ask; a lowering from xhigh to high is silent.
- Classifier error and timeout: request goes on unchanged, log line written.
- Stale pick dropped when a newer prompt arrives.
- Hold released when the menu moves; `off` clears the hold and the label.
- Rendering on `terminal` and `desktop`.

`tests/run.sh` runs `tests/test_effort_picker.sh`, which calls
`claude plugin test plugins/effort-picker` and `claude plugin validate plugins/effort-picker`,
and prints a skip line (not a failure) when `claude` is not on `PATH`.

### 7.2 Classifier quality (manual, real model)
`plugins/effort-picker/tests/quality.sh` sends nine prompts and compares with the expected level:

| Prompt | Expected |
|---|---|
| почини опечатку в README | low |
| что делает git rebase --onto? | low |
| почини авторизацию, после логина кидает на 500 | high |
| добавь кнопку экспорта в CSV на страницу отчётов | medium |
| отрефактори модуль платежей и мигрируй базу на новую схему | high or xhigh |
| сделай с нуля приложение-трекер привычек на SwiftUI, план утверждён, работай сам | xhigh |
| перепиши это письмо клиенту повежливее | low |
| проверь договор аренды на риски, 12 страниц | high |
| да, давай | keep |

Not part of `tests/run.sh` (it needs the network).

### 7.3 Checks in the plan
- coredev installed from `./` does not load anything from `plugins/effort-picker/`.
- The plugin loads and works on the current Claude Code (2.1.309) in the terminal and the
  desktop Code tab.

## 8. Release
- `plugins/effort-picker/.claude-plugin/plugin.json` version `0.1.0`, `"license": "MIT"`.
- An entry in `plugins/effort-picker/CHANGELOG.md` and an install line in the root README.
- coredev's version is not bumped: coredev does not change.

## 9. Out of scope
- Effort for coredev's crew agents (`/coredev:task`).
- Changing the app's effort menu itself (a chat cannot).
- Any learning from the person's past choices.
