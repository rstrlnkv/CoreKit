// The pick for one prompt (classify, then switch, ask or suggest) and its record: the session
// counts ($.state stats) and the transcript rows ($.state marks).
import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import type { Band, Level, Mark, Stats } from '../types'
import { classify, Cut, failed, pickWorked } from './ask'
import { LEVELS, type Pick, toLevel } from './classifier'
import { applyLevel, applyModel, dropBand, releaseHold, showBand } from './hold'
import { allowedModels, chatTokens, currentMode, isEmptyChat, log, pickOn, refreshListed } from './host'
import { type ModelKey, standIn, toModel } from './models'
import { decide, decideModel, effortOptions, LOCALES, modelOptions, texts } from './policy'
import { type Held, session } from './session'

const marks = atom({ plugin: 'coremodel', key: 'marks' } as const, {})

const stats = atom({ plugin: 'coremodel', key: 'stats' } as const, null)

const NO_STATS: Stats = { picks: { low: 0, medium: 0, high: 0, xhigh: 0, max: 0 }, kept: 0, last: null, marks: 0, models: { haiku: 0, sonnet: 0, opus: 0, fable: 0 } }

/**
 * A new chat starts with nothing held: the hold and the undo line go, and a pick still on its way
 * is dropped. Models the account refused stay dropped.
 * `fromEngine`: /clear, /resume or a fork. The prompt typed for the new chat may reach us before
 * the engine's SessionStart does, so a prompt still waiting for its first request stays (with the
 * new generation), and the rows of the old chat's switches go. A new session or a reload (`false`)
 * starts clean, and keeps the rows its transcript still shows.
 */
export async function newChat($: EngineInterface, fromEngine: boolean): Promise<void> {
  session.gen += 1
  session.lastUndo = null
  session.held = fromEngine && session.held ? { ...session.held, gen: session.gen } : null
  session.seen = toLevel(session.asked)
  await releaseHold($)
  if (fromEngine) await update($, marks, () => ({}))
  await dropBand($)
  $.ui.invalidate('ui.render')
}

/** Updates this session's counts, starting from zeros. */
async function count($: EngineInterface, f: (s: Stats) => Stats): Promise<void> {
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

/** A level named in typed text, in any locale; undefined when it names none. */
function typedLevel(text: string): Level | undefined {
  const x = text.trim().toLowerCase().replace(/[«»"]/g, '')
  return toLevel(x) || LEVELS.find(l => Object.values(LOCALES).some(s => s.level[l].toLowerCase() === x))
}

/** The pick for one prompt, then the switch, the question, or nothing. */
export async function runPick(
  $: EngineInterface,
  options: Readonly<Record<string, unknown>>,
  h: Held,
  now: Level | '',
  base: string,
  nowModel: ModelKey | '',
  baseModel: string,
  hasEffort: boolean,
) {
  const began = session.touched
  const mode = await currentMode($, options)
  if (mode === 'off') return
  const t = texts(h.lang)
  try {
    await $.ui.status(pickOn(options) ? t.checking : t.checkingEffort)
  } catch {
    // The status line is a nicety.
  }
  let pick: Pick
  try {
    pick = await classify($, h.text, now, options.classifier === 'haiku' ? 'haiku' : 'sonnet')
  } catch (err) {
    await log($, 'classify', err)
    if (!(err instanceof Cut)) await failed($, h.lang, err instanceof Error ? err.message : String(err))
    return
  } finally {
    try {
      await $.ui.status(undefined)
    } catch {
      // Nothing to clear.
    }
  }
  await pickWorked($)
  // The person may have turned the plugin off while the classifier ran.
  const stale = async () => h.gen !== session.gen || session.touched !== began || (await currentMode($, options)) === 'off'
  if (await stale()) return
  // A model the plugin may not use (the account lacks it, or its switch is off) gives way to the nearest
  // one it may use, below it first. The reason says so wherever the pick is shown: the questions, the
  // switch line, the transcript marks and the pane's last pick.
  await refreshListed($)
  const allowed = allowedModels(options)
  if (pick.model && !allowed.includes(pick.model) && pickOn(options)) {
    const sub = standIn(pick.model, allowed)
    pick = sub ? { ...pick, model: sub, why: [t.insteadOfModel(pick.model, sub), pick.why].filter(Boolean).join('; ') } : { ...pick, model: '' }
  }
  const named = pick.level === 'keep' ? null : pick.level
  // The pick is remembered as asked; the counts wait for what was applied below.
  await count($, s => (named ? { ...s, last: { level: named, why: pick.why, ...(pick.model ? { model: pick.model } : {}) } } : s))
  if (pick.level === 'keep') return keptPrompt($, false)
  const level = pick.level

  const isFirst = await isEmptyChat($)
  const mAction = decideModel({ mode, pickModel: pickOn(options), isFirst, now: nowModel, pick: pick.model, allowed })
  // A request with no effort has nowhere to put a level: that part is skipped, not asked or marked.
  const action = hasEffort ? decide(mode, now, pick) : 'none'

  // Suggest: never a dialog. The prompt runs as it is; the band offers the pick, and a press holds it.
  if (mAction === 'suggest' || action === 'suggest') {
    const suggestion: Mark = {
      level: action === 'suggest' ? level : null,
      from: now,
      model: mAction === 'suggest' && pick.model ? pick.model : null,
      fromModel: nowModel,
      why: pick.why,
      lang: h.lang,
    }
    await showBand($, { id: session.nextBand++, ...suggestion, undo: null, suggest: true })
    return
  }

  let modelTo: ModelKey | null = mAction === 'apply' && pick.model ? pick.model : null
  let levelTo: Level | null = action === 'apply' ? level : null

  // The model first (it decides what the chat costs from here on), then the effort. In
  // each question the recommended choice comes first and the current one is there to keep. When both
  // are asked, the effort question ends with "Back to the model", which asks the model again.
  let askModel: (() => Promise<void>) | null = null
  if (mAction === 'ask' && pick.model) {
    const to = pick.model
    // Mid-chat the question is the cost question: the pick and the current model, nothing else (modelOptions).
    const opts: ModelKey[] = modelOptions(to, nowModel, allowed, isFirst)
    const labels = opts.map(m => (m === nowModel ? t.keepModel(m) : isFirst ? t.modelOption(m, m === to) : t.switchToModel(m)))
    const question = isFirst ? t.firstModel(to, pick.why) : t.costQuestion(to, nowModel, await chatTokens($), pick.why)
    askModel = async () => {
      modelTo = null
      try {
        const chosen = opts[labels.indexOf(await $.ui.ask(question, { options: labels, header: t.modelHeader }))]
        if (chosen && chosen !== nowModel) modelTo = chosen
      } catch {
        // A dismissed question keeps the model; the effort is still asked.
      }
    }
  }
  if (askModel) {
    await askModel()
    if (await stale()) return
  }
  if (action === 'ask') {
    // With Back among them the question has room for three levels; any level can still be typed.
    const opts = effortOptions(level, now).slice(0, askModel ? 3 : 4)
    const labels = opts.map(l => (l === now ? t.keepLevel(l) : t.levelOption(l, l === level)))
    const question = t.question(level, askModel ? '' : pick.why)
    for (let round = 0; round < 5; round += 1) {
      let answer = ''
      try {
        answer = await $.ui.ask(question, { options: askModel ? [...labels, t.backToModel] : labels, header: t.effortHeader })
      } catch {
        // A dismissed question keeps the level.
      }
      if (await stale()) return
      if (askModel && answer === t.backToModel) {
        await askModel()
        if (await stale()) return
        continue
      }
      // A level typed under Other counts too, in either language ("max", "Максимальное").
      const chosen = opts[labels.indexOf(answer)] ?? typedLevel(answer)
      if (chosen && chosen !== now) levelTo = chosen
      break
    }
  }

  if (!modelTo && !levelTo) return keptPrompt($, true)
  // A silent switch can be undone, part by part: back to the menu's own value, or to the one held before.
  const parts: NonNullable<Band['undo']> = {}
  if (modelTo && mAction === 'apply' && nowModel) parts.model = nowModel === toModel(baseModel) ? 'release' : nowModel
  if (levelTo && action === 'apply' && now) parts.level = now === toLevel(base) ? 'release' : now
  if (modelTo) await applyModel($, modelTo, baseModel)
  if (levelTo) await applyLevel($, levelTo, base)
  const change: Mark = { level: levelTo, from: levelTo ? now : '', model: modelTo, fromModel: modelTo ? nowModel : '', why: pick.why, lang: h.lang }
  await applied($, change)
  // The band is for a silent switch, where it carries the undo; a switch the person agreed to in a
  // dialog is in the transcript row and the footer already.
  if (parts.model || parts.level) await showBand($, { id: session.nextBand++, ...change, undo: parts })
}

/** A prompt left as it was: counted, and its named pick marked as not applied. */
export async function keptPrompt($: EngineInterface, named: boolean): Promise<void> {
  await count($, s => ({ ...s, kept: s.kept + 1, last: named && s.last ? { ...s.last, declined: true } : s.last }))
}

/** An applied switch: the session counts and a row in the transcript. */
export async function applied($: EngineInterface, change: Mark): Promise<void> {
  const modelTo = change.model
  const levelTo = change.level
  await count($, s => {
    const models = { ...s.models }
    if (modelTo) models[modelTo] += 1
    const picks = levelTo ? { ...s.picks, [levelTo]: s.picks[levelTo] + 1 } : s.picks
    const last = s.last ? { ...s.last, level: levelTo ?? s.last.level, ...(modelTo ? { model: modelTo } : { model: undefined }) } : s.last
    if (last) delete last.declined
    if (last && !modelTo) delete last.model
    return { ...s, picks, models, last }
  })
  try {
    await placeMark($, change)
  } catch (err) {
    await log($, 'mark', err)
  }
}

/** This session's counts, or null until something is counted. */
export async function sessionStats($: EngineInterface) {
  return read($, stats)
}

/** The transcript rows placed for switches, by row id. */
export async function placedMarks($: EngineInterface) {
  return read($, marks)
}
