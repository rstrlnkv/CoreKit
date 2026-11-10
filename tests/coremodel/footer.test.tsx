// The footer: the engine's mode words, the CoreModel button and the working line.
import { expect, test } from 'claude-code/testing'

import { ABOVE, engineParts, footer, MODE, OPUS_HIGH, pick, run, SPIN, SURFACES, switchTo } from './surfaces'
import { start, world } from './world'

test('the footer names what CoreModel set and is a plain button otherwise', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect(String((await ui.find({ type: 'Button', key: 'pane' }))?.props.label)).toBe('CoreModel')
    await ui.unmount()
  }
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect(String((await ui.find({ type: 'Button', key: 'pane' }))?.props.label)).toBe('CoreModel · Sonnet · High')
    expect((await ui.find({ type: 'Text', text: /default/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('a new session start clears the footer label and the line', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await start($)
  const footer = await $.ui.mount({ ...MODE, surface: 'desktop' })
  expect(await footer.find({ type: 'Text', text: /Effort High/ })).toBe(undefined)
  await footer.unmount()
  const above = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect(await above.find({ type: 'Text', text: /Effort:/ })).toBe(undefined)
  await above.unmount()
})

test('the footer button carries the state', async ($, on) => {
  const w = world(on)
  engineParts(on)
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
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await $.ui.mount({ ...SPIN, surface: 'desktop' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Thinking…')
  await ui.unmount()
})

test('the footer carries a button that opens and closes the pane without the chat', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  const closed = w.closed
  engineParts(on)
  await start($)
  for (const surface of SURFACES) {
    const before = w.opened.length
    let ui = await $.ui.mount({ ...MODE, surface })
    const btn = await ui.find({ type: 'Button', key: 'pane' })
    expect(String(btn?.props.label)).toBe('CoreModel')
    expect(btn?.props.variant).toBe(undefined)
    // The engine's own mode labels stay beside it.
    expect((await ui.find({ type: 'Text', text: /default/ })) !== undefined).toBe(true)
    await ui.press({ key: 'pane' })
    await ui.unmount()
    expect(w.opened.length).toBe(before + 1)
    expect(w.opened[before]).toEqual({ id: 'coremodel', title: 'CoreModel' })
    // Open now: the button is marked and a second press closes it.
    ui = await $.ui.mount({ ...MODE, surface })
    expect((await ui.find({ type: 'Button', key: 'pane' }))?.props.variant).toBe('primary')
    await ui.press({ key: 'pane' })
    await ui.unmount()
    expect(closed).toEqual(['coremodel'])
    // Close it for the next surface.
    closed.length = 0
    w.opened.length = 0
  }
  expect(w.prompts.length).toBe(0)
})
