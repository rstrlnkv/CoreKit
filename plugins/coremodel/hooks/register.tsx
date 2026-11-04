import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Band, Level, Stats } from '../types'
import { buildPrompt, parseAnswer, type Pick, toLevel } from './classifier'
import { MODELS, type ModelKey, parseModels, switchCost, toModel } from './models'
import { decide, decideModel, effortOptions, type Lang, type Mode, modelOptions, texts, uiLang } from './policy'

const PLUGIN = 'coremodel'
const band = atom({ plugin: 'coremodel', key: 'band' } as const, null)
const override = atom({ plugin: 'coremodel', key: 'override' } as const, null)
const marks = atom({ plugin: 'coremodel', key: 'marks' } as const, {})
const stats = atom({ plugin: 'coremodel', key: 'stats' } as const, null)
const NO_STATS: Stats = { picks: { low: 0, medium: 0, high: 0, xhigh: 0, max: 0 }, kept: 0, last: null, marks: 0 }
const CLASSIFIERS = { haiku: 'claude-haiku-5-5', sonnet: 'claude-sonnet-5-5' } as const
const MODES: readonly Mode[] = ['suggest', 'auto', 'off']
const LOG_KEEP = 20_000
const BAND_MS = 15_000

// Module variables start over on a reload; what must outlive one is in $.state or $.store.
// Bumped on every prompt, so a pick for an older prompt is dropped.
let gen = 0
let nextBand = 1
// The prompt waiting for its pick at the turn's first request.
let held: { text: string; gen: number; lang: Lang } | null = null
// The chosen level, put on every main-chat request until the person moves the menu. It lives in
// this chat only: the app's own effort setting is never written. `base` is the menu's level when
// the hold began.
let hold: { level: Level; base: string } | null = null
// The chosen model, held the same way; `base` is the request's own model when the hold began.
let modelHold: { key: ModelKey; base: string } | null = null
// The level the last main-chat request ran at, and the language of the last prompt.
let seen: Level | '' = ''
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
  modelHold = null
  await syncOverride($)
}

/** Updates this session's counts, starting from zeros. */
export async function count($: EngineInterface, f: (s: Stats) => Stats): Promise<void> {
  await update($, stats, cur => f(cur ?? NO_STATS))
}

/** A row in the transcript for an applied switch. Its id comes from $.state, so a reload never reuses one. */
async function placeMark($: EngineInterface, level: Level, from: Level | '', why: string, lang: Lang) {
  let n = 0
  await count($, s => {
    n = s.marks + 1
    return { ...s, marks: n }
  })
  const id = `mark-${n}`
  await update($, marks, cur => ({ ...cur, [id]: { level, from, why, lang } }))
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

async function announce($: EngineInterface, level: Level, from: Level | '', why: string, lang: Lang, undo: Band['undo']) {
  const b: Band = { id: nextBand++, level, from, why, lang, undo }
  await update($, band, () => b)
  void (async () => {
    await $.clock.sleep(BAND_MS)
    await update($, band, cur => (cur && cur.id === b.id ? null : cur))
  })().catch(err => log($, 'band', err))
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
  const r = await $.model.complete({
    model,
    prompt: buildPrompt({ prompt: text, lastReply, now }),
    maxTokens: 120,
    effort: 'low',
    timeoutMs: 10_000,
  })
  if (!r.isAnswered) throw new Error(`classifier gave no answer: ${r.reason}`)
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
) {
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
  const stale = async () => h.gen !== gen || (await currentMode($, options)) === 'off'
  if (await stale()) return
  const named = pick.level === 'keep' ? null : pick.level
  await count($, s => (named ? { ...s, picks: { ...s.picks, [named]: s.picks[named] + 1 }, last: { level: named, why: pick.why } } : s))
  const kept = () => count($, s => ({ ...s, kept: s.kept + 1 }))
  if (pick.level === 'keep') return kept()
  const level = pick.level

  // The model first (spec §4.3): it decides what the chat costs from here on.
  const allowed = parseModels(options.models)
  const isFirst = !(await $.session.messages()).some(m => m.role === 'assistant')
  const mAction = decideModel({ mode, pickModel: options.pickModel !== 'off', isFirst, now: nowModel, pick: pick.model, allowed })
  let modelTo: ModelKey | null = mAction === 'apply' && pick.model ? pick.model : null
  if (mAction === 'ask' && pick.model) {
    const to = pick.model
    const tokens = isFirst ? undefined : await chatTokens($)
    const opts = modelOptions(to, nowModel, allowed)
    const labels = opts.map(m => (m === nowModel ? t.keepModel(m) : t.modelOption(m, m === to)))
    try {
      const answer = await $.ui.ask(t.modelQuestion(to, switchCost(tokens, nowModel, to), tokens, isFirst, pick.why), { options: labels, header: t.modelHeader })
      const chosen = opts[labels.indexOf(answer)]
      if (chosen && chosen !== nowModel) modelTo = chosen
    } catch {
      // A dismissed question keeps the model; the effort is still asked.
    }
    if (await stale()) return
  }

  // Then the effort.
  const action = decide(mode, now, pick)
  let levelTo: Level | null = action === 'apply' ? level : null
  if (action === 'ask') {
    const opts = effortOptions(level, now)
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
  if (modelTo) await applyModel($, modelTo, baseModel)
  if (!levelTo) return
  // A silent switch can be undone: back to the menu's own level, or to the level held before.
  const undo: Band['undo'] = action === 'apply' && now ? (now === toLevel(base) ? 'release' : now) : null
  await applyLevel($, levelTo, base)
  await announce($, levelTo, now, pick.why, h.lang, undo)
  try {
    await placeMark($, levelTo, now, pick.why, h.lang)
  } catch (err) {
    await log($, 'mark', err)
  }
}

/** Sets the mode as `/coremodel <mode>` does; returns the reply. */
export async function setMode($: EngineInterface, options: { mode?: unknown }, arg: Mode | 'on'): Promise<string> {
  let text: string
  if (arg === 'auto' || arg === 'suggest') {
    await $.store.set('mode', arg)
    await $.store.set('lastMode', arg)
    text = `CoreModel: ${arg}. ${arg === 'auto' ? 'Levels change by themselves; xhigh and max still ask first.' : 'Every change of level asks first.'}`
  } else if (arg === 'off') {
    await $.store.set('mode', 'off')
    await releaseHold($)
    await update($, band, () => null)
    text = 'CoreModel is off. /coremodel on turns it back on.'
  } else {
    const last = await $.store.get('lastMode')
    const mode: Mode = last === 'auto' || last === 'suggest' ? last : options.mode === 'auto' ? 'auto' : 'suggest'
    await $.store.set('mode', mode)
    text = `CoreModel is on: ${mode}.`
  }
  $.ui.invalidate('ui.render')
  return text
}

/**
 * A level the person picks in the pane (null: Release). It is their newest choice, so the undo line
 * goes, and the hold takes the menu's level from the next request as its base.
 */
async function paneChoice($: EngineInterface, level: Level | null): Promise<void> {
  if (level) await applyLevel($, level, '')
  else await releaseHold($)
  await update($, band, () => null)
}

const ASK_MODES: readonly Mode[] = ['auto', 'suggest', 'off']
const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

export const register: Register = (on, options) => {
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'composer' && e.origin.kind !== 'bridge') return next(e)
    const text = e.text.trim()
    if (!text || text.startsWith('/')) return next(e)
    gen += 1
    lastLang = uiLang(text)
    held = { text, gen, lang: lastLang }
    return next(e)
  }).catch(($, e, next) => next(e))

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
    if (modelHold && modelHold.base === '') modelHold = { ...modelHold, base: e.model }
    // The person chose another model with /model: their choice stands.
    if (modelHold && e.model !== modelHold.base) await releaseModel($)
    if (held && e.index === 0) {
      const h = held
      held = null
      try {
        await runPick($, options, h, hasEffort ? (hold?.level ?? toLevel(asked)) : '', hasEffort ? asked : '', modelHold?.key ?? toModel(e.model), e.model)
      } catch (err) {
        await log($, 'pick', err)
      }
    }
    const want = hasEffort ? (hold?.level ?? null) : null
    const was = seen
    seen = want ?? (toLevel(asked) || seen)
    if (seen !== was) $.ui.invalidate('ui.render')
    const model = modelHold ? MODELS[modelHold.key].id : e.model
    if ((!want || want === e.effort) && model === e.model) return yield* next(e)
    return yield* next({ ...e, effort: want ?? e.effort, model })
  })

  on('session.start', async ($, e, next) => {
    // A new session, or a reload of this module, starts with no held level: drop what $.state kept.
    held = null
    await releaseHold($)
    await update($, band, () => null)
    await $.command.register({
      name: 'coremodel',
      description: 'CoreModel: show the real effort level, set the mode (auto, suggest, off, on), or open the pane (panel)',
      argumentHint: '[auto|suggest|off|on|panel]',
    })
    return next(e)
  })

  on('command.run', { command: 'coremodel' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'auto' || arg === 'suggest' || arg === 'off' || arg === 'on') return { text: await setMode($, options, arg) }
    if (arg === 'panel') {
      const r = await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      return { text: r.isPlaced ? 'CoreModel pane is open.' : `CoreModel pane is waiting: ${r.reason}` }
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
        `CoreModel: ${mode}.`,
        `This chat runs at: ${level ? texts('en').levelName(level) : 'unknown yet'}${hold ? ' (held by the plugin; the menu still shows your own setting)' : ''}.`,
        'Type /coremodel auto, suggest, off, on or panel.',
      ].join('\n'),
    }
  })

  // The app's menu shows the person's own setting; the footer slot beside it names a held level.
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    const level = (await read($, override))?.level
    if (!level) return next(e)
    return next({ ...e, props: { ...e.props, modes: [...e.props.modes, texts(lastLang).label(level)] } })
  })

  on('ui.render', { component: 'Pane', requestId: PLUGIN }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(lastLang)
    const mode = await currentMode($, options)
    const held = (await read($, override))?.level ?? null
    const s = await read($, stats)
    const act = (what: string, f: () => Promise<unknown>) => () => {
      f().catch(err => log($, what, err))
    }
    return (
      <Box flexDirection="column">
        <Box key="modes" flexWrap="wrap">
          {MODES.map(m => (
            <Button key={`mode-${m}`} label={m === mode ? `● ${m}` : m} onPress={act('mode', () => setMode($, options, m))} />
          ))}
        </Box>
        <Text bold>{t.runsAt(held ?? seen)}</Text>
        {held && toLevel(asked) ? <Text dimColor>{t.inMenu(toLevel(asked))}</Text> : null}
        <Text dimColor>{t.lastPick}</Text>
        <Text>{s?.last ? `${t.levelName(s.last.level)} · ${s.last.why}` : t.noPicks}</Text>
        {s ? <Text dimColor>{t.session}</Text> : null}
        {s ? LEVELS.filter(l => s.picks[l] > 0).map(l => <Text>{`${t.levelName(l)} ${s.picks[l]}`}</Text>) : null}
        {s && s.kept > 0 ? <Text>{`${t.kept} ${s.kept}`}</Text> : null}
        <Box key="levels" flexWrap="wrap">
          {held ? <Button key="release" label={t.release} onPress={act('release', () => paneChoice($, null))} /> : null}
          {LEVELS.map(l => (
            <Button key={`level-${l}`} label={t.levelName(l)} onPress={act('level', () => paneChoice($, l))} />
          ))}
        </Box>
      </Box>
    )
  })

  // The working line names the menu's level; while a level is held it says the real one too.
  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const level = (await read($, override))?.level
    if (!level) return next(e)
    return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix} · ${texts(lastLang).levelName(level)}` } })
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== PLUGIN) return next(e)
    const m = (await read($, marks))[e.props.id]
    if (!m) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{texts(m.lang).mark(m.level, m.from, m.why)}</Text>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const b = await read($, band)
    if (!b || e.props.hasSurvey) return next(e)
    const rest = await next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(b.lang)
    const undo = b.undo
    const onUndo = async () => {
      // An old band, or a hold the menu already took back: the person's own choice stands.
      const cur = await read($, band)
      if (!cur || cur.id !== b.id || !hold || hold.level !== b.level || !undo) return
      if (undo === 'release') await releaseLevel($)
      else await applyLevel($, undo, hold.base)
      await update($, band, () => null)
    }
    return (
      <Box flexDirection="column">
        {rest}
        <Box>
          <Text wrap="truncate-end">{`✓ ${t.applied(b.level, b.from, b.why)} `}</Text>
          {undo ? <Button key="undo" hotkey="1" label={t.back(undo === 'release' ? (b.from || b.level) : undo)} onPress={() => onUndo().catch(err => log($, 'undo', err))} /> : null}
        </Box>
      </Box>
    )
  })
}
