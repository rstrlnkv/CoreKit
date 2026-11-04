import { expect, test } from 'claude-code/testing'

import { row, start, step, submit, world } from './world'

test('skips slash commands, empty prompts and non-composer origins', async ($, on) => {
  const w = world(on)
  await start($)
  for (const [text, kind] of [['/help', 'composer'], ['   ', 'composer'], ['fix the login', 'sdk']] as const) {
    await submit($, text, kind)
    await step($, 'medium')
  }
  expect(w.model.length).toBe(0)
  expect(w.efforts).toEqual(['medium', 'medium', 'medium'])
})

test('a subagent request is untouched', async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium', 0, 'a1')
  expect(w.model.length).toBe(0)
  expect(w.efforts).toEqual(['medium'])
})

test('suggest asks and Switch applies', async ($, on) => {
  const w = world(on)
  w.reply = 'Switch to High'
  await start($)
  await submit($, 'fix the login, it throws 500')
  await step($, 'medium')
  expect(w.asked).toEqual([['Switch to High', 'Switch, and auto-adjust from now', 'Keep Medium']])
  expect(w.efforts).toEqual(['high'])
})

test('the app setting is never written: the level is held in the chat', async ($, on) => {
  const w = world(on)
  w.reply = 'Switch to High'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await step($, 'medium', 1)
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['high', 'high'])
})

test('a turn with no new prompt keeps the held level only until the menu moves', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  w.reply = 'Switch to Extra high'
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  await step($, 'medium', 0)
  await step($, 'low', 0)
  await step($, 'low', 1)
  expect(w.model.length).toBe(1)
  expect(w.efforts).toEqual(['xhigh', 'xhigh', 'low', 'low'])
})

test('a new session start lets go of a held level', async ($, on) => {
  const w = world(on)
  w.reply = 'Switch to High'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await start($)
  await step($, 'medium', 0)
  expect(w.efforts).toEqual(['high', 'medium'])
})

test('suggest Keep, a dismissed question and an other answer keep the level', async ($, on) => {
  const w = world(on)
  await start($)
  for (const r of ['Keep Medium', null, 'maybe later']) {
    w.reply = r
    await submit($, 'fix the login')
    await step($, 'medium')
  }
  expect(w.asked.length).toBe(3)
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['medium', 'medium', 'medium'])
})

test('Switch and auto-adjust stores auto mode', async ($, on) => {
  const w = world(on)
  w.reply = 'Switch, and auto-adjust from now'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.efforts).toEqual(['high'])
  w.answer = '{"level":"low","why":"typo"}'
  await submit($, 'fix a typo')
  await step($, 'high')
  expect(w.asked.length).toBe(1)
  expect(w.efforts).toEqual(['high', 'low'])
})

test('auto applies low, medium and high silently', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  for (const [now, l] of [['medium', 'high'], ['high', 'low'], ['low', 'medium']] as const) {
    w.answer = `{"level":"${l}","why":"w"}`
    await submit($, 'do it')
    await step($, now)
  }
  expect(w.asked.length).toBe(0)
  expect(w.efforts).toEqual(['high', 'low', 'medium'])
})

test('auto asks before xhigh and max', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Keep High'
  await start($)
  for (const l of ['xhigh', 'max']) {
    w.answer = `{"level":"${l}","why":"w"}`
    await submit($, 'build the whole app')
    await step($, 'high')
  }
  expect(w.asked.length).toBe(2)
  expect(w.efforts).toEqual(['high', 'high'])
})

test('off does nothing', { options: { mode: 'off' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.model.length).toBe(0)
})

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
  expect(w.logs.every(l => l.startsWith('/fake-home/.claude/mods-logs/coreeffort.log\n'))).toBe(true)
  expect(w.logs[1]!.includes('api-error')).toBe(true)
  expect(w.logs[2]!.includes('not readable')).toBe(true)
})

test('a stale pick is dropped', async ($, on) => {
  const w = world(on)
  let answer!: (r: string) => void
  w.reply = new Promise<string>(r => (answer = r))
  await start($)
  await submit($, 'fix the login')
  const first = step($, 'medium')
  for (let i = 0; w.asked.length === 0; i += 1) {
    if (i > 500) throw new Error('the question was never asked')
    await w.clock.settle()
  }
  await submit($, 'never mind, fix a typo')
  answer('Switch to High')
  await first
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['medium'])
})

test('a locked row falls back to the hold, kept on later requests', async ($, on) => {
  const w = world(on)
  w.row = row('Medium', true)
  w.reply = 'Switch to High'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await step($, 'medium', 1)
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['high', 'high'])
})

test('a row without the level falls back to the hold', async ($, on) => {
  const w = world(on)
  w.row = { ...row(), options: ['Low', 'Medium', 'High'] }
  w.answer = '{"level":"xhigh","why":"w"}'
  w.reply = 'Switch to Extra high'
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'high')
  expect(w.efforts).toEqual(['xhigh'])
})

test('moving the menu releases the hold', async ($, on) => {
  const w = world(on)
  w.row = null
  w.reply = 'Switch to High'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await step($, 'low', 1)
  await step($, 'low', 2)
  expect(w.efforts).toEqual(['high', 'low', 'low'])
})

test('the payload is cut and the classifier model follows the setting', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"keep","why":"w"}'
  w.lastReply = 'r'.repeat(1000)
  await start($)
  await submit($, 'p'.repeat(5000))
  await step($, 'medium')
  expect(w.model).toEqual(['claude-sonnet-5-5'])
  expect(w.prompts[0]!.includes('p'.repeat(4000))).toBe(true)
  expect(w.prompts[0]!.includes('p'.repeat(4001))).toBe(false)
  expect(w.prompts[0]!.includes('r'.repeat(600))).toBe(true)
  expect(w.prompts[0]!.includes('r'.repeat(601))).toBe(false)
})

test('haiku when the setting says so', { options: { classifier: 'haiku' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"keep","why":"w"}'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.model).toEqual(['claude-haiku-5-5'])
})

test('a Russian prompt gets the question in Russian', async ($, on) => {
  const w = world(on)
  w.reply = 'Оставить «Среднее»'
  await start($)
  await submit($, 'почини авторизацию')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Переключить на «Высокое»', 'Переключить и дальше сам', 'Оставить «Среднее»'])
  expect(w.efforts).toEqual(['medium'])
})
