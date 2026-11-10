import { expect, test } from 'claude-code/testing'

import type { Level } from '../types'
import * as policy from '../hooks/policy'
import { decide, decideModel, effortOptions, hostLang, LOCALES, modelOptions, settingLang, texts } from '../hooks/policy'

const pick = (level: Level | 'keep') => ({ level, model: '' as const, why: '' })

test('decide does nothing when off, without a pick, on keep, or on the same level', () => {
  expect(decide('off', 'high', pick('low'))).toBe('none')
  expect(decide('suggest', 'high', null)).toBe('none')
  expect(decide('auto', 'high', null)).toBe('none')
  expect(decide('suggest', 'high', pick('keep'))).toBe('none')
  expect(decide('auto', 'high', pick('high'))).toBe('none')
})

test('suggest offers every different level, never asks', () => {
  for (const l of ['low', 'medium', 'high', 'xhigh', 'max'] as const) {
    expect(decide('suggest', l === 'medium' ? 'high' : 'medium', pick(l))).toBe('suggest')
  }
})

test('auto applies switches among low, medium and high, both ways, and from xhigh or max down', () => {
  const cases: [Level | '', Level][] = [
    ['medium', 'low'], ['low', 'medium'], ['low', 'high'], ['high', 'medium'],
    ['xhigh', 'high'], ['max', 'low'], ['', 'medium'],
  ]
  for (const [now, to] of cases) expect(decide('auto', now, pick(to))).toBe('apply')
})

test('auto asks before xhigh and max', () => {
  expect(decide('auto', 'high', pick('xhigh'))).toBe('ask')
  expect(decide('auto', 'low', pick('max'))).toBe('ask')
  expect(decide('auto', '', pick('xhigh'))).toBe('ask')
  expect(decide('auto', 'xhigh', pick('max'))).toBe('ask')
})

test('hostLang is ru only when the host setting names Russian', () => {
  for (const v of ['russian', 'Russian', 'RU', ' ru ', 'ru-RU', 'ru_RU.UTF-8', 'русский']) expect(hostLang(v)).toBe('ru')
  for (const v of ['ukrainian', 'uk', 'українська', 'bulgarian', 'japanese', 'english', 'en', 'rust', '', undefined, null, 42]) expect(hostLang(v)).toBe('en')
})

// No function decides the language by the text of a prompt: Cyrillic is not Russian.
test('policy has no language-by-text rule', () => {
  expect('uiLang' in policy).toBe(false)
})

/** Every key of a locale with the type of its value, nested objects by path: `level.low string`. */
function shape(x: object, at = ''): string[] {
  return Object.entries(x).flatMap(([k, v]) =>
    v && typeof v === 'object' && Object.getPrototypeOf(v) === Object.prototype ? shape(v, `${at}${k}.`) : [`${at}${k} ${typeof v}`],
  )
}

test('every locale has exactly the keys of en, with the same value types', () => {
  const en = shape(texts('en'))
  for (const lang of Object.keys(LOCALES) as (keyof typeof LOCALES)[]) {
    const other = shape(texts(lang))
    // Each list names the keys one locale has and the other lacks, so a failure says which key.
    expect({ lang, missing: en.filter(k => !other.includes(k)), extra: other.filter(k => !en.includes(k)) }).toEqual({ lang, missing: [], extra: [] })
  }
})

test('the language setting names a locale, never a name every object has', () => {
  for (const v of ['toString', 'constructor', 'de', '', 'auto', undefined, null, 42]) expect(settingLang(v)).toBe(null)
  expect(settingLang('en')).toBe('en')
  expect(settingLang('ru')).toBe('ru')
})

test('each locale but English says which host language names it; English is the fallback', () => {
  expect(LOCALES.en.hostNames).toBe(null)
  expect(LOCALES.ru.hostNames instanceof RegExp).toBe(true)
})

test('texts name the level in each language', () => {
  expect(texts('en').levelOption('high', true)).toBe('High (recommended)')
  expect(texts('ru').levelOption('high', true)).toBe('Высокое (советую)')
  expect(texts('ru').keepModel('sonnet')).toBe('Оставить Sonnet')
  expect(texts('ru').keepLevel('medium')).toBe('Оставить «Среднее»')
  expect(texts('en').change(null, '', 'high', 'medium', 'auth bug')).toBe('Effort High (was Medium) · auth bug')
  expect(texts('en').change('opus', 'sonnet', 'high', 'medium', '')).toBe('Opus · High (was Sonnet · Medium)')
  expect(texts('en').change('opus', 'sonnet', null, '', '')).toBe('Opus (was Sonnet)')
})

test('the effort question says an Extra high, a High', () => {
  expect(texts('en').question('xhigh', 'x')).toContain('an Extra high effort task')
  expect(texts('en').question('high', 'x')).toContain('a High effort task')
  expect(texts('en').question('max', 'x')).toContain('a Max effort task')
})

test('back names what to go back to', () => {
  expect(texts('en').backTo(texts('en').pair('', 'low'))).toBe('Back to Low')
  expect(texts('ru').backTo(texts('ru').pair('sonnet', 'low'))).toBe('Вернуть Sonnet · Низкое')
})

test('mark points up or down by level and says it in its language', () => {
  expect(texts('en').markPair(null, '', 'high', 'low', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').markPair(null, '', 'low', 'high', 'x').startsWith('↓')).toBe(true)
  expect(texts('en').markPair(null, '', 'medium', '', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').markPair(null, '', 'high', 'low', 'auth bug').includes('Effort High (was Low) · auth bug')).toBe(true)
  expect(texts('ru').markPair(null, '', 'high', 'low', 'x').includes('Усилие')).toBe(true)
})

test('the mode question ends as a question', () => {
  expect(texts('en').modeQuestionFor('auto', 'opus', 'high').endsWith('?')).toBe(true)
  expect(texts('ru').modeQuestionFor('auto', '', '').endsWith('?')).toBe(true)
})

test('decideModel follows the rules', () => {
  const base = { mode: 'auto' as const, pickModel: true, isFirst: true, now: 'sonnet' as const, pick: 'opus' as const, allowed: ['haiku', 'sonnet', 'opus', 'fable'] as const }
  expect(decideModel(base)).toBe('apply')
  expect(decideModel({ ...base, mode: 'suggest' })).toBe('suggest')
  expect(decideModel({ ...base, mode: 'suggest', isFirst: false, pick: 'haiku' })).toBe('none')
  expect(decideModel({ ...base, pick: 'fable' })).toBe('ask')
  expect(decideModel({ ...base, isFirst: false })).toBe('ask')
  expect(decideModel({ ...base, isFirst: false, pick: 'haiku' })).toBe('none')
  expect(decideModel({ ...base, isFirst: false, now: '' })).toBe('none')
  expect(decideModel({ ...base, pick: '' })).toBe('none')
  expect(decideModel({ ...base, pick: 'sonnet' })).toBe('none')
  expect(decideModel({ ...base, pickModel: false })).toBe('none')
  expect(decideModel({ ...base, allowed: ['sonnet'] })).toBe('none')
  expect(decideModel({ ...base, mode: 'off' })).toBe('none')
})

test('options put the pick first, then the current, then the nearest', () => {
  expect(modelOptions('opus', 'sonnet', ['haiku', 'sonnet', 'opus', 'fable'])).toEqual(['opus', 'sonnet', 'fable', 'haiku'])
  expect(modelOptions('opus', '', ['sonnet', 'opus'])).toEqual(['opus', 'sonnet'])
  expect(effortOptions('high', 'medium')).toEqual(['high', 'medium', 'xhigh', 'low'])
  expect(effortOptions('low', '')).toEqual(['low', 'medium', 'high', 'xhigh'])
})


test('the cost question names the lasting price, then the one-off re-read, then the reason', () => {
  const en = texts('en').costQuestion('opus', 'sonnet', 100_000, 'many files')
  expect(en).toBe('Switch to Opus? From now on each reply costs about 2× Sonnet. Switching also re-reads this chat once: ≈ 100k tokens, about $0.50 at API prices (on a subscription it counts toward your limits). Because: many files.')
  const ru = texts('ru').costQuestion('opus', 'sonnet', 100_000, 'много файлов')
  expect(ru).toContain('Перейти на Opus?')
  expect(ru).toContain('примерно 2× от цены на Sonnet')
  expect(ru).toContain('≈ 100 тыс. токенов, около $0,50')
  expect(ru).toContain('Причина: много файлов.')
  expect(texts('en').costQuestion('fable', 'opus', undefined, '')).toContain('about 2.5× Opus')
  expect(texts('en').costQuestion('sonnet', 'opus', undefined, '')).toContain('about 1/2 of Opus, after this chat is re-read once')
  expect(texts('en').costQuestion('haiku', 'sonnet', 50_000, '')).toContain('< $0.01')
  expect(texts('en').costQuestion('opus', '', undefined, '')).toBe('Switch to Opus? Switching also re-reads this chat once, which costs tokens.')
  expect(texts('en').firstModel('opus', 'many files')).toBe('This looks like work for Opus: many files. Switch the model?')
})
