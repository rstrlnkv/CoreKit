// The held pair on main-chat requests: which prompt gets a pick, when the hold goes, new chats and sessions.
import { expect, test } from 'claude-code/testing'

import { start, step, submit, world, type Eng, type World } from './world'

async function holdOpusHigh($: Eng, w: World) {
  w.answer = '{"level":"high","model":"opus","why":"x"}'
  await submit($, 'fix the login')
  await step($, 'medium')
}

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

test('the app setting is never written: the level is held in the chat', async ($, on) => {
  const w = world(on)
  w.reply = 'High (recommended)'
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
  w.reply = 'Extra high (recommended)'
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
  w.reply = 'High (recommended)'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await start($)
  await step($, 'medium', 0)
  expect(w.efforts).toEqual(['high', 'medium'])
})

// /clear, /resume and a fork start another chat in the same process: session.start does not run,
// so the hold must go here, or the new chat runs on the old pick with no label in the footer.
for (const source of ['clear', 'resume', 'fork'] as const) {
  test(`a new chat (${source}) lets go of a held model and level`, { options: { mode: 'auto' } }, async ($, on) => {
    const w = world(on)
    w.answer = '{"level":"low","model":"haiku","why":"w"}'
    await start($)
    await submit($, 'rename x to count')
    await step($, 'medium')
    await $.classic.SessionStart({ source } as never)
    await step($, 'medium', 0)
    expect(w.efforts).toEqual(['low', 'medium'])
    expect(w.models).toEqual(['haiku', 'claude-sonnet-5-5'])
  })
}

test('a compacted chat keeps its held model and level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"low","model":"haiku","why":"w"}'
  await start($)
  await submit($, 'rename x to count')
  await step($, 'medium')
  await $.classic.SessionStart({ source: 'compact' } as never)
  await step($, 'medium', 0)
  expect(w.efforts).toEqual(['low', 'low'])
  expect(w.models).toEqual(['haiku', 'haiku'])
})

test('a pick still running when a new chat starts is dropped', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  let answer: (a: string) => void = () => {}
  w.answer = new Promise<string>(r => (answer = r))
  await start($)
  await submit($, 'rename x to count')
  const first = step($, 'medium')
  // The pick is on its way once the classifier has been asked.
  for (let i = 0; w.model.length === 0; i += 1) {
    if (i > 500) throw new Error('the classifier was never asked')
    await w.clock.settle()
  }
  await $.classic.SessionStart({ source: 'clear' } as never)
  answer('{"level":"low","model":"haiku","why":"w"}')
  await first
  await step($, 'medium', 0)
  expect(w.efforts).toEqual(['medium', 'medium'])
  expect(w.models).toEqual(['claude-sonnet-5-5', 'claude-sonnet-5-5'])
})

test('a stale pick is dropped', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
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
  answer('Extra high (recommended)')
  await first
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['medium'])
})

test('moving the menu releases the hold', async ($, on) => {
  const w = world(on)
  w.reply = 'High (recommended)'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  await step($, 'low', 1)
  await step($, 'low', 2)
  expect(w.efforts).toEqual(['high', 'low', 'low'])
})

test('the held model goes on every main-chat request', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await step($, 'medium', 1)
  await step($, 'medium', 0)
  expect(w.models).toEqual(['opus', 'opus', 'opus'])
})

test('model and effort release on their own', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await step($, 'medium', 1, undefined, 'claude-haiku-5-5')
  expect(w.models.at(-1)).toBe('claude-haiku-5-5')
  expect(w.efforts.at(-1)).toBe('high')
  await step($, 'low', 2, undefined, 'claude-haiku-5-5')
  expect(w.efforts.at(-1)).toBe('low')
  await step($, 'low', 3, undefined, 'claude-haiku-5-5')
  expect(w.models.at(-1)).toBe('claude-haiku-5-5')
})

test('a model without effort gets none', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await step($, undefined, 1)
  expect(w.efforts.at(-1)).toBe(undefined)
  expect(w.models.at(-1)).toBe('opus')
})

test('subagent requests keep their model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await step($, 'medium', 0, 'a1', 'claude-haiku-5-5')
  expect(w.models.at(-1)).toBe('claude-haiku-5-5')
})

test('a new session drops the model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await start($)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
})

test('the held model keeps the context suffix of the request', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'claude-sonnet-5-5[1m]')
  expect(w.models).toEqual(['opus[1m]'])
})

// The waiting prompt belongs to the next turn only.
test('a submit that was dropped leaves nothing waiting', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.drop = 'blocked'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium', 0)
  expect(w.model.length).toBe(0)
  expect(w.efforts).toEqual(['medium'])
})

test('a turn that ended without a step leaves nothing waiting', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await $.turn.complete({ turnId: 't0', answer: '', durationMs: 1, isAborted: true, reason: 'aborted' } as never)
  await step($, 'medium', 0)
  expect(w.model.length).toBe(0)
})

test('a prompt queued behind a running turn survives that turn ending', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await $.prompt.submit({ text: 'fix the login', wait: false, turnId: 't0', origin: { kind: 'composer' } as never })
  await $.turn.complete({ turnId: 't0', answer: 'x', durationMs: 1, isAborted: false, reason: 'answer' } as never)
  await step($, 'medium', 0)
  expect(w.model.length).toBe(1)
  expect(w.efforts).toEqual(['high'])
})

test('a prompt of another origin takes the next turn, so an older waiting one goes', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await submit($, 'background note', 'sdk')
  await step($, 'medium', 0)
  expect(w.model.length).toBe(0)
})

test('a prompt sent before the new chat hook fires still gets its pick', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await $.classic.SessionStart({ source: 'clear' } as never)
  await step($, 'medium', 0)
  expect(w.model.length).toBe(1)
  expect(w.efforts).toEqual(['high'])
})

// Remote Control (the phone or the web) sends its prompts as `bridge`: they are the person's own.
test('a Remote Control prompt gets its pick like a typed one', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login', 'bridge')
  await step($, 'medium')
  expect(w.model.length).toBe(1)
  expect(w.efforts).toEqual(['high'])
})
