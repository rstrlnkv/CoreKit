import { expect, test } from 'claude-code/testing'

import { detectModels, enabledModels, LADDER, MODELS, standIn, stronger, switchUsd, toModel } from '../hooks/models'

test('the ladder and ids follow the spec', () => {
  expect(LADDER).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  expect(MODELS.opus.id).toBe('claude-opus-5-5')
  expect(MODELS.fable.id).toBe('claude-fable-5-1')
})

test('switchUsd is one cache write of the chat on the new model, at API prices', () => {
  expect(switchUsd(100_000, 'opus')).toBe(0.5)
  expect(Math.round(switchUsd(100_000, 'haiku')! * 1e6)).toBe(12_500)
  expect(switchUsd(100_000, 'fable')).toBe(1.25)
  expect(switchUsd(undefined, 'opus')).toBe(null)
  expect(switchUsd(0, 'opus')).toBe(null)
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

test('enabledModels reads one switch per model, all on by default', () => {
  expect(enabledModels({})).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  expect(enabledModels({ useFable: false })).toEqual(['haiku', 'sonnet', 'opus'])
  expect(enabledModels({ useHaiku: false, useOpus: false })).toEqual(['sonnet', 'fable'])
  // a switch may arrive as text; only an explicit "off" word turns it off
  expect(enabledModels({ useFable: 'false', useOpus: 'off', useSonnet: '0', useHaiku: 'true' })).toEqual(['haiku'])
  expect(enabledModels({ useFable: 'yes', useOpus: 1, useSonnet: undefined })).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  // every switch off is a valid choice: no model is ever picked
  expect(enabledModels({ useHaiku: false, useSonnet: false, useOpus: false, useFable: false })).toEqual([])
})

test('detectModels reads the models the /config Model row offers', () => {
  // the real row of one account: aliases, 1M variants and the non-model words are all there
  const all = ['default', 'sonnet', 'opus', 'haiku', 'fable', 'best', 'sonnet[1m]', 'opus[1m]', 'fable[1m]', 'opusplan']
  expect(detectModels(all)).toEqual(['haiku', 'sonnet', 'opus', 'fable'])
  expect(detectModels(['default', 'sonnet', 'opus', 'haiku', 'best', 'opusplan'])).toEqual(['haiku', 'sonnet', 'opus'])
  expect(detectModels(['default', 'Opus[1m]', 'claude-sonnet-5-5'])).toEqual(['sonnet', 'opus'])
  // nothing recognisable (no row, an empty row, only words that are no model): no verdict, so no filtering
  expect(detectModels(undefined)).toBe(null)
  expect(detectModels([])).toBe(null)
  expect(detectModels(['default', 'best', 'opusplan'])).toBe(null)
})

test('standIn takes the nearest allowed model below, else above', () => {
  expect(standIn('fable', ['haiku', 'sonnet', 'opus'])).toBe('opus')
  expect(standIn('fable', ['haiku', 'sonnet'])).toBe('sonnet')
  expect(standIn('opus', ['haiku', 'fable'])).toBe('haiku')
  expect(standIn('haiku', ['opus', 'fable'])).toBe('opus')
  expect(standIn('sonnet', [])).toBe(null)
})
