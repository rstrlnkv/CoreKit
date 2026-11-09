// The band above the prompt: the modes, Suggest, the switch line and its undo.
import { expect, test } from 'claude-code/testing'

import { ABOVE, band, engineParts, footer, has, MID, OPUS_HIGH, paneTexts, pick, pressBand, pressPane, pressUndo, run, SURFACES, switchPair, switchTo, undoButton } from './surfaces'
import { start, step, submit, world } from './world'

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
  await start($)
  await pick($, w, OPUS_HIGH)
  await w.clock.advance(15_000)
  expect((await band($)).texts).toEqual(['engine'])
})

test('Suggest mid-chat: Switch to a stronger model asks the cost first', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
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
  await start($)
  await pick($, w, '{"level":"medium","model":"sonnet","why":"x"}')
  expect((await band($)).texts).toEqual(['engine'])
})

test('a switch agreed in a dialog shows no band, only the transcript row', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
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
  await start($)
  await pick($, w, OPUS_HIGH)
  const b = await band($)
  expect(b.texts.some(t => /^✓ CoreModel: Opus · High \(was Sonnet · Medium\) · auth bug/.test(t))).toBe(true)
  expect(b.buttons.map(x => [x.key, x.label, x.hotkey])).toEqual([['undo', 'Back to Sonnet · Medium', '1']])
})

test('the applied line shows level, from and why, then goes after 15 s', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect((await ui.find({ type: 'Text', text: /^✓ CoreModel: Effort High \(was Medium\) · auth bug/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
  await w.clock.advance(15_000)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect(await ui.find({ type: 'Text', text: /CoreModel:/ })).toBe(undefined)
    await ui.unmount()
  }
})

test('the switch line says when a stand-in replaced an unavailable model', { options: { mode: 'auto', useFable: false } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchPair($, w, 'fable', 'high', 'whole app')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Opus · High \(was Sonnet · Medium\) · Fable is not available, Opus instead; whole app/ })) !== undefined).toBe(true)
  await ui.unmount()
  w.answer = '{"level":"high","model":"fable","why":"всё приложение"}'
  w.hostLanguage = 'russian'
  await start($)
  await submit($, 'собери всё приложение')
  await step($, 'medium')
  const ru = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ru.find({ type: 'Text', text: /Fable недоступна, вместо неё Opus; всё приложение/ })) !== undefined).toBe(true)
  await ru.unmount()
})

test('switch line names both parts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect((await ui.find({ type: 'Text', text: /Opus · High \(was Sonnet · Medium\) · auth bug/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('a model without effort shows no level in the applied line', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.answer = '{"level":"high","model":"opus","why":"auth bug"}'
  await start($)
  await submit($, 'fix the login')
  await step($, undefined, 0)
  expect(w.models.length).toBe(1)
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Opus/ })).not.toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Effort|High/ })).toBe(undefined)
  await ui.unmount()
  expect(await has($, /^Opus$/)).toBe(true)
})

test('an auto switch shows an undo button that releases the hold', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const b = await undoButton($, surface)
    expect(String(b?.props.label ?? '')).toMatch(/Back to Medium/)
  }
  await pressUndo($)
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Effort:/ })).toBe(undefined)
  await ui.unmount()
})

test('undo holds the previous held level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await switchTo($, w, 'low', 'medium', 'rename a variable')
  expect(w.efforts.at(-1)).toBe('low')
  await pressUndo($)
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('high')
})

test('no undo after an agreed switch', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.reply = 'Extra high (recommended)'
  await start($)
  await switchTo($, w, 'xhigh', 'medium')
  expect(w.efforts.at(-1)).toBe('xhigh')
  expect(await undoButton($)).toBe(undefined)
})

test('undo after the menu moved does nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await step($, 'low', 1)
  await pressUndo($)
  await step($, 'low', 2)
  expect(w.efforts.at(-1)).toBe('low')
})

test('no undo when the previous level is unknown', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'unset')
  expect(w.efforts.at(-1)).toBe('high')
  expect(await undoButton($)).toBe(undefined)
})

test('an undo button drawn before off does nothing when pressed after', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  await run($, 'off')
  await run($, 'auto')
  await pressPane($, 'level-low')
  try {
    await ui.press({ key: 'undo' })
  } catch {
    // The engine may refuse a press on a button it no longer draws; either way nothing changes.
  }
  await ui.unmount()
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('undo restores both parts the silent switch changed', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  expect(String((await undoButton($))?.props.label)).toMatch(/Back to Sonnet · Medium/)
  await pressUndo($)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('medium')
})

test('/coremodel undo takes back the last silent switch, after its band is gone too', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  await w.clock.advance(15_000)
  expect(await undoButton($)).toBe(undefined)
  expect(await run($, 'undo')).toContain('Sonnet · Medium')
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('medium')
  // nothing left to take back
  expect(await run($, 'undo')).toContain('Nothing to undo')
})

test('/coremodel undo leaves a choice the person made since', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'level-low')
  expect(await run($, 'undo')).toContain('Nothing to undo')
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('in VS Code, where the band is not drawn, a silent switch is told in a toast with the undo command', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: '/w', surface: 'vscode', isInteractive: true })
  await switchTo($, w, 'high', 'medium')
  expect(w.toasts.length).toBe(1)
  expect(w.toasts[0]).toContain('High')
  expect(w.toasts[0]).toContain('/coremodel undo')
})

test('on the terminal and the desktop a silent switch raises no toast: the band says it', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(w.toasts).toEqual([])
})
