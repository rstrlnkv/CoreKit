import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { start, step, submit, world, type Eng, type World } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const ABOVE = { plugin: 'coreeffort', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 80, scroll: { offset: 0, bodyRows: 6 }, view: {} } } as const
const MODE = { plugin: 'coreeffort', component: 'SessionMode', props: { modes: ['default'] } } as const

// The engine's own footer: what draws when the plugin leaves the slot alone.
function engineFooter(on: On) {
  on('ui.render', { component: 'SessionMode' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{(e.props as { modes: readonly string[] }).modes.join(' | ')}</Text>
  })
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

async function switchTo($: Eng, w: World, level: string, from: string, text = 'fix the login') {
  w.answer = `{"level":"${level}","why":"auth bug"}`
  await submit($, text)
  await step($, from)
}

test('the applied line shows level, from and why, then goes after 15 s', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect((await ui.find({ type: 'Text', text: /Effort: High \(was Medium\) · auth bug/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
  await w.clock.advance(15_000)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect(await ui.find({ type: 'Text', text: /Effort:/ })).toBe(undefined)
    await ui.unmount()
  }
})

test('a Russian prompt gives the line in Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Усилие: Высокое \(было Среднее\)/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('the footer names a held level and leaves the slot alone otherwise', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect(await ui.find({ type: 'Text', text: /Effort High/ })).toBe(undefined)
    await ui.unmount()
  }
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect((await ui.find({ type: 'Text', text: /Effort High/ })) !== undefined).toBe(true)
    expect((await ui.find({ type: 'Text', text: /default/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('a new session start clears the footer label and the line', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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

async function run($: Eng, args: string) {
  const r = await $.command.run({ command: 'coreeffort', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as never)
  return (r as { text?: string }).text ?? ''
}

test('/coreeffort reports the mode and the level the chat runs at', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'Switch to High'
  await start($)
  expect(await run($, '')).toContain('suggest')
  await switchTo($, w, 'high', 'medium')
  expect(await run($, '')).toContain('High')
})

test('/coreeffort auto, suggest, off and on store the mode over the setting', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  await start($)
  await run($, 'auto')
  await switchTo($, w, 'high', 'medium')
  expect(w.asked.length).toBe(0)
  await run($, 'off')
  await switchTo($, w, 'low', 'high')
  expect(w.model.length).toBe(1)
  await run($, 'on')
  await switchTo($, w, 'low', 'high')
  expect(w.asked.length).toBe(0)
  expect(w.efforts.at(-1)).toBe('low')
  await run($, 'suggest')
  w.reply = 'Keep Low'
  await switchTo($, w, 'medium', 'low')
  expect(w.asked.length).toBe(1)
})

test('off clears a held level and its label', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await run($, 'off')
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
  const ui = await $.ui.mount({ ...MODE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Effort High/ })).toBe(undefined)
  await ui.unmount()
})

async function undoButton($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...ABOVE, surface })
  const b = await ui.find({ type: 'Button', key: 'undo' })
  await ui.unmount()
  return b
}

async function pressUndo($: Eng) {
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  await ui.press({ key: 'undo' })
  await ui.unmount()
}

test('an auto switch shows an undo button that releases the hold', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await switchTo($, w, 'low', 'medium', 'rename a variable')
  expect(w.efforts.at(-1)).toBe('low')
  await pressUndo($)
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('high')
})

test('no undo after an agreed switch', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'Switch to High'
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(await undoButton($)).toBe(undefined)
})

test('undo after the menu moved does nothing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await step($, 'low', 1)
  await pressUndo($)
  await step($, 'low', 2)
  expect(w.efforts.at(-1)).toBe('low')
})

function placed(id: string, plugin = 'coreeffort') {
  return { plugin: 'coreeffort', component: 'Placed', props: { id, plugin } } as const
}

test('each applied switch places one mark', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await switchTo($, w, 'keep', 'medium', 'ok')
  await switchTo($, w, 'low', 'medium', 'rename it')
  expect(w.placed).toEqual(['mark-1', 'mark-2'])
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...placed('mark-2'), surface })
    expect((await ui.find({ type: 'Text', text: /↓ Effort: Low \(was High\)/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('a placed row of another plugin is left alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  const ui = await $.ui.mount({ ...placed('mark-1', 'other'), surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /engine/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('mark ids stay unique across a session restart', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await start($)
  await switchTo($, w, 'low', 'medium', 'rename it')
  expect(w.placed).toEqual(['mark-1', 'mark-2'])
  const ui = await $.ui.mount({ ...placed('mark-1'), surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Effort: High/ })) !== undefined).toBe(true)
  await ui.unmount()
})

const PANE = {
  plugin: 'coreeffort',
  component: 'Pane',
  requestId: 'coreeffort',
  props: { title: 'CoreEffort', isFocused: false, bodyColumns: 40, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

async function pane($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  return $.ui.mount({ ...PANE, surface })
}

async function has($: Eng, text: RegExp, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await pane($, surface)
  const found = await ui.find({ type: 'Text', text })
  await ui.unmount()
  return found !== undefined
}

async function pressPane($: Eng, key: string) {
  const ui = await pane($)
  await ui.press({ key })
  await ui.unmount()
}

test('/coreeffort panel opens the pane', async ($, on) => {
  const w = world(on)
  await start($)
  await run($, 'panel')
  expect(w.opened).toEqual([{ id: 'coreeffort', title: 'CoreEffort' }])
})

test('the pane shows mode, level, last pick and counts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    expect(await has($, /Chat runs at: High/, surface)).toBe(true)
    expect(await has($, /in the menu: Medium/, surface)).toBe(true)
    expect(await has($, /High · auth bug/, surface)).toBe(true)
    expect(await has($, /^High 1$/, surface)).toBe(true)
    const ui = await pane($, surface)
    expect(String((await ui.find({ type: 'Button', key: 'mode-auto' }))?.props.label)).toBe('● auto')
    await ui.unmount()
  }
})

test('a mode button in the pane sets the mode', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pressPane($, 'mode-off')
  await switchTo($, w, 'high', 'medium')
  expect(w.model.length).toBe(0)
  const ui = await pane($)
  expect(String((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.label)).toBe('● off')
  await ui.unmount()
})

test('a level picked in the pane holds at once, xhigh included', async ($, on) => {
  const w = world(on)
  w.row = null
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
  w.row = null
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
  w.row = null
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
  engineFooter(on)
  w.row = null
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

test('a fresh pane says there are no picks yet', async ($, on) => {
  const w = world(on)
  w.answer = new Error('down')
  await start($)
  await submit($, 'почини авторизацию')
  await step($, 'medium')
  expect(await has($, /Пока нет выборов/)).toBe(true)
})

test('the pane counts kept prompts', async ($, on) => {
  const w = world(on)
  w.row = null
  w.reply = 'Keep Medium'
  await start($)
  await switchTo($, w, 'high', 'medium')
  await switchTo($, w, 'keep', 'medium', 'ok')
  expect(await has($, /^High 1$/)).toBe(true)
  expect(await has($, /Kept as it was 2/)).toBe(true)
  expect(await has($, /High · auth bug/)).toBe(true)
})
