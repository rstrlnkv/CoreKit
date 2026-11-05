import { expect, test } from 'claude-code/testing'

import { type Eng, row, start, step, submit, world, type World } from './world'

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
  w.reply = 'High (recommended)'
  await start($)
  await submit($, 'fix the login, it throws 500')
  await step($, 'medium')
  expect(w.asked).toEqual([['High (recommended)', 'Keep Medium', 'Extra high', 'Low']])
  expect(w.efforts).toEqual(['high'])
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
    expect(w.models).toEqual(['claude-haiku-5-5', 'claude-sonnet-5-5'])
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
  expect(w.models).toEqual(['claude-haiku-5-5', 'claude-haiku-5-5'])
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
  expect(w.logs.every(l => l.startsWith('/fake-home/.claude/mods-logs/coremodel.log\n'))).toBe(true)
  expect(w.logs[1]!.includes('api-error')).toBe(true)
  expect(w.logs[2]!.includes('not readable')).toBe(true)
})

// A classifier call sometimes hangs (seen live on a chat's first prompt, beside the title request):
// a second call starts after 3 s, the first answer of the two is used, and the wait is 8 s at most.
const HIGH = '{"level":"high","why":"auth bug"}'

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
  answer('High (recommended)')
  await first
  expect(w.set.length).toBe(0)
  expect(w.efforts).toEqual(['medium'])
})

test('moving the menu releases the hold', async ($, on) => {
  const w = world(on)
  w.row = null
  w.reply = 'High (recommended)'
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
  expect(w.model).toEqual(['claude-haiku-5-5'])
})

test('a Russian prompt gets the question in Russian', async ($, on) => {
  const w = world(on)
  w.reply = 'Оставить «Среднее»'
  await start($)
  await submit($, 'почини авторизацию')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Высокое (советую)', 'Оставить «Среднее»', 'Очень высокое', 'Низкое'])
  expect(w.headers[0]).toBe('Усилие')
  expect(w.efforts).toEqual(['medium'])
})

// CoreModel: the model part of a pick (spec §4.2, §4.3).
const MID = 'an earlier answer'

test('first prompt in auto switches the model silently', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"many files"}'
  await start($)
  await submit($, 'refactor the module')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-opus-5-5'])
})

test('first prompt in suggest asks the model', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"many files"}'
  w.reply = ['Opus (recommended)']
  await start($)
  await submit($, 'refactor the module')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Opus (recommended)', 'Keep Sonnet', 'Fable', 'Haiku'])
  expect(w.headers[0]).toBe('Model')
  expect(w.models).toEqual(['claude-opus-5-5'])
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
test('suggest mode asks the model, then the effort, the pick first', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"auth bug"}'
  w.reply = ['Opus (recommended)', 'High (recommended)']
  await start($)
  await submit($, 'fix the login, it throws 500')
  await step($, 'medium')
  expect(w.dialogs).toEqual([
    [['Opus (recommended)', 'Keep Sonnet', 'Fable', 'Haiku']],
    [['High (recommended)', 'Keep Medium', 'Extra high', '← Back to the model']],
  ])
  expect(w.headers).toEqual(['Model', 'Effort'])
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
  expect(w.efforts.at(-1)).toBe('high')
})

test('Back to the model asks the model again, then the effort', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"auth bug"}'
  w.reply = ['Opus (recommended)', '← Back to the model', 'Keep Sonnet', 'Extra high']
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.headers).toEqual(['Model', 'Effort', 'Model', 'Effort'])
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('xhigh')
})

test('the effort question alone has no Back and four levels', async ($, on) => {
  const w = world(on)
  w.reply = 'High (recommended)'
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.asked).toEqual([['High (recommended)', 'Keep Medium', 'Extra high', 'Low']])
})

test('a level typed under Other counts, in English or Russian', async ($, on) => {
  const w = world(on)
  await start($)
  w.reply = 'max'
  await submit($, 'fix the login')
  await step($, 'medium')
  w.reply = 'Низкое'
  await submit($, 'почини вход')
  await step($, 'medium')
  expect(w.efforts).toEqual(['max', 'low'])
})

test('a question left unanswered keeps its part; the other part is applied', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"auth bug"}'
  w.reply = ['Opus (recommended)', null]
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
  expect(w.efforts.at(-1)).toBe('medium')
})

test('dismissed questions change nothing', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"auth bug"}'
  w.reply = null
  await start($)
  await submit($, 'fix the login')
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
  expect(w.models).toEqual(['claude-fable-5-1'])
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

test('a plain High question keeps the pick first', async ($, on) => {
  const w = world(on)
  w.reply = 'High (recommended)'
  await start($)
  await submit($, 'fix the login, it throws 500')
  await step($, 'medium')
  expect(w.asked[0]![0]).toBe('High (recommended)')
})

test('mid-chat stronger pick asks with the cost',{ options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.tokens = 100_000
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  w.reply = ['Opus (recommended)']
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.questions[0]).toContain('≈ 100k tokens')
  expect(w.questions[0]).toContain('about $0.50')
  expect(w.questions[0]).toContain('(x)')
  expect(w.models).toEqual(['claude-opus-5-5'])
})

test('mid-chat question without a known size says it costs tokens', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.questions[0]).toContain('read again once, which costs tokens')
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

test('dismissed model question still asks effort', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"opus","why":"x"}'
  w.reply = [null, 'High (recommended)']
  await start($)
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(w.headers).toEqual(['Model', 'Effort'])
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['high'])
})

test('a model outside the list is ignored', { options: { mode: 'auto', useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"high","model":"fable","why":"x"}'
  await start($)
  await submit($, 'build it all')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['high'])
})

test('unknown current model asks nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium', 0, undefined, 'claude-opus-4-8')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-opus-4-8'])
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

// CoreModel: holding the pair (spec §4.4).
async function holdOpusHigh($: Eng, w: World) {
  w.answer = '{"level":"high","model":"opus","why":"x"}'
  await submit($, 'fix the login')
  await step($, 'medium')
}

test('the held model goes on every main-chat request', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await holdOpusHigh($, w)
  await step($, 'medium', 1)
  await step($, 'medium', 0)
  expect(w.models).toEqual(['claude-opus-5-5', 'claude-opus-5-5', 'claude-opus-5-5'])
})

test('model and effort release on their own', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
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

// Final review fixes.
test('mid-chat the model question offers only the pick and Keep', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'now the hard part')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Opus (recommended)', 'Keep Sonnet'])
})

test('Keep is offered for a current model outside the list', { options: { useOpus: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"sonnet","why":"x"}'
  w.reply = ['Keep Opus']
  await start($)
  await submit($, 'write the report')
  await step($, 'medium', 0, undefined, 'claude-opus-5-5')
  expect(w.asked[0]).toEqual(['Sonnet (recommended)', 'Keep Opus', 'Haiku'])
  expect(w.models).toEqual(['claude-opus-5-5'])
})

test('a one-model list still gives two options', { options: { useHaiku: false, useSonnet: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium')
  expect(w.asked[0]).toEqual(['Opus (recommended)', 'Keep Sonnet'])
})

test('an unknown current model gets a plain Keep', async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  w.reply = ['Keep the current model']
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'claude-opus-4-8')
  expect(w.asked[0]?.[1]).toBe('Keep the current model')
  expect(w.models).toEqual(['claude-opus-4-8'])
})

test('the held model keeps the context suffix of the request', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"medium","model":"opus","why":"x"}'
  await start($)
  await submit($, 'refactor it')
  await step($, 'medium', 0, undefined, 'claude-sonnet-5-5[1m]')
  expect(w.models).toEqual(['claude-opus-5-5[1m]'])
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

// A model without effort carries none: the level part sleeps.
test('a model without effort is not asked about a level', async ($, on) => {
  const w = world(on)
  await start($)
  await submit($, 'fix the login')
  await step($, undefined, 0)
  expect(w.asked.length).toBe(0)
  expect(w.efforts).toEqual([undefined])
})

// The account's own list (the /config Model row) decides which models are offered at all.
const WITHOUT_FABLE = ['default', 'sonnet', 'opus', 'haiku', 'best', 'sonnet[1m]', 'opus[1m]', 'opusplan']
const WITH_FABLE = [...WITHOUT_FABLE, 'fable', 'fable[1m]']

test('a model the account does not list is never picked or asked about', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.modelRow = WITHOUT_FABLE
  w.answer = '{"level":"medium","model":"fable","why":"whole app"}'
  w.reply = ['Fable (recommended)']
  await start($)
  await submit($, 'build the whole app, work alone')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
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
  expect(w.models).toEqual(['claude-fable-5-1'])
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
  expect(w.models.at(-1)).toBe('claude-fable-5-1')
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
  expect(w.models.at(-1)).toBe('claude-fable-5-1')
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
  expect(w.models).toEqual(['claude-fable-5-1'])
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
