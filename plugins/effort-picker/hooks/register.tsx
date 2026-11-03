import type { ConfigRow, EngineInterface, Register } from 'claude-code'

import type { Band, Level } from '../types'
import { buildPrompt, parseAnswer, toLevel } from './classifier'
import { decide, type Lang, type Mode, texts, uiLang } from './policy'

const PLUGIN = 'effort-picker'
const BAND = { plugin: 'effort-picker', key: 'band' } as const
const OVERRIDE = { plugin: 'effort-picker', key: 'override' } as const
const MODELS = { haiku: 'claude-haiku-5-5', sonnet: 'claude-sonnet-5-5' } as const
const MODES: readonly Mode[] = ['suggest', 'auto', 'off']
const LOG_KEEP = 20_000

// Module variables start over on a reload; what must outlive one is in $.state or $.store.
// Bumped on every prompt, so a pick for an older prompt is dropped.
let gen = 0
let nextBand = 1
// The prompt waiting for its pick at the turn's first request.
let held: { text: string; gen: number; lang: Lang } | null = null
// The level for the rest of the running turn, chosen by a switch.
let turnLevel: Level | null = null
// A level the config menu could not take: put on every main-chat request until the menu moves.
// `base` is the menu's level when the hold began.
let hold: { level: Level; base: string } | null = null

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

/** The mode: what /effort-picker stored wins over the setting. */
export async function currentMode($: EngineInterface, options: { mode?: unknown }): Promise<Mode> {
  const stored = await $.store.get('mode')
  if (MODES.includes(stored as Mode)) return stored as Mode
  return MODES.includes(options.mode as Mode) ? (options.mode as Mode) : 'suggest'
}

function isEffortRow(r: ConfigRow) {
  return /effort/i.test(`${r.key} ${r.label}`) && r.kind === 'choice' && (r.options ?? []).some(o => toLevel(o) !== '')
}

/** Switches to `level`: through the config menu when it takes it, else by holding it on every request. */
export async function applyLevel($: EngineInterface, level: Level, base: string): Promise<void> {
  turnLevel = level
  try {
    const row = (await $.config.list()).find(isEffortRow)
    const option = row?.options?.find(o => toLevel(o) === level)
    if (row && option && !row.isLocked) {
      const r = await $.config.set({ key: row.key, value: option })
      if (!r.deny) {
        hold = null
        await $.state.set(OVERRIDE, null)
        return
      }
      await log($, 'config.set', r.deny)
    }
  } catch (err) {
    await log($, 'config', err)
  }
  hold = { level, base }
  await $.state.set(OVERRIDE, level)
}

async function announce($: EngineInterface, level: Level, from: Level | '', why: string, lang: Lang) {
  const band: Band = { id: nextBand++, level, from, why, lang }
  await $.state.set(BAND, band)
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
async function runPick($: EngineInterface, options: { mode?: unknown; classifier?: unknown }, h: NonNullable<typeof held>, now: Level | '', base: string) {
  const mode = await currentMode($, options)
  if (mode === 'off') return
  const t = texts(h.lang)
  try {
    await $.ui.status(t.checking)
  } catch {
    // The status line is a nicety.
  }
  let pick
  try {
    pick = await classify($, h.text, now, options.classifier === 'sonnet' ? MODELS.sonnet : MODELS.haiku)
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
  if (h.gen !== gen) return
  const action = decide(mode, now, pick)
  if (action === 'none' || pick.level === 'keep') return
  const level = pick.level
  if (action === 'ask') {
    const go = t.switchTo(level)
    let answer = ''
    try {
      answer = await $.ui.ask(t.question(level, pick.why), { options: [go, t.switchAndAuto, t.keep(now)], header: 'Effort' })
    } catch {
      // A dismissed question keeps the level.
      return
    }
    if (h.gen !== gen) return
    if (answer === t.switchAndAuto) await $.store.set('mode', 'auto')
    else if (answer !== go) return
  }
  await applyLevel($, level, base)
  await announce($, level, now, pick.why, h.lang)
}

export const register: Register = (on, options) => {
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'composer' && e.origin.kind !== 'bridge') return next(e)
    const text = e.text.trim()
    if (!text || text.startsWith('/')) return next(e)
    gen += 1
    turnLevel = null
    held = { text, gen, lang: uiLang(text) }
    return next(e)
  }).catch(($, e, next) => next(e))

  // Every main-chat request: release a hold the menu moved past, run a waiting pick, put the level on.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined || typeof e.effort !== 'string') return yield* next(e)
    const asked = e.effort
    if (hold && asked !== hold.base) {
      hold = null
      turnLevel = null
      await $.state.set(OVERRIDE, null)
    }
    if (held && e.index === 0) {
      const h = held
      held = null
      try {
        await runPick($, options, h, hold?.level ?? toLevel(asked), asked)
      } catch (err) {
        await log($, 'pick', err)
      }
    }
    const want = turnLevel ?? hold?.level ?? null
    if (!want || want === asked) return yield* next(e)
    return yield* next({ ...e, effort: want })
  })
}
