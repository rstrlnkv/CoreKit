import { expect, test } from 'claude-code/testing'

import type { Level } from '../types'
import { decide, decideModel, effortOptions, isCostlyLevel, keepFirst, modelOptions, texts, uiLang } from '../hooks/policy'

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
  expect(texts('en').label('xhigh')).toBe('Effort XHigh')
  expect(texts('ru').label('high')).toBe('Усилие High')
})

test('back names the level to go back to', () => {
  expect(texts('en').back('low').includes('Low')).toBe(true)
  expect(texts('ru').back('low').includes('Низкое')).toBe(true)
})

test('mark points up or down by level and says it in the prompt language', () => {
  expect(texts('en').mark('high', 'low', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').mark('low', 'high', 'x').startsWith('↓')).toBe(true)
  expect(texts('en').mark('medium', '', 'x').startsWith('↑')).toBe(true)
  expect(texts('en').mark('high', 'low', 'auth bug').includes('Effort: High (was Low) · auth bug')).toBe(true)
  expect(texts('ru').mark('high', 'low', 'x').includes('Усилие')).toBe(true)
})

test('the mode question ends as a question', () => {
  expect(texts('en').modeQuestion('auto', 'high').endsWith('?')).toBe(true)
  expect(texts('ru').modeQuestion('auto', '').endsWith('?')).toBe(true)
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

test('keepFirst moves Keep to the top only for a costly pick', () => {
  expect(keepFirst(['fable', 'sonnet', 'opus'], 'sonnet', true)).toEqual(['sonnet', 'fable', 'opus'])
  expect(keepFirst(['opus', 'sonnet'], 'sonnet', false)).toEqual(['opus', 'sonnet'])
  expect(keepFirst(['opus', 'haiku'], 'sonnet', true)).toEqual(['opus', 'haiku'])
  expect(isCostlyLevel('xhigh')).toBe(true)
  expect(isCostlyLevel('max')).toBe(true)
  expect(isCostlyLevel('high')).toBe(false)
})

test('the model question names the cost in the prompt language', () => {
  expect(texts('ru').modelQuestion('opus', 50, 100_000, false, '')).toContain('Чат перечитается заново: ≈ 100 тыс. токенов, как ~50')
  expect(texts('en').modelQuestion('opus', null, undefined, false, '')).toContain('which costs tokens')
  expect(texts('en').modelQuestion('opus', null, undefined, true, 'many files')).toContain('Opus')
})
