// The classifier call: its payload and model, the second try, the timeout, and failures in a row.
import { expect, test } from 'claude-code/testing'

import { start, step, submit, world, type Eng, type World } from './world'

const HIGH = '{"level":"high","why":"auth bug"}'

// A classifier that keeps failing is said once, not left to look like a quiet plugin.
async function failOnce($: Eng, w: World, text = 'fix the login') {
  w.answers = [{ fail: true }, { fail: true }]
  await submit($, text)
  await step($, 'medium')
}

test('classifier error and timeout leave the level and write a log line', async ($, on) => {
  const w = world(on)
  await start($)
  for (const a of [new Error('boom'), { isAnswered: false } as const, 'no json at all']) {
    w.answer = a
    await submit($, 'fix the login')
    await step($, 'medium')
  }
  expect(w.efforts).toEqual(['medium', 'medium', 'medium'])
  expect(w.asked.length).toBe(0)
  // A test hook that throws is skipped by the engine, so the plugin sees a failed call, not 'boom'.
  expect(w.logs.length).toBe(3)
  // The debug log only (claude --debug): no file is written, nothing reaches the transcript.
  expect(w.logSinks).toEqual(['debug', 'debug', 'debug'])
  expect(w.logs.every(l => l.startsWith('coremodel: classify: '))).toBe(true)
  expect(w.written).toEqual([])
  expect(w.logs[1]!.includes('api-error')).toBe(true)
  expect(w.logs[2]!.includes('not readable')).toBe(true)
})

test('one failure says nothing; the second in a row raises one toast', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await failOnce($, w)
  expect(w.toasts).toEqual([])
  await failOnce($, w)
  expect(w.toasts.length).toBe(1)
  expect(w.toasts[0]).toContain('api-error')
  expect(w.toasts[0]).toContain('unchanged')
  await failOnce($, w)
  expect(w.toasts.length).toBe(1)
})

test('a pick that works clears the failures; two more raise the toast again', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await failOnce($, w)
  await failOnce($, w)
  w.answers = [HIGH]
  await submit($, 'fix the login')
  await step($, 'medium')
  await failOnce($, w)
  expect(w.toasts.length).toBe(1)
  await failOnce($, w)
  expect(w.toasts.length).toBe(2)
})

test('the failure toast speaks the host language', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await failOnce($, w, 'почини авторизацию')
  await failOnce($, w, 'почини авторизацию')
  expect(w.toasts[0]).toContain('CoreModel')
  expect(w.toasts[0]).toContain('без изменений')
})

test('an Esc on the turn is not a classifier failure', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  for (let i = 0; i < 3; i += 1) {
    w.answers = [{ after: 1_000, cut: true }]
    await submit($, 'fix the login')
    const s = step($, 'medium')
    await w.clock.advance(1_000)
    await s
  }
  expect(w.toasts).toEqual([])
})

// A classifier call sometimes hangs (seen live on a chat's first prompt, beside the title request):
// a second call starts after 3 s, the first answer of the two is used, and the wait is 8 s at most.
test('a quick classifier answer makes one call only', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ after: 2_000, text: HIGH }]
  await start($)
  await submit($, 'fix the login')
  const s = step($, 'medium')
  await w.clock.advance(2_000)
  await s
  expect(w.model.length).toBe(1)
  expect(w.timeouts).toEqual([8_000])
  expect(w.efforts).toEqual(['high'])
})

test('a hung classifier call gets a second try after 3 s', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ after: 0 }, HIGH]
  await start($)
  await submit($, 'fix the login')
  const s = step($, 'medium')
  await w.clock.advance(3_000)
  await s
  expect(w.model.length).toBe(2)
  expect(w.timeouts).toEqual([8_000, 5_000])
  expect(w.efforts).toEqual(['high'])
  expect(w.logs.length).toBe(0)
})

test('a quick API failure is tried once more at once', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ fail: true }, HIGH]
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.model.length).toBe(2)
  expect(w.timeouts).toEqual([8_000, 8_000])
  expect(w.efforts).toEqual(['high'])
  expect(w.logs.length).toBe(0)
})

test('two quick failures log the last one and leave the level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ fail: true }, { fail: true }]
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.model.length).toBe(2)
  expect(w.efforts).toEqual(['medium'])
  expect(w.logs[0]!.includes('api-error')).toBe(true)
})

test('a late first answer still wins over the second try', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ after: 4_000, text: HIGH }, { after: 0 }]
  await start($)
  await submit($, 'fix the login')
  const s = step($, 'medium')
  await w.clock.advance(3_000)
  await w.clock.advance(1_000)
  await s
  expect(w.efforts).toEqual(['high'])
})

test('two hung calls let the prompt go after 8 s and log a timeout', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ after: 0 }, { after: 0 }]
  await start($)
  await submit($, 'fix the login')
  const s = step($, 'medium')
  await w.clock.advance(3_000)
  await w.clock.advance(5_000)
  await s
  expect(w.efforts).toEqual(['medium'])
  expect(w.logs.length).toBe(1)
  expect(w.logs[0]!.includes('classify: classifier timed out after 8 s (two tries)')).toBe(true)
})

test('calls cut by an Esc before 8 s are not logged as a timeout', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ after: 4_000, cut: true }, { after: 1_000, cut: true }]
  await start($)
  await submit($, 'fix the login')
  const s = step($, 'medium')
  await w.clock.advance(3_000)
  await w.clock.advance(1_000)
  await s
  expect(w.efforts).toEqual(['medium'])
  expect(w.logs.length).toBe(1)
  expect(w.logs[0]!.includes('classify: classifier gave no answer: aborted')).toBe(true)
})

test('the payload is cut and the classifier model follows the setting, by its alias', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"keep","why":"w"}'
  w.lastReply = 'r'.repeat(1000)
  await start($)
  await submit($, 'p'.repeat(5000))
  await step($, 'medium')
  expect(w.model).toEqual(['sonnet'])
  expect(w.prompts[0]!.includes('p'.repeat(2000))).toBe(true)
  expect(w.prompts[0]!.includes('p'.repeat(2001))).toBe(false)
  expect(w.prompts[0]!.includes('r'.repeat(600))).toBe(true)
  expect(w.prompts[0]!.includes('r'.repeat(601))).toBe(false)
})

test('haiku when the setting says so', { options: { classifier: 'haiku' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"keep","why":"w"}'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.model).toEqual(['haiku'])
})

// Every call, the second try included: the classifier only sorts the prompt, it does not do the work.
test('the classifier is asked at low effort, on the second try too', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answers = [{ fail: true }, HIGH]
  await start($)
  await submit($, 'fix the login')
  await step($, 'xhigh')
  expect(w.classifierEfforts).toEqual(['low', 'low'])
})
