# coremodel Implementation Plan

> **Historical (done).** Shipped as coremodel 0.4.0 and refined through 0.4.x (see plugins/coremodel/CHANGELOG.md). The checkboxes below were never ticked; the tree and the spec docs/specs/2026-11-04-coremodel-design.md win where they differ.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `coreeffort` plugin (0.3.0) into `coremodel` (0.4.0), which picks a model as well as the effort for each main-chat prompt, holds the pair, and names the token cost of a mid-chat model switch.

**Architecture:** The plugin folder moves with `git mv`. Pure logic stays `$`-free: `hooks/classifier.ts` (prompt and parser, now with `model`), `hooks/models.ts` (new: the model table, the ladder order, the cost line), `hooks/policy.ts` (consent rules and texts). `hooks/register.tsx` keeps the hooks; the single `hold` becomes a pair whose parts release on their own.

**Tech Stack:** TypeScript, the `claude-code` plugin API (types in `plugins/coremodel/.claude-plugin/types/` once the engine has loaded it), `claude plugin test` / `claude plugin validate`, bash 3.2 for repo tests.

**Spec:** docs/specs/2026-11-04-coremodel-design.md (M-decisions and § numbers below are its). It builds on docs/specs/2026-11-04-effort-picker-design.md §4.7.

## Global Constraints

- Plugin `coremodel`, `displayName` `CoreModel`, version `0.4.0`, command `/coremodel`, pane id `coremodel`, log `~/.claude/mods-logs/coremodel.log`, state under `PluginState['coremodel']`.
- `renames`: `"coreeffort": "coremodel"`, `"effort-picker": "coremodel"` (M1).
- Model ids: `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-fable-5-1`; ladder in that order (§3).
- Prices: input $/MTok 0.10, 2.00, 4.00, 10.00; cache read 0.1, 0.05, 0.05, 0.025; cache write 1.25 (§3).
- Consent: `xhigh`, `max` and Fable always ask on the classifier path; a pane press needs no question except the mid-chat model cost question (M6, §7.5).
- Mid-chat: only a stronger model, always asked, with the cost line (M4, M5).
- The app's model and effort settings are never written (M7).
- All UI words in `texts()` (policy.ts), Russian and English by `uiLang`.
- TDD; after each task `bash tests/run.sh` → `ALL TESTS PASSED`, `claude plugin validate .` and `claude plugin validate plugins/coremodel` without errors.
- Commits in repo style, no `Co-Authored-By` lines; branch `feat/coremodel`; never commit to `main`.

## Review Focus

1. The person moves `/model` and the effort menu in the same turn: each part releases alone, neither restores the other. Test in Task 4 (`model and effort release on their own`).
2. `/model` set to a model outside the four (e.g. an older Opus): the cost line falls back to the plain text, the ladder compare treats an unknown current model as "not weaker", so no question. Test in Task 3 (`unknown current model asks nothing`).
3. `models` setting with spaces, capitals or an unknown word (`"Opus, sonnet,gpt"`): parsed to `['sonnet','opus']`, never throws. Test in Task 2 (`models setting is forgiving`).
4. A dismissed model question followed by the effort question: the effort still asks and applies alone. Test in Task 3 (`dismissed model question still asks effort`).
5. Fable picked on the first prompt in `auto` while `models` lacks Fable: nothing about the model happens, the effort goes on. Test in Task 3 (`a model outside the list is ignored`).

---

### Task 1: Move and rename to coremodel

**Files:**
- Move: `plugins/coreeffort/` → `plugins/coremodel/` (`git mv`), `tests/test_coreeffort.sh` → `tests/test_coremodel.sh`
- Modify: `plugins/coremodel/.claude-plugin/plugin.json` (name, displayName, version 0.4.0, description, `models` and `pickModel` in `userConfig` per spec §6), `types/index.d.ts` (state key `coremodel`), `hooks/register.tsx` (`PLUGIN`, atoms, command, pane id, texts), tests (plugin name), `.claude-plugin/marketplace.json` (entry + renames), `tests/test_manifest.sh`, `tests/test_coreopinion.sh` (path to the sibling manifest and the plugin list), `.gitignore` (both ignored paths), root `README.md`, `CLAUDE.md` layout line, `plugins/coremodel/README.md`, `plugins/coremodel/CHANGELOG.md` (`## 0.4.0 — 2026-11-04` started with the rename note of spec §10)

**Interfaces:**
- Produces: plugin `coremodel` with every CoreEffort 0.3.0 behaviour unchanged under the new names; `options.models: string`, `options.pickModel: 'on' | 'off'` available to `register`.

- [ ] **Step 1:** In `tests/test_manifest.sh` assert `"name": "coremodel"`, `"source": "./plugins/coremodel"`, `"coreeffort": "coremodel"` and `"effort-picker": "coremodel"`; in `ui.test.tsx` change every `plugin: 'coreeffort'` and `command: 'coreeffort'` to `coremodel`.
- [ ] **Step 2: Run** `bash tests/test_manifest.sh` and `claude plugin test plugins/coreeffort` → FAIL.
- [ ] **Step 3:** Move and rename as listed. `userConfig.models`: type string, default `"haiku,sonnet,opus,fable"`; `userConfig.pickModel`: options `on`, `off`, default `on`.
- [ ] **Step 4: Run** `bash tests/run.sh`, both validates → PASS; `grep -rn coreeffort . --exclude-dir=.git --exclude-dir=docs` shows only CHANGELOG history lines, renames and the coremodel CHANGELOG note.
- [ ] **Step 5: Commit** `feat: rename coreeffort to coremodel (0.4.0)`.

### Task 2: Model table, classifier answer, settings

**Files:**
- Create: `plugins/coremodel/hooks/models.ts`, `plugins/coremodel/tests/models.test.ts`
- Modify: `hooks/classifier.ts` (TEMPLATE gains the model ladder of spec §4.1 and the answer shape; `Pick` gains `model`), `tests/classifier.test.ts`

**Interfaces:**
- Produces (`models.ts`): `type ModelKey = 'haiku' | 'sonnet' | 'opus' | 'fable'`; `MODELS: Record<ModelKey, { id: string; name: string; input: number; read: number }>`; `LADDER: readonly ModelKey[]`; `toModel(v: unknown): ModelKey | ''` (accepts a key, a display name or an id, any case, also ids reported by the engine such as `claude-opus-5-5[1m]`); `stronger(a: ModelKey, b: ModelKey | ''): boolean` (false when `b` is `''`); `parseModels(setting: unknown): ModelKey[]`; `switchCost(tokens: number | undefined, from: ModelKey | '', to: ModelKey): number | null` (replies, `null` when unknown).
- Produces (`classifier.ts`): `Pick = { level: Level | 'keep'; model: ModelKey | ''; why: string }`.

- [ ] **Step 1: Write the failing tests.**
  - `models.test.ts`: `switchCost(100_000, 'sonnet', 'opus')` → `50`; `switchCost(undefined, 'sonnet', 'opus')` → `null`; `switchCost(100_000, '', 'opus')` → `null`; result never below 1; `stronger('opus','sonnet')` true, `stronger('sonnet','opus')` false, `stronger('opus','')` false; `toModel('claude-opus-5-5[1m]')` → `'opus'`, `toModel('Fable 5.1')` → `'fable'`, `toModel('gpt')` → `''`; `models setting is forgiving`: `parseModels('Opus, sonnet,gpt')` → `['sonnet','opus']` (ladder order), `parseModels(undefined)` → all four.
  - `classifier.test.ts`: `parseAnswer('{"level":"high","model":"opus","why":"x"}')` → model `'opus'`; no `model` → `''`; `"model":"gpt"` → `''`; `TEMPLATE` contains `haiku`, `sonnet`, `opus`, `fable` and `"model"`.
- [ ] **Step 2: Run** `claude plugin test plugins/coremodel` → FAIL.
- [ ] **Step 3: Implement.** `switchCost` = `Math.max(1, Math.ceil(tokens × input(to) × 1.25 / (tokens × input(from) × read(from))))`. TEMPLATE wording is new prose per §4.1; keep the existing level ladder text.
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coremodel model table and classifier model`.

### Task 3: Picking and asking the model

**Files:**
- Modify: `hooks/policy.ts`, `hooks/register.tsx`, `tests/policy.test.ts`, `tests/flow.test.ts`, `tests/world.ts`

**Interfaces:**
- Consumes: `Pick.model`, `stronger`, `switchCost`, `parseModels`, `MODELS` (Task 2).
- Produces (`policy.ts`): `decideModel(i: { mode: Mode; pickModel: boolean; isFirst: boolean; now: ModelKey | ''; pick: ModelKey | ''; allowed: readonly ModelKey[] }): 'none' | 'apply' | 'ask'`; texts `modelQuestion(to, cost: number | null, tokens: number | undefined, isFirst)`, `modelOption(m, recommended)`, `keepModel(m)`, `effortQuestion(level, why)`, `levelOption(l, recommended)`; `effortOptions(pick: Level, now: Level | ''): Level[]` and `modelOptions(pick, now, allowed): ModelKey[]` (pick first, then now, then nearest, at most 4).
- Produces (`register.tsx`): `runPick` asks the model first, then the effort (spec §4.3), each dismiss keeps that part; `isFirst` = no assistant message in `$.session.messages()`; `tokens` from `$.session.usage()` only when asking mid-chat. `world.ts` answers `session.usage` from `w.tokens`.

Rules for `decideModel`: `none` when `!pickModel`, `pick === ''`, pick not in `allowed`, `pick === now`, or (not first and not `stronger(pick, now)`); `ask` when mode `suggest`, pick is `fable`, or not first; else `apply`. `off` mode is handled before (`none`).

- [ ] **Step 1: Write the failing tests** (`flow.test.ts`; `w.answer` gains `"model"`; current model comes from `step($, effort, index, agentId, model)` — extend `step` with a `model` argument, default `'claude-sonnet-5-5'`):
  - `first prompt in auto switches the model silently` → request carries `claude-opus-5-5`, no question.
  - `first prompt in suggest asks the model` → `w.asked[0]` is `['Opus (recommended)', 'Keep Sonnet', …]`.
  - `fable always asks` (auto, first prompt).
  - `mid-chat stronger pick asks with the cost` → question text contains `≈ 100k tokens` and `~50` with `w.tokens = 100_000`; with `w.tokens` unset it contains `which costs tokens`.
  - `mid-chat weaker pick changes nothing` → no question, model unchanged.
  - `dismissed model question still asks effort` (Review Focus 4).
  - `a model outside the list is ignored` (options `models: 'haiku,sonnet,opus'`, pick fable) (Review Focus 5).
  - `unknown current model asks nothing` (request model `claude-opus-4-8`, pick opus mid-chat) (Review Focus 2).
  - `pickModel off keeps CoreEffort behaviour` → no model question, model never rewritten.
  - `policy.test.ts`: `decideModel` table for the rules above; `modelOptions('opus','sonnet',all)` → `['opus','sonnet','haiku','fable']`; Russian `modelQuestion` contains `Чат перечитается заново` and `тыс.`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** The old one-question flow (`switchAndAuto`) is removed from `runPick`; existing flow tests that expect it change to the two-question shape in the same step.
- [ ] **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coremodel picks and asks the model`.

### Task 4: Holding the pair

**Files:**
- Modify: `types/index.d.ts`, `hooks/register.tsx`, `tests/flow.test.ts`

**Interfaces:**
- Produces: module `hold: { model?: { key: ModelKey; base: string }; level?: { level: Level; base: string } } | null`; state `override: { model: ModelKey | null; level: Level | null } | null` (replaces `Level | null`); `applyModel($, m: ModelKey, base: string)`, `applyLevel` unchanged, `releaseModel($)`, `releaseLevel($)`, `releaseHold($)` (both). `turn.step` rewrites `model` to `MODELS[key].id` and `effort` as today; drops `effort` when the request has none.

- [ ] **Step 1: Write the failing tests:** `the held model goes on every main-chat request`; `model and effort release on their own` (Review Focus 1: next request with a new model releases only the model; a new effort releases only the level); `a model without effort gets none` (request without `effort`, held level high → passes without effort); `subagent requests keep their model`; `a new session drops the model`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coremodel holds model and effort`.

### Task 5: Interface for the pair

**Files:**
- Modify: `hooks/policy.ts`, `hooks/register.tsx`, `types/index.d.ts` (`Band`, `Mark`, `Stats` gain model fields), `tests/ui.test.tsx`

**Interfaces:**
- Consumes: hold and override (Task 4), `switchCost` (Task 2), `decideModel` texts (Task 3).
- Produces: `Band = { …; model?: { to: ModelKey; from: ModelKey | '' }; undo: { model?: ModelKey | 'release'; level?: Level | 'release' } | null }`; `Mark` gains `model?`, `from` for model; `Stats.models: Record<ModelKey, number>`; texts `pair(m, l)`, `appliedPair`, `markPair`.

Spec §7 values: switch line `✓ Opus · Высокое (было Sonnet · Среднее) · why`; mark arrow by model, else by effort; footer `Opus · High` (one part when one is held); working line `· Opus · Высокое`; pane rows: models (only `allowed`, key `model-<key>`, `flexWrap="wrap"`), levels (as now); a `model-*` press mid-chat asks the cost question via `$.ui.ask` with options `Switch to <name>` / `Cancel`, first prompt or empty chat holds at once; counts per model and per level.

- [ ] **Step 1: Write the failing tests** (both surfaces): `switch line names both parts`, `undo restores both parts the silent switch changed`, `mark arrow follows the model`, `footer shows the pair`, `working line names the pair`, `pane model buttons only for allowed models`, `pane model press mid-chat asks the cost`, `pane counts per model`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** plugin tests, `bash tests/run.sh`, validates → PASS.
- [ ] **Step 5: Commit** `feat: coremodel shows model and effort`.

### Task 6: A model the account cannot use (spec §4.5)

**Files:**
- Modify: `hooks/register.tsx`, `hooks/policy.ts`, `tests/flow.test.ts`, `tests/ui.test.tsx`

- [ ] **Step 1: Check first** how a rejected model reaches `turn.step`: grep the engine types for what `next(e)` does on an API error (`ModelApiError`, `StopFailure`) and write the finding into spec §4.5 in one line. If no hook can see it, stop this task, record it in the spec as not built, and go to Task 7.
- [ ] **Step 2: Write the failing tests:** `an unavailable model is dropped for the session` (the mocked step fails with a not-found error naming `claude-fable-5-1` → next request carries the menu's model, later picks of fable change nothing, a log line, pane shows `Fable is not available`).
- [ ] **Step 3: Run** → FAIL. **Step 4: Implement** with a module `unavailable: Set<ModelKey>` (session; cleared at session start). **Step 5: Run** → PASS. **Step 6: Commit** `feat: coremodel skips a model the account cannot use`.

### Task 7: Quality check, docs, release

**Files:**
- Modify: `plugins/coremodel/tests/quality.sh` (expected model per prompt, spec §9.2; prints level and model OK/MISS and `N/9`), `plugins/coremodel/README.md` (what CoreModel does, the cache cost and why, settings `models` and `pickModel`, commands), `plugins/coremodel/CHANGELOG.md` (complete the 0.4.0 entry), spec status `draft` → `accepted`

- [ ] **Step 1:** Update `quality.sh`; run `bash plugins/coremodel/tests/quality.sh sonnet` (needs network; record the table in the commit body; a MISS on the model is reported to the owner, not fixed blindly).
- [ ] **Step 2:** README and CHANGELOG.
- [ ] **Step 3: Run** `bash tests/run.sh`, both validates → PASS.
- [ ] **Step 4: Live check with the owner** in the terminal (`claude --plugin-dir plugins/coremodel`): first-prompt model switch, a mid-chat question with the cost line, the pane's two rows, `/model` releasing the hold. Report what was seen.
- [ ] **Step 5: Commit** `docs: coremodel 0.4.0 readme and changelog`. Stop; no merge or push without the owner's "ок".
