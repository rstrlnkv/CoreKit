import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { start, step, submit, world, type Eng, type World } from './world'

// The quiet interface: Auto by default, Suggest without dialogs, the state in the footer, the pane
// with state and mode first, the cost question with the lasting price first, words per locale.
const SURFACES = ['terminal', 'desktop'] as const
const ABOVE = { plugin: 'coremodel', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 80, scroll: { offset: 0, bodyRows: 6 }, view: {} } } as const
const MODE = { plugin: 'coremodel', component: 'SessionMode', props: { modes: ['default'] } } as const
const PANE = {
  plugin: 'coremodel',
  component: 'Pane',
  requestId: 'coremodel',
  props: { title: 'CoreModel', isFocused: false, bodyColumns: 40, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const
const SPIN = { plugin: 'coremodel', component: 'Spinner', props: { word: 'Thinking', message: null, suffix: '…', mode: 'thinking' } } as const
const MID = 'an earlier answer'

function engineParts(on: On) {
  on('ui.render', { component: 'SessionMode' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{(e.props as { modes: readonly string[] }).modes.join(' | ')}</Text>
  })
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('ui.render', { component: 'Spinner' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    const p = e.props as { word: string; suffix: string }
    return <Text>{p.word + p.suffix}</Text>
  })
}

async function run($: Eng, args: string) {
  const r = await $.command.run({ command: 'coremodel', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as never)
  return (r as { text?: string }).text ?? ''
}

async function pick($: Eng, w: World, answer: string, text = 'fix the login', effort = 'medium', model?: string) {
  w.answer = answer
  await submit($, text)
  await step($, effort, 0, undefined, model)
}

async function band($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...ABOVE, surface })
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  const buttons = (await ui.findAll({ type: 'Button' })).map(b => ({ key: String(b.key), label: String(b.props.label), hotkey: b.props.hotkey }))
  await ui.unmount()
  return { texts, buttons }
}

async function pressBand($: Eng, key: string) {
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  await ui.press({ key })
  await ui.unmount()
}

async function paneTexts($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...PANE, surface })
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  const buttons = Object.fromEntries((await ui.findAll({ type: 'Button' })).map(b => [String(b.key), String(b.props.label)]))
  await ui.unmount()
  return { texts, buttons }
}

async function footer($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...MODE, surface })
  const label = String((await ui.find({ type: 'Button', key: 'pane' }))?.props.label)
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  await ui.unmount()
  return { label, texts }
}

const OPUS_HIGH = '{"level":"high","model":"opus","why":"auth bug"}'

// ---- modes ----
test('Auto is the default: a High pick is applied with no question', async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, '{"level":"high","why":"auth bug"}')
  expect(w.asked.length).toBe(0)
  expect(w.efforts).toEqual(['high'])
  w.reply = null
  expect(await run($, '')).toContain('Mode: Auto.')
})

test('Suggest asks nothing: the prompt runs as it is and the band offers the pick', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.efforts).toEqual(['medium'])
  for (const surface of SURFACES) {
    const b = await band($, surface)
    expect(b.texts.some(t => /^CoreModel suggests Opus · High · auth bug/.test(t))).toBe(true)
    expect(b.buttons.map(x => [x.key, x.label, x.hotkey])).toEqual([['switch', 'Switch', '1'], ['keep', 'Keep', '2']])
  }
  expect(w.placed).toEqual([])
})

test('Switch on a suggestion holds the pair from the next request and leaves a mark', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  await pressBand($, 'switch')
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
  expect(w.efforts.at(-1)).toBe('high')
  expect((await band($)).texts).toEqual(['engine'])
  expect(w.placed).toEqual(['mark-1'])
  expect((await footer($)).label).toBe('CoreModel · Opus · High')
})

test('Keep on a suggestion changes nothing and counts the prompt as unchanged', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  await pressBand($, 'keep')
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('medium')
  expect((await band($)).texts).toEqual(['engine'])
  expect((await paneTexts($)).texts.some(t => /unchanged 1/.test(t))).toBe(true)
})

test('a suggestion goes after 15 s', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  await w.clock.advance(15_000)
  expect((await band($)).texts).toEqual(['engine'])
})

test('Suggest mid-chat: Switch to a stronger model asks the cost first', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  w.lastReply = MID
  w.tokens = 100_000
  await start($)
  await pick($, w, OPUS_HIGH)
  expect(w.asked.length).toBe(0)
  w.reply = 'Switch to Opus'
  await pressBand($, 'switch')
  expect(w.questions[0]).toContain('about 2× Sonnet')
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
  expect(w.efforts.at(-1)).toBe('high')
})

test('Suggest mid-chat never offers a weaker model, only the effort', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  w.lastReply = MID
  await start($)
  await pick($, w, '{"level":"low","model":"haiku","why":"a typo"}')
  const b = await band($)
  expect(b.texts.some(t => /^CoreModel suggests Effort Low · a typo/.test(t))).toBe(true)
  expect(b.texts.some(t => /Haiku/.test(t))).toBe(false)
})

test('a pick that matches the chat suggests nothing', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, '{"level":"medium","model":"sonnet","why":"x"}')
  expect((await band($)).texts).toEqual(['engine'])
})

// ---- the band only after a silent switch ----
test('a switch agreed in a dialog shows no band, only the transcript row', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  w.reply = 'Extra high (recommended)'
  await start($)
  await pick($, w, '{"level":"xhigh","why":"whole app"}')
  expect(w.efforts).toEqual(['xhigh'])
  expect((await band($)).texts).toEqual(['engine'])
  expect(w.placed).toEqual(['mark-1'])
})

test('a silent switch shows the band with its undo', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  const b = await band($)
  expect(b.texts.some(t => /^✓ CoreModel: Opus · High \(was Sonnet · Medium\) · auth bug/.test(t))).toBe(true)
  expect(b.buttons.map(x => [x.key, x.label, x.hotkey])).toEqual([['undo', 'Back to Sonnet · Medium', '1']])
})

// ---- footer and spinner ----
test('the footer button carries the state', async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  for (const surface of SURFACES) expect((await footer($, surface)).label).toBe('CoreModel')
  await pick($, w, OPUS_HIGH)
  for (const surface of SURFACES) {
    const f = await footer($, surface)
    expect(f.label).toBe('CoreModel · Opus · High')
    // the engine's own mode words stay beside it, with no pair of ours
    expect(f.texts).toContain('default')
    expect(f.texts.some(t => /Opus/.test(t))).toBe(false)
  }
  await run($, 'off')
  for (const surface of SURFACES) expect((await footer($, surface)).label).toBe('CoreModel · off')
})

test('the working line is left alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await $.ui.mount({ ...SPIN, surface: 'desktop' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Thinking…')
  await ui.unmount()
})

// ---- the pane ----
test('the pane puts state and mode first, marks the selection in text and says it in plain words', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  for (const surface of SURFACES) {
    const p = await paneTexts($, surface)
    expect(p.texts[0]).toBe('CoreModel · Auto')
    expect(p.buttons['mode-auto']).toBe('● Auto')
    expect(p.buttons['mode-suggest']).toBe('Suggest')
    expect(p.buttons['mode-off']).toBe('Off')
    expect(p.texts).toContain('Asks only before Fable, Extra high, Max and a stronger model mid-chat')
    expect(p.texts).toContain('This chat')
    expect(p.texts).toContain('Opus · High')
    expect(p.texts).toContain('Set by CoreModel for this chat · your default: Sonnet · Medium')
    expect(p.buttons.release).toBe('Use my default')
    expect(p.buttons['model-opus']).toBe('● Opus')
    expect(p.buttons['model-sonnet']).toBe('Sonnet')
    expect(p.buttons['level-high']).toBe('● High')
    expect(p.texts).toContain('Effort')
    expect(p.texts.some(t => /Level/.test(t))).toBe(false)
    expect(p.texts).toContain('This session')
    expect(p.texts).toContain('Opus 1 · High 1')
    // the last pick is what the chat runs at: not repeated
    expect(p.texts).not.toContain('Last pick')
  }
})

test('the mode order is Auto, Suggest, Off everywhere', async ($, on) => {
  const w = world(on)
  await start($)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.findAll({ type: 'Button' })).map(b => String(b.key)).filter(k => k.startsWith('mode-'))).toEqual(['mode-auto', 'mode-suggest', 'mode-off'])
  await ui.unmount()
  w.reply = null
  await run($, '')
  expect(w.asked.at(-1)).toEqual(['Auto', 'Suggest', 'Off'])
})

test('an empty pane says when the state shows and draws no stray separator', async ($, on) => {
  world(on)
  await start($)
  const p = await paneTexts($, 'terminal')
  expect(p.texts).toContain('shown after your first message')
  expect(p.texts).not.toContain('This session')
  expect(p.texts.filter(t => /^─+$/.test(t)).length).toBe(1)
  expect(/^─+$/.test(p.texts.at(-1) ?? '')).toBe(false)
})

test('the last pick shows when it was not applied', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.reply = 'Keep Medium'
  await start($)
  await pick($, w, '{"level":"xhigh","why":"whole app"}')
  const p = await paneTexts($)
  expect(p.texts).toContain('Last pick')
  expect(p.texts).toContain('Extra high · whole app · not applied')
  expect(p.texts.some(t => /unchanged 1/.test(t))).toBe(true)
})

test('the pane draws no picture: the session is one line of text on every surface', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.findAll({ type: 'Svg' })).toHaveLength(0)
  await ui.unmount()
})

// ---- the cost question ----
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
  w.row = null
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

// ---- language ----
test('the language setting wins over the prompt', { options: { mode: 'auto', language: 'ru' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, OPUS_HIGH)
  expect((await band($)).texts.some(t => /^✓ CoreModel: Opus · Высокое \(было Sonnet · Среднее\)/.test(t))).toBe(true)
  expect((await paneTexts($)).texts).toContain('Этот чат')
})

test('in auto the language of the last prompt survives a reload', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}', 'почини авторизацию')
  await start($)
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · Автоматически')
  expect(p.buttons['mode-suggest']).toBe('Советовать')
  expect(p.texts).toContain('Этот чат')
})

test('the Russian pane and band', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.row = null
  await start($)
  await pick($, w, '{"level":"high","model":"opus","why":"ошибка входа"}', 'почини авторизацию')
  const p = await paneTexts($)
  expect(p.buttons['mode-auto']).toBe('● Автоматически')
  expect(p.texts).toContain('Выбрано CoreModel для этого чата · ваш выбор по умолчанию: Sonnet · Среднее')
  expect(p.buttons.release).toBe('Вернуть мой выбор')
  expect(p.texts).toContain('Усилие')
  expect(p.texts).toContain('За сессию')
  expect((await band($)).buttons[0]?.label).toBe('Вернуть Sonnet · Среднее')
})
