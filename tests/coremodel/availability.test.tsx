// The models CoreModel may use: the settings switches, the account list, stand-ins and recheck.
import { expect, test } from 'claude-code/testing'

import { has, MID, pane, run, switchPair } from './surfaces'
import { start, step, submit, world } from './world'

// The account's own list (the /config Model row) decides which models are offered at all.
const WITHOUT_FABLE = ['default', 'sonnet', 'opus', 'haiku', 'best', 'sonnet[1m]', 'opus[1m]', 'opusplan']

const WITH_FABLE = [...WITHOUT_FABLE, 'fable', 'fable[1m]']

test('a model switched off is replaced by the nearest one below it', { options: { mode: 'auto', useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"fable","why":"x"}'
  await start($)
  await submit($, 'build it all')
  await step($, 'medium')
  // auto: Opus on the first prompt is switched silently, the note says why
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['opus'])
  expect(w.efforts).toEqual(['high'])
})

test('a model the account does not list is never picked or asked about; the nearest below stands in', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = WITHOUT_FABLE
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['opus'])
})

test('the cost question for a stand-in says why', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = WITHOUT_FABLE
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Switch to Opus']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Switch to Opus', 'Keep Sonnet'])
  expect(w.questions[0]).toContain('Fable is not available, Opus instead')
  expect(w.models).toEqual(['opus'])
})

test('with nothing below, the nearest model above stands in', { options: { mode: 'auto', useHaiku: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"low","model":"haiku","why":"a typo"}'
  await start($)
  await submit($, 'fix a typo')
  await step($, 'medium', 0, undefined, 'claude-opus-5-5')
  // Haiku is off; Sonnet is the nearest above, and the chat runs on Opus: Sonnet is applied on the first prompt
  expect(w.models).toEqual(['sonnet'])
})

test('a stand-in equal to the current model changes nothing', { options: { mode: 'auto', useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"x"}'
  await start($)
  await submit($, 'build it all')
  await step($, 'medium', 0, undefined, 'claude-opus-5-5')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-opus-5-5'])
})

test('no model allowed at all: the model part is skipped', { options: { mode: 'auto', useHaiku: false, useSonnet: false, useOpus: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"x"}'
  await start($)
  await submit($, 'build it all')
  await step($, 'medium')
  expect(w.models).toEqual(['claude-sonnet-5-5'])
})

test('a model the account lists is offered as before', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = WITH_FABLE
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked[0]![0]).toBe('Fable (recommended)')
  expect(w.models).toEqual(['fable'])
})

test('a model that becomes available later is offered from the next pick, no restart', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = WITHOUT_FABLE
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  w.modelRow = WITH_FABLE
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(1)
  expect(w.models.at(-1)).toBe('fable')
})

test('the model switches and the account list both apply (their intersection)', { options: { mode: 'auto', useHaiku: false } }, async ($, on) => {
  const w = world(on)
  w.modelRow = ['default', 'sonnet', 'fable', 'haiku']   // the account lacks Opus; the switches leave Haiku off
  await start($)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'   // switched on, not in the account
  await submit($, 'review the design')
  await step($, 'medium')
  w.answer = '{"level":"medium","model":"haiku","why":"x"}'   // in the account, switched off
  await submit($, 'say hi')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-sonnet-5-5', 'claude-sonnet-5-5'])
  w.answer = '{"level":"medium","model":"fable","why":"x"}'   // in both: applied (auto asks for Fable)
  w.reply = ['Fable (recommended)']
  await submit($, 'build everything')
  await step($, 'medium')
  expect(w.models.at(-1)).toBe('fable')
})

test('an unreadable settings list filters nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.listThrows = true
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(1)
  expect(w.models).toEqual(['fable'])
})

test('a row with no known model, or no row, filters nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = ['default', 'best']
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(1)
})

test('an unavailable model is dropped for the session', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('opus')
  await $.classic.StopFailure({ error: 'model_not_found', error_details: 'model: claude-opus-5-5' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.logs.some(l => l.includes('Opus'))).toBe(true)
  expect(await has($, /Opus is not available/)).toBe(true)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
})

test('the pane offers only the models the account lists', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku', 'best']
  await start($)
  const btn = async (k: string) => {
    const ui = await pane($)
    const f = await ui.find({ type: 'Button', key: `model-${k}` })
    await ui.unmount()
    return f !== undefined
  }
  expect(await btn('sonnet')).toBe(true)
  expect(await btn('fable')).toBe(false)
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku', 'fable', 'best']
  await run($, 'recheck')
  expect(await btn('fable')).toBe(true)
})

test('/coremodel recheck brings back a model dropped after model_not_found', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found', error_details: 'model: claude-opus-5-5' } as never)
  expect(await has($, /Opus is not available/)).toBe(true)
  const text = await run($, 'recheck')
  expect(text).toContain('Opus')
  expect(await has($, /Opus is not available/)).toBe(false)
})

test('the unavailable note offers recheck and never sends the person to the models setting', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /Opus is not available — CoreModel will not pick it again this session \(\/coremodel recheck tries again\)/)).toBe(true)
  expect(await has($, /models setting/)).toBe(false)
})

test('the unavailable note is the same when the model is switched on in the settings', { options: { mode: 'auto', useHaiku: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /recheck tries again/)).toBe(true)
  expect(await has($, /remove it from/)).toBe(false)
})

test('/coremodel recheck says what CoreModel may pick, in the host language', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku']
  await start($)
  expect(await run($, 'recheck')).toBe('Models CoreModel may pick: Haiku, Sonnet, Opus.')
  w.answer = '{"level":"keep","why":"x"}'
  w.hostLanguage = 'russian'
  await submit($, 'почини авторизацию')
  await step($, 'medium')
  expect(await run($, 'recheck')).toBe('Модели, которые может выбрать CoreModel: Haiku, Sonnet, Opus.')
})

test('/coremodel recheck says when the list is unusable, empty, or the model is not picked', async ($, on) => {
  const w = world(on)
  w.listThrows = true
  await start($)
  expect(await run($, 'recheck')).toContain('could not be used')
  w.listThrows = false
  w.modelRow = ['default', 'sonnet', 'opus']
  expect(await run($, 'recheck')).not.toContain('could not be used')
})

test('/coremodel recheck explains an empty result', { options: { useHaiku: false, useSonnet: false, useOpus: false } }, async ($, on) => {
  const w = world(on)
  w.modelRow = ['default', 'sonnet', 'opus']
  await start($)
  expect(await run($, 'recheck')).toContain('share no model')
})

test('/coremodel recheck with pickModel off names the effort only', { options: { pickModel: 'off' } }, async ($, on) => {
  world(on)
  await start($)
  expect(await run($, 'recheck')).toContain('picks the effort only')
})

test('other failures leave the model alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'rate_limit' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
})

test('no model warning and no log line with the default switches', async ($, on) => {
  const w = world(on)
  await start($)
  expect(await has($, /models setting|настройк/)).toBe(false)
  expect(w.logs.length).toBe(0)
})

test('a model switched off in the settings has no pane button and is never picked', { options: { mode: 'auto', useHaiku: false } }, async ($, on) => {
  world(on)
  await start($)
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-haiku' })).toBe(undefined)
  expect(await ui.find({ type: 'Button', key: 'model-sonnet' })).not.toBe(undefined)
  await ui.unmount()
})

test('a subagent failing with model_not_found does not drop the held model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found', agent_id: 'a1' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
  expect(await has($, /not available/)).toBe(false)
})

test('/coremodel recheck says when every model is switched off in the settings', { options: { useHaiku: false, useSonnet: false, useOpus: false, useFable: false } }, async ($, on) => {
  world(on)
  await start($)
  expect(await run($, 'recheck')).toContain('switched off in the settings')
})
