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
  expect(parseAnswer('Sure: {"level":"high","why":"auth bug"} ok')).toEqual({ level: 'high', model: '', why: 'auth bug' })
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
  expect(out.includes('p'.repeat(2000))).toBe(true)
  expect(out.includes('p'.repeat(2001))).toBe(false)
  expect(out.includes('r'.repeat(600))).toBe(true)
  expect(out.includes('r'.repeat(601))).toBe(false)
  expect(out.includes('The chat runs at: unknown')).toBe(true)
  for (const w of ['low', 'medium', 'high', 'xhigh', 'max', 'keep']) expect(out.includes(w)).toBe(true)
})

// The point of a long prompt (the error, the question) is often at its end: keep both ends.
test('buildPrompt keeps the head and the tail of a long prompt', () => {
  const long = `${'a'.repeat(2500)}MIDDLE${'b'.repeat(2500)}END`
  const out = buildPrompt({ prompt: long, lastReply: '', now: 'high' })
  expect(out.includes('a'.repeat(2000))).toBe(true)
  expect(out.includes('a'.repeat(2001))).toBe(false)
  expect(out.includes('b'.repeat(1997) + 'END')).toBe(true)
  expect(out.includes('MIDDLE')).toBe(false)
  expect(out.includes('[…]')).toBe(true)
})

test('buildPrompt leaves a prompt of 4000 characters or less whole', () => {
  const edge = `${'x'.repeat(3990)}THE END`
  const out = buildPrompt({ prompt: edge, lastReply: '', now: 'high' })
  expect(out.includes(edge)).toBe(true)
  expect(out.includes('[…]')).toBe(false)
})

test('why loses a trailing period, so the question never shows two', () => {
  expect(parseAnswer('{"level":"high","why":"auth bug."}')?.why).toBe('auth bug')
  expect(parseAnswer('{"level":"high","why":"нужно расследование..."}')?.why).toBe('нужно расследование')
})

test('parseAnswer reads the model', () => {
  expect(parseAnswer('{"level":"high","model":"opus","why":"x"}')?.model).toBe('opus')
  expect(parseAnswer('{"level":"high","why":"x"}')?.model).toBe('')
  expect(parseAnswer('{"level":"high","model":"gpt","why":"x"}')?.model).toBe('')
  expect(parseAnswer('{"level":"keep","model":"opus","why":"x"}')?.model).toBe('opus')
})

test('the template asks for a model from the ladder', () => {
  for (const w of ['haiku', 'sonnet', 'opus', 'fable', '"model"']) expect(TEMPLATE.includes(w)).toBe(true)
})

// The reason comes first, so the classifier names what decides before it names the level and the model.
test('the template asks for the reason before the level and the model', () => {
  const answer = TEMPLATE.slice(TEMPLATE.lastIndexOf('{"'))
  expect(answer.indexOf('"why"')).toBeGreaterThan(-1)
  expect(answer.indexOf('"why"') < answer.indexOf('"level"')).toBe(true)
  expect(answer.indexOf('"why"') < answer.indexOf('"model"')).toBe(true)
})

test('parseAnswer reads an answer with the reason first', () => {
  expect(parseAnswer('{"why": "причина неизвестна", "level": "high", "model": "opus"}')).toEqual({ level: 'high', model: 'opus', why: 'причина неизвестна' })
})

// Haiku answered keep to first prompts and to the person's own questions: keep needs a reply to answer.
// Sonnet answered high to "option 2" when the option was a big one.
test('the template says a question is never keep, and a picked option is', () => {
  expect(TEMPLATE.includes('is new work and never keep, even on the first prompt of a chat')).toBe(true)
  expect(TEMPLATE.includes('picks one of the options Claude offered (even a big one')).toBe(true)
})

// Both classifiers answered keep to "почини" after a reply that described a bug and asked nothing.
test('the template says a command after a finding is the work, not keep', () => {
  expect(TEMPLATE.includes('Keep needs something to answer')).toBe(true)
  expect(TEMPLATE.includes('ок, поправь')).toBe(false)
})

test('a why with a closing brace in it is still readable', () => {
  const p = parseAnswer('Sure: {"level":"high","model":"opus","why":"fix the } in config"} done {x}')
  expect(p?.level).toBe('high')
  expect(p?.model).toBe('opus')
  expect(p?.why).toBe('fix the } in config')
})

test('a brace inside an earlier text does not hide the answer', () => {
  expect(parseAnswer('I think {maybe} this: {"level":"low","why":"x"}')?.level).toBe('low')
})
