import { expect, test } from 'claude-code/testing'

import { LADDER, MODELS, parseModels, stronger, switchCost, toModel } from '../hooks/models'

test('the ladder and ids follow the spec', () => {
  expect(LADDER).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  expect(MODELS.opus.id).toBe('claude-opus-5-5')
  expect(MODELS.fable.id).toBe('claude-fable-5-1')
})

test('switchCost compares a cache write on the new model with a cache read on the current one', () => {
  expect(switchCost(100_000, 'sonnet', 'opus')).toBe(50)
  expect(switchCost(undefined, 'sonnet', 'opus')).toBe(null)
  expect(switchCost(100_000, '', 'opus')).toBe(null)
  expect(switchCost(0, 'sonnet', 'opus')).toBe(null)
  expect(switchCost(100_000, 'fable', 'haiku')).toBe(1)
})

test('stronger follows the ladder and is false for an unknown model', () => {
  expect(stronger('opus', 'sonnet')).toBe(true)
  expect(stronger('sonnet', 'opus')).toBe(false)
  expect(stronger('opus', 'opus')).toBe(false)
  expect(stronger('opus', '')).toBe(false)
})

test('toModel reads keys, names and ids', () => {
  expect(toModel('claude-opus-5-5[1m]')).toBe('opus')
  expect(toModel('Fable 5.1')).toBe('fable')
  expect(toModel('HAIKU')).toBe('haiku')
  expect(toModel('claude-opus-4-8')).toBe('')
  expect(toModel('gpt')).toBe('')
  expect(toModel(3)).toBe('')
})

test('models setting is forgiving', () => {
  expect(parseModels('Opus, sonnet,gpt')).toEqual(['sonnet', 'opus'])
  expect(parseModels(undefined)).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  expect(parseModels('')).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
})
