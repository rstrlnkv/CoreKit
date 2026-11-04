import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { start, step, submit, world, type Eng, type World } from './world'

const SURFACES = ['terminal', 'desktop'] as const
const ABOVE = { plugin: 'coremodel', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 80, scroll: { offset: 0, bodyRows: 6 }, view: {} } } as const
const MODE = { plugin: 'coremodel', component: 'SessionMode', props: { modes: ['default'] } } as const

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
  const r = await $.command.run({ command: 'coremodel', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as never)
  return (r as { text?: string }).text ?? ''
}

test('/coremodel reports the mode and the level the chat runs at', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'High (recommended)'
  await start($)
  expect(await run($, '')).toContain('suggest')
  await switchTo($, w, 'high', 'medium')
  expect(await run($, '')).toContain('High')
})

test('/coremodel auto, suggest, off and on store the mode over the setting', async ($, on) => {
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
  w.reply = 'High (recommended)'
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

function placed(id: string, plugin = 'coremodel') {
  return { plugin: 'coremodel', component: 'Placed', props: { id, plugin } } as const
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
  plugin: 'coremodel',
  component: 'Pane',
  requestId: 'coremodel',
  props: { title: 'CoreModel', isFocused: false, bodyColumns: 40, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
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

test('/coremodel panel opens the pane', async ($, on) => {
  const w = world(on)
  await start($)
  await run($, 'panel')
  expect(w.opened).toEqual([{ id: 'coremodel', title: 'CoreModel' }])
})

test('the pane shows mode, level, last pick and counts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    expect(await has($, /^Now$/, surface)).toBe(true)
    expect(await has($, /^Sonnet · High$/, surface)).toBe(true)
    expect(await has($, /^held by CoreModel · in the menu: Medium \(yours\)$/, surface)).toBe(true)
    expect(await has($, /^Last pick · High$/, surface)).toBe(true)
    expect(await has($, /^auth bug$/, surface)).toBe(true)
    expect(await has($, /^High 1$/, surface)).toBe(true)
    expect(await has($, /^▇+$/, surface)).toBe(true)
    expect(await has($, /Switches by itself, asks before Fable/, surface)).toBe(true)
    const ui = await pane($, surface)
    const auto = await ui.find({ type: 'Button', key: 'mode-auto' })
    expect(String(auto?.props.label)).toBe('Auto')
    expect(auto?.props.variant).toBe('primary')
    expect((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.variant).toBe(undefined)
    expect((await ui.find({ type: 'Button', key: 'level-high' }))?.props.variant).toBe('primary')
    expect((await ui.find({ type: 'Button', key: 'level-medium' }))?.props.variant).toBe(undefined)
    expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
    expect(String((await ui.find({ type: 'Button', key: 'release' }))?.props.label)).toBe("Back to the menu's choice")
    await ui.unmount()
  }
})

test('the pane speaks Russian after a Russian prompt', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  expect(await has($, /^Сейчас$/)).toBe(true)
  expect(await has($, /^Sonnet · Высокое$/)).toBe(true)
  expect(await has($, /^держит CoreModel · в меню: Среднее \(ваше\)$/)).toBe(true)
  expect(await has($, /^Режим$/)).toBe(true)
  expect(await has($, /Меняет сам, спрашивает перед Fable/)).toBe(true)
  const ui = await pane($)
  expect(String((await ui.find({ type: 'Button', key: 'mode-suggest' }))?.props.label)).toBe('Подсказывать')
  expect(String((await ui.find({ type: 'Button', key: 'mode-auto' }))?.props.label)).toBe('Сам')
  expect(String((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.label)).toBe('Выкл')
  expect(String((await ui.find({ type: 'Button', key: 'release' }))?.props.label)).toBe('Вернуть как в меню')
  await ui.unmount()
})

test('the pane marks what the chat runs at when nothing is held', async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await step($, 'medium')
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'level-medium' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
  expect(await ui.find({ type: 'Button', key: 'release' })).toBe(undefined)
  await ui.unmount()
  expect(await has($, /held by/)).toBe(false)
})

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
  expect(await has($, /^Left as it was: 2$/)).toBe(true)
  // The person answered Keep, so the last pick is shown as not applied.
  expect(await has($, /^Last pick · High · not applied$/)).toBe(true)
})

const SPIN = { plugin: 'coremodel', component: 'Spinner', props: { word: 'Thinking', message: null, suffix: '…', mode: 'thinking' } } as const

async function spinner($: Eng, surface: 'terminal' | 'desktop') {
  const ui = await $.ui.mount({ ...SPIN, surface })
  const t = await ui.find({ type: 'Text' })
  await ui.unmount()
  return t?.text
}

test('the working line names a held level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Spinner' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    const p = e.props as { word: string; suffix: string }
    return <Text>{p.word + p.suffix}</Text>
  })
  w.row = null
  await start($)
  for (const surface of SURFACES) expect(await spinner($, surface)).toBe('Thinking…')
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) expect(await spinner($, surface)).toBe('Thinking… · High')
  await run($, 'off')
  for (const surface of SURFACES) expect(await spinner($, surface)).toBe('Thinking…')
})

test('/coremodel with no argument asks for the mode', async ($, on) => {
  const w = world(on)
  w.reply = 'auto'
  await start($)
  const text = await run($, '')
  expect(w.asked.at(-1)).toEqual(['auto', 'suggest', 'off'])
  expect(text).toContain('Mode: auto. Switches by itself')
  expect(text.startsWith('CoreModel')).toBe(false)
  await switchTo($, w, 'high', 'medium')
  expect(w.asked.length).toBe(1)
})

test('a dismissed mode question changes nothing', async ($, on) => {
  const w = world(on)
  w.reply = null
  await start($)
  const text = await run($, '')
  expect(w.asked.length).toBe(1)
  expect(text).toContain('Mode: suggest.')
  w.reply = 'Keep Medium'
  await switchTo($, w, 'high', 'medium')
  expect(w.asked.length).toBe(2)
})

test('off pressed while the classifier runs leaves the level alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'level-low')
  expect(await undoButton($)).toBe(undefined)
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('a pane pick made after the menu moved still holds', async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await step($, 'medium')
  await pressPane($, 'level-high')
  await step($, 'low', 1)
  expect(w.efforts.at(-1)).toBe('high')
})

test('the pane button rows wrap in a narrow pane', async ($, on) => {
  world(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    for (const key of ['modes', 'levels']) expect((await ui.find({ type: 'Box', key }))?.props.flexWrap).toBe('wrap')
    await ui.unmount()
  }
})

test('the pane hides the menu line until a request shows the menu', async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await pressPane($, 'level-high')
  expect(await has($, /in the menu/)).toBe(false)
  expect(await has($, /^held by CoreModel$/)).toBe(true)
  await step($, 'medium')
  expect(await has($, /in the menu: Medium/)).toBe(true)
})

test('no undo when the previous level is unknown', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'unset')
  expect(w.efforts.at(-1)).toBe('high')
  expect(await undoButton($)).toBe(undefined)
})

test('an undo button drawn before off does nothing when pressed after', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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

// CoreModel: the pair in the interface (spec §7).
async function switchPair($: Eng, w: World, model: string, level: string, why = 'auth bug') {
  w.answer = `{"level":"${level}","model":"${model}","why":"${why}"}`
  await submit($, 'fix the login')
  await step($, 'medium')
}

test('switch line names both parts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...ABOVE, surface })
    expect((await ui.find({ type: 'Text', text: /Opus · High \(was Sonnet · Medium\) · auth bug/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('undo restores both parts the silent switch changed', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  expect(String((await undoButton($))?.props.label)).toMatch(/Back to Sonnet · Medium/)
  await pressUndo($)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.efforts.at(-1)).toBe('medium')
})

test('mark arrow follows the model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Placed' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  w.row = null
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
  w.row = null
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

test('footer shows the pair', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect((await ui.find({ type: 'Text', text: /Opus · High/ })) !== undefined).toBe(true)
    await ui.unmount()
  }
})

test('working line names the pair', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  on('ui.render', { component: 'Spinner' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    const p = e.props as { word: string; suffix: string }
    return <Text>{p.word + p.suffix}</Text>
  })
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) expect(await spinner($, surface)).toBe('Thinking… · Opus · High')
})

test('pane model buttons only for allowed models', { options: { models: 'sonnet,opus' } }, async ($, on) => {
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
  expect(w.models).toEqual(['claude-opus-5-5'])
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
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
})

test('pane counts per model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  expect(await has($, /^Opus 1$/)).toBe(true)
  expect(await has($, /^Opus · High$/)).toBe(true)
  expect(await has($, /^held by CoreModel · in the menu: Sonnet · Medium \(yours\)$/)).toBe(true)
  expect(await has($, /^Last pick · Opus · High$/)).toBe(true)
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'model-opus' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe(undefined)
  await ui.unmount()
})

// CoreModel: a model the account cannot use (spec §4.5).
test('an unavailable model is dropped for the session', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
  await $.classic.StopFailure({ error: 'model_not_found', error_details: 'model: claude-opus-5-5' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.logs.some(l => l.includes('Opus'))).toBe(true)
  expect(await has($, /Opus is not available/)).toBe(true)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
})

test('the unavailable note does not mention the setting when it is empty', { options: { mode: 'auto', models: '' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /Opus is not available — CoreModel will not pick it again/)).toBe(true)
  expect(await has($, /models setting/)).toBe(false)
})

test('the unavailable note names the models setting when it is set', { options: { mode: 'auto', models: 'sonnet,opus' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /remove it from the models setting/)).toBe(true)
})

test('other failures leave the model alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'rate_limit' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-opus-5-5')
})

test('with pickModel off the pane shows no model buttons or model counts', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-opus' })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /^Opus 1$/ })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Fable/ })).toBe(undefined)
  expect((await ui.find({ type: 'Text', text: /^High$/ })) !== undefined).toBe(true)
  await ui.unmount()
})

// Small things from the live check.
test('after Back the pane shows the menu level at once', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(await has($, /^Sonnet · High$/)).toBe(true)
  await pressPane($, 'release')
  expect(await has($, /^Sonnet · Medium$/)).toBe(true)
  expect(await has($, /^Sonnet · High$/)).toBe(false)
})

test('a pick the person kept is marked not applied in the pane', async ($, on) => {
  const w = world(on)
  w.reply = 'Keep Medium'
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(await has($, /^Last pick · High · not applied$/)).toBe(true)
  w.reply = 'High (recommended)'
  await switchTo($, w, 'high', 'medium')
  expect(await has($, /^Last pick · High$/)).toBe(true)
})

test('a not applied pick reads in Russian too', async ($, on) => {
  const w = world(on)
  w.reply = 'Оставить «Среднее»'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  expect(await has($, /^Последний выбор · Высокое · не применён$/)).toBe(true)
})

test('an unknown word in models is shown in the pane and logged once', { options: { models: 'hauki, sonnet, opus' } }, async ($, on) => {
  const w = world(on)
  await start($)
  expect(await has($, /models setting.*hauki/)).toBe(true)
  expect(w.logs.length).toBe(1)
  expect(w.logs[0]!.includes('hauki')).toBe(true)
  // Haiku never became one of the choices: the typo dropped it.
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-haiku' })).toBe(undefined)
  expect(await ui.find({ type: 'Button', key: 'model-sonnet' })).not.toBe(undefined)
  await ui.unmount()
})

test('a correct models setting shows no warning', { options: { models: 'haiku, sonnet' } }, async ($, on) => {
  const w = world(on)
  await start($)
  expect(await has($, /models setting/)).toBe(false)
  expect(w.logs.length).toBe(0)
})

test('the models warning is in Russian after a Russian prompt', { options: { models: 'hauki, sonnet' } }, async ($, on) => {
  const w = world(on)
  w.reply = null
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  expect(await has($, /В настройке models неизвестно: «hauki»/)).toBe(true)
})

test('/coremodel replies speak of the pair, not only the level', async ($, on) => {
  world(on)
  await start($)
  expect(await run($, 'auto')).toContain('asks before Fable, Extra high, Max')
  expect(await run($, 'suggest')).toContain('Every switch asks first')
  expect(await run($, 'off')).toBe('Off. /coremodel on turns it back on.')
  expect(await run($, 'on')).toMatch(/^On: (auto|suggest)\.$/)
  expect(await run($, 'panel')).toBe('The pane is open.')
})

test('a model without effort shows no level in the applied line', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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
