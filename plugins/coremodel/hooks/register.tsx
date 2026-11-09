import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { Band, Level, Mark, Stats } from '../types'
import { classifierFault, classify, Cut, FAIL_SHOW, failed, pickWorked } from './ask'
import { LEVELS, type Pick, toLevel } from './classifier'
import { allowedModels, chatTokens, currentLang, currentMode, isEmptyChat, log, pickOn, PLUGIN, refreshListed } from './host'
import { enabledModels, LADDER, type ModelKey, MODELS, requestModel, standIn, toModel } from './models'
import { decide, decideModel, effortOptions, LOCALES, type Mode, modelOptions, MODES, texts } from './policy'
import { BAND_MS, type Held, session } from './session'

const band = atom({ plugin: 'coremodel', key: 'band' } as const, null)

const override = atom({ plugin: 'coremodel', key: 'override' } as const, null)

const marks = atom({ plugin: 'coremodel', key: 'marks' } as const, {})

const stats = atom({ plugin: 'coremodel', key: 'stats' } as const, null)

const NO_STATS: Stats = { picks: { low: 0, medium: 0, high: 0, xhigh: 0, max: 0 }, kept: 0, last: null, marks: 0, models: { haiku: 0, sonnet: 0, opus: 0, fable: 0 } }

/** Switches to `level` by holding it on this chat's requests. */
async function applyLevel($: EngineInterface, level: Level, base: string): Promise<void> {
  session.hold = { level, base }
  await syncOverride($)
}

/** What the drawings read: the held pair, or null when nothing is held. */
async function syncOverride($: EngineInterface): Promise<void> {
  const pair = { model: session.modelHold?.key ?? null, level: session.hold?.level ?? null }
  await update($, override, () => (pair.model || pair.level ? pair : null))
}

/** Lets go of the held level: the chat runs at the menu's level again. */
async function releaseLevel($: EngineInterface): Promise<void> {
  session.hold = null
  // The pane reads `seen`: after a release it is the menu's level, not the one just let go.
  session.seen = toLevel(session.asked) || session.seen
  await syncOverride($)
}

/** Lets go of the held model: the chat runs on the person's own model again. */
async function releaseModel($: EngineInterface): Promise<void> {
  session.modelHold = null
  await syncOverride($)
}

/** Lets go of both parts (off, Release, a new session). */
async function releaseHold($: EngineInterface): Promise<void> {
  session.hold = null
  session.seen = toLevel(session.asked) || session.seen
  session.modelHold = null
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
  session.gen += 1
  session.lastUndo = null
  session.held = fromEngine && session.held ? { ...session.held, gen: session.gen } : null
  session.seen = toLevel(session.asked)
  await releaseHold($)
  if (fromEngine) await update($, marks, () => ({}))
  await update($, band, () => null)
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

/** Switches to `key` by holding it on this chat's requests. */
async function applyModel($: EngineInterface, key: ModelKey, base: string): Promise<void> {
  session.modelHold = { key, base }
  await syncOverride($)
}

/**
 * What the chat runs at, from the held pair: each held part, else what the last request showed.
 * "Your default" names only the held parts, as the chat's own menu sets them. The model only while
 * CoreModel picks it.
 */
function chatState(pair: { model: ModelKey | null; level: Level | null } | null, options: { pickModel?: unknown }) {
  const withModel = pickOn(options)
  const nowModel: ModelKey | '' = withModel ? (pair?.model ?? toModel(session.seenModel)) : ''
  const nowLevel: Level | '' = pair?.level ?? session.seen
  const defaultModel: ModelKey | '' = withModel && pair?.model ? toModel(session.seenModel) : ''
  const defaultLevel: Level | '' = pair?.level ? toLevel(session.asked) : ''
  return { nowModel, nowLevel, isHeld: !!(pair?.model || pair?.level), defaultModel, defaultLevel }
}

/** The cost question before a switch to `key` mid-chat; true on the person's yes. */
async function confirmCost($: EngineInterface, key: ModelKey, nowModel: ModelKey | '', why: string): Promise<boolean> {
  const t = texts(session.lastLang)
  const yes = t.switchToModel(key)
  try {
    const answer = await $.ui.ask(t.costQuestion(key, nowModel, await chatTokens($), why), { options: [yes, nowModel ? t.keepModel(nowModel) : t.cancel], header: t.modelHeader })
    return answer === yes
  } catch {
    return false
  }
}

/** Takes `b` down unless a newer band has replaced it. */
async function clearBand($: EngineInterface, b: Band): Promise<void> {
  await update($, band, cur => (cur && cur.id === b.id ? null : cur))
}

/**
 * Puts `b` above the prompt for BAND_MS: a silent switch with its undo, or a suggestion. VS Code draws
 * no band, so there it is said in a toast, a silent switch with the undo command.
 */
async function showBand($: EngineInterface, b: Band) {
  if (b.undo) session.lastUndo = b
  await update($, band, () => b)
  if (session.surface === 'vscode') {
    const t = texts(b.lang)
    try {
      $.ui.toast(
        b.suggest
          ? `${t.suggests} ${t.change(b.model, '', b.level, '', b.why)}`
          : `CoreModel: ${t.change(b.model, b.fromModel, b.level, b.from, b.why)}${b.undo ? ` · ${t.undoHint}` : ''}`,
      )
    } catch {
      // The transcript row still says it.
    }
  }
  void (async () => {
    await $.clock.sleep(BAND_MS)
    await clearBand($, b)
  })().catch(err => log($, 'band', err))
}

/** A level named in typed text, in any locale; undefined when it names none. */
function typedLevel(text: string): Level | undefined {
  const x = text.trim().toLowerCase().replace(/[«»"]/g, '')
  return toLevel(x) || LEVELS.find(l => Object.values(LOCALES).some(s => s.level[l].toLowerCase() === x))
}

/** The pick for one prompt, then the switch, the question, or nothing. */
async function runPick(
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
    // Mid-chat the question is the cost question: the pick and the current model, nothing else.
    const opts: (ModelKey | 'keep')[] = isFirst ? modelOptions(to, nowModel, allowed, true) : [to, nowModel || 'keep']
    const labels = opts.map(m =>
      m === 'keep' ? t.keepCurrentModel : m === nowModel ? t.keepModel(m) : isFirst ? t.modelOption(m, m === to) : t.switchToModel(m),
    )
    const question = isFirst ? t.firstModel(to, pick.why) : t.costQuestion(to, nowModel, await chatTokens($), pick.why)
    askModel = async () => {
      modelTo = null
      try {
        const chosen = opts[labels.indexOf(await $.ui.ask(question, { options: labels, header: t.modelHeader }))]
        if (chosen && chosen !== 'keep' && chosen !== nowModel) modelTo = chosen
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
    const labels = opts.map(l => (l === now ? t.keepLevel(now) : t.levelOption(l, l === level)))
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
async function keptPrompt($: EngineInterface, named: boolean): Promise<void> {
  await count($, s => ({ ...s, kept: s.kept + 1, last: named && s.last ? { ...s.last, declined: true } : s.last }))
}

/** An applied switch: the session counts and a row in the transcript. */
async function applied($: EngineInterface, change: Mark): Promise<void> {
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

/**
 * Switch on a suggestion: the person's yes, held from the next request. Mid-chat a stronger model
 * still gets the cost question first; a No there keeps the model and takes the effort.
 */
async function acceptSuggestion($: EngineInterface, b: Band): Promise<void> {
  session.touched += 1
  await clearBand($, b)
  const nowModel = session.modelHold?.key ?? toModel(session.seenModel)
  let modelTo = b.model && b.model !== nowModel ? b.model : null
  if (modelTo && !(await isEmptyChat($)) && !(await confirmCost($, modelTo, nowModel, b.why))) modelTo = null
  const nowLevel = session.hold?.level ?? session.seen
  const levelTo = b.level && b.level !== nowLevel ? b.level : null
  if (!modelTo && !levelTo) return keptPrompt($, true)
  if (modelTo) await applyModel($, modelTo, '')
  if (levelTo) await applyLevel($, levelTo, '')
  await applied($, { level: levelTo, from: levelTo ? nowLevel : '', model: modelTo, fromModel: modelTo ? nowModel : '', why: b.why, lang: b.lang })
}

/** Keep on a suggestion: nothing changes; the prompt counts as unchanged. */
async function declineSuggestion($: EngineInterface, b: Band): Promise<void> {
  await clearBand($, b)
  await keptPrompt($, true)
}

/** Takes back what a silent switch changed, part by part; a part the person changed since stays. True when anything went back. */
async function undoChange($: EngineInterface, b: Band): Promise<boolean> {
  const undo = b.undo
  if (!undo) return false
  session.touched += 1
  let done = false
  if (undo.model && b.model && session.modelHold?.key === b.model) {
    if (undo.model === 'release') await releaseModel($)
    else await applyModel($, undo.model, session.modelHold.base)
    done = true
  }
  if (undo.level && b.level && session.hold?.level === b.level) {
    if (undo.level === 'release') await releaseLevel($)
    else await applyLevel($, undo.level, session.hold.base)
    done = true
  }
  if (session.lastUndo?.id === b.id) session.lastUndo = null
  await clearBand($, b)
  return done
}

/** What an undo of `b` goes back to: a model and a level, each named or empty. */
function undoTarget(b: Band): { model: ModelKey | '' | undefined; level: Level | '' | undefined } {
  return {
    model: b.undo?.model === 'release' ? b.fromModel : b.undo?.model,
    level: b.undo?.level === 'release' ? b.from : b.undo?.level,
  }
}

/** Sets the mode as `/coremodel <mode>` does; returns the reply. */
async function setMode($: EngineInterface, options: { mode?: unknown; pickModel?: unknown }, arg: Mode | 'on'): Promise<string> {
  const t = texts(session.lastLang)
  let text: string
  if (arg === 'auto' || arg === 'suggest') {
    await $.store.set('mode', arg)
    await $.store.set('lastMode', arg)
    // A suggestion of the other mode has no place any more.
    await update($, band, cur => (cur?.suggest && arg === 'auto' ? null : cur))
    text = t.modeSet(arg, pickOn(options))
  } else if (arg === 'off') {
    await $.store.set('mode', 'off')
    await releaseHold($)
    await update($, band, () => null)
    text = t.modeOff
  } else {
    const last = await $.store.get('lastMode')
    const mode: Mode = last === 'auto' || last === 'suggest' ? last : options.mode === 'suggest' ? 'suggest' : 'auto'
    await $.store.set('mode', mode)
    text = t.modeOnFor(mode)
  }
  $.ui.invalidate('ui.render')
  return text
}

/**
 * A level the person picks in the pane (null: Use my default). It is their newest choice, so the band
 * goes, and the hold takes the menu's level from the next request as its base.
 */
async function paneChoice($: EngineInterface, level: Level | null): Promise<void> {
  session.touched += 1
  if (level) await applyLevel($, level, '')
  else await releaseHold($)
  await update($, band, () => null)
}

/**
 * A model the person presses in the pane. Mid-chat the cost question comes first;
 * the press itself is their yes, so no other question follows.
 */
async function paneModel($: EngineInterface, key: ModelKey): Promise<void> {
  session.touched += 1
  const nowModel = session.modelHold?.key ?? toModel(session.seenModel)
  if (key === nowModel) return
  if (!(await isEmptyChat($)) && !(await confirmCost($, key, nowModel, ''))) return
  await applyModel($, key, '')
  await update($, band, () => null)
}

const RULE = '─'.repeat(40)
// The width of the captions in the pane's rows, in cells: the longest caption of the language, plus one,
// so every row's value starts in the same column.
const captionWidth = (t: ReturnType<typeof texts>) =>
  Math.max(...[t.thisChat, t.model, t.effort, t.thisSession, t.lastPick].map(c => c.length)) + 1

export const register: Register = (on, options) => {

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'composer' && e.origin.kind !== 'bridge') {
      // That prompt takes the next turn; an older one waiting is not it.
      session.held = null
      return next(e)
    }
    const text = e.text.trim()
    if (!text || text.startsWith('/')) {
      // A prompt of ours is not the next turn's any more.
      session.held = null
      return next(e)
    }
    session.gen += 1
    session.lastLang = await currentLang($, options)
    const mine = { text, gen: session.gen, lang: session.lastLang, ...(e.turnId ? { turn: e.turnId } : {}) }
    session.held = mine
    const r = await next(e)
    // Refused beneath us: no turn will come of it.
    if (r.drop !== undefined && session.held === mine) session.held = null
    return r
  }).catch(($, e, next) => next(e))

  // A turn that ends with a prompt still waiting (blocked, Esc'd before its first request) leaves
  // nothing for the next turn; only a prompt queued behind this very turn stays.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && session.held && session.held.turn !== e.turnId) session.held = null
    return next(e)
  })

  // Every main-chat request: release a hold the menu moved past, run a waiting pick, put the level on.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) return yield* next(e)
    // A model without effort carries none; the level part then sleeps.
    const hasEffort = typeof e.effort === 'string'
    if (hasEffort) {
      session.asked = e.effort as string
      // A level picked in the pane before any request learns the menu's level here.
      if (session.hold && session.hold.base === '') session.hold = { ...session.hold, base: session.asked }
      if (session.hold && session.asked !== session.hold.base) await releaseLevel($)
    }
    session.seenModel = e.model
    if (session.modelHold && session.modelHold.base === '') session.modelHold = { ...session.modelHold, base: e.model }
    // The person chose another model with /model: their choice stands.
    if (session.modelHold && e.model !== session.modelHold.base) await releaseModel($)
    if (session.held && e.index === 0) {
      const h = session.held
      session.held = null
      try {
        await runPick($, options, h, hasEffort ? (session.hold?.level ?? toLevel(session.asked)) : '', hasEffort ? session.asked : '', session.modelHold?.key ?? toModel(e.model), e.model, hasEffort)
      } catch (err) {
        await log($, 'pick', err)
      }
    }
    const want = hasEffort ? (session.hold?.level ?? null) : null
    const was = session.seen
    session.seen = want ?? (toLevel(session.asked) || session.seen)
    if (session.seen !== was) $.ui.invalidate('ui.render')
    // The request's context suffix (`[1m]`) stays on the held model: a long chat must still fit.
    const model = session.modelHold ? requestModel(session.modelHold.key, e.model) : e.model
    if ((!want || want === e.effort) && model === e.model) return yield* next(e)
    return yield* next({ ...e, effort: want ?? e.effort, model })
  })

  // A model the account cannot use: the turn fails with model_not_found, naming no model, so the
  // held one is the one refused. Drop it for this session, once, instead of failing every request.
  on('classic.StopFailure', async ($, e, next) => {
    // A subagent's failure says nothing about the main chat's model.
    if (e.error === 'model_not_found' && session.modelHold && e.agent_id === undefined) {
      const key = session.modelHold.key
      session.unavailable.add(key)
      await releaseModel($)
      await log($, 'model', `${MODELS[key].name} is not available: ${e.error_details ?? e.error}`)
      $.ui.invalidate('ui.render')
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // /clear, /resume and a fork start another chat in this process, and session.start does not run
  // for them; the module's own variables would carry the hold into the new chat. A compacted chat
  // is the same chat and keeps it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') await newChat($, true)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.start', async ($, e, next) => {
    session.surface = e.surface ?? ''
    // The language: the plugin's setting, else the host's. A `lang` that 0.7.0 stored is left alone and unread.
    session.lastLang = await currentLang($, options)
    session.unavailable.clear()
    await refreshListed($)
    // A new session, or a reload of this module, starts with no held level: drop what $.state kept.
    await newChat($, false)
    await $.command.register({
      name: 'coremodel',
      description: 'CoreModel: show what the chat runs at, set the mode (auto, suggest, off, on), open the pane (panel), take back the last switch (undo); recheck reads the account\'s model list again',
      argumentHint: '[auto|suggest|off|on|panel|undo|recheck]',
    })
    return next(e)
  })

  on('command.run', { command: 'coremodel' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    const t = texts(session.lastLang)
    if (arg === 'auto' || arg === 'suggest' || arg === 'off' || arg === 'on') return { text: await setMode($, options, arg) }
    if (arg === 'panel') {
      const r = await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      if (r.isPlaced) return { text: t.paneOpen }
      // The engine's reason is for the debug log; the person gets a plain sentence.
      await log($, 'pane not shown', r.reason)
      return { text: r.reason.startsWith('no-surface') ? t.paneNoSurface : t.paneWaiting }
    }
    if (arg === 'undo') {
      const b = session.lastUndo
      if (!b || !(await undoChange($, b))) return { text: t.nothingToUndo }
      const to = undoTarget(b)
      return { text: t.undone(t.pair(to.model, to.level)) }
    }
    if (arg === 'recheck') {
      // Models dropped after model_not_found come back, and the account's list is read again.
      session.unavailable.clear()
      await refreshListed($)
      $.ui.invalidate('ui.render')
      const names = allowedModels(options).map(k => MODELS[k].name)
      return { text: t.recheck(names, enabledModels(options).length, session.listed !== null, pickOn(options)) }
    }
    if (arg === 'probe') {
      // A diagnostic, left out of the command's hint: what /config offers, to see whether it lists the
      // models this account can use. Reads only, and writes to the debug log, never to the chat.
      let rows: Awaited<ReturnType<typeof $.config.list>> = []
      try {
        rows = await $.config.list()
      } catch (err) {
        await log($, 'probe', `no rows (${err instanceof Error ? err.message : String(err)})`)
        return { text: t.probeLogged(0) }
      }
      const line = (r: (typeof rows)[number]) => {
        const opts = r.options ? ` · options: ${r.options.slice(0, 16).join(', ')}${r.options.length > 16 ? ', …' : ''}` : ''
        return `${r.key} · ${r.label} · ${r.kind} · value: ${String(r.value)}${opts}`
      }
      await log($, 'probe', rows.length ? `${rows.length} rows\n${rows.map(line).join('\n')}` : 'no rows')
      return { text: t.probeLogged(rows.length) }
    }
    const mode = await currentMode($, options)
    // pickModel off: the level only, as everywhere else.
    const { nowModel: model, nowLevel: level, isHeld, defaultModel, defaultLevel } = chatState(await read($, override), options)
    const yours = t.pair(defaultModel, defaultLevel)
    if (!arg) {
      let answer = ''
      try {
        const picked = await $.ui.ask(t.modeQuestionFor(mode, model, level), { options: MODES.map(m => t.modeName(m)), header: 'CoreModel' })
        answer = MODES.find(m => t.modeName(m) === picked) ?? ''
      } catch {
        // Dismissed: say where things stand, change nothing.
      }
      if ((MODES as readonly string[]).includes(answer)) return { text: await setMode($, options, answer as Mode) }
    }
    return { text: t.status(mode, pickOn(options), model, level, isHeld, yours) }
  })

  // The footer slot: the engine's own mode words, then a button that carries CoreModel's state and
  // opens and closes the pane (no chat command, so a running turn is not interrupted).
  on('ui.render', { component: 'SessionMode' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(session.lastLang)
    const { nowModel, nowLevel, isHeld } = chatState(await read($, override), options)
    const mode = await currentMode($, options)
    // While a model or level is set, both parts are named: the part not set is what the chat last showed.
    const state = mode === 'off' ? t.off : isHeld ? t.pair(nowModel, nowLevel) : ''
    const isUp = (await $.ui.panes()).some(p => p.id === PLUGIN)
    const toggle = async () => {
      if ((await $.ui.panes()).some(p => p.id === PLUGIN)) await $.ui.close({ id: PLUGIN })
      else await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      $.ui.invalidate('ui.render')
    }
    return (
      <Box gap="sm">
        {e.props.modes.length ? <Text dimColor>{e.props.modes.join(' & ')}</Text> : null}
        <Button key="pane" label={state ? `CoreModel · ${state}` : 'CoreModel'} variant={isUp ? 'primary' : undefined} onPress={() => void toggle().catch(err => log($, 'pane', err))} />
      </Box>
    )
  })

  // A hook's filter is read from literals in its own file, so the pane id is spelled out here.
  on('ui.render', { component: 'Pane', requestId: 'coremodel' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(session.lastLang)
    const mode = await currentMode($, options)
    const { nowModel, nowLevel, isHeld, defaultModel, defaultLevel } = chatState(await read($, override), options)
    const s = await read($, stats)
    const fault = await classifierFault($)
    const allowed = allowedModels(options)
    // pickModel off: effort only.
    const withModel = pickOn(options)
    const act = (what: string, f: () => Promise<unknown>) => () => {
      f().catch(err => log($, what, err))
    }
    // A selected button says so in its words, not by colour alone; the colour stays as a second cue.
    const mark = (label: string, isOn: boolean) => (isOn ? `● ${label}` : label)
    const nowPair = t.pair(nowModel, nowLevel)
    const yours = t.pair(defaultModel, defaultLevel)
    const caption = captionWidth(t)
    const row = (key: string, label: string, body: RenderChildren) => (
      <Box key={key} flexDirection="row" gap="sm">
        <Box key={`${key}-caption`} minWidth={caption}>
          <Text dimColor>{label}</Text>
        </Box>
        {body}
      </Box>
    )
    const rule = (key: string) => (
      <Text key={key} dimColor wrap="truncate-end">
        {RULE}
      </Text>
    )
    // The session in one line: models, then efforts, then the prompts left as they were.
    const sessionLine = s
      ? [
          ...(withModel ? LADDER.filter(m => s.models[m] > 0).map(m => `${MODELS[m].name} ${s.models[m]}`) : []),
          ...LEVELS.filter(l => s.picks[l] > 0).map(l => `${t.levelName(l)} ${s.picks[l]}`),
          ...(s.kept > 0 ? [t.unchanged(s.kept)] : []),
        ].join(' · ')
      : ''
    // The last pick, only when it says something the chat does not: it was not applied, or it differs.
    const last = s?.last
    const lastPair = last ? t.pair(withModel && last.model ? last.model : '', last.level) : ''
    const showLast = !!last && (!!last.declined || last.level !== nowLevel || (withModel && !!last.model && last.model !== nowModel))
    const lastLine = last ? [lastPair, last.why, last.declined ? t.notApplied : ''].filter(Boolean).join(' · ') : ''
    return (
      <Box flexDirection="column" gap="sm">
        <Box key="mode" flexDirection="column" gap="xs">
          <Text weight="semibold">{`CoreModel · ${t.modeName(mode)}`}</Text>
          <Box key="modes" flexWrap="wrap" gap="xs">
            {MODES.map(m => (
              <Button key={`mode-${m}`} label={mark(t.modeName(m), m === mode)} variant={m === mode ? 'primary' : undefined} onPress={act('mode', () => setMode($, options, m))} />
            ))}
          </Box>
          <Text dimColor>{t.modeHintFor(mode, withModel)}</Text>
        </Box>
        {rule('d1')}
        <Box key="now" flexDirection="column" gap="xs">
          {row('chat', t.thisChat, nowPair ? <Text weight="semibold">{nowPair}</Text> : <Text dimColor>{t.shownLater}</Text>)}
          {isHeld ? <Text dimColor>{yours ? `${t.setBy} · ${t.yourDefault(yours)}` : t.setBy}</Text> : null}
          {isHeld ? (
            <Box key="release-row">
              <Button key="release" label={t.useDefault} onPress={act('release', () => paneChoice($, null))} />
            </Box>
          ) : null}
          {fault && fault.count >= FAIL_SHOW ? <Text key="fault" color="warning">{`⚠ ${t.classifierDown(fault.reason)}`}</Text> : null}
          {[...session.unavailable].map(m => (
            <Text key={`unavailable-${m}`} color="warning">{`⚠ ${t.unavailableModel(m)}`}</Text>
          ))}
        </Box>
        {withModel && allowed.length
          ? row(
              'choose-model',
              t.model,
              <Box key="models" flexWrap="wrap" gap="xs" flexShrink={1}>
                {allowed.map(m => (
                  <Button key={`model-${m}`} label={mark(MODELS[m].name, m === nowModel)} variant={m === nowModel ? 'primary' : undefined} onPress={act('model', () => paneModel($, m))} />
                ))}
              </Box>,
            )
          : null}
        {row(
          'choose',
          t.effort,
          <Box key="levels" flexWrap="wrap" gap="xs" flexShrink={1}>
            {LEVELS.map(l => (
              <Button key={`level-${l}`} label={mark(t.levelName(l), l === nowLevel)} variant={l === nowLevel ? 'primary' : undefined} onPress={act('level', () => paneChoice($, l))} />
            ))}
          </Box>,
        )}
        {sessionLine || showLast ? rule('d2') : null}
        {sessionLine ? row('session', t.thisSession, <Text>{sessionLine}</Text>) : null}
        {showLast ? row('last', t.lastPick, <Text>{lastLine}</Text>) : null}
      </Box>
    )
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
    // A press on an old band, or after the person changed it: their own choice stands.
    const current = async () => {
      const cur = await read($, band)
      return !!cur && cur.id === b.id
    }
    if (b.suggest) {
      const what = t.change(b.model, '', b.level, '', b.why)
      return (
        <Box flexDirection="column">
          {rest}
          <Box gap="sm">
            <Text wrap="truncate-end">{`${t.suggests} ${what}`}</Text>
            <Button key="switch" hotkey="1" label={t.switchButton} onPress={() => void (async () => (await current()) && acceptSuggestion($, b))().catch(err => log($, 'switch', err))} />
            <Button key="keep" hotkey="2" label={t.keepButton} onPress={() => void (async () => (await current()) && declineSuggestion($, b))().catch(err => log($, 'keep', err))} />
          </Box>
        </Box>
      )
    }
    const back = undoTarget(b)
    return (
      <Box flexDirection="column">
        {rest}
        <Box gap="sm">
          <Text wrap="truncate-end">{`✓ CoreModel: ${t.change(b.model, b.fromModel, b.level, b.from, b.why)}`}</Text>
          {b.undo ? <Button key="undo" hotkey="1" label={t.backTo(t.pair(back.model, back.level))} onPress={() => void (async () => (await current()) && undoChange($, b))().catch(err => log($, 'undo', err))} /> : null}
        </Box>
      </Box>
    )
  })
}
