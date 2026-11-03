import { expect, test } from 'claude-code/testing'

import { buildPrompt, parseAnswer, TEMPLATE, toLevel } from '../hooks/classifier'

test('toLevel reads the spellings of xhigh and refuses the rest', () => {
  expect(toLevel('Extra high')).toBe('xhigh')
  expect(toLevel('x-high')).toBe('xhigh')
  expect(toLevel('XHIGH')).toBe('xhigh')
  expect(toLevel('Medium')).toBe('medium')
  expect(toLevel('ultra')).toBe('')
  expect(toLevel(3)).toBe('')
  expect(toLevel(null)).toBe('')
})

test('parseAnswer takes the JSON out of surrounding prose', () => {
  expect(parseAnswer('Sure: {"level":"high","why":"auth bug"} ok')).toEqual({ level: 'high', why: 'auth bug' })
})

test('parseAnswer reads keep', () => {
  expect(parseAnswer('{"level":"keep","why":"approval"}')?.level).toBe('keep')
})

test('parseAnswer refuses an unknown level, no JSON and broken JSON', () => {
  expect(parseAnswer('{"level":"ultra"}')).toBe(null)
  expect(parseAnswer('no json')).toBe(null)
  expect(parseAnswer('{bad')).toBe(null)
})

test('parseAnswer cleans why: trimmed, no dashes, at most 90 characters, empty when missing', () => {
  expect(parseAnswer('{"level":"low","why":"  quick — easy – cheap  "}')?.why).toBe('quick, easy, cheap')
  expect(parseAnswer(`{"level":"low","why":"${'a'.repeat(200)}"}`)?.why.length).toBe(90)
  expect(parseAnswer('{"level":"low"}')?.why).toBe('')
})

test('TEMPLATE holds each placeholder exactly once', () => {
  for (const ph of ['{{NOW}}', '{{REPLY}}', '{{PROMPT}}']) expect(TEMPLATE.split(ph).length).toBe(2)
})

test('buildPrompt keeps $-patterns and placeholders in the person text verbatim', () => {
  const out = buildPrompt({ prompt: 'cost $& and {{NOW}}', lastReply: '', now: 'high' })
  expect(out.includes('cost $& and {{NOW}}')).toBe(true)
  expect(out.includes('The chat runs at: high')).toBe(true)
})

test('buildPrompt cuts the prompt and the reply and names an unknown level', () => {
  const out = buildPrompt({ prompt: 'p'.repeat(5000), lastReply: 'r'.repeat(1000), now: '' })
  expect(out.includes('p'.repeat(4000))).toBe(true)
  expect(out.includes('p'.repeat(4001))).toBe(false)
  expect(out.includes('r'.repeat(600))).toBe(true)
  expect(out.includes('r'.repeat(601))).toBe(false)
  expect(out.includes('The chat runs at: unknown')).toBe(true)
  for (const w of ['low', 'medium', 'high', 'xhigh', 'max', 'keep']) expect(out.includes(w)).toBe(true)
})
