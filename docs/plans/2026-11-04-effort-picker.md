# effort-picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second plugin in the corekit marketplace, `effort-picker`, that picks the effort level for each main-chat prompt and asks before any switch to xhigh or max.

**Architecture:** A function hooks module (TypeScript/TSX, Claude Code early-access plugin API) in `plugins/effort-picker/`. Pure logic lives in two files with no `$` calls (`classifier.ts`: prompt and parser; `policy.ts`: the consent rule and UI texts); `register.tsx` wires hooks, the model call, the level hold and the UI. coredev is not touched.

**Tech Stack:** TypeScript 5.4+, the `claude-code` plugin API (types in the plugin-authoring skill's `types/claude-code.d.ts`, and in `plugins/effort-picker/.claude-plugin/types/` once the engine has loaded the plugin), `claude plugin test` / `claude plugin validate`, bash 3.2 for the repo test wrapper.

**Spec:** docs/specs/2026-11-04-effort-picker-design.md (section and decision numbers below are the spec's).

## Global Constraints

- Plugin name `effort-picker`, command `/effort-picker`, version `0.1.0`, `"license": "MIT"`, folder `plugins/effort-picker/` (E1, E2).
- Written from scratch: nothing copied from the Ben AI mod, its code or its texts (E3).
- Consent (E6): never switch to `xhigh` or `max` without the person's yes, in any mode. `auto`: every other switch, up or down, silent plus the announce line. `suggest`: asks on every change.
- A failed classifier call never blocks the prompt (E7); errors go to `~/.claude/mods-logs/effort-picker.log`, last 20 KB kept.
- Classifier: prompt first 4000 chars, last reply first 600 chars, effort `low`, `maxTokens: 120`, `timeoutMs: 10_000`. Model ids: `claude-haiku-5-5`, `claude-sonnet-5-5`.
- `userConfig`: `mode` (`suggest` | `auto` | `off`, default `suggest`), `classifier` (`haiku` | `sonnet`, default decided in Task 5).
- Only main-chat requests are touched: `turn.step` with `agentId === undefined`; the pick runs at `index === 0`.
- Everything on disk in English; UI texts in Russian or English by the prompt (§4.5); talk to the owner in Russian.
- Commit messages in repo style (`feat:`, `test:`, `docs:`), **no `Co-Authored-By` or `Generated with` lines**. Branch `feat/effort-picker`; never commit to `main`.
- TDD: failing test first. After every task: `bash tests/run.sh` → `ALL TESTS PASSED`, `claude plugin validate .` and `claude plugin validate plugins/effort-picker` → no errors.
- `.claude-plugin/types/` inside the plugin is engine-written: add it to `.gitignore`, never commit it.
- The plugin keeps its own `plugins/effort-picker/CHANGELOG.md`: the root CHANGELOG is coredev's, and `tests/test_manifest.sh` pins its first entry to coredev's version.

## Review Focus

1. A prompt sent while the previous pick's question is still open (person typed fast): the older pick must not apply its level to the newer turn. Test in Task 3 (`stale pick is dropped`).
2. The config row exists but is locked, or lacks `xhigh` / `max`: the level must still reach the request through the hold, and the footer label must show it. Test in Task 3 (`locked row falls back to hold`).
3. A free-text answer under "Other" in the question dialog: compared with the labels exactly, anything else means keep. Test in Task 3 (`other answer keeps the level`).
4. A classifier answer with prose around the JSON, or `"level": "Extra high"`: parsed; `"level": "ultra"`: no answer. Tests in Task 1.
5. A mixed-language prompt (Russian with English code identifiers): UI in Russian when most letters are Cyrillic. Test in Task 2 (`uiLang` cases).

---

### Task 1: Plugin skeleton, classifier, repo wiring

**Files:**
- Create: `plugins/effort-picker/.claude-plugin/plugin.json`, `plugins/effort-picker/hooks/hooks.json`, `plugins/effort-picker/hooks/register.tsx` (empty `register` for now), `plugins/effort-picker/hooks/classifier.ts` (exports `TEMPLATE` too), `plugins/effort-picker/types/index.d.ts`, `plugins/effort-picker/tests/classifier.test.ts`, `plugins/effort-picker/CHANGELOG.md`, `tests/test_effort_picker.sh`
- Modify: `.claude-plugin/marketplace.json` (second entry), `.gitignore` (`plugins/effort-picker/.claude-plugin/types/`), `tests/test_manifest.sh` (assert the entry)

**Interfaces:**
- Produces (`types/index.d.ts`): `export type Level = 'low' | 'medium' | 'high' | 'xhigh' | 'max'`; `export type Band = { id: number; level: Level; from: Level | ''; why: string; lang: 'ru' | 'en' }`; `PluginState['effort-picker'] = { band: Band | null; override: Level | null }`.
- Produces (`classifier.ts`): `type Pick = { level: Level | 'keep'; why: string }`; `toLevel(v: unknown): Level | ''`; `buildPrompt(i: { prompt: string; lastReply: string; now: Level | '' }): string`; `parseAnswer(text: string): Pick | null`.

- [ ] **Step 1: Write `tests/test_effort_picker.sh`** — sources `tests/lib.sh`; if `command -v claude` fails, prints `SKIP effort-picker: claude not on PATH` and exits 0; else runs `claude plugin validate "$ROOT/plugins/effort-picker"` and `claude plugin test "$ROOT/plugins/effort-picker"`, failing on non-zero. Add to `tests/test_manifest.sh`: `assert_contains "$M" '"name": "effort-picker"'` and `assert_contains "$M" '"source": "./plugins/effort-picker"'`.
- [ ] **Step 2: Write `classifier.test.ts`** with `test` / `expect` from `claude-code/testing`:
  - `toLevel`: `'Extra high'`, `'x-high'`, `'XHIGH'` → `'xhigh'`; `'ultra'`, `3`, `null` → `''`.
  - `parseAnswer('Sure: {"level":"high","why":"auth bug"} ok')` → `{ level: 'high', why: 'auth bug' }`.
  - `parseAnswer('{"level":"keep","why":"approval"}')` → `level: 'keep'`.
  - `parseAnswer('{"level":"ultra"}')`, `parseAnswer('no json')`, `parseAnswer('{bad')` → `null`.
  - `why` is trimmed, em/en dashes become `, `, cut to 90 chars; a missing `why` → `''`.
  - `TEMPLATE` contains each placeholder exactly once; `buildPrompt` of a prompt holding `$&` and `{{NOW}}` keeps them verbatim.
  - `buildPrompt` output contains the prompt cut to 4000 chars, the reply cut to 600 chars, `The chat runs at: unknown` when `now` is `''`, and all six answer words `low medium high xhigh max keep`.
- [ ] **Step 3: Run** `bash tests/test_effort_picker.sh` and `bash tests/test_manifest.sh` — expect FAIL (no plugin, no entry).
- [ ] **Step 4: Implement.** Manifest per Global Constraints with `userConfig` (`classifier` default `haiku` for now) and `"types": "./types/index.d.ts"`; marketplace entry with a one-line description; `classifier.ts` with the ladder of spec §6 written as the model prompt (own wording; both code and office examples per level; the three notes: length is not difficulty, short prompts can hide big work, any language; JSON answer with `why` under 12 words in the prompt's language). The prompt text is one exported constant `TEMPLATE` between the lines `// TEMPLATE-START` and `// TEMPLATE-END`, with placeholders `{{NOW}}`, `{{REPLY}}`, `{{PROMPT}}` (inside `<reply>` / `<prompt>` tags); `buildPrompt` fills them with `split`/`join`, so `$`-patterns in the person's text are never interpreted.
- [ ] **Step 5: Run** `bash tests/run.sh`, `claude plugin validate .`, `claude plugin validate plugins/effort-picker` — expect PASS. Also run `tsc -p plugins/effort-picker` once the engine has laid its types (or the scratch tsconfig from the types file header).
- [ ] **Step 6: Commit** `feat: effort-picker skeleton and classifier`.

### Task 2: Consent policy and UI texts

**Files:**
- Create: `plugins/effort-picker/hooks/policy.ts`, `plugins/effort-picker/tests/policy.test.ts`

**Interfaces:**
- Consumes: `Level`, `Pick` (Task 1).
- Produces: `type Mode = 'suggest' | 'auto' | 'off'`; `decide(mode: Mode, now: Level | '', pick: Pick | null): 'none' | 'apply' | 'ask'`; `uiLang(text: string): 'ru' | 'en'`; `texts(lang: 'ru' | 'en')` returning `{ question(level, why), switchTo(level), switchAndAuto, keep(now | ''), applied(level, from, why), label(level), levelName(level) }`.

- [ ] **Step 1: Write `policy.test.ts`:**
  - `decide('off', 'high', {level:'low',why:''})` → `'none'`; `decide(any, 'high', null)` → `'none'`; `keep` → `'none'`; pick equal to `now` → `'none'`.
  - `suggest`: every differing pick (`low`, `medium`, `high`, `xhigh`, `max`) → `'ask'`.
  - `auto`: `medium→low`, `low→medium`, `low→high`, `high→medium`, `xhigh→high`, `max→low` → `'apply'`; `high→xhigh`, `low→max`, `''→xhigh` → `'ask'`; `''→medium` → `'apply'`.
  - `uiLang`: `'почини авторизацию'` → `'ru'`; `'почини loginController в auth.ts'` → `'ru'`; `'fix the login'` → `'en'`; `'123 ???'` → `'en'`.
  - `texts('ru').switchTo('high')` and `texts('en').switchTo('high')` differ and both name the level; `texts('en').applied('high','medium','auth bug')` contains `High`, `Medium`, `auth bug`.
- [ ] **Step 2: Run** `claude plugin test plugins/effort-picker` — expect FAIL.
- [ ] **Step 3: Implement** `decide` per E6 and §4.3; `uiLang` = `'ru'` when Cyrillic letters are more than half of all letters. Russian level names: Низкое, Среднее, Высокое, Очень высокое, Максимальное; English: Low, Medium, High, Extra high, Max. Footer label stays short: `Effort High` / `Усилие High` (fits ~14 cells).
- [ ] **Step 4: Run** the plugin tests — expect PASS; `bash tests/run.sh` — PASS.
- [ ] **Step 5: Commit** `feat: effort-picker consent policy and texts`.

### Task 3: Hooks — pick, ask, apply, hold

**Files:**
- Modify: `plugins/effort-picker/hooks/register.tsx`
- Create: `plugins/effort-picker/tests/flow.test.ts`

**Interfaces:**
- Consumes: `buildPrompt`, `parseAnswer`, `toLevel` (Task 1); `decide`, `uiLang`, `texts`, `Mode` (Task 2).
- Produces: hooks on `session.start`, `prompt.submit`, `turn.step`; module functions `currentMode($, options): Promise<Mode>` (`$.store.get('mode')` wins over `options.mode`) and `applyLevel($, level): Promise<void>` used by Task 4. State keys `band`, `override` as declared in Task 1.

Flow (spec §4.1–4.4, §4.6): `prompt.submit` from origin `composer` or `bridge`, non-empty, not starting with `/` → bump a generation counter and remember `{ text, gen }`. `turn.step` (async generator) with no `agentId` and a string `effort`: record the request's effort; release the hold if `e.effort` differs from the effort seen when the hold began; at `index === 0` with a remembered prompt, run the pick (status line `checking effort…` while it runs), drop it if the generation moved, `decide`, then ask (`$.ui.ask(question, { options: [switchTo, switchAndAuto, keep], header: 'Effort' })`, a rejection or any other answer = keep; `switchAndAuto` also stores mode `auto`) or apply. `applyLevel`: config row whose key or label matches `/effort/i`, kind `choice`, with an option normalising to the level, not locked → `$.config.set`; otherwise hold (`override` = level). The request goes on with `{ ...e, effort: level }` whenever the turn's chosen level or the held level differs from `e.effort`. Every failure is logged and the request goes on unchanged.

- [ ] **Step 1: Write `flow.test.ts`** (mock `model.complete`, `config.list`, `config.set`, `ui.ask`, `store.get`/`store.set`, `session.messages` with `on(...)`; drive with `$.session.start`, `$.prompt.submit`, `$.turn.step`):
  - `skips slash commands, empty prompts and non-composer origins` — `model.complete` never called.
  - `subagent request untouched` — `agentId: 'a1'` → effort passes unchanged, no call.
  - `suggest asks and Switch applies` — pick `high`, now `medium`, answer `switchTo` → `config.set` with the high option; request effort `high`.
  - `suggest Keep, dismiss and other answer keep the level` — three cases, request effort stays `medium` (Review Focus 3).
  - `auto applies low/medium/high silently` — `ui.ask` never called, band set with `from`.
  - `auto asks before xhigh and max` — `ui.ask` called; Keep → effort unchanged.
  - `classifier error and timeout leave the level` — `model.complete` answers `{ isAnswered: false, reason: 'timeout' }` and throws; request unchanged, a log line written (`fs.write` path ends `mods-logs/effort-picker.log`).
  - `stale pick is dropped` — second prompt submitted while the first pick's `ui.ask` is pending; first answer `switchTo` changes nothing (Review Focus 1).
  - `locked row falls back to hold` — row `isLocked: true` → `override` = `high`, later requests of the session carry `high` (Review Focus 2).
  - `moving the menu releases the hold` — next request arrives with a new `e.effort` → `override` cleared, effort passes as given.
  - `the payload is cut` — the prompt sent to `model.complete` holds 4000 chars of a 5000-char prompt and 600 of a 1000-char reply; `model` is `claude-haiku-5-5` by default and `claude-sonnet-5-5` with `{ options: { classifier: 'sonnet' } }`.
- [ ] **Step 2: Run** plugin tests — expect FAIL.
- [ ] **Step 3: Implement** the flow above in `register.tsx`.
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, both validates, `tsc` — PASS.
- [ ] **Step 5: Commit** `feat: effort-picker pick, consent and hold`.

### Task 4: UI and the command

**Files:**
- Modify: `plugins/effort-picker/hooks/register.tsx`
- Create: `plugins/effort-picker/tests/ui.test.tsx`

**Interfaces:**
- Consumes: `currentMode`, `applyLevel`, `texts`, state `band` / `override` (Task 3).
- Produces: `ui.render` on `AbovePrompt` (the applied line, gone after 15 s via `$.clock.sleep` and a band `id` check) and on `SessionMode` (label while `override` is set: `<Text>` on `desktop`/`vscode`, appended to `props.modes` elsewhere); `/effort-picker` registered in `session.start` and answered by `command.run`.

- [ ] **Step 1: Write `ui.test.tsx`**, each UI case looped over `['terminal', 'desktop'] as const`:
  - `applied line shows level, from and why` — band set → `find({ type: 'Text', text: /High/ })` and `/Medium/` present; after advancing the mocked clock 15 s the line is gone.
  - `footer label while held` — `override: 'high'` → label `Effort High`; `override: null` → engine's own drawing.
  - `Russian prompt gives Russian texts` — band `lang: 'ru'` → `Усилие`.
  - `/effort-picker` with no args prints mode and level; `auto` / `suggest` / `off` store the mode and win over `options.mode`; `on` restores the last non-off mode; `off` clears `override` and `band`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, validates, `tsc` — PASS.
- [ ] **Step 5: Commit** `feat: effort-picker band, footer label and command`.

### Task 5: Classifier quality and the default model (E5)

**Files:**
- Create: `plugins/effort-picker/tests/quality.sh`
- Modify: `plugins/effort-picker/.claude-plugin/plugin.json` (`classifier` default, only if Sonnet wins)

- [ ] **Step 1: Write `quality.sh <haiku|sonnet>`** — portable bash; cuts `TEMPLATE` out of `hooks/classifier.ts` between the marker lines (`sed -n`, then strip the backtick line ends), fills `{{NOW}}` with `high`, `{{REPLY}}` with `(none, this is the first prompt)` and `{{PROMPT}}` with each of the nine prompts of spec §7.2 (with `awk`, not `sed`, so `/` and `&` in prompts are safe), runs `claude -p --model <id> --effort low`, and prints `prompt → level (expected …) OK|MISS`, then `N/9 OK`. Not called by `tests/run.sh`.
- [ ] **Step 2: Run** `bash plugins/effort-picker/tests/quality.sh sonnet` and `… haiku`. Record both result tables in the commit message body.
- [ ] **Step 3: Decide** — Haiku stays the default only if it has no MISS on a prompt where Sonnet is OK; else set the default to `sonnet` and update the default test in Task 3's `the payload is cut` case.
- [ ] **Step 4: Run** `bash tests/run.sh` — PASS. **Commit** `test: effort-picker classifier quality check`.

### Task 6: Docs, release and live checks

**Files:**
- Create: `plugins/effort-picker/README.md`
- Modify: `plugins/effort-picker/CHANGELOG.md` (`## 0.1.0 — <date>`), root `README.md` (an "effort-picker" section with the install line `/plugin install effort-picker@corekit` and the minimum Claude Code version), `CLAUDE.md` (layout: `plugins/effort-picker/`, its spec path), spec status `draft` → `accepted`

- [ ] **Step 1: README** — what it does, both modes and the xhigh/max consent, the menu caveat (§4.5), cost (one short call per prompt, ~1–3 s), settings, `/effort-picker`, minimum Claude Code 2.1.287, credit line "idea from Ben AI's Effort Optimizer; no code reused".
- [ ] **Step 2: coredev isolation check (§7.3)** — `claude --plugin-dir . --debug` in a scratch folder (or install `coredev@corekit` from the local marketplace): the debug log shows no module loaded from `plugins/effort-picker` under coredev. Record the command and its output in the task report.
- [ ] **Step 3: Live check on 2.1.309** — `claude --plugin-dir plugins/effort-picker` in the terminal: a Russian low prompt in `suggest` asks in Russian; `auto` + `почини авторизацию, после логина кидает на 500` switches to high silently with the line; `сделай с нуля приложение… работай сам` asks before xhigh; `/effort-picker` shows the real level. Repeat one prompt in the desktop Code tab via `CLAUDE_CODE_PLUGIN_DIRS`. Report what was seen.
- [ ] **Step 4: Run** `bash tests/run.sh`, `claude plugin validate .`, `claude plugin validate plugins/effort-picker` — PASS.
- [ ] **Step 5: Commit** `docs: effort-picker 0.1.0 readme and changelog`. Stop and tell the owner in Russian how to install and try it, and what may break (early-access API changes between Claude Code releases).
