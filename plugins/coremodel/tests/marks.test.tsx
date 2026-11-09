// The transcript rows of applied switches.
import { expect, test } from 'claude-code/testing'

import { engineParts, placed, SURFACES, switchPair, switchTo } from './surfaces'
import { start, world } from './world'

test('each applied switch places one mark', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await start($)
  await switchTo($, w, 'high', 'medium')
  await switchTo($, w, 'keep', 'medium', 'ok')
  await switchTo($, w, 'low', 'medium', 'rename it')
  expect(w.placed).toEqual(['mark-1', 'mark-2'])
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...placed('mark-2'), surface })
    expect((await ui.find({ type: 'Text', text: /↓ Effort Low \(was High\)/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('a placed row of another plugin is left alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await start($)
  await switchTo($, w, 'high', 'medium')
  const ui = await $.ui.mount({ ...placed('mark-1', 'other'), surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /engine/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('mark ids stay unique across a session restart', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await start($)
  await switchTo($, w, 'low', 'medium', 'rename it')
  expect(w.placed).toEqual(['mark-1', 'mark-2'])
  const ui = await $.ui.mount({ ...placed('mark-1'), surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Effort High/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('mark arrow follows the model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await start($)
  await switchPair($, w, 'haiku', 'high')
  const ui = await $.ui.mount({ ...placed('mark-1'), surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^↓ Haiku · High \(was Sonnet · Medium\)/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('a new chat clears the rows of the old chat, a reload keeps them', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await start($)
  await switchPair($, w, 'haiku', 'high')
  const shown = async () => {
    const ui = await $.ui.mount({ ...placed('mark-1'), surface: 'desktop' })
    const found = (await ui.find({ type: 'Text', text: /Haiku/ })) !== undefined
    await ui.unmount()
    return found
  }
  await start($)
  expect(await shown()).toBe(true)
  await $.classic.SessionStart({ source: 'clear' } as never)
  expect(await shown()).toBe(false)
})
