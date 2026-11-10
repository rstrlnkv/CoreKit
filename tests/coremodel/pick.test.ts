// The pick for one prompt: what auto applies, the model and effort questions, and the cost question.
import { expect, test } from 'claude-code/testing'

import { MID, PANE, pick, pressPane } from './surfaces'
import { start, step, submit, world } from './world'

test('Keep, a dismissed question and an other answer keep the level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  await start($)
  for (const r of ['Keep Medium', null, 'maybe later']) {
    w.reply = r
    await submit($, 'build the whole app')
    await step($, 'medium')
  }
  expect(w.asked.length).toBe(3)
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['medium', 'medium', 'medium'])
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

test('a Russian prompt gets the question in Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  w.reply = 'Оставить «Среднее»'
  w.hostLanguage = 'russian'
  await start($)
  await submit($, 'собери всё приложение')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Очень высокое (советую)', 'Оставить «Среднее»', 'Высокое', 'Максимальное'])
  expect(w.headers[0]).toBe('Усилие')
  expect(w.efforts).toEqual(['medium'])
})

test('first prompt in auto switches the model silently', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"many files"}'
  await start($)
  await submit($, 'refactor the module')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['opus'])
})

test('fable always asks', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(1)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
})

// The model is asked first, then the effort; in each the recommended choice comes first and the
// current one is there to keep. When both are asked the effort question can go back to the model.
test('auto asks the model, then the effort, the pick first', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)', 'Extra high (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.dialogs).toEqual([
    [['Fable (recommended)', 'Keep Sonnet', 'Opus', 'Haiku']],
    [['Extra high (recommended)', 'Keep Medium', 'High', '← Back to the model']],
  ])
  expect(w.headers).toEqual(['Model', 'Effort'])
  expect(w.models.at(-1)).toBe('fable')
  expect(w.efforts.at(-1)).toBe('xhigh')
})

test('Back to the model asks the model again, then the effort', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)', '← Back to the model', 'Keep Sonnet', 'Max']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.headers).toEqual(['Model', 'Effort', 'Model', 'Effort'])
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('max')
})

test('the effort question alone has no Back and four levels', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  w.reply = 'Extra high (recommended)'
  await start($)
  await submit($, 'build the whole app')
  await step($, 'medium')
  expect(w.asked).toEqual([['Extra high (recommended)', 'Keep Medium', 'High', 'Max']])
})

test('a level typed under Other counts, in English or Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  await start($)
  w.reply = 'max'
  await submit($, 'fix the login')
  await step($, 'medium')
  w.reply = 'Низкое'
  w.hostLanguage = 'russian'
  await submit($, 'почини вход')
  await step($, 'medium')
  expect(w.efforts).toEqual(['max', 'low'])
})

test('a question left unanswered keeps its part; the other part is applied', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)', null]
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.models.at(-1)).toBe('fable')
  expect(w.efforts.at(-1)).toBe('medium')
})

test('dismissed questions change nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"whole app"}'
  w.reply = null
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.headers).toEqual(['Model', 'Effort'])
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['medium'])
})

test('the Fable question lists the pick first', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Fable (recommended)', 'Keep Sonnet', 'Opus', 'Haiku'])
  expect(w.models).toEqual(['fable'])
})

test('the Extra high and Max questions list the pick first', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = ['Extra high (recommended)', 'Max (recommended)']
  await start($)
  for (const l of ['xhigh', 'max']) {
    w.answer = `{"level":"${l}","why":"w"}`
    await submit($, 'build the whole app')
    await step($, 'medium')
  }
  expect(w.asked[0]).toEqual(['Extra high (recommended)', 'Keep Medium', 'High', 'Max'])
  // The first answer is held, so the second question's Keep is the held Extra high.
  expect(w.asked[1]![0]).toBe('Max (recommended)')
  expect(w.asked[1]).toContain('Keep Extra high')
})

test('mid-chat stronger pick asks with the cost',{ options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.tokens = 100_000
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  w.reply = ['Switch to Opus']
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.questions[0]).toContain('≈ 100k tokens')
  expect(w.questions[0]).toContain('about $0.50')
  expect(w.questions[0]).toContain('Because: x.')
  expect(w.models).toEqual(['opus'])
})

test('mid-chat question without a known size says it costs tokens', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.questions[0]).toContain('re-reads this chat once, which costs tokens')
})

test('mid-chat weaker pick changes nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"haiku","why":"x"}'
  await start($)
  await submit($, 'a small question')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
})

test('dismissed model question still asks effort', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"whole app"}'
  w.reply = [null, 'Extra high (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.headers).toEqual(['Model', 'Effort'])
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['xhigh'])
})

test('a current model of no known family asks nothing mid-chat', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium', 0, undefined, 'my-gateway-model')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['my-gateway-model'])
})

test('pickModel off keeps CoreEffort behaviour', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"x"}'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['high'])
})

test('mid-chat the model question offers only the pick and Keep', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Switch to Opus', 'Keep Sonnet'])
})

test('Keep is offered for a current model outside the list', { options: { mode: 'auto', useOpus: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"x"}'
  w.reply = ['Keep Opus']
  await start($)
  await submit($, 'write the whole report')
  await step($, 'medium', 0, undefined, 'claude-opus-5-5')
  expect(w.asked[0]).toEqual(['Fable (recommended)', 'Keep Opus', 'Sonnet', 'Haiku'])
  expect(w.models).toEqual(['claude-opus-5-5'])
})

test('a one-model list still gives two options', { options: { mode: 'auto', useHaiku: false, useSonnet: false, useOpus: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"fable","why":"x"}'
  await start($)
  await submit($, 'build it all')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Fable (recommended)', 'Keep Sonnet'])
})

test('a current model of no known family is never switched or asked about', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'my-gateway-model')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['my-gateway-model'])
})

test('auto on the first prompt does not switch away from a model of no known family', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'my-gateway-model')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['my-gateway-model'])
})

test('a provider id of a known family is switched by the alias', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'us.anthropic.claude-sonnet-5-5-v1:0')
  expect(w.models).toEqual(['opus'])
})

test('a newer generation of the same family counts as that family', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'claude-opus-6')
  expect(w.models).toEqual(['claude-opus-6'])
})

// A model without effort carries none: the level part sleeps.
test('a model without effort is not asked about a level', async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await step($, undefined, 0)
  expect(w.asked.length).toBe(0)
  expect(w.efforts).toEqual([undefined])
})

test('the mid-chat question names the lasting price first, then the one-off re-read', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.tokens = 100_000
  w.reply = ['Switch to Opus']
  await start($)
  await pick($, w, '{"level":"medium","model":"opus","why":"a design choice"}')
  expect(w.asked[0]).toEqual(['Switch to Opus', 'Keep Sonnet'])
  const q = w.questions[0]!
  expect(q.startsWith('Switch to Opus? From now on each reply costs about 2× Sonnet.')).toBe(true)
  expect(q).toContain('Switching also re-reads this chat once: ≈ 100k tokens, about $0.50 at API prices (on a subscription it counts toward your limits).')
  expect(q).toContain('Because: a design choice.')
  expect(w.models).toEqual(['opus'])
})

test('Fable mid-chat costs about 5× Sonnet', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  await start($)
  await pick($, w, '{"level":"medium","model":"fable","why":"x"}')
  expect(w.questions[0]).toContain('about 5× Sonnet')
  expect(w.questions[0]).toContain('re-reads this chat once, which costs tokens')
})

test('a cheaper model pressed in the pane mid-chat says the saving starts after the re-read', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.tokens = 100_000
  await start($)
  await step($, 'medium', 0, undefined, 'claude-opus-5-5')
  w.reply = 'Switch to Sonnet'
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'model-sonnet' })
  await ui.unmount()
  expect(w.asked[0]).toEqual(['Switch to Sonnet', 'Keep Opus'])
  expect(w.questions[0]).toContain('about 1/2 of Opus')
  expect(w.questions[0]).toContain('after this chat is re-read once')
})

test('pane model press mid-chat asks the cost', async ($, on) => {
  const w = world(on)
  w.lastReply = 'an earlier answer'
  w.tokens = 100_000
  await start($)
  await step($, 'medium')
  w.reply = 'Switch to Opus'
  await pressPane($, 'model-opus')
  expect(w.questions[0]).toContain('about $0.50')
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
})
