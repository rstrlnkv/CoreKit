// The pane: its layout, captions and the lines it shows.
import { expect, test } from 'claude-code/testing'

import { engineParts, has, OPUS_HIGH, PANE, pane, paneTexts, pick, pressPane, run, SURFACES, switchPair, switchTo } from './surfaces'
import { start, step, submit, world } from './world'

test('the pane puts state and mode first, marks the selection in text and says it in plain words', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
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
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.findAll({ type: 'Svg' })).toHaveLength(0)
  await ui.unmount()
})

test('the pane shows the mode, what the chat runs at, and the session', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    expect(await has($, /^CoreModel · Auto$/, surface)).toBe(true)
    expect(await has($, /^This chat$/, surface)).toBe(true)
    expect(await has($, /^Sonnet · High$/, surface)).toBe(true)
    expect(await has($, /^Set by CoreModel for this chat · your default: Medium$/, surface)).toBe(true)
    expect(await has($, /^This session$/, surface)).toBe(true)
    expect(await has($, /^High 1$/, surface)).toBe(true)
    // the last pick is what the chat runs at: not said twice
    expect(await has($, /^Last pick$/, surface)).toBe(false)
    expect(await has($, /^Model$/, surface)).toBe(true)
    expect(await has($, /^Effort$/, surface)).toBe(true)
    expect(await has($, /Asks only before Fable/, surface)).toBe(true)
    const ui = await pane($, surface)
    const auto = await ui.find({ type: 'Button', key: 'mode-auto' })
    expect(String(auto?.props.label)).toBe('● Auto')
    expect(auto?.props.variant).toBe('primary')
    expect((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.variant).toBe(undefined)
    expect((await ui.find({ type: 'Button', key: 'level-high' }))?.props.variant).toBe('primary')
    expect((await ui.find({ type: 'Button', key: 'level-medium' }))?.props.variant).toBe(undefined)
    expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
    expect(String((await ui.find({ type: 'Button', key: 'release' }))?.props.label)).toBe('Use my default')
    await ui.unmount()
  }
})

test('the pane captions are as wide as the longest English caption, plus one', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  const ui = await pane($)
  // "This session" is the longest English caption
  for (const key of ['chat-caption', 'choose-caption', 'session-caption']) {
    expect((await ui.find({ type: 'Box', key }))?.props.minWidth).toBe('This session'.length + 1)
  }
  await ui.unmount()
})

test('the pane captions are as wide as the longest Russian caption, plus one', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  const ui = await pane($)
  // "Последний выбор" is the longest Russian caption: every row's value starts in the same column
  for (const key of ['chat-caption', 'choose-caption', 'session-caption']) {
    expect((await ui.find({ type: 'Box', key }))?.props.minWidth).toBe('Последний выбор'.length + 1)
  }
  await ui.unmount()
})

test('the pane marks what the chat runs at when nothing is held', async ($, on) => {
  world(on)
  await start($)
  await step($, 'medium')
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'level-medium' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
  expect(await ui.find({ type: 'Button', key: 'release' })).toBe(undefined)
  await ui.unmount()
  expect(await has($, /Set by/)).toBe(false)
})

test('a fresh pane says when the chat shows what it runs at', async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await submit($, 'почини авторизацию')
  expect(await has($, /^появится после первого сообщения$/)).toBe(true)
})

test('the pane counts kept prompts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Keep Medium'
  await start($)
  await switchTo($, w, 'xhigh', 'medium')
  await switchTo($, w, 'keep', 'medium', 'ok')
  // Prompts the person kept are not counted as picks.
  expect(await has($, /Extra high 1/)).toBe(false)
  expect(await has($, /^unchanged 2$/)).toBe(true)
  // The person answered Keep, so the last pick is shown as not applied.
  expect(await has($, /^Extra high · auth bug · not applied$/)).toBe(true)
})

test('the pane button rows wrap in a narrow pane', async ($, on) => {
  world(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    for (const key of ['models', 'modes', 'levels']) expect((await ui.find({ type: 'Box', key }))?.props.flexWrap).toBe('wrap')
    await ui.unmount()
  }
})

test('the pane names your default only once a request shows it', async ($, on) => {
  world(on)
  await start($)
  await pressPane($, 'level-high')
  expect(await has($, /your default/)).toBe(false)
  expect(await has($, /^Set by CoreModel for this chat$/)).toBe(true)
  await step($, 'medium')
  expect(await has($, /your default: Medium/)).toBe(true)
})

test('with only the model held, the pane and /coremodel name the same default: the held part', async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.reply = 'nothing'   // the mode question is dismissed: the reply says where things stand
  await start($)
  await step($, 'medium')
  await pressPane($, 'model-opus')
  expect(await has($, /^Set by CoreModel for this chat · your default: Sonnet$/)).toBe(true)
  expect(await run($, '')).toContain('set by CoreModel; your default: Sonnet)')
})

test('pane counts per model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) expect(await has($, /^Opus 1 · High 1$/, surface)).toBe(true)
  expect(await has($, /^Opus · High$/)).toBe(true)
  expect(await has($, /^Set by CoreModel for this chat · your default: Sonnet · Medium$/)).toBe(true)
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'model-opus' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe(undefined)
  await ui.unmount()
})

test('with pickModel off the pane shows no model buttons or model counts', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-opus' })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Opus/ })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Fable/ })).toBe(undefined)
  expect((await ui.find({ type: 'Text', text: /^High$/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('after Back the pane shows the menu level at once', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(await has($, /^Sonnet · High$/)).toBe(true)
  await pressPane($, 'release')
  expect(await has($, /^Sonnet · Medium$/)).toBe(true)
  expect(await has($, /^Sonnet · High$/)).toBe(false)
})

test('a pick the person kept is marked not applied in the pane', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Keep Medium'
  await start($)
  await switchTo($, w, 'xhigh', 'medium')
  expect(await has($, /^Extra high · auth bug · not applied$/)).toBe(true)
  w.reply = 'Extra high (recommended)'
  await switchTo($, w, 'xhigh', 'medium')
  expect(await has($, /not applied/)).toBe(false)
})

test('session counts follow what was applied, not what the classifier asked for', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"x"}'
  w.reply = [null, 'Extra high (recommended)']
  await start($)
  await submit($, 'build the whole app')
  await step($, 'medium')
  for (const surface of SURFACES) expect(await has($, /^Extra high 1$/, surface)).toBe(true)
})

test('every pane row keeps its caption apart from what follows', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($, 'desktop')
  for (const key of ['mode', 'now']) expect((await ui.find({ type: 'Box', key }))?.props.gap).toBe('xs')
  for (const key of ['chat', 'choose-model', 'choose', 'session']) {
    const b = await ui.find({ type: 'Box', key })
    expect(b?.props.flexDirection).toBe('row')
    expect(b?.props.gap).toBe('sm')
  }
  await ui.unmount()
})

test('the pane names a classifier that keeps failing, and drops the line once a pick works', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  for (let i = 0; i < 2; i += 1) {
    w.answers = [{ fail: true }, { fail: true }]
    await submit($, 'fix the login')
    await step($, 'medium')
  }
  expect(await has($, /classifier.*api-error.*unchanged/)).toBe(true)
  w.answers = ['{"level":"high","why":"auth bug"}']
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(await has($, /classifier/)).toBe(false)
})

test('the pane draws its bold text with weight, not the deprecated bold', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  const t = await ui.find({ type: 'Text', text: /^Opus · High$/ })
  expect(t?.props.weight).toBe('semibold')
  await ui.unmount()
})
