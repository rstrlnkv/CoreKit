import { expect, test } from 'claude-code/testing'

import type { Level } from '../types'
import { decide, texts, uiLang } from '../hooks/policy'

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
  expect(texts('ru').switchTo('high')).not.toBe(texts('en').switchTo('high'))
  expect(texts('en').switchTo('high').includes('High')).toBe(true)
  expect(texts('ru').switchTo('high').includes('Высокое')).toBe(true)
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
