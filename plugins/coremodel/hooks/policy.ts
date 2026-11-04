// The consent rule and the words the person reads. No calls on `$` here.
import type { Level } from '../types'
import type { Pick } from './classifier'
import { LADDER, MODELS, type ModelKey, stronger } from './models'

export type Mode = 'suggest' | 'auto' | 'off'
export type Lang = 'ru' | 'en'

/** Levels the plugin never switches to without the person's yes (spec E6). */
const ASK_FIRST: readonly Level[] = ['xhigh', 'max']

/** What to do with a pick: nothing, switch now, or ask first. */
export function decide(mode: Mode, now: Level | '', pick: Pick | null): 'none' | 'apply' | 'ask' {
  if (mode === 'off' || !pick || pick.level === 'keep' || pick.level === now) return 'none'
  if (mode === 'suggest' || ASK_FIRST.includes(pick.level)) return 'ask'
  return 'apply'
}

/**
 * Russian when the text holds a Cyrillic word of three letters or more: a Russian prompt is often
 * mostly Latin code names, while an English one carries no Cyrillic at all.
 */
export function uiLang(text: string): Lang {
  return /[Ѐ-ӿ]{3,}/.test(text) ? 'ru' : 'en'
}

const ORDER: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

/** What to do with the model part of a pick (spec §4.2, M4, M6). */
export function decideModel(i: {
  mode: Mode
  pickModel: boolean
  isFirst: boolean
  now: ModelKey | ''
  pick: ModelKey | ''
  allowed: readonly ModelKey[]
}): 'none' | 'apply' | 'ask' {
  if (i.mode === 'off' || !i.pickModel || !i.pick || !i.allowed.includes(i.pick) || i.pick === i.now) return 'none'
  // Mid-chat a switch re-reads the whole chat: only a stronger model, and only with a question.
  if (!i.isFirst && !stronger(i.pick, i.now)) return 'none'
  if (i.mode === 'suggest' || i.pick === 'fable' || !i.isFirst) return 'ask'
  return 'apply'
}

/** The pick, then the current, then the nearest others by distance (cheaper first on a tie); at most four. */
function nearest<T>(order: readonly T[], pick: T, now: T | '', allowed: readonly T[]): T[] {
  const out: T[] = [pick]
  if (now !== '' && now !== pick && allowed.includes(now as T)) out.push(now as T)
  const at = order.indexOf(pick)
  const rest = allowed
    .filter(x => !out.includes(x))
    .sort((a, b) => Math.abs(order.indexOf(a) - at) - Math.abs(order.indexOf(b) - at) || order.indexOf(a) - order.indexOf(b))
  return [...out, ...rest].slice(0, 4)
}

/**
 * The models the question offers. The current one is always among them, listed or not. Mid-chat
 * only the pick and the current: a weaker model never pays back the re-read, and the cost line
 * fits the pick alone (spec M4, M5).
 */
export function modelOptions(pick: ModelKey, now: ModelKey | '', allowed: readonly ModelKey[], isFirst = true): ModelKey[] {
  if (!isFirst) return now ? [pick, now] : [pick]
  return nearest(LADDER, pick, now, now && !allowed.includes(now) ? [...allowed, now] : allowed)
}

/** Levels that cost the most: a question about them never has its pick under Enter. */
export function isCostlyLevel(l: Level): boolean {
  return ASK_FIRST.includes(l)
}

/**
 * The options with `keep` moved to the top when `when` holds. A question can pop up while the
 * person types the next message and their Enter takes the first option: for a costly pick that
 * must be the safe one. Without `keep` among the options nothing moves.
 */
export function keepFirst<T>(opts: readonly T[], keep: T, when: boolean): T[] {
  if (!when || !opts.includes(keep)) return [...opts]
  return [keep, ...opts.filter(o => o !== keep)]
}

export function effortOptions(pick: Level, now: Level | ''): Level[] {
  return nearest(ORDER, pick, now, ORDER)
}

const NAMES: Record<Lang, Record<Level, string>> = {
  en: { low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' },
  ru: { low: 'Низкое', medium: 'Среднее', high: 'Высокое', xhigh: 'Очень высокое', max: 'Максимальное' },
}

const MODE_NAMES: Record<Lang, Record<Mode, string>> = {
  en: { suggest: 'Suggest', auto: 'Auto', off: 'Off' },
  ru: { suggest: 'Подсказывать', auto: 'Сам', off: 'Выкл' },
}

// One line under the mode buttons: what the chosen mode does.
const MODE_HINTS: Record<Lang, Record<Mode, string>> = {
  en: {
    suggest: 'Asks before every switch',
    auto: 'Switches by itself, asks before Fable, Extra high, Max and a model change mid-chat',
    off: 'Changes nothing',
  },
  ru: {
    suggest: 'Спрашивает перед каждой сменой',
    auto: 'Меняет сам, спрашивает перед Fable, Очень высоким, Максимальным и сменой модели посреди чата',
    off: 'Ничего не меняет',
  },
}

// auto with pickModel off: effort only.
const AUTO_EFFORT_HINT: Record<Lang, string> = {
  en: 'Changes the level by itself, asks before Extra high and Max',
  ru: 'Меняет уровень сам, спрашивает перед Очень высоким и Максимальным',
}

// The footer slot fits about 14 cells.
const SHORT: Record<Level, string> = { low: 'Low', medium: 'Medium', high: 'High', xhigh: 'XHigh', max: 'Max' }

export function texts(lang: Lang) {
  const n = (l: Level) => NAMES[lang][l]
  const ru = lang === 'ru'
  const back = (l: Level) => (ru ? `Вернуть «${n(l)}»` : `Back to ${n(l)}`)
  const applied = (l: Level, from: Level | '', why: string) =>
    (ru ? `Усилие: ${n(l)}` : `Effort: ${n(l)}`) + (from ? (ru ? ` (было ${n(from)})` : ` (was ${n(from)})`) : '') + (why ? ` · ${why}` : '')
  const markLevel = (l: Level, from: Level | '', why: string) => `${from && ORDER.indexOf(from) > ORDER.indexOf(l) ? '↓' : '↑'} ${applied(l, from, why)}`
  return {
    levelName: n,
    question: (l: Level, why: string) =>
      ru
        ? `Похоже, задаче нужно усилие «${n(l)}»${why ? `: ${why}` : ''}. Переключить, пока Claude не начал?`
        : `This looks like ${l === 'xhigh' ? 'an' : 'a'} ${n(l)} effort task${why ? `: ${why}` : ''}. Switch before Claude starts?`,
    effortHeader: ru ? 'Усилие' : 'Effort',
    levelOption: (l: Level, recommended: boolean) => `${n(l)}${recommended ? (ru ? ' (советую)' : ' (recommended)') : ''}`,
    modelHeader: ru ? 'Модель' : 'Model',
    modelOption: (m: ModelKey, recommended: boolean) => `${MODELS[m].name}${recommended ? (ru ? ' (советую)' : ' (recommended)') : ''}`,
    keepCurrent: ru ? 'Оставить текущую модель' : 'Keep the current model',
    keepModel: (m: ModelKey) => (ru ? `Оставить ${MODELS[m].name}` : `Keep ${MODELS[m].name}`),
    modelQuestion: (to: ModelKey, usd: number | null, tokens: number | undefined, isFirst: boolean, why: string) => {
      const name = MODELS[to].name
      if (isFirst) return ru ? `Похоже, это работа для ${name}${why ? `: ${why}` : ''}. Сменить модель?` : `This looks like work for ${name}${why ? `: ${why}` : ''}. Switch the model?`
      // Mid-chat the new model reads the whole chat again, once: say why, and what that costs.
      const head = ru ? `Перейти на ${name}${why ? ` (${why})` : ''}?` : `Switch to ${name}${why ? ` (${why})` : ''}?`
      if (usd === null || !tokens) return ru ? `${head} Чат один раз перечитается заново, это стоит токенов.` : `${head} The chat is read again once, which costs tokens.`
      const k = Math.max(1, Math.round(tokens / 1000))
      const money = usd < 0.01 ? '< $0.01' : `$${usd.toFixed(2)}`
      return ru
        ? `${head} Чат один раз перечитается заново: ≈ ${k} тыс. токенов, около ${money.replace('.', ',')} по ценам API.`
        : `${head} The chat is read again once: ≈ ${k}k tokens, about ${money} at API prices.`
    },
    back,
    keep: (now: Level | '') =>
      now ? (ru ? `Оставить «${n(now)}»` : `Keep ${n(now)}`) : ru ? 'Оставить как есть' : 'Keep it as it is',
    applied,
    mark: markLevel,
    inMenu: (l: Level | '') => (ru ? `в меню: ${l ? n(l) : '?'} (ваше)` : `in the menu: ${l ? n(l) : '?'} (yours)`),
    modeQuestion: (mode: Mode, l: Level | '') =>
      ru
        ? `CoreModel: ${mode}. Чат работает на: ${l ? n(l) : 'пока неизвестно'}. Какой режим?`
        : `CoreModel: ${mode}. Chat runs at: ${l ? n(l) : 'unknown yet'}. Which mode?`,
    now: ru ? 'Сейчас в чате' : 'Now in the chat',
    paneModel: ru ? 'Модель' : 'Model',
    paneLevel: ru ? 'Уровень' : 'Level',
    pickApplied: ru ? 'применён' : 'applied',
    nowPair: (m: ModelKey | '', l: Level | '') =>
      [m ? MODELS[m].name : '', l ? n(l) : ''].filter(Boolean).join(' · ') || (ru ? 'пока неизвестно' : 'unknown yet'),
    heldBy: ru ? 'держит CoreModel' : 'held by CoreModel',
    mode: ru ? 'Режим' : 'Mode',
    modeName: (m: Mode) => MODE_NAMES[lang][m],
    modeHint: (m: Mode, pickModel: boolean) => (m === 'auto' && !pickModel ? AUTO_EFFORT_HINT[lang] : MODE_HINTS[lang][m]),
    lastPick: ru ? 'Последний выбор' : 'Last pick',
    notApplied: ru ? 'не применён' : 'not applied',
    unknownModels: (words: string[]) =>
      ru
        ? `В настройке models неизвестно: ${words.map(w => `«${w}»`).join(', ')} (нужно haiku, sonnet, opus, fable)`
        : `In the models setting, unknown: ${words.map(w => `"${w}"`).join(', ')} (use haiku, sonnet, opus, fable)`,
    modeSet: (mode: 'auto' | 'suggest', pickModel: boolean) => {
      if (mode === 'suggest') return 'Mode: suggest. Every switch asks first.'
      return pickModel
        ? 'Mode: auto. Switches by itself; asks before Fable, Extra high, Max and a model change mid-chat.'
        : 'Mode: auto. Switches the level by itself; asks before Extra high and Max.'
    },
    session: ru ? 'За сессию' : 'This session',
    kept: (k: number) => (ru ? `Уровень не меняли: ${k}` : `Left as it was: ${k}`),
    release: ru ? 'Вернуть как в меню' : "Back to the menu's choice",
    noPicks: ru ? 'Пока нет выборов.' : 'No picks yet.',
    label: (l: Level) => `${ru ? 'Усилие' : 'Effort'} ${SHORT[l]}`,
    // The pair (spec §7). With no model part each falls back to the effort-only text above.
    change: (m: ModelKey | null | undefined, fromM: ModelKey | '' | undefined, l: Level | null, fromL: Level | '', why: string) => {
      if (!m && l) return applied(l, fromL, why)
      const was = [fromM ? MODELS[fromM].name : '', l && fromL ? n(fromL) : ''].filter(Boolean).join(' · ')
      const now = m ? (l ? `${MODELS[m].name} · ${n(l)}` : `${ru ? 'Модель' : 'Model'}: ${MODELS[m].name}`) : ''
      return now + (was ? (ru ? ` (было ${was})` : ` (was ${was})`) : '') + (why ? ` · ${why}` : '')
    },
    markPair: (m: ModelKey | null | undefined, fromM: ModelKey | '' | undefined, l: Level | null, fromL: Level | '', why: string) => {
      if (!m && l) return markLevel(l, fromL, why)
      const down = m && fromM ? LADDER.indexOf(fromM) > LADDER.indexOf(m) : !!(l && fromL && ORDER.indexOf(fromL) > ORDER.indexOf(l))
      return `${down ? '↓' : '↑'} ${texts(lang).change(m, fromM, l, fromL, why)}`
    },
    backPair: (m: ModelKey | '' | undefined, l: Level | '' | undefined) =>
      m && l ? (ru ? `Вернуть ${MODELS[m].name} · ${n(l)}` : `Back to ${MODELS[m].name} · ${n(l)}`) : m ? (ru ? `Вернуть ${MODELS[m].name}` : `Back to ${MODELS[m].name}`) : l ? back(l) : '',
    pairLabel: (m: ModelKey | null, l: Level | null) => (m && l ? `${MODELS[m].name} · ${SHORT[l]}` : m ? MODELS[m].name : l ? `${ru ? 'Усилие' : 'Effort'} ${SHORT[l]}` : ''),
    pairSuffix: (m: ModelKey | null, l: Level | null) => [m ? MODELS[m].name : '', l ? n(l) : ''].filter(Boolean).join(' · '),
    inMenuPair: (m: ModelKey | '', l: Level | '') => {
      const what = [m ? MODELS[m].name : '?', l ? n(l) : ''].filter(Boolean).join(' · ')
      return ru ? `в меню: ${what} (ваше)` : `in the menu: ${what} (yours)`
    },
    switchModel: (m: ModelKey) => (ru ? `Перейти на ${MODELS[m].name}` : `Switch to ${MODELS[m].name}`),
    cancel: ru ? 'Отмена' : 'Cancel',
    unavailable: (m: ModelKey) =>
      ru ? `Модель ${MODELS[m].name} недоступна — уберите её из настройки models` : `${MODELS[m].name} is not available — remove it from the models setting`,
    checking: ru ? 'подбираю усилие…' : 'checking effort…',
  }
}
