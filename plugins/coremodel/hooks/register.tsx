import { atom, read, update } from 'claude-code'
import type { EngineInterface, ModelCompleteResult, Register, RenderChildren } from 'claude-code'

import type { Band, Level, Mark, Stats } from '../types'
import { buildPrompt, LEVELS, parseAnswer, type Pick, toLevel } from './classifier'
import { detectModels, enabledModels, LADDER, MODELS, type ModelKey, requestModel, standIn, toModel } from './models'
import { decide, decideModel, effortOptions, type Lang, type Mode, MODES, modelOptions, settingLang, texts, uiLang } from './policy'

const PLUGIN = 'coremodel'
const band = atom({ plugin: 'coremodel', key: 'band' } as const, null)
const override = atom({ plugin: 'coremodel', key: 'override' } as const, null)
const marks = atom({ plugin: 'coremodel', key: 'marks' } as const, {})
const stats = atom({ plugin: 'coremodel', key: 'stats' } as const, null)
const failure = atom({ plugin: 'coremodel', key: 'failure' } as const, null)
const NO_STATS: Stats = { picks: { low: 0, medium: 0, high: 0, xhigh: 0, max: 0 }, kept: 0, last: null, marks: 0, models: { haiku: 0, sonnet: 0, opus: 0, fable: 0 } }
// Classifier failures in a row before the person is told: one is often a passing API hiccup.
const FAIL_SHOW = 2
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
// Models this account refused in this session: never picked again until a new session.
const unavailable = new Set<ModelKey>()
// The models the account lists in /config (the Model row), read again before every pick and at a new
// session; null when the row says nothing usable. Never stored: a model that appears later is seen.
let listed: ModelKey[] | null = null
// The menu's own effort as the last main-chat request carried it.
let asked = ''
let lastLang: Lang = 'en'
// Where the session draws: VS Code draws neither the band nor the footer, so a switch is told in a toast.
let surface = ''
// The last silent switch, for /coremodel undo after its band is gone.
let lastUndo: Band | null = null

/** Reads the /config Model row again; any failure means "no verdict" (nothing is filtered). */
async function refreshListed($: EngineInterface): Promise<void> {
  try {
    const row = (await $.config.list()).find(r => r.key === 'model')
    listed = detectModels(row?.options)
  } catch {
    listed = null
  }
}

/** The models CoreModel may pick: switched on in the settings, listed by the account, minus those that failed. */
function allowedModels(options: Readonly<Record<string, unknown>>): ModelKey[] {
  return enabledModels(options).filter(k => (listed === null || listed.includes(k)) && !unavailable.has(k))
}

/** A line in Claude Code's debug log (`claude --debug`); never in the transcript, never a file. */
async function log($: EngineInterface, what: string, err: unknown) {
  try {
    $.ui.log(`${PLUGIN}: ${what}: ${err instanceof Error ? err.message : String(err)}`, { to: 'debug' })
  } catch {
    // Nowhere left to report it.
  }
}

/** An Esc on the turn cut the classifier: the person stopped it, nothing is broken. */
class Cut extends Error {}

/** One more classifier failure in a row; the second one is told once, in a toast. */
async function failed($: EngineInterface, lang: Lang, reason: string): Promise<void> {
  let inRow = 0
  await update($, failure, cur => {
    inRow = (cur?.count ?? 0) + 1
    return { count: inRow, reason }
  })
  if (inRow === FAIL_SHOW) {
    try {
      $.ui.toast(texts(lang).classifierDown(reason))
    } catch {
      // The pane still says it.
    }
  }
}

/** The mode: what /coremodel stored wins over the setting. */
async function currentMode($: EngineInterface, options: { mode?: unknown }): Promise<Mode> {
  const stored = await $.store.get('mode')
  if (MODES.includes(stored as Mode)) return stored as Mode
  return MODES.includes(options.mode as Mode) ? (options.mode as Mode) : MODES[0]!
}

/** Switches to `level` by holding it on this chat's requests. */
async function applyLevel($: EngineInterface, level: Level, base: string): Promise<void> {
  hold = { level, base }
  await syncOverride($)
}

/** What the drawings read: the held pair, or null when nothing is held. */
async function syncOverride($: EngineInterface): Promise<void> {
  const pair = { model: modelHold?.key ?? null, level: hold?.level ?? null }
  await update($, override, () => (pair.model || pair.level ? pair : null))
}

/** Lets go of the held level: the chat runs at the menu's level again. */
async function releaseLevel($: EngineInterface): Promise<void> {
  hold = null
  // The pane reads `seen`: after a release it is the menu's level, not the one just let go.
  seen = toLevel(asked) || seen
  await syncOverride($)
}

/** Lets go of the held model: the chat runs on the person's own model again. */
async function releaseModel($: EngineInterface): Promise<void> {
  modelHold = null
  await syncOverride($)
}

/** Lets go of both parts (off, Release, a new session). */
async function releaseHold($: EngineInterface): Promise<void> {
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
  lastUndo = null
  held = fromEngine && held ? { ...held, gen } : null
  seen = toLevel(asked)
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

/**
 * Puts `b` above the prompt for BAND_MS: a silent switch with its undo, or a suggestion. VS Code draws
 * no band, so there it is said in a toast, a silent switch with the undo command.
 */
async function showBand($: EngineInterface, b: Band) {
  if (b.undo) lastUndo = b
  await update($, band, () => b)
  if (surface === 'vscode') {
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
    if (r.reason === 'aborted') throw new Cut('classifier gave no answer: aborted')
    const status = 'status' in r && r.status ? ` ${r.status}` : ''
    throw new Error(`classifier gave no answer: ${r.reason}${status}`)
  }
  const pick = parseAnswer(r.text)
  if (!pick) throw new Error(`classifier answer not readable: ${r.text.slice(0, 200)}`)
  return pick
}

/** A level named in typed text, in English or Russian; undefined when it names none. */
function typedLevel(text: string): Level | undefined {
  const x = text.trim().toLowerCase().replace(/[«»"]/g, '')
  return toLevel(x) || LEVELS.find(l => texts('en').levelName(l).toLowerCase() === x || texts('ru').levelName(l).toLowerCase() === x)
}

/** The pick for one prompt, then the switch, the question, or nothing. */
async function runPick(
  $: EngineInterface,
  options: Readonly<Record<string, unknown>>,
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
    await $.ui.status(options.pickModel !== 'off' ? t.checking : t.checkingEffort)
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
  if (await read($, failure)) await update($, failure, () => null)
  // The person may have turned the plugin off while the classifier ran.
  const stale = async () => h.gen !== gen || touched !== began || (await currentMode($, options)) === 'off'
  if (await stale()) return
  // A model the plugin may not use (the account lacks it, or its switch is off) gives way to the nearest
  // one it may use, below it first. The reason says so wherever the pick is shown: the questions, the
  // switch line, the transcript marks and the pane's last pick.
  await refreshListed($)
  const allowed = allowedModels(options)
  if (pick.model && !allowed.includes(pick.model) && options.pickModel !== 'off') {
    const sub = standIn(pick.model, allowed)
    pick = sub ? { ...pick, model: sub, why: [t.insteadOfModel(pick.model, sub), pick.why].filter(Boolean).join('; ') } : { ...pick, model: '' }
  }
  const named = pick.level === 'keep' ? null : pick.level
  // The pick is remembered as asked; the counts wait for what was applied below.
  await count($, s => (named ? { ...s, last: { level: named, why: pick.why, ...(pick.model ? { model: pick.model } : {}) } } : s))
  if (pick.level === 'keep') return keptPrompt($, false)
  const level = pick.level

  const isFirst = !(await $.session.messages()).some(m => m.role === 'assistant')
  const mAction = decideModel({ mode, pickModel: options.pickModel !== 'off', isFirst, now: nowModel, pick: pick.model, allowed })
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
    await showBand($, { id: nextBand++, ...suggestion, undo: null, suggest: true })
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
  if (parts.model || parts.level) await showBand($, { id: nextBand++, ...change, undo: parts })
}

/** A prompt left as it was: counted, and its named pick marked as not applied. */
async function keptPrompt($: EngineInterface, named: boolean): Promise<void> {
  await count($, s => ({ ...s, kept: s.kept + 1, last: named && s.last ? { ...s.last, declined: true } : s.last }))
}

/** An applied switch: the session counts and a row in the transcript. */
async function applied($: EngineInterface, change: Mark): Promise<void> {
  const modelTo = change.model ?? null
  const levelTo = change.level
  await count($, s => {
    const models = { ...NO_STATS.models!, ...s.models }
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
  touched += 1
  await update($, band, cur => (cur && cur.id === b.id ? null : cur))
  const nowModel = modelHold?.key ?? toModel(seenModel)
  let modelTo = b.model && b.model !== nowModel ? b.model : null
  if (modelTo && (await $.session.messages()).some(m => m.role === 'assistant')) {
    const t = texts(lastLang)
    const yes = t.switchToModel(modelTo)
    try {
      const answer = await $.ui.ask(t.costQuestion(modelTo, nowModel, await chatTokens($), b.why), { options: [yes, nowModel ? t.keepModel(nowModel) : t.cancel], header: t.modelHeader })
      if (answer !== yes) modelTo = null
    } catch {
      modelTo = null
    }
  }
  const nowLevel = hold?.level ?? seen
  const levelTo = b.level && b.level !== nowLevel ? b.level : null
  if (!modelTo && !levelTo) return keptPrompt($, true)
  if (modelTo) await applyModel($, modelTo, '')
  if (levelTo) await applyLevel($, levelTo, '')
  await applied($, { level: levelTo, from: levelTo ? nowLevel : '', model: modelTo, fromModel: modelTo ? nowModel : '', why: b.why, lang: b.lang })
}

/** Keep on a suggestion: nothing changes; the prompt counts as unchanged. */
async function declineSuggestion($: EngineInterface, b: Band): Promise<void> {
  await update($, band, cur => (cur && cur.id === b.id ? null : cur))
  await keptPrompt($, true)
}

/** Takes back what a silent switch changed, part by part; a part the person changed since stays. True when anything went back. */
async function undoChange($: EngineInterface, b: Band): Promise<boolean> {
  const undo = b.undo
  if (!undo) return false
  touched += 1
  let done = false
  if (undo.model && b.model && modelHold?.key === b.model) {
    if (undo.model === 'release') await releaseModel($)
    else await applyModel($, undo.model, modelHold.base)
    done = true
  }
  if (undo.level && b.level && hold?.level === b.level) {
    if (undo.level === 'release') await releaseLevel($)
    else await applyLevel($, undo.level, hold.base)
    done = true
  }
  if (lastUndo?.id === b.id) lastUndo = null
  await update($, band, cur => (cur && cur.id === b.id ? null : cur))
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
  const t = texts(lastLang)
  let text: string
  if (arg === 'auto' || arg === 'suggest') {
    await $.store.set('mode', arg)
    await $.store.set('lastMode', arg)
    // A suggestion of the other mode has no place any more.
    await update($, band, cur => (cur?.suggest && arg === 'auto' ? null : cur))
    text = t.modeSet(arg, options.pickModel !== 'off')
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
  touched += 1
  if (level) await applyLevel($, level, '')
  else await releaseHold($)
  await update($, band, () => null)
}

/**
 * A model the person presses in the pane. Mid-chat the cost question comes first;
 * the press itself is their yes, so no other question follows.
 */
async function paneModel($: EngineInterface, key: ModelKey): Promise<void> {
  touched += 1
  const nowModel = modelHold?.key ?? toModel(seenModel)
  if (key === nowModel) return
  const isEmpty = !(await $.session.messages()).some(m => m.role === 'assistant')
  if (!isEmpty) {
    const t = texts(lastLang)
    const yes = t.switchToModel(key)
    try {
      const answer = await $.ui.ask(t.costQuestion(key, nowModel, await chatTokens($), ''), { options: [yes, nowModel ? t.keepModel(nowModel) : t.cancel], header: t.modelHeader })
      if (answer !== yes) return
    } catch {
      return
    }
  }
  await applyModel($, key, '')
  await update($, band, () => null)
}

const RULE = '─'.repeat(40)
// The width of the captions in the pane's rows, in cells: the longest caption of the language, plus one,
// so every row's value starts in the same column.
const captionWidth = (t: ReturnType<typeof texts>) =>
  Math.max(...[t.thisChat, t.model, t.effort, t.thisSession, t.lastPick].map(c => c.length)) + 1

/** The language of a prompt: the setting when it names one, else the prompt's own, kept for a reload. */
async function promptLang($: EngineInterface, options: { language?: unknown }, text: string): Promise<Lang> {
  const fixed = settingLang(options.language)
  if (fixed) return fixed
  const lang = uiLang(text)
  if (lang !== lastLang) await $.store.set('lang', lang)
  return lang
}

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
    lastLang = await promptLang($, options, text)
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
    const model = modelHold ? requestModel(modelHold.key, e.model) : e.model
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
  }).catch(($, e, next) => next(e))

  // /clear, /resume and a fork start another chat in this process, and session.start does not run
  // for them; the module's own variables would carry the hold into the new chat. A compacted chat
  // is the same chat and keeps it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') await newChat($, true)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.start', async ($, e, next) => {
    surface = e.surface ?? ''
    // The language: the setting, else the last prompt's, kept across a reload.
    const stored = await $.store.get('lang')
    lastLang = settingLang(options.language) ?? settingLang(stored) ?? 'en'
    unavailable.clear()
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
    const t = texts(lastLang)
    if (arg === 'auto' || arg === 'suggest' || arg === 'off' || arg === 'on') return { text: await setMode($, options, arg) }
    if (arg === 'panel') {
      const r = await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      if (r.isPlaced) return { text: t.paneOpen }
      // The engine's reason is for the debug log; the person gets a plain sentence.
      await log($, 'pane not shown', r.reason)
      return { text: r.reason.startsWith('no-surface') ? t.paneNoSurface : t.paneWaiting }
    }
    if (arg === 'undo') {
      const b = lastUndo
      if (!b || !(await undoChange($, b))) return { text: t.nothingToUndo }
      const to = undoTarget(b)
      return { text: t.undone(t.pair(to.model, to.level)) }
    }
    if (arg === 'recheck') {
      // Models dropped after model_not_found come back, and the account's list is read again.
      unavailable.clear()
      await refreshListed($)
      $.ui.invalidate('ui.render')
      const names = allowedModels(options).map(k => MODELS[k].name)
      return { text: t.recheck(names, enabledModels(options).length, listed !== null, options.pickModel !== 'off') }
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
    const level = hold?.level ?? seen
    // pickModel off: the level only, as everywhere else.
    const pickOn = options.pickModel !== 'off'
    const model = pickOn ? (modelHold?.key ?? toModel(seenModel)) : ''
    const yours = t.pair(modelHold && pickOn ? toModel(seenModel) : '', hold ? toLevel(asked) : '')
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
    return { text: t.status(mode, pickOn, model, level, !!(hold || modelHold), yours) }
  })

  // The footer slot: the engine's own mode words, then a button that carries CoreModel's state and
  // opens and closes the pane (no chat command, so a running turn is not interrupted).
  on('ui.render', { component: 'SessionMode' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(lastLang)
    const pair = await read($, override)
    const mode = await currentMode($, options)
    // While a model or level is set, both parts are named: the part not set is what the chat last showed.
    const level = pair ? (pair.level ?? seen) : ''
    const model = pair && options.pickModel !== 'off' ? (pair.model ?? toModel(seenModel)) : ''
    const state = mode === 'off' ? t.off : t.pair(model, level)
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

  on('ui.render', { component: 'Pane', requestId: PLUGIN }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(lastLang)
    const mode = await currentMode($, options)
    const pair = await read($, override)
    const heldLevel = pair?.level ?? null
    const heldModel = pair?.model ?? null
    const isHeld = !!(heldLevel || heldModel)
    const s = await read($, stats)
    const fault = await read($, failure)
    const allowed = allowedModels(options)
    // pickModel off: effort only.
    const pickOn = options.pickModel !== 'off'
    const act = (what: string, f: () => Promise<unknown>) => () => {
      f().catch(err => log($, what, err))
    }
    // A selected button says so in its words, not by colour alone; the colour stays as a second cue.
    const mark = (label: string, isOn: boolean) => (isOn ? `● ${label}` : label)
    const nowLevel = heldLevel ?? seen
    const nowModel = pickOn ? (heldModel ?? toModel(seenModel)) : ''
    const nowPair = t.pair(nowModel, nowLevel)
    const yours = t.pair(heldModel && pickOn ? toModel(seenModel) : '', toLevel(asked))
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
          ...(pickOn && s.models ? LADDER.filter(m => s.models![m] > 0).map(m => `${MODELS[m].name} ${s.models![m]}`) : []),
          ...LEVELS.filter(l => s.picks[l] > 0).map(l => `${t.levelName(l)} ${s.picks[l]}`),
          ...(s.kept > 0 ? [t.unchanged(s.kept)] : []),
        ].join(' · ')
      : ''
    // The last pick, only when it says something the chat does not: it was not applied, or it differs.
    const last = s?.last
    const lastPair = last ? t.pair(pickOn && last.model ? last.model : '', last.level) : ''
    const showLast = !!last && (!!last.declined || last.level !== nowLevel || (pickOn && !!last.model && last.model !== nowModel))
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
          <Text dimColor>{t.modeHintFor(mode, pickOn)}</Text>
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
          {[...unavailable].map(m => (
            <Text key={`unavailable-${m}`} color="warning">{`⚠ ${t.unavailableModel(m)}`}</Text>
          ))}
        </Box>
        {pickOn && allowed.length
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
