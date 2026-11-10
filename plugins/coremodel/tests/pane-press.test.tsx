// The pane's buttons: mode, level, model and Release, and a press against a pick on its way.
import { expect, test } from 'claude-code/testing'

import { ABOVE, engineParts, MID, OPUS_HIGH, pane, pressPane, SURFACES, switchTo, undoButton } from './surfaces'
import { start, step, submit, world, type World } from './world'

async function waitForQuestion(w: World) {
  for (let i = 0; w.asked.length === 0; i += 1) {
    if (i > 500) throw new Error('the question was never asked')
    await w.clock.settle()
  }
}

test('a mode button in the pane sets the mode', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pressPane($, 'mode-off')
  await switchTo($, w, 'high', 'medium')
  expect(w.model.length).toBe(0)
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.variant).toBe('primary')
  await ui.unmount()
})

test('a level picked in the pane holds at once, xhigh included', async ($, on) => {
  const w = world(on)
  await start($)
  await step($, 'medium')
  await pressPane($, 'level-xhigh')
  await step($, 'medium', 1)
  expect(w.asked.length).toBe(0)
  expect(w.efforts.at(-1)).toBe('xhigh')
  expect(w.placed).toEqual([])
})

test('a pane pick before any request survives the first request', async ($, on) => {
  const w = world(on)
  await start($)
  await pressPane($, 'level-high')
  await step($, 'medium')
  await step($, 'medium', 1)
  expect(w.efforts).toEqual(['high', 'high'])
  await step($, 'low', 2)
  expect(w.efforts.at(-1)).toBe('low')
})

test('Release in the pane drops the hold', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'release')
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'release' })).toBe(undefined)
  await ui.unmount()
})

test('off from the pane clears the band and its undo', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'mode-off')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /engine/ })) !== undefined).toBe(true)
  expect(await ui.find({ type: 'Button', key: 'undo' })).toBe(undefined)
  await ui.unmount()
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
})

test('off pressed while the classifier runs leaves the level alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  let answer: (s: string) => void = () => {}
  w.answer = new Promise<string>(r => {
    answer = r
  })
  await start($)
  await submit($, 'fix the login')
  const running = step($, 'medium')
  await pressPane($, 'mode-off')
  answer('{"level":"high","why":"auth bug"}')
  await running
  expect(w.efforts).toEqual(['medium'])
  expect(w.placed).toEqual([])
})

test('a level picked in the pane takes the undo button away', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'level-low')
  expect(await undoButton($)).toBe(undefined)
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('a pane pick made after the menu moved still holds', async ($, on) => {
  const w = world(on)
  await start($)
  await step($, 'medium')
  await pressPane($, 'level-high')
  await step($, 'low', 1)
  expect(w.efforts.at(-1)).toBe('high')
})

test('pane model buttons only for allowed models', { options: { useHaiku: false, useFable: false } }, async ($, on) => {
  world(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    expect((await ui.find({ type: 'Button', key: 'model-opus' })) !== undefined).toBe(true)
    expect((await ui.find({ type: 'Button', key: 'model-sonnet' })) !== undefined).toBe(true)
    expect(await ui.find({ type: 'Button', key: 'model-haiku' })).toBe(undefined)
    expect((await ui.find({ type: 'Box', key: 'models' }))?.props.flexWrap).toBe('wrap')
    await ui.unmount()
  }
})

test('pane model press on an empty chat holds at once', async ($, on) => {
  const w = world(on)
  await start($)
  await pressPane($, 'model-opus')
  await step($, 'medium')
  expect(w.asked.length).toBe(0)
  expect(w.models).toEqual(['opus'])
})

test('a level pressed in the pane while a question is open is not overridden by the late answer', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","why":"w"}'
  let answer!: (r: string) => void
  w.reply = new Promise<string>(r => (answer = r))
  await start($)
  await submit($, 'fix the login')
  const first = step($, 'medium')
  await waitForQuestion(w)
  await pressPane($, 'level-low')
  answer('Extra high (recommended)')
  await first
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('Release pressed in the pane while the classifier runs is not overridden by the late pick', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  let answer!: (r: string) => void
  w.answer = new Promise<string>(r => (answer = r))
  await submit($, 'now fix the typo')
  const second = step($, 'medium', 0)
  for (let i = 0; w.model.length < 2; i += 1) {
    if (i > 500) throw new Error('the classifier was never asked')
    await w.clock.settle()
  }
  await pressPane($, 'release')
  answer('{"level":"low","why":"typo"}')
  await second
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
})

test('a dismissed cost question after a model press mid-chat keeps the current model', async ($, on) => {
  const w = world(on)
  w.lastReply = MID
  w.reply = null
  await start($)
  await step($, 'medium')
  await pressPane($, 'model-opus')
  await waitForQuestion(w)
  await w.clock.settle()
  expect(w.asked).toEqual([['Switch to Opus', 'Keep Sonnet']])
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
  await ui.unmount()
})

test('a model pressed in the pane while the classifier runs is not overridden by the late pick', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  let answer!: (r: string) => void
  w.answer = new Promise<string>(r => (answer = r))
  await start($)
  await submit($, 'fix the login')
  const first = step($, 'medium')
  for (let i = 0; w.model.length < 1; i += 1) {
    if (i > 500) throw new Error('the classifier was never asked')
    await w.clock.settle()
  }
  await pressPane($, 'model-haiku')
  answer(OPUS_HIGH)
  await first
  await step($, 'medium', 1)
  expect(w.models).toEqual(['haiku', 'haiku'])
  expect(w.efforts).toEqual(['medium', 'medium'])
  expect(w.placed).toEqual([])
})
