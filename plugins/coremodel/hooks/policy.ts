// The consent rule and the words the person reads. No calls on `$` here.
import type { Lang, Level } from '../types'
import { LEVELS, type Pick } from './classifier'
import { en, type Strings } from './locales/en'
import { ru } from './locales/ru'
import { LADDER, MODELS, type ModelKey, stronger, switchUsd } from './models'

export type Mode = 'suggest' | 'auto' | 'off'

/** Every locale, English first. A new one is added here, in Lang (types/index.d.ts) and in the manifest's `language` options. */
export const LOCALES: Record<Lang, Strings> = { en, ru }

/** The modes in the one order every surface shows them; the first is the default. */
export const MODES: readonly Mode[] = ['auto', 'suggest', 'off']

/**
 * What to do with one part of a pick: nothing, switch now (Auto, with an undo), ask first (Auto,
 * a dialog before Claude starts), or suggest (Suggest: a band, never a dialog).
 */
export type Action = 'none' | 'apply' | 'ask' | 'suggest'

/** Levels the plugin never switches to without the person's yes: they cost the most. */
const ASK_FIRST: readonly Level[] = ['xhigh', 'max']

/** What to do with the effort part of a pick. */
export function decide(mode: Mode, now: Level | '', pick: Pick | null): Action {
  if (mode === 'off' || !pick || pick.level === 'keep' || pick.level === now) return 'none'
  if (mode === 'suggest') return 'suggest'
  return ASK_FIRST.includes(pick.level) ? 'ask' : 'apply'
}

/**
 * Claude Code's own `language` setting (free text: "russian", "Russian", "ru", "ru-RU", "русский")
 * as a language of ours: the first locale whose `hostNames` matches it, English for any other or
 * none. The text of a prompt never decides: Cyrillic letters are also Ukrainian, Bulgarian, Serbian
 * or Kazakh.
 */
export function hostLang(v: unknown): Lang {
  if (typeof v !== 'string') return 'en'
  const x = v.trim().toLowerCase()
  for (const [lang, s] of Object.entries(LOCALES) as [Lang, Strings][]) if (s.hostNames?.test(x)) return lang
  return 'en'
}

/** What to do with the model part of a pick. */
export function decideModel(i: {
  mode: Mode
  pickModel: boolean
  isFirst: boolean
  now: ModelKey | ''
  pick: ModelKey | ''
  allowed: readonly ModelKey[]
}): Action {
  if (i.mode === 'off' || !i.pickModel || !i.pick || !i.allowed.includes(i.pick) || i.pick === i.now) return 'none'
  // A model of no known family (a gateway's own name) is the person's choice: never switched or asked about.
  if (!i.now) return 'none'
  // Mid-chat a switch re-reads the whole chat: only a stronger model, and only with a question.
  if (!i.isFirst && !stronger(i.pick, i.now)) return 'none'
  if (i.mode === 'suggest') return 'suggest'
  return i.pick === 'fable' || !i.isFirst ? 'ask' : 'apply'
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
 * fits the pick alone.
 */
export function modelOptions(pick: ModelKey, now: ModelKey | '', allowed: readonly ModelKey[], isFirst = true): ModelKey[] {
  if (!isFirst) return now ? [pick, now] : [pick]
  return nearest(LADDER, pick, now, now && !allowed.includes(now) ? [...allowed, now] : allowed)
}

export function effortOptions(pick: Level, now: Level | ''): Level[] {
  return nearest(LEVELS, pick, now, LEVELS)
}

/** The plugin's own `language` setting when it names a language of ours; null for `auto` or anything else. */
export function settingLang(v: unknown): Lang | null {
  // An own key only: `v in LOCALES` would also take 'toString'.
  return typeof v === 'string' && Object.prototype.hasOwnProperty.call(LOCALES, v) ? (v as Lang) : null
}

const fmt = (x: number) => String(Math.round(x * 10) / 10)

/**
 * The words in `lang`: the locale table, and the phrases built from it the same way in every language
 * (a pair is "Opus · High", a change names what was before it, a row points up or down).
 */
export function texts(lang: Lang) {
  const s = LOCALES[lang]
  const n = (l: Level) => s.level[l]
  const name = (m: ModelKey) => MODELS[m].name
  const pair = (m: ModelKey | '' | null | undefined, l: Level | '' | null | undefined) => [m ? name(m) : '', l ? n(l) : ''].filter(Boolean).join(' · ')
  /** "Opus · High (was Sonnet · Medium) · why"; the effort alone: "Effort High (was Medium) · why". */
  const change = (m: ModelKey | null | undefined, fromM: ModelKey | '' | undefined, l: Level | null, fromL: Level | '', why: string) => {
    const now = m ? pair(m, l) : l ? `${s.effortWord} ${n(l)}` : ''
    const was = m ? pair(fromM, l ? fromL : '') : fromL ? n(fromL) : ''
    return now + (was ? ` (${s.was(was)})` : '') + (why ? ` · ${why}` : '')
  }
  /** The mode's hint; Auto says less when CoreModel picks the effort only. */
  const modeHint = (mode: Mode, pickModel: boolean) => (mode === 'auto' && !pickModel ? s.autoEffortHint : s.modeHint[mode])
  return {
    ...s,
    levelName: n,
    modeName: (m: Mode) => s.mode[m],
    modeHintFor: modeHint,
    pair,
    change,
    /** A transcript row: an arrow up or down, then the change. */
    markPair: (m: ModelKey | null | undefined, fromM: ModelKey | '' | undefined, l: Level | null, fromL: Level | '', why: string) => {
      const down = m && fromM ? LADDER.indexOf(fromM) > LADDER.indexOf(m) : !!(l && fromL && LEVELS.indexOf(fromL) > LEVELS.indexOf(l))
      return `${down ? '↓' : '↑'} ${change(m, fromM, l, fromL, why)}`
    },
    question: (l: Level, why: string) => s.effortQuestion(n(l), l === 'xhigh', why),
    levelOption: (l: Level, recommended: boolean) => (recommended ? s.recommended(n(l)) : n(l)),
    modelOption: (m: ModelKey, recommended: boolean) => (recommended ? s.recommended(name(m)) : name(m)),
    keepLevel: (now: Level) => s.keepLevel(n(now)),
    keepModel: (m: ModelKey) => s.keep(name(m)),
    switchToModel: (m: ModelKey) => s.switchTo(name(m)),
    firstModel: (to: ModelKey, why: string) => s.firstModelQuestion(name(to), why),
    /**
     * A switch mid-chat: the lasting price per reply first (by the input price of the two models),
     * then the one-off re-read of the chat, then the reason.
     */
    costQuestion: (to: ModelKey, from: ModelKey | '', tokens: number | undefined, why: string) => {
      const parts = [s.costHead(name(to))]
      if (from && from !== to) {
        const r = MODELS[to].input / MODELS[from].input
        if (r > 1) parts.push(s.costMore(fmt(r), name(from)))
        else if (r < 1) parts.push(s.costLess(fmt(1 / r), name(from)))
      }
      const usd = switchUsd(tokens, to)
      if (usd === null || !tokens) parts.push(s.reread)
      else parts.push(s.rereadSized(Math.max(1, Math.round(tokens / 1000)), usd < 0.01 ? '< $0.01' : `$${usd.toFixed(2)}`))
      if (why) parts.push(s.because(why))
      return parts.join(' ')
    },
    insteadOfModel: (from: ModelKey, to: ModelKey) => s.insteadOf(name(from), name(to)),
    unavailableModel: (m: ModelKey) => s.unavailable(name(m)),
    modeQuestionFor: (mode: Mode, m: ModelKey | '', l: Level | '') => s.modeQuestion(s.mode[mode], pair(m, l) || s.unknownPair),
    modeSet: (mode: Mode, pickModel: boolean) => s.modeIs(s.mode[mode], modeHint(mode, pickModel)),
    modeOnFor: (mode: Mode) => s.modeOn(s.mode[mode]),
    /** The /coremodel reply: the mode, what the chat runs at, the commands. */
    status: (mode: Mode, pickModel: boolean, m: ModelKey | '', l: Level | '', held: boolean, yours: string) =>
      [
        s.modeIs(s.mode[mode], modeHint(mode, pickModel)),
        held ? s.chatIsSet(pair(m, l) || s.unknownPair, yours) : s.chatIs(pair(m, l) || s.unknownPair),
        s.commands,
      ].join('\n'),
    /** /coremodel recheck: what CoreModel may pick now. `usable` is false when the account's list could not be used. */
    recheck: (names: string[], enabled: number, usable: boolean, pickModel: boolean) => {
      if (!pickModel) return s.recheckEffortOnly
      if (!enabled) return s.recheckAllOff
      if (!names.length) return s.recheckNone
      return s.recheckModels(names.join(', ')) + (usable ? '' : s.recheckUnfiltered)
    },
  }
}
