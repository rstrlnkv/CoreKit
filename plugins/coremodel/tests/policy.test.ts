import { expect, test } from 'claude-code/testing'

import type { Level } from '../types'
import { decide, decideModel, effortOptions, modelOptions, texts, uiLang } from '../hooks/policy'

const pick = (level: Level | 'keep') => ({ level, why: '' })

test('decide does nothing when off, without a pick, on keep, or on the same level', () => {
  expect(decide('off', 'high', pick('low'))).toBe('none')
  expect(decide('suggest', 'high', null)).toBe('none')
  expect(decide('auto', 'high', null)).toBe('none')
  expect(decide('suggest', 'high', pick('keep'))).toBe('none')
  expect(decide('auto', 'high', pick('high'))).toBe('none')
})

test('suggest asks on every different level', () => {
  for (const l of ['low', 'medium', 'high', 'xhigh', 'max'] as const) {
    expect(decide('suggest', l === 'medium' ? 'high' : 'medium', pick(l))).toBe('ask')
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

test('uiLang is ru when most letters are Cyrillic', () => {
  expect(uiLang('почини авторизацию')).toBe('ru')
  expect(uiLang('почини loginController в auth.ts')).toBe('ru')
  expect(uiLang('fix the login')).toBe('en')
  expect(uiLang('123 ???')).toBe('en')
})

test('texts name the level in each language', () => {
  expect(texts('en').levelOption('high', true)).toBe('High (recommended)')
  expect(texts('ru').levelOption('high', true)).toBe('Высокое (советую)')
  expect(texts('ru').keepModel('sonnet')).toBe('Оставить Sonnet')
  const line = texts('en').applied('high', 'medium', 'auth bug')
  for (const w of ['High', 'Medium', 'auth bug']) expect(line.includes(w)).toBe(true)
})

test('the effort question says an Extra high, a High', () => {
  expect(texts('en').question('xhigh', 'x')).toContain('an Extra high effort task')
  expect(texts('en').question('high', 'x')).toContain('a High effort task')
  expect(texts('en').question('max', 'x')).toContain('a Max effort task')
})

test('back names the level to go back to', () => {
  expect(texts('en').back('low').includes('Low')).toBe(true)
  expect(texts('ru').back('low').includes('Низкое')).toBe(true)
})

test('mark points up or down by level and says it in the prompt language', () => {
  expect(texts('en').markPair(null, '', 'high', 'low', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').markPair(null, '', 'low', 'high', 'x').startsWith('↓')).toBe(true)
  expect(texts('en').markPair(null, '', 'medium', '', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').markPair(null, '', 'high', 'low', 'auth bug').includes('Effort: High (was Low) · auth bug')).toBe(true)
  expect(texts('ru').markPair(null, '', 'high', 'low', 'x').includes('Усилие')).toBe(true)
})

test('the mode question ends as a question', () => {
  expect(texts('en').modeQuestion('auto', 'opus', 'high').endsWith('?')).toBe(true)
  expect(texts('ru').modeQuestion('auto', '', '').endsWith('?')).toBe(true)
})

test('decideModel follows the spec rules', () => {
  const base = { mode: 'auto' as const, pickModel: true, isFirst: true, now: 'sonnet' as const, pick: 'opus' as const, allowed: ['haiku', 'sonnet', 'opus', 'fable'] as const }
  expect(decideModel(base)).toBe('apply')
  expect(decideModel({ ...base, mode: 'suggest' })).toBe('ask')
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


test('the model question names the reason and the one-time cost in the prompt language', () => {
  const ru = texts('ru').modelQuestion('opus', 0.5, 100_000, false, 'много файлов')
  expect(ru).toContain('Перейти на Opus (много файлов)?')
  expect(ru).toContain('Чат один раз перечитается заново: ≈ 100 тыс. токенов, около $0,50')
  const en = texts('en').modelQuestion('opus', 0.5, 100_000, false, 'many files')
  expect(en).toContain('Switch to Opus (many files)?')
  expect(en).toContain('The chat is read again once: ≈ 100k tokens, about $0.50 at API prices.')
  // No "ordinary replies" figure and no claim that replies get cheap: a stronger model costs more per reply.
  for (const t of [ru, en]) expect(/replies|ответ|cheap|дешёв/.test(t)).toBe(false)
  expect(texts('en').modelQuestion('haiku', 0.004, 100_000, false, '')).toContain('< $0.01')
  expect(texts('en').modelQuestion('opus', null, undefined, false, '')).toContain('read again once, which costs tokens')
  expect(texts('en').modelQuestion('opus', null, undefined, true, 'many files')).toContain('Opus')
})
