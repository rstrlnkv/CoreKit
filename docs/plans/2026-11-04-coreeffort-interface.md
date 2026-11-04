# coreeffort 0.3.0 interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the interface of spec §4.7 to the `coreeffort` plugin: a CoreEffort pane, an undo button on the switch line, switch marks in the transcript, the held level beside the working line, and `/coreeffort` asking for the mode.

**Architecture:** Everything stays in the existing hooks module. Pure words and counting live in `hooks/policy.ts` (no `$` calls); `hooks/register.tsx` gains the new `ui.render` hooks (`Pane`, `Placed`, `Spinner`), button handlers and two new `$.state` keys. The hold itself (§4.4) does not change, except that a hold started before any request learns its menu base from the first request.

**Tech Stack:** TypeScript, the `claude-code` plugin API (types: the plugin-authoring skill's `types/claude-code.d.ts`, or `plugins/coreeffort/.claude-plugin/types/` once the engine has loaded the plugin), `claude plugin test` / `claude plugin validate`.

**Spec:** docs/specs/2026-11-04-effort-picker-design.md, §4.7 (plus §4.3–4.5 it builds on). Section numbers below are the spec's.

## Global Constraints

- Plugin `coreeffort`, command `/coreeffort`, log `~/.claude/mods-logs/coreeffort.log`, pane id `coreeffort`, pane title `CoreEffort`.
- Consent (E6) unchanged: the classifier path never switches to `xhigh` or `max` without a yes. A level the person picks in the pane is that yes.
- The app's effort setting is never written (§4.4); every level change goes through `applyLevel` / `releaseHold`.
- UI words in Russian or English by `uiLang` of the last prompt (§4.5); every new string lives in `texts()` in `policy.ts`, both languages.
- A failure in any new UI path is caught, logged with `log($, '<what>', err)` and never blocks the prompt (E7).
- Version `0.3.0` in `plugins/coreeffort/.claude-plugin/plugin.json`, entry `## 0.3.0 — <date>` in `plugins/coreeffort/CHANGELOG.md`. corecrew is not touched and not bumped.
- TDD: failing test first. After every task: `bash tests/run.sh` → `ALL TESTS PASSED`; `claude plugin validate .` and `claude plugin validate plugins/coreeffort` → no errors.
- Commit messages in repo style (`feat:`, `test:`, `docs:`), no `Co-Authored-By` or `Generated with` lines. Work on this branch; never commit to `main`.
- UI tests loop over `['terminal', 'desktop'] as const` (§7.1).

## Review Focus

1. A level picked in the pane before any request has run: the hold has no menu base yet, and the first request must not read that as "the menu moved" and drop it. Test in Task 4 (`a pane pick before any request survives the first request`).
2. A plugin reload mid-session (`session.start` runs again, `$.state` stays): mark ids must not repeat, or a new mark overwrites an old row; counts must survive. Test in Task 3 (`mark ids stay unique across a session restart`).
3. The undo button pressed after the person already moved the menu (the hold is gone): pressing must not bring back a hold over the person's own choice. Test in Task 2 (`undo after the menu moved does nothing`).
4. `/coreeffort off` pressed in the pane while a band with an undo button stands: the band and its button go, and an old press handler does nothing. Test in Task 4 (`off from the pane clears the band`).
5. A pane mode press while the classifier question is open: the new mode applies to the next prompt only; the open question is answered as before. Covered by the existing `stale pick` flow; no new test, check by reading.

---

### Task 1: Live checks before the code (§7.3)

**Files:**
- Modify: `docs/specs/2026-11-04-effort-picker-design.md` (§4.7 points 4 and 5: record the result)

No code. Done with the owner in a real session, because the answers decide Tasks 5 and 6.

- [ ] **Step 1:** In the desktop Code tab and in a terminal `claude --plugin-dir plugins/coreeffort`, mode `auto`: set the menu to Medium, send `почини авторизацию, после логина кидает на 500`, and while Claude works read the working line. Record which effort it names: the held `high`, the menu's `medium`, or none.
- [ ] **Step 2:** In a scratch mod (scratchpad, not the repo) register a command whose `command.run` hook awaits `$.ui.ask('Pick', ['a', 'b'])` and returns `{ text: answer }`. Run it on both surfaces. Record: the question shows and the answer comes back, or it rejects (and how).
- [ ] **Step 3:** Write both results into §4.7 as one line each (`Checked 2026-11-xx: ...`). If Step 1 shows the held level, Task 5 is dropped; if Step 2 rejects, Task 6 is dropped. Say so in the spec line.
- [ ] **Step 4: Commit** `docs: coreeffort 0.3.0 live checks`.

### Task 2: The undo button

**Files:**
- Modify: `plugins/coreeffort/types/index.d.ts`, `plugins/coreeffort/hooks/policy.ts`, `plugins/coreeffort/hooks/register.tsx`, `plugins/coreeffort/tests/world.ts`, `plugins/coreeffort/tests/policy.test.ts`, `plugins/coreeffort/tests/ui.test.tsx`

**Interfaces:**
- Produces (`types/index.d.ts`):
  - `Band` gains `undo: Level | 'release' | null`: the level to hold on a press, `'release'` to drop the hold, `null` for no button.
- Produces (`policy.ts`, inside `texts(lang)`): `back(l: Level): string` (`Back to Low` / `Вернуть «Низкое»`).
- Produces (`register.tsx`): `releaseHold($): Promise<void>` (sets `hold = null`, `override` → null; replaces the three inline copies).
- Consumes: `applyLevel`, `announce`, `runPick` as they are.

Rules: `announce` takes the `undo` value. In `runPick`, a silent `apply` (mode `auto`, `decide` = `'apply'`) passes `undo` = `'release'` when `now === toLevel(base)`, `now` when `now !== ''`, else `null`; an agreed switch passes `null`. The press handler (Button `key="undo"`, `hotkey="1"`) does nothing when the band's `id` is no longer current or there is no hold; else `'release'` → `releaseHold`, a level → `applyLevel($, level, hold.base)`; then the band goes.

- [ ] **Step 1: Write the failing tests.**
  - `policy.test.ts`: `texts('en').back('low')` contains `Low`; `texts('ru').back('low')` contains `Низкое`.
  - `ui.test.tsx` `an auto switch shows an undo button that releases the hold` — mode `auto`, menu `medium`, pick `high`; on both surfaces `find({ type: 'Button', key: 'undo' })` exists with a label matching `/Back to Medium/`; `ui.press({ key: 'undo' })`; next `step($, 'medium', 1)` → `w.efforts.at(-1)` is `'medium'`; the band text is gone.
  - `undo holds the previous held level` — held `high` (first switch), then pick `low` silently; press undo → next request runs at `high`.
  - `no undo after an agreed switch` — mode `suggest`, reply `Switch to High` → band has no `undo` Button.
  - `undo after the menu moved does nothing` (Review Focus 3) — switch to `high`, then `step($, 'low', 1)` (menu moved), press undo → `step($, 'low', 2)` runs at `low`.
- [ ] **Step 2: Run** `claude plugin test plugins/coreeffort` → the new tests FAIL.
- [ ] **Step 3: Implement** the `undo` field, `back`, `releaseHold`, the `undo` value and the Button in the `AbovePrompt` hook (resolve `Button` from `$.ui.resolve(e)`).
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, both validates → PASS.
- [ ] **Step 5: Commit** `feat: coreeffort undo button`.

### Task 3: Switch marks in the transcript

**Files:**
- Modify: `plugins/coreeffort/types/index.d.ts`, `plugins/coreeffort/hooks/policy.ts`, `plugins/coreeffort/hooks/register.tsx`, `plugins/coreeffort/tests/world.ts`, `plugins/coreeffort/tests/ui.test.tsx`, `plugins/coreeffort/tests/policy.test.ts`

**Interfaces:**
- Consumes: `announce`, `runPick` (Task 2).
- Produces (`types`): `export type Mark = { level: Level; from: Level | ''; why: string; lang: 'ru' | 'en' }`; `export type Stats = { picks: Record<Level, number>; kept: number; last: { level: Level; why: string } | null; marks: number }`; `PluginState['coreeffort']` gains `marks: Record<string, Mark>` and `stats: Stats | null` (null = nothing counted yet).
- Produces (`register.tsx`): `count($, f: (s: Stats) => Stats): Promise<void>` (updates `stats`, starting from zeros); Task 3 uses only `marks`, Task 4 the rest.
- Produces (`policy.ts`): `texts(lang).mark(l: Level, from: Level | '', why: string): string`: `↑` when `from` is `''` or lower than `l`, `↓` when higher, then the words of `applied` (`↑ Effort: High (was Low) · auth bug`). Order of levels: `low < medium < high < xhigh < max`.
- Produces (`register.tsx`): `ui.render` on `{ component: 'Placed' }` drawing `<Text dimColor>` of `mark(...)` when `e.props.plugin === 'coreeffort'` and the id is in `marks`; otherwise `next(e)`.

Rules: after every applied switch (silent or agreed) `runPick` bumps `stats.marks`, stores `marks['mark-' + stats.marks]` and calls `$.ui.place({ id })`. Pane picks (Task 4) and undo presses place no mark. `marks` and `stats` are not cleared in `session.start` (a reload keeps them; a new session starts with an empty `$.state`). `world.ts` answers `ui.place` with `{ value: { isPlaced: true } }` and records the ids in `w.placed: string[]`.

- [ ] **Step 1: Write the failing tests.**
  - `policy.test.ts`: `mark('high','low','x')` starts with `↑`; `mark('low','high','x')` with `↓`; `mark('medium','','x')` with `↑`; Russian `mark` contains `Усилие`.
  - `ui.test.tsx` `each applied switch places one mark` — auto: `high` from `medium`, then `keep`, then `low`; `w.placed` is `['mark-1', 'mark-2']`; mounting `{ plugin: 'coreeffort', component: 'Placed', props: { id: 'mark-2', plugin: 'coreeffort' } }` on both surfaces finds `/↓ Effort: Low \(was High\)/`.
  - `a row of another plugin is left alone` — `props.plugin: 'other'` → the engine's drawing.
  - `mark ids stay unique across a session restart` (Review Focus 2) — one switch, `start($)` again, another switch → `w.placed` is `['mark-1', 'mark-2']` and `mark-1` still draws.
- [ ] **Step 2: Run** plugin tests → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, both validates → PASS.
- [ ] **Step 5: Commit** `feat: coreeffort marks switches in the transcript`.

### Task 4: The CoreEffort pane

**Files:**
- Modify: `plugins/coreeffort/hooks/policy.ts`, `plugins/coreeffort/hooks/register.tsx`, `plugins/coreeffort/tests/world.ts`, `plugins/coreeffort/tests/ui.test.tsx`, `plugins/coreeffort/tests/policy.test.ts`

**Interfaces:**
- Consumes: `Stats`, `count` (Task 3), `releaseHold` (Task 2), `applyLevel`, `currentMode`.

Counting, added to `runPick` here: every readable pick with a level adds `picks[level]` and sets `last`; a `keep` pick, a pick equal to `now`, a "Keep" or other answer and a dismissed question add `kept`.
- Produces (`policy.ts`, `texts(lang)`): `runsAt(l: Level | ''): string` (`Chat runs at: High` / `Чат работает на: Высокое`, `unknown yet` / `пока неизвестно` for `''`), `inMenu(l: Level): string` (`in the menu: Medium (yours)` / `в меню: Среднее (ваше)`), `lastPick`, `session`, `kept`, `release` (`Release` / `Снять`), `noPicks` (`No picks yet.` / `Пока нет выборов.`).
- Produces (`register.tsx`): `setMode($, mode: Mode | 'on'): Promise<string>` — the body of today's `/coreeffort auto|suggest|off|on`, returning the reply text, shared by the command, the pane buttons and Task 6. A module variable `menu: Level | ''`, the menu's level from the last main-chat request.
- Produces: `/coreeffort panel` → `$.ui.open({ id: 'coreeffort', title: 'CoreEffort' })`; replies `CoreEffort pane is open.`, or, when `isPlaced` is false, `CoreEffort pane is waiting: <reason>`; `argumentHint` becomes `[auto|suggest|off|on|panel]`.

Pane body (`ui.render` on `{ component: 'Pane', requestId: 'coreeffort' }`), top to bottom: three Buttons `mode-suggest`, `mode-auto`, `mode-off` (the current one labelled with a leading `●`); `runsAt(hold?.level ?? seen)`; `inMenu(menu)` only while a level is held; `lastPick` and `last` (or `noPicks`); `session` with one line per level whose count is above 0 and the `kept` line; Buttons `release` (only while a level is held) and `level-low` … `level-max` (labels from `levelName`). A `level-*` press calls `applyLevel($, level, menu)` with no question, places no mark and shows no band. A hold started with `base === ''` takes the first request's `e.effort` as its base in `turn.step` instead of being released.

- [ ] **Step 1: Write the failing tests.** `world.ts` answers `ui.open` with `{ value: { isPlaced: true } }` and records `w.opened`. A `PANE` mount constant like the example's (`requestId: 'coreeffort'`, `placement: 'dock'`).
  - `/coreeffort panel opens the pane` — `w.opened` holds `{ id: 'coreeffort', title: 'CoreEffort' }`.
  - `the pane shows mode, level and counts` — after one auto switch to `high` from `medium`, both surfaces find `/Chat runs at: High/`, `/in the menu: Medium/`, `/High · auth bug/`, a `● auto` button and `/High\s+1/`.
  - `a mode button sets the mode` — press `mode-off` → `$.store` `mode` is `off`; the next prompt calls no classifier.
  - `a level picked in the pane holds at once, xhigh included` — press `level-xhigh` → `w.asked` empty; the next request runs at `xhigh`; `w.placed` unchanged.
  - `a pane pick before any request survives the first request` (Review Focus 1) — fresh session, press `level-high`, `step($, 'medium')` then `step($, 'medium', 1)` → both at `high`; `step($, 'low', 2)` → `low` (menu moved).
  - `Release drops the hold` — press `release` → next request at the menu's level; the `release` button is gone.
  - `off from the pane clears the band` (Review Focus 4) — auto switch, press `mode-off` → `AbovePrompt` draws the engine's own; pressing the old `undo` key does nothing.
  - `a fresh pane says there are no picks yet` — Russian prompt submitted, classifier error → `/Пока нет выборов/`.
  - `the pane counts kept prompts` — `suggest`: pick `high` with reply `Keep Medium`, then pick `keep` → `/High\s+1/` and a kept line with `2`; last pick `High`.
- [ ] **Step 2: Run** plugin tests → FAIL.
- [ ] **Step 3: Implement**, moving the command's mode branches into `setMode` (existing `/coreeffort` tests must stay green unchanged).
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, both validates → PASS.
- [ ] **Step 5: Commit** `feat: coreeffort pane`.

### Task 5: The held level beside the working line (only if Task 1 Step 1 showed the menu's level)

**Files:**
- Modify: `plugins/coreeffort/hooks/register.tsx`, `plugins/coreeffort/tests/ui.test.tsx`

**Interfaces:**
- Consumes: `override` state, `texts(lang).levelName`.
- Produces: `ui.render` on `{ component: 'Spinner' }`: while `override` is set, `next({ ...e, props: { ...e.props, suffix: e.props.suffix + ' · ' + levelName(level) } })`; otherwise `next(e)` untouched.

- [ ] **Step 1: Write the failing test** `the working line names a held level` — engine stand-in draws `word + suffix`; with no hold the text is `Thinking…`; after an auto switch to `high` it matches `/Thinking… · High/` on both surfaces; after `/coreeffort off` it is `Thinking…` again.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coreeffort shows the held level on the working line`.

### Task 6: `/coreeffort` with no argument asks (only if Task 1 Step 2 worked)

**Files:**
- Modify: `plugins/coreeffort/hooks/policy.ts`, `plugins/coreeffort/hooks/register.tsx`, `plugins/coreeffort/tests/ui.test.tsx`

**Interfaces:**
- Consumes: `setMode` (Task 4), `texts(lang).runsAt`.
- Produces: the no-argument branch calls `$.ui.ask(texts(lastLang).modeQuestion(mode, level), { options: ['auto', 'suggest', 'off'], header: 'CoreEffort' })`; one of the three answers goes to `setMode` and its text is the reply; a rejection (dismiss) or any other answer returns today's status text unchanged. `modeQuestion(mode: Mode, l: Level | '')` = `CoreEffort: auto. Chat runs at: High.` / `CoreEffort: auto. Чат работает на: Высокое.`

- [ ] **Step 1: Write the failing tests.** `no argument asks for the mode` — `w.reply = 'auto'`, `run($, '')` → `w.asked.at(-1)` is `['auto', 'suggest', 'off']`, `$.store` mode `auto`. `a dismissed mode question changes nothing` — `w.reply = null` → mode stays, reply contains `suggest` (the existing `/coreeffort reports…` test keeps passing as is).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coreeffort asks for the mode`.

### Task 7: Release 0.3.0 and the live check

**Files:**
- Modify: `plugins/coreeffort/.claude-plugin/plugin.json` (`0.3.0`), `plugins/coreeffort/CHANGELOG.md`, `plugins/coreeffort/README.md` (the pane, `/coreeffort panel`, undo, marks; what was dropped in Task 1, if anything), spec §4.7 if anything changed on the way

- [ ] **Step 1:** Version, changelog entry (plain words: what the person now sees), README.
- [ ] **Step 2: Live check** in the desktop Code tab and the terminal (`claude --plugin-dir plugins/coreeffort`): `/coreeffort panel` opens the pane; an auto switch shows the line with `Back to …`, the mark in the chat and the counts in the pane; pressing `1` undoes; a level button in the pane holds at once. Report what was seen, with one screenshot per surface.
- [ ] **Step 3: Run** `bash tests/run.sh`, `claude plugin validate .`, `claude plugin validate plugins/coreeffort` → PASS.
- [ ] **Step 4: Commit** `docs: coreeffort 0.3.0 readme and changelog`. Stop; tell the owner in Russian how to try it and what may break. No merge or push without their separate "ок".
