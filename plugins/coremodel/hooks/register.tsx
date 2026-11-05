import { atom, read, update } from 'claude-code'
import type { EngineInterface, ModelCompleteResult, Register } from 'claude-code'

import type { Band, Level, Mark, Stats } from '../types'
import { buildPrompt, parseAnswer, type Pick, toLevel } from './classifier'
import { LADDER, MODELS, type ModelKey, parseModels, switchUsd, toModel, unknownModels } from './models'
import { decide, decideModel, effortOptions, isCostlyLevel, keepFirst, type Lang, type Mode, modelOptions, texts, uiLang } from './policy'

const PLUGIN = 'coremodel'
const band = atom({ plugin: 'coremodel', key: 'band' } as const, null)
const override = atom({ plugin: 'coremodel', key: 'override' } as const, null)
const marks = atom({ plugin: 'coremodel', key: 'marks' } as const, {})
const stats = atom({ plugin: 'coremodel', key: 'stats' } as const, null)
const NO_STATS: Stats = { picks: { low: 0, medium: 0, high: 0, xhigh: 0, max: 0 }, kept: 0, last: null, marks: 0, models: { haiku: 0, sonnet: 0, opus: 0, fable: 0 } }
const CLASSIFIERS = { haiku: 'claude-haiku-5-5', sonnet: 'claude-sonnet-5-5' } as const
const MODES: readonly Mode[] = ['suggest', 'auto', 'off']
const LOG_KEEP = 20_000
const BAND_MS = 15_000
// The classifier answers in about 2 s; the whole pick waits CLASSIFY_MS at most, and a second
// call starts when the first has not answered in HEDGE_MS.
const CLASSIFY_MS = 8_000
const HEDGE_MS = 3_000

// Module variables start over on a reload; what must outlive one is in $.state or $.store.
// Bumped on every prompt, so a pick for an older prompt is dropped.
let gen = 0
let nextBand = 1
// Bumped when the person changes the hold themselves (a pane press, Back): a pick that began
// earlier is dropped, so its late answer never overrides their newer choice.
let touched = 0
// The prompt waiting for its pick at the turn's first request. `turn` is the turn that was
// running when it was typed (it waits in the queue behind that turn); absent when the chat was idle.
let held: { text: string; gen: number; lang: Lang; turn?: string } | null = null
// The chosen level, put on every main-chat request until the person moves the menu. It lives in
// this chat only: the app's own effort setting is never written. `base` is the menu's level when
// the hold began.
let hold: { level: Level; base: string } | null = null
// The chosen model, held the same way; `base` is the request's own model when the hold began.
let modelHold: { key: ModelKey; base: string } | null = null
// The level the last main-chat request ran at, and the language of the last prompt.
let seen: Level | '' = ''
// The model the last main-chat request named (the person's own unless held).
let seenModel = ''
// Models this account refused in this session (spec §4.5): never picked again until a new session.
const unavailable = new Set<ModelKey>()
// The menu's own effort as the last main-chat request carried it.
let asked = ''
let lastLang: Lang = 'en'

async function log($: EngineInterface, what: string, err: unknown) {
  try {
    const path = `${(await $.env.get('HOME')) ?? ''}/.claude/mods-logs/${PLUGIN}.log`
    const old = (await $.fs.exists(path)) ? String(await $.fs.read(path)) : ''
    const msg = err instanceof Error ? err.message : String(err)
    await $.fs.write(path, `${old.slice(-LOG_KEEP)}${new Date(await $.clock.now()).toISOString()} ${what}: ${msg}\n`)
  } catch {
    // Nowhere left to report it.
  }
}

/** The mode: what /coremodel stored wins over the setting. */
export async function currentMode($: EngineInterface, options: { mode?: unknown }): Promise<Mode> {
  const stored = await $.store.get('mode')
  if (MODES.includes(stored as Mode)) return stored as Mode
  return MODES.includes(options.mode as Mode) ? (options.mode as Mode) : 'suggest'
}

/** Switches to `level` by holding it on this chat's requests (spec §4.4). */
export async function applyLevel($: EngineInterface, level: Level, base: string): Promise<void> {
  hold = { level, base }
  await syncOverride($)
}

/** What the drawings read: the held pair, or null when nothing is held. */
async function syncOverride($: EngineInterface): Promise<void> {
  const pair = { model: modelHold?.key ?? null, level: hold?.level ?? null }
  await update($, override, () => (pair.model || pair.level ? pair : null))
}

/** Lets go of the held level: the chat runs at the menu's level again. */
export async function releaseLevel($: EngineInterface): Promise<void> {
  hold = null
  // The pane reads `seen`: after a release it is the menu's level, not the one just let go.
  seen = toLevel(asked) || seen
  await syncOverride($)
}

/** Lets go of the held model: the chat runs on the person's own model again. */
export async function releaseModel($: EngineInterface): Promise<void> {
  modelHold = null
  await syncOverride($)
}

/** Lets go of both parts (off, Release, a new session). */
export async function releaseHold($: EngineInterface): Promise<void> {
  hold = null
  seen = toLevel(asked) || seen
  modelHold = null
  await syncOverride($)
}

/**
 * A new chat starts with nothing held: the hold and the undo line go, and a pick still on its way
 * is dropped. Models the account refused stay dropped.
 * `fromEngine`: /clear, /resume or a fork. The prompt typed for the new chat may reach us before
 * the engine's SessionStart does, so a prompt still waiting for its first request stays (with the
 * new generation), and the rows of the old chat's switches go. A new session or a reload (`false`)
 * starts clean, and keeps the rows its transcript still shows.
 */
async function newChat($: EngineInterface, fromEngine: boolean): Promise<void> {
  gen += 1
  held = fromEngine && held ? { ...held, gen } : null
  seen = toLevel(asked)
  await releaseHold($)
  if (fromEngine) await update($, marks, () => ({}))
  await update($, band, () => null)
  $.ui.invalidate('ui.render')
}

/** Updates this session's counts, starting from zeros. */
export async function count($: EngineInterface, f: (s: Stats) => Stats): Promise<void> {
  await update($, stats, cur => f(cur ?? NO_STATS))
}

/** A row in the transcript for an applied switch. Its id comes from $.state, so a reload never reuses one. */
async function placeMark($: EngineInterface, change: Mark) {
  let n = 0
  await count($, s => {
    n = s.marks + 1
    return { ...s, marks: n }
  })
  const id = `mark-${n}`
  await update($, marks, cur => ({ ...cur, [id]: change }))
  await $.ui.place({ id })
}

/** Switches to `key` by holding it on this chat's requests (spec §4.4, M7). */
export async function applyModel($: EngineInterface, key: ModelKey, base: string): Promise<void> {
  modelHold = { key, base }
  await syncOverride($)
}

/** The chat's size as the last response read it; undefined when Claude Code does not say. */
async function chatTokens($: EngineInterface): Promise<number | undefined> {
  try {
    return (await $.session.usage()).context.tokens
  } catch {
    return undefined
  }
}

async function announce($: EngineInterface, change: Mark, undo: Band['undo']) {
  const b: Band = { id: nextBand++, ...change, undo }
  await update($, band, () => b)
  void (async () => {
    await $.clock.sleep(BAND_MS)
    await update($, band, cur => (cur && cur.id === b.id ? null : cur))
  })().catch(err => log($, 'band', err))
}

/** The first call that answers; when none does, the last failure (a call that throws counts as one). */
function firstAnswered(calls: Promise<ModelCompleteResult>[]): Promise<ModelCompleteResult> {
  return new Promise((resolve, reject) => {
    let left = calls.length
    const failed = (settle: () => void) => {
      left -= 1
      if (left === 0) settle()
    }
    for (const c of calls) {
      c.then(
        r => (r.isAnswered ? resolve(r) : failed(() => resolve(r))),
        err => failed(() => reject(err)),
      )
    }
  })
}

async function classify($: EngineInterface, text: string, now: Level | '', model: string) {
  const messages = await $.session.messages()
  let lastReply = ''
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const m = messages[i]!
    if (m.role === 'assistant' && m.text.trim()) {
      lastReply = m.text
      break
    }
  }
  const prompt = buildPrompt({ prompt: text, lastReply, now })
  const ask = (timeoutMs: number, stop: AbortController) =>
    $.model.complete({ model, prompt, maxTokens: 120, effort: 'low', timeoutMs }, { signal: stop.signal })
  // A call sometimes hangs with no reply (seen on a chat's first prompt, beside the title request):
  // a second one starts after HEDGE_MS, the first answer of the two is used, the other is cut.
  // A call that fails outright before that (a 529, a throw) is tried once more at once; an Esc
  // ('aborted') is not a failure to retry.
  const first = new AbortController()
  const second = new AbortController()
  const began = await $.clock.now()
  type Done = { r: ModelCompleteResult } | { err: unknown }
  const a = ask(CLASSIFY_MS, first)
  const aDone: Promise<Done> = a.then(r => ({ r }), err => ({ err }))
  // A sleep that fails never fires the second call early: the first one is simply waited for.
  const hedge = $.clock.sleep(HEDGE_MS).then(() => 'hedge' as const, () => new Promise<never>(() => {}))
  const early = await Promise.race([aDone, hedge])
  const retry = async (): Promise<ModelCompleteResult> => ask(Math.max(1_000, CLASSIFY_MS - ((await $.clock.now()) - began)), second)
  let r: ModelCompleteResult
  let tried = false
  if (early === 'hedge') {
    tried = true
    r = await firstAnswered([a, ask(CLASSIFY_MS - HEDGE_MS, second)])
  } else if ('r' in early && (early.r.isAnswered || early.r.reason === 'aborted')) {
    r = early.r
  } else {
    tried = true
    r = await retry()
  }
  first.abort()
  second.abort()
  if (!r.isAnswered) {
    // An Esc on the turn cuts both calls too, sooner: only the full wait is a timeout.
    const waited = (await $.clock.now()) - began
    if (tried && r.reason === 'aborted' && waited >= CLASSIFY_MS) throw new Error(`classifier timed out after ${CLASSIFY_MS / 1000} s (two tries)`)
    throw new Error(`classifier gave no answer: ${r.reason}`)
  }
  const pick = parseAnswer(r.text)
  if (!pick) throw new Error(`classifier answer not readable: ${r.text.slice(0, 200)}`)
  return pick
}

/** The pick for one prompt, then the switch, the question, or nothing. */
async function runPick(
  $: EngineInterface,
  options: { mode?: unknown; classifier?: unknown; models?: unknown; pickModel?: unknown },
  h: NonNullable<typeof held>,
  now: Level | '',
  base: string,
  nowModel: ModelKey | '',
  baseModel: string,
  hasEffort: boolean,
) {
  const began = touched
  const mode = await currentMode($, options)
  if (mode === 'off') return
  const t = texts(h.lang)
  try {
    await $.ui.status(t.checking)
  } catch {
    // The status line is a nicety.
  }
  let pick: Pick
  try {
    pick = await classify($, h.text, now, options.classifier === 'haiku' ? CLASSIFIERS.haiku : CLASSIFIERS.sonnet)
  } catch (err) {
    await log($, 'classify', err)
    return
  } finally {
    try {
      await $.ui.status(undefined)
    } catch {
      // Nothing to clear.
    }
  }
  // The person may have turned the plugin off while the classifier ran.
  const stale = async () => h.gen !== gen || touched !== began || (await currentMode($, options)) === 'off'
  if (await stale()) return
  const named = pick.level === 'keep' ? null : pick.level
  await count($, s => {
    if (!named) return s
    const models = { ...NO_STATS.models!, ...s.models }
    if (pick.model) models[pick.model] += 1
    return { ...s, picks: { ...s.picks, [named]: s.picks[named] + 1 }, models, last: { level: named, why: pick.why, ...(pick.model ? { model: pick.model } : {}) } }
  })
  // A named pick the person did not take stays the last pick, marked so the pane does not show it as applied.
  const kept = () => count($, s => ({ ...s, kept: s.kept + 1, last: named && s.last ? { ...s.last, declined: true } : s.last }))
  if (pick.level === 'keep') return kept()
  const level = pick.level

  // The model first (spec §4.3): it decides what the chat costs from here on.
  const allowed = parseModels(options.models).filter(k => !unavailable.has(k))
  const isFirst = !(await $.session.messages()).some(m => m.role === 'assistant')
  const mAction = decideModel({ mode, pickModel: options.pickModel !== 'off', isFirst, now: nowModel, pick: pick.model, allowed })
  let modelTo: ModelKey | null = mAction === 'apply' && pick.model ? pick.model : null
  if (mAction === 'ask' && pick.model) {
    const to = pick.model
    const tokens = isFirst ? undefined : await chatTokens($)
    const models = modelOptions(to, nowModel, allowed, isFirst)
    // A current model CoreModel does not know still gets its Keep, second, so a question never has one option.
    const listed: (ModelKey | 'keep')[] = nowModel ? models : [models[0]!, 'keep' as const, ...models.slice(1)].slice(0, 4)
    const opts = keepFirst(listed, nowModel || 'keep', to === 'fable')
    const labels = opts.map(m => (m === 'keep' ? t.keepCurrent : m === nowModel ? t.keepModel(m) : t.modelOption(m, m === to)))
    try {
      const answer = await $.ui.ask(t.modelQuestion(to, switchUsd(tokens, to), tokens, isFirst, pick.why), { options: labels, header: t.modelHeader })
      const chosen = opts[labels.indexOf(answer)]
      if (chosen && chosen !== 'keep' && chosen !== nowModel) modelTo = chosen
    } catch {
      // A dismissed question keeps the model; the effort is still asked.
    }
    if (await stale()) return
  }

  // Then the effort.
  // A request with no effort has nowhere to put a level: that part is skipped, not asked or marked.
  const action = hasEffort ? decide(mode, now, pick) : 'none'
  let levelTo: Level | null = action === 'apply' ? level : null
  if (action === 'ask') {
    const opts = keepFirst(effortOptions(level, now), now as Level, isCostlyLevel(level))
    const labels = opts.map(l => (l === now ? t.keep(now) : t.levelOption(l, l === level)))
    try {
      const answer = await $.ui.ask(t.question(level, pick.why), { options: labels, header: t.effortHeader })
      const chosen = opts[labels.indexOf(answer)]
      if (chosen && chosen !== now) levelTo = chosen
    } catch {
      // A dismissed question keeps the level.
    }
    if (await stale()) return
  }

  if (!modelTo && !levelTo) return kept()
  // A silent switch can be undone, part by part: back to the menu's own value, or to the one held before.
  const parts: NonNullable<Band['undo']> = {}
  if (modelTo && mAction === 'apply' && nowModel) parts.model = nowModel === toModel(baseModel) ? 'release' : nowModel
  if (levelTo && action === 'apply' && now) parts.level = now === toLevel(base) ? 'release' : now
  if (modelTo) await applyModel($, modelTo, baseModel)
  if (levelTo) await applyLevel($, levelTo, base)
  const change: Mark = { level: levelTo, from: levelTo ? now : '', model: modelTo, fromModel: modelTo ? nowModel : '', why: pick.why, lang: h.lang }
  await announce($, change, parts.model || parts.level ? parts : null)
  try {
    await placeMark($, change)
  } catch (err) {
    await log($, 'mark', err)
  }
}

/** Sets the mode as `/coremodel <mode>` does; returns the reply. */
export async function setMode($: EngineInterface, options: { mode?: unknown; pickModel?: unknown }, arg: Mode | 'on'): Promise<string> {
  let text: string
  if (arg === 'auto' || arg === 'suggest') {
    await $.store.set('mode', arg)
    await $.store.set('lastMode', arg)
    text = texts('en').modeSet(arg, options.pickModel !== 'off')
  } else if (arg === 'off') {
    await $.store.set('mode', 'off')
    await releaseHold($)
    await update($, band, () => null)
    text = 'Off. /coremodel on turns it back on.'
  } else {
    const last = await $.store.get('lastMode')
    const mode: Mode = last === 'auto' || last === 'suggest' ? last : options.mode === 'auto' ? 'auto' : 'suggest'
    await $.store.set('mode', mode)
    text = `On: ${mode}.`
  }
  $.ui.invalidate('ui.render')
  return text
}

/**
 * A level the person picks in the pane (null: Release). It is their newest choice, so the undo line
 * goes, and the hold takes the menu's level from the next request as its base.
 */
async function paneChoice($: EngineInterface, level: Level | null): Promise<void> {
  touched += 1
  if (level) await applyLevel($, level, '')
  else await releaseHold($)
  await update($, band, () => null)
}

/**
 * A model the person presses in the pane. Mid-chat the cost question comes first (spec §7.5);
 * the press itself is their yes, so no other question follows.
 */
async function paneModel($: EngineInterface, key: ModelKey): Promise<void> {
  touched += 1
  const nowModel = modelHold?.key ?? toModel(seenModel)
  if (key === nowModel) return
  const isEmpty = !(await $.session.messages()).some(m => m.role === 'assistant')
  if (!isEmpty) {
    const t = texts(lastLang)
    const tokens = await chatTokens($)
    try {
      const answer = await $.ui.ask(t.modelQuestion(key, switchUsd(tokens, key), tokens, false, ''), { options: [t.switchModel(key), t.cancel], header: t.modelHeader })
      if (answer !== t.switchModel(key)) return
    } catch {
      return
    }
  }
  await applyModel($, key, '')
  await update($, band, () => null)
}

/** True when the `models` setting names `key` itself; an empty setting means all four without naming any. */
function namedInSetting(setting: unknown, key: ModelKey): boolean {
  return typeof setting === 'string' && setting.split(',').some(w => toModel(w) === key)
}

const ASK_MODES: readonly Mode[] = ['auto', 'suggest', 'off']
const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

const MODEL_COLOR: Record<string, string> = { haiku: '#1D9E75', sonnet: '#378ADD', opus: '#7F77DD', fable: '#D4537E' }
const LEVEL_SHADES = ['#B5D4F4', '#85B7EB', '#378ADD', '#185FA5', '#0C447C']

const xml = (v: string) => v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

// The session counts as one drawing: a share bar per model and one stacked bar for the levels.
// An image on the desktop cannot read the theme, so it draws on a neutral track and mid-grey text.
function statsSvg(models: { key: string; name: string; n: number }[], levels: { name: string; n: number }[]) {
  const W = 304
  const X = 64
  const BAR = 200
  const rows: string[] = []
  const maxM = Math.max(1, ...models.map(m => m.n))
  let y = 0
  for (const m of models) {
    const w = Math.max(6, Math.round((m.n / maxM) * BAR))
    rows.push(`<text x="0" y="${y + 11}" font-size="12" fill="#888780">${xml(m.name)}</text>`)
    rows.push(`<rect x="${X}" y="${y + 3}" width="${BAR}" height="8" rx="4" fill="#888780" fill-opacity="0.25"/>`)
    rows.push(`<rect x="${X}" y="${y + 3}" width="${w}" height="8" rx="4" fill="${MODEL_COLOR[m.key] ?? '#378ADD'}"/>`)
    rows.push(`<text x="${W}" y="${y + 11}" font-size="12" fill="#888780" text-anchor="end">${m.n}</text>`)
    y += 20
  }
  if (levels.length) {
    const total = levels.reduce((a, l) => a + l.n, 0)
    let x = X
    levels.forEach((l, i) => {
      const w = i === levels.length - 1 ? X + BAR - x : Math.max(2, Math.floor((l.n / total) * BAR))
      rows.push(`<rect x="${x}" y="${y + 3}" width="${w}" height="8" fill="${LEVEL_SHADES[i % LEVEL_SHADES.length]}"/>`)
      x += w
    })
    y += 20
    rows.push(`<text x="0" y="${y - 9}" font-size="12" fill="#888780">${xml(levels.map(l => `${l.name} ${l.n}`).join(' · '))}</text>`)
    y += 4
  }
  return { height: y, source: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${y}" width="${W}" height="${y}">${rows.join('')}</svg>` }
}

const RULE = '─'.repeat(60)

export const register: Register = (on, options) => {
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'composer' && e.origin.kind !== 'bridge') {
      // That prompt takes the next turn; an older one waiting is not it.
      held = null
      return next(e)
    }
    const text = e.text.trim()
    if (!text || text.startsWith('/')) {
      // A prompt of ours is not the next turn's any more.
      held = null
      return next(e)
    }
    gen += 1
    lastLang = uiLang(text)
    const mine = { text, gen, lang: lastLang, ...(e.turnId ? { turn: e.turnId } : {}) }
    held = mine
    const r = await next(e)
    // Refused beneath us: no turn will come of it.
    if (r.drop !== undefined && held === mine) held = null
    return r
  }).catch(($, e, next) => next(e))

  // A turn that ends with a prompt still waiting (blocked, Esc'd before its first request) leaves
  // nothing for the next turn; only a prompt queued behind this very turn stays.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && held && held.turn !== e.turnId) held = null
    return next(e)
  })

  // Every main-chat request: release a hold the menu moved past, run a waiting pick, put the level on.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) return yield* next(e)
    // A model without effort carries none; the level part then sleeps.
    const hasEffort = typeof e.effort === 'string'
    if (hasEffort) {
      asked = e.effort as string
      // A level picked in the pane before any request learns the menu's level here.
      if (hold && hold.base === '') hold = { ...hold, base: asked }
      if (hold && asked !== hold.base) await releaseLevel($)
    }
    seenModel = e.model
    if (modelHold && modelHold.base === '') modelHold = { ...modelHold, base: e.model }
    // The person chose another model with /model: their choice stands.
    if (modelHold && e.model !== modelHold.base) await releaseModel($)
    if (held && e.index === 0) {
      const h = held
      held = null
      try {
        await runPick($, options, h, hasEffort ? (hold?.level ?? toLevel(asked)) : '', hasEffort ? asked : '', modelHold?.key ?? toModel(e.model), e.model, hasEffort)
      } catch (err) {
        await log($, 'pick', err)
      }
    }
    const want = hasEffort ? (hold?.level ?? null) : null
    const was = seen
    seen = want ?? (toLevel(asked) || seen)
    if (seen !== was) $.ui.invalidate('ui.render')
    // The request's context suffix (`[1m]`) stays on the held model: a long chat must still fit.
    const model = modelHold ? MODELS[modelHold.key].id + (/\[[^\]]*\]$/.exec(e.model)?.[0] ?? '') : e.model
    if ((!want || want === e.effort) && model === e.model) return yield* next(e)
    return yield* next({ ...e, effort: want ?? e.effort, model })
  })

  // A model the account cannot use: the turn fails with model_not_found, naming no model, so the
  // held one is the one refused. Drop it for this session, once, instead of failing every request.
  on('classic.StopFailure', async ($, e, next) => {
    // A subagent's failure says nothing about the main chat's model.
    if (e.error === 'model_not_found' && modelHold && e.agent_id === undefined) {
      const key = modelHold.key
      unavailable.add(key)
      await releaseModel($)
      await log($, 'model', `${MODELS[key].name} is not available: ${e.error_details ?? e.error}`)
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  // /clear, /resume and a fork start another chat in this process, and session.start does not run
  // for them; the module's own variables would carry the hold into the new chat. A compacted chat
  // is the same chat and keeps it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') await newChat($, true)
    return next(e)
  })

  on('session.start', async ($, e, next) => {
    unavailable.clear()
    const typos = unknownModels(options.models)
    if (typos.length) await log($, 'models', `unknown in the setting: ${typos.join(', ')} (use haiku, sonnet, opus, fable)`)
    // A new session, or a reload of this module, starts with no held level: drop what $.state kept.
    await newChat($, false)
    await $.command.register({
      name: 'coremodel',
      description: 'CoreModel: show what the chat runs at, set the mode (auto, suggest, off, on), or open the pane (panel)',
      argumentHint: '[auto|suggest|off|on|panel]',
    })
    return next(e)
  })

  on('command.run', { command: 'coremodel' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'auto' || arg === 'suggest' || arg === 'off' || arg === 'on') return { text: await setMode($, options, arg) }
    if (arg === 'panel') {
      const r = await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      return { text: r.isPlaced ? 'The pane is open.' : `The pane is waiting: ${r.reason}` }
    }
    const mode = await currentMode($, options)
    const level = hold?.level ?? seen
    if (!arg) {
      let answer = ''
      try {
        answer = await $.ui.ask(texts(lastLang).modeQuestion(mode, level), { options: [...ASK_MODES], header: 'CoreModel' })
      } catch {
        // Dismissed: say where things stand, change nothing.
      }
      if ((ASK_MODES as readonly string[]).includes(answer)) return { text: await setMode($, options, answer as Mode) }
    }
    return {
      text: [
        `Mode: ${mode}.`,
        `This chat runs at: ${level ? texts('en').levelName(level) : 'unknown yet'}${hold ? ' (held by the plugin; the menu still shows your own setting)' : ''}.`,
        'Type /coremodel auto, suggest, off, on or panel.',
      ].join('\n'),
    }
  })

  // The app's menu shows the person's own setting; the footer slot beside it names a held level.
  // The footer slot also holds a button that opens and closes the pane: no chat command, so a
  // running turn is not interrupted. It lists the mode labels itself, the engine's first.
  on('ui.render', { component: 'SessionMode' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const pair = await read($, override)
    const modes = pair ? [...e.props.modes, texts(lastLang).pairLabel(pair.model, pair.level)] : [...e.props.modes]
    const isUp = (await $.ui.panes()).some(p => p.id === PLUGIN)
    const toggle = async () => {
      if ((await $.ui.panes()).some(p => p.id === PLUGIN)) await $.ui.close({ id: PLUGIN })
      else await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      $.ui.invalidate('ui.render')
    }
    return (
      <Box gap="sm">
        {modes.length ? <Text dimColor>{modes.join(' & ')}</Text> : null}
        <Button key="pane" label="CoreModel" variant={isUp ? 'primary' : undefined} onPress={() => void toggle().catch(err => log($, 'pane', err))} />
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PLUGIN }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Button, Text } = ui
    const Svg = e.surface === 'terminal' ? undefined : (ui as { Svg?: typeof Box }).Svg
    const t = texts(lastLang)
    const mode = await currentMode($, options)
    const pair = await read($, override)
    const held = pair?.level ?? null
    const heldModel = pair?.model ?? null
    const s = await read($, stats)
    const allowed = parseModels(options.models).filter(k => !unavailable.has(k))
    // pickModel off: effort only, as CoreEffort was (spec §6).
    const pickOn = options.pickModel !== 'off'
    const act = (what: string, f: () => Promise<unknown>) => () => {
      f().catch(err => log($, what, err))
    }
    const nowLevel = held ?? seen
    const nowModel = heldModel ?? toModel(seenModel)
    const menuLevel = toLevel(asked)
    const menu = heldModel ? t.inMenuPair(toModel(seenModel), menuLevel) : menuLevel ? t.inMenu(menuLevel) : ''
    const modelCounts = pickOn && s?.models ? LADDER.filter(m => s.models![m] > 0) : []
    const levelCounts = s ? LEVELS.filter(l => s.picks[l] > 0) : []
    const modelMax = Math.max(1, ...modelCounts.map(m => s?.models?.[m] ?? 0))
    const levelMax = Math.max(1, ...levelCounts.map(l => s?.picks[l] ?? 0))
    const nameW = Math.max(0, ...modelCounts.map(m => MODELS[m].name.length), ...levelCounts.map(l => t.levelName(l).length))
    const usageRow = (name: string, n: number, max: number) => `${name.padEnd(nameW)}  ${'█'.repeat(Math.max(1, Math.round((n / max) * 12)))} ${n}`
    return (
      <Box flexDirection="column" gap="sm">
        <Box key="now" flexDirection="column">
          <Text dimColor>{t.now}</Text>
          <Text bold>{t.nowPair(pickOn ? nowModel : '', nowLevel)}</Text>
          {held || heldModel ? <Text dimColor>{menu ? `${t.heldBy} · ${menu}` : t.heldBy}</Text> : null}
          {unknownModels(options.models).length ? (
            <Text key="typo" color="warning">{t.unknownModels(unknownModels(options.models))}</Text>
          ) : null}
          {[...unavailable].map(m => (
            <Text key={`unavailable-${m}`} color="warning">{t.unavailable(m, namedInSetting(options.models, m))}</Text>
          ))}
        </Box>
        <Text key="d1" dimColor wrap="truncate-end">{RULE}</Text>
        {pickOn && allowed.length ? (
          <Box key="choose-model" flexDirection="column">
            <Text dimColor>{t.paneModel}</Text>
            <Box key="models" flexWrap="wrap" gap="xs">
              {allowed.map(m => (
                <Button
                  key={`model-${m}`}
                  label={MODELS[m].name}
                  variant={m === nowModel ? 'primary' : undefined}
                  onPress={act('model', () => paneModel($, m))}
                />
              ))}
            </Box>
          </Box>
        ) : null}
        <Box key="choose" flexDirection="column">
          <Text dimColor>{t.paneLevel}</Text>
          <Box key="levels" flexWrap="wrap" gap="xs">
            {LEVELS.map(l => (
              <Button
                key={`level-${l}`}
                label={t.levelName(l)}
                variant={l === nowLevel ? 'primary' : undefined}
                onPress={act('level', () => paneChoice($, l))}
              />
            ))}
          </Box>
          {held || heldModel ? (
            <Box key="release-row">
              <Button key="release" label={t.release} dimColor onPress={act('release', () => paneChoice($, null))} />
            </Box>
          ) : null}
        </Box>
        <Text key="d2" dimColor wrap="truncate-end">{RULE}</Text>
        <Box key="mode" flexDirection="column">
          <Text dimColor>{t.mode}</Text>
          <Box key="modes" flexWrap="wrap" gap="xs">
            {MODES.map(m => (
              <Button
                key={`mode-${m}`}
                label={t.modeName(m)}
                variant={m === mode ? 'primary' : undefined}
                onPress={act('mode', () => setMode($, options, m))}
              />
            ))}
          </Box>
          <Text dimColor>{t.modeHint(mode, pickOn)}</Text>
        </Box>
        <Text key="d3" dimColor wrap="truncate-end">{RULE}</Text>
        <Box key="last" flexDirection="column">
          <Text dimColor>{t.lastPick}</Text>
          {s?.last ? (
            <>
              <Text bold>{`${t.nowPair(pickOn && s.last.model ? s.last.model : '', s.last.level)} · ${s.last.declined ? t.notApplied : t.pickApplied}`}</Text>
              {s.last.why ? <Text>{s.last.why}</Text> : null}
            </>
          ) : (
            <Text>{t.noPicks}</Text>
          )}
        </Box>
        <Text key="d4" dimColor wrap="truncate-end">{RULE}</Text>
        {modelCounts.length > 0 || levelCounts.length > 0 || (s && s.kept > 0) ? (
          <Box key="session" flexDirection="column">
            <Text dimColor>{t.session}</Text>
            {Svg ? (
              (() => {
                const models = modelCounts.map(m => ({ key: m, name: MODELS[m].name, n: s?.models?.[m] ?? 0 }))
                const levels = levelCounts.map(l => ({ name: t.levelName(l), n: s?.picks[l] ?? 0 }))
                const d = statsSvg(models, levels)
                const alt = [...models.map(m => `${m.name} ${m.n}`), ...levels.map(l => `${l.name} ${l.n}`)].join(', ')
                return <Svg key="stats" source={d.source} alt={alt} width={304} height={d.height} />
              })()
            ) : (
              <>
                {modelCounts.map(m => (
                  <Text key={`count-${m}`}>{usageRow(MODELS[m].name, s?.models?.[m] ?? 0, modelMax)}</Text>
                ))}
                {levelCounts.map(l => (
                  <Text key={`count-${l}`}>{usageRow(t.levelName(l), s?.picks[l] ?? 0, levelMax)}</Text>
                ))}
              </>
            )}
            {s && s.kept > 0 ? <Text dimColor>{t.kept(s.kept)}</Text> : null}
          </Box>
        ) : null}
      </Box>
    )
  })

  // The working line names the menu's level; while a level is held it says the real one too.
  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const pair = await read($, override)
    if (!pair) return next(e)
    return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix} · ${texts(lastLang).pairSuffix(pair.model, pair.level)}` } })
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== PLUGIN) return next(e)
    const m = (await read($, marks))[e.props.id]
    if (!m) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{texts(m.lang).markPair(m.model, m.fromModel, m.level, m.from, m.why)}</Text>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const b = await read($, band)
    if (!b || e.props.hasSurvey) return next(e)
    const rest = await next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(b.lang)
    const undo = b.undo
    const onUndo = async () => {
      // An old band, or a part the person already changed: their own choice stands.
      const cur = await read($, band)
      if (!cur || cur.id !== b.id || !undo) return
      touched += 1
      if (undo.model && b.model && modelHold?.key === b.model) {
        if (undo.model === 'release') await releaseModel($)
        else await applyModel($, undo.model, modelHold.base)
      }
      if (undo.level && b.level && hold?.level === b.level) {
        if (undo.level === 'release') await releaseLevel($)
        else await applyLevel($, undo.level, hold.base)
      }
      await update($, band, () => null)
    }
    const backModel = undo?.model === 'release' ? b.fromModel : undo?.model
    const backLevel = undo?.level === 'release' ? b.from : undo?.level
    return (
      <Box flexDirection="column">
        {rest}
        <Box>
          <Text wrap="truncate-end">{`✓ ${t.change(b.model, b.fromModel, b.level, b.from, b.why)} `}</Text>
          {undo ? <Button key="undo" hotkey="1" label={t.backPair(backModel, backLevel)} onPress={() => onUndo().catch(err => log($, 'undo', err))} /> : null}
        </Box>
      </Box>
    )
  })
}
