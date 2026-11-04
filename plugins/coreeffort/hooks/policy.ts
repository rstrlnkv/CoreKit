// The consent rule and the words the person reads. No calls on `$` here.
import type { Level } from '../types'
import type { Pick } from './classifier'

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

const NAMES: Record<Lang, Record<Level, string>> = {
  en: { low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' },
  ru: { low: 'Низкое', medium: 'Среднее', high: 'Высокое', xhigh: 'Очень высокое', max: 'Максимальное' },
}

// The footer slot fits about 14 cells.
const SHORT: Record<Level, string> = { low: 'Low', medium: 'Medium', high: 'High', xhigh: 'XHigh', max: 'Max' }

export function texts(lang: Lang) {
  const n = (l: Level) => NAMES[lang][l]
  const ru = lang === 'ru'
  return {
    levelName: n,
    question: (l: Level, why: string) =>
      ru
        ? `Похоже, задаче нужно усилие «${n(l)}»${why ? `: ${why}` : ''}. Переключить, пока Claude не начал?`
        : `This looks like a ${n(l)} effort task${why ? `: ${why}` : ''}. Switch before Claude starts?`,
    switchTo: (l: Level) => (ru ? `Переключить на «${n(l)}»` : `Switch to ${n(l)}`),
    switchAndAuto: ru ? 'Переключить и дальше сам' : 'Switch, and auto-adjust from now',
    back: (l: Level) => (ru ? `Вернуть «${n(l)}»` : `Back to ${n(l)}`),
    keep: (now: Level | '') =>
      now ? (ru ? `Оставить «${n(now)}»` : `Keep ${n(now)}`) : ru ? 'Оставить как есть' : 'Keep it as it is',
    applied: (l: Level, from: Level | '', why: string) =>
      (ru ? `Усилие: ${n(l)}` : `Effort: ${n(l)}`) +
      (from ? (ru ? ` (было ${n(from)})` : ` (was ${n(from)})`) : '') +
      (why ? ` · ${why}` : ''),
    mark: (l: Level, from: Level | '', why: string) =>
      `${from && ORDER.indexOf(from) > ORDER.indexOf(l) ? '↓' : '↑'} ` +
      (ru ? `Усилие: ${n(l)}` : `Effort: ${n(l)}`) +
      (from ? (ru ? ` (было ${n(from)})` : ` (was ${n(from)})`) : '') +
      (why ? ` · ${why}` : ''),
    runsAt: (l: Level | '') =>
      ru ? `Чат работает на: ${l ? n(l) : 'пока неизвестно'}` : `Chat runs at: ${l ? n(l) : 'unknown yet'}`,
    inMenu: (l: Level | '') => (ru ? `в меню: ${l ? n(l) : '?'} (ваше)` : `in the menu: ${l ? n(l) : '?'} (yours)`),
    lastPick: ru ? 'Последний выбор' : 'Last pick',
    session: ru ? 'За сессию' : 'This session',
    kept: ru ? 'Оставлено как есть' : 'Kept as it was',
    release: ru ? 'Снять' : 'Release',
    noPicks: ru ? 'Пока нет выборов.' : 'No picks yet.',
    label: (l: Level) => `${ru ? 'Усилие' : 'Effort'} ${SHORT[l]}`,
    checking: ru ? 'подбираю усилие…' : 'checking effort…',
  }
}
