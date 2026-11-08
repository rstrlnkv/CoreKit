import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { texts } from '../hooks/policy'
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

test('a Russian prompt gives the line in Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Усилие Высокое \(было Среднее\)/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('the footer names what CoreModel set and is a plain button otherwise', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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

test('/coremodel auto, suggest, off and on store the mode over the setting', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  await start($)
  await run($, 'auto')
  await switchTo($, w, 'high', 'medium')
  expect(w.efforts.at(-1)).toBe('high')
  await run($, 'off')
  await switchTo($, w, 'low', 'high')
  expect(w.model.length).toBe(1)
  await run($, 'on')
  await switchTo($, w, 'low', 'high')
  expect(w.efforts.at(-1)).toBe('low')
  await run($, 'suggest')
  await switchTo($, w, 'medium', 'low')
  // Suggest offers it above the prompt; the request runs as it was
  expect(w.asked.length).toBe(0)
  expect(w.efforts.at(-1)).toBe('low')
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

test('no undo after an agreed switch', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'Extra high (recommended)'
  await start($)
  await switchTo($, w, 'xhigh', 'medium')
  expect(w.efforts.at(-1)).toBe('xhigh')
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
  expect((await ui.find({ type: 'Text', text: /Effort High/ })) !== undefined).toBe(true)
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

test('the footer carries a button that opens and closes the pane without the chat', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  const closed = w.closed
  engineFooter(on)
  w.row = null
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

test('/coremodel panel opens the pane', async ($, on) => {
  const w = world(on)
  await start($)
  await run($, 'panel')
  expect(w.opened).toEqual([{ id: 'coremodel', title: 'CoreModel' }])
})

// The world without its own ui.open answer, so a test can answer it (a hook registers once per event).
function withoutOpen(on: On): On {
  return ((name: string, ...rest: unknown[]) => (name === 'ui.open' ? undefined : (on as (...a: unknown[]) => unknown)(name, ...rest))) as On
}

// With no surface attached (a -p run, say) the engine answers with an internal reason; the reply is plain words.
test('/coremodel panel with no surface says so in plain words', async ($, on) => {
  const w = world(withoutOpen(on))
  on('ui.open', () => ({ value: { isPlaced: false, reason: 'no-surface: no surface is attached ($.session.surfaces() is empty)' } }) as never)
  await start($)
  const text = await run($, 'panel')
  expect(text).toBe(texts('en').paneNoSurface)
  expect(text).not.toContain('no-surface')
  expect(text).not.toContain('$.')
  w.answer = '{"level":"keep","why":"x"}'
  w.hostLanguage = 'russian'
  await submit($, 'почини авторизацию')
  expect(await run($, 'panel')).toBe(texts('ru').paneNoSurface)
})

test('/coremodel panel that waits for another reason shows no internal reason', async ($, on) => {
  world(withoutOpen(on))
  on('ui.open', () => ({ value: { isPlaced: false, reason: 'attached surfaces place no panes: web' } }) as never)
  await start($)
  const text = await run($, 'panel')
  expect(text).toBe(texts('en').paneWaiting)
  expect(text).not.toContain('surfaces')
})

test('the pane shows the mode, what the chat runs at, and the session', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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

test('the pane speaks Russian after a Russian prompt', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  expect(await has($, /^Этот чат$/)).toBe(true)
  expect(await has($, /^Sonnet · Высокое$/)).toBe(true)
  expect(await has($, /^Выбрано CoreModel для этого чата · ваш выбор по умолчанию: Среднее$/)).toBe(true)
  expect(await has($, /^CoreModel · Автоматически$/)).toBe(true)
  expect(await has($, /^Модель$/)).toBe(true)
  expect(await has($, /^Усилие$/)).toBe(true)
  expect(await has($, /^За сессию$/)).toBe(true)
  expect(await has($, /Спрашивает только перед Fable/)).toBe(true)
  const ui = await pane($)
  expect(String((await ui.find({ type: 'Button', key: 'mode-suggest' }))?.props.label)).toBe('Советовать')
  expect(String((await ui.find({ type: 'Button', key: 'mode-auto' }))?.props.label)).toBe('● Автоматически')
  expect(String((await ui.find({ type: 'Button', key: 'mode-off' }))?.props.label)).toBe('Выкл')
  expect(String((await ui.find({ type: 'Button', key: 'release' }))?.props.label)).toBe('Вернуть мой выбор')
  await ui.unmount()
})

test('the pane captions are as wide as the longest English caption, plus one', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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
  w.row = null
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
  const w = world(on)
  w.row = null
  await start($)
  await step($, 'medium')
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'level-medium' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe('primary')
  expect(await ui.find({ type: 'Button', key: 'release' })).toBe(undefined)
  await ui.unmount()
  expect(await has($, /Set by/)).toBe(false)
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

test('a fresh pane says when the chat shows what it runs at', async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await submit($, 'почини авторизацию')
  expect(await has($, /^появится после первого сообщения$/)).toBe(true)
})

test('the pane counts kept prompts', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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

test('/coremodel with no argument asks for the mode', async ($, on) => {
  const w = world(on)
  w.reply = 'Suggest'
  await start($)
  const text = await run($, '')
  expect(w.asked.at(-1)).toEqual(['Auto', 'Suggest', 'Off'])
  expect(text).toContain('Mode: Suggest. Never asks')
  expect(text.startsWith('CoreModel')).toBe(false)
  await switchTo($, w, 'xhigh', 'medium')
  expect(w.asked.length).toBe(1)
})

test('a dismissed mode question changes nothing', async ($, on) => {
  const w = world(on)
  w.reply = null
  await start($)
  const text = await run($, '')
  expect(w.asked.length).toBe(1)
  expect(text).toContain('Mode: Auto.')
  await switchTo($, w, 'xhigh', 'medium')
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
    for (const key of ['models', 'modes', 'levels']) expect((await ui.find({ type: 'Box', key }))?.props.flexWrap).toBe('wrap')
    await ui.unmount()
  }
})

test('the pane names your default only once a request shows it', async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await pressPane($, 'level-high')
  expect(await has($, /your default/)).toBe(false)
  expect(await has($, /^Set by CoreModel for this chat$/)).toBe(true)
  await step($, 'medium')
  expect(await has($, /your default: Medium/)).toBe(true)
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

// CoreModel: the pair in the interface.
async function switchPair($: Eng, w: World, model: string, level: string, why = 'auth bug') {
  w.answer = `{"level":"${level}","model":"${model}","why":"${why}"}`
  await submit($, 'fix the login')
  await step($, 'medium')
}

test('/coremodel probe writes the /config rows to the debug log, never to the chat', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  await start($)
  const out = await run($, 'probe')
  expect(out).not.toContain('effortLevel')
  expect(w.logs.some(l => l.includes('effortLevel') && l.includes('Low, Medium, High, Extra high, Max'))).toBe(true)
  expect(w.logSinks.every(s => s === 'debug')).toBe(true)
  expect(w.set.length).toBe(0)
})

test('/coremodel probe says so when the rows cannot be read', async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await run($, 'probe')
  expect(w.logs.some(l => l.includes('no rows'))).toBe(true)
})

test('/coremodel names the model and the level, in the host language', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'nothing'   // the mode question is dismissed: the reply says where things stand
  await start($)
  await switchPair($, w, 'opus', 'high')
  const en = await run($, '')
  expect(en).toContain('Opus · High')
  expect(en).toContain('set by CoreModel; your default: Sonnet · Medium')
  w.answer = '{"level":"high","model":"opus","why":"x"}'
  w.hostLanguage = 'russian'
  await submit($, 'почини авторизацию')
  await step($, 'high', 1, undefined, 'claude-opus-5-5')
  const ru = await run($, '')
  expect(ru).toContain('Opus · Высокое')
  expect(ru).toContain('/coremodel auto')
  expect(ru).not.toContain('This chat runs at')
  // the mode replies follow the same language
  expect(await run($, 'suggest')).toContain('Режим: «Советовать»')
  expect(await run($, 'off')).toContain('/coremodel on')
  expect(await run($, 'off')).not.toContain('Off.')
  expect(await run($, 'on')).toContain('Включён')
})

test('/coremodel with pickModel off names the level only', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  w.reply = 'nothing'
  await start($)
  await switchTo($, w, 'high', 'medium')
  const out = await run($, '')
  expect(out).toContain('High')
  expect(out).not.toContain('Sonnet')
})

test('the switch line says when a stand-in replaced an unavailable model', { options: { mode: 'auto', useFable: false } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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

test('pane counts per model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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

// CoreModel: a model the account cannot use.
test('an unavailable model is dropped for the session', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('opus')
  await $.classic.StopFailure({ error: 'model_not_found', error_details: 'model: claude-opus-5-5' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
  expect(w.logs.some(l => l.includes('Opus'))).toBe(true)
  expect(await has($, /Opus is not available/)).toBe(true)
  await switchPair($, w, 'opus', 'medium')
  expect(w.models.at(-1)).toBe('claude-sonnet-5-5')
})

test('the pane offers only the models the account lists', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku', 'best']
  await start($)
  const btn = async (k: string) => {
    const ui = await pane($)
    const f = await ui.find({ type: 'Button', key: `model-${k}` })
    await ui.unmount()
    return f !== undefined
  }
  expect(await btn('sonnet')).toBe(true)
  expect(await btn('fable')).toBe(false)
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku', 'fable', 'best']
  await run($, 'recheck')
  expect(await btn('fable')).toBe(true)
})

test('/coremodel recheck brings back a model dropped after model_not_found', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found', error_details: 'model: claude-opus-5-5' } as never)
  expect(await has($, /Opus is not available/)).toBe(true)
  const text = await run($, 'recheck')
  expect(text).toContain('Opus')
  expect(await has($, /Opus is not available/)).toBe(false)
})

test('the unavailable note offers recheck and never sends the person to the models setting', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /Opus is not available — CoreModel will not pick it again this session \(\/coremodel recheck tries again\)/)).toBe(true)
  expect(await has($, /models setting/)).toBe(false)
})

test('the unavailable note is the same when the model is switched on in the settings', { options: { mode: 'auto', useHaiku: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found' } as never)
  expect(await has($, /recheck tries again/)).toBe(true)
  expect(await has($, /remove it from/)).toBe(false)
})

test('/coremodel recheck says what CoreModel may pick, in the host language', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.modelRow = ['default', 'sonnet', 'opus', 'haiku']
  await start($)
  expect(await run($, 'recheck')).toBe('Models CoreModel may pick: Haiku, Sonnet, Opus.')
  w.answer = '{"level":"keep","why":"x"}'
  w.hostLanguage = 'russian'
  await submit($, 'почини авторизацию')
  await step($, 'medium')
  expect(await run($, 'recheck')).toBe('Модели, которые может выбрать CoreModel: Haiku, Sonnet, Opus.')
})

test('/coremodel recheck says when the list is unusable, empty, or the model is not picked', async ($, on) => {
  const w = world(on)
  w.row = null
  w.listThrows = true
  await start($)
  expect(await run($, 'recheck')).toContain('could not be used')
  w.listThrows = false
  w.modelRow = ['default', 'sonnet', 'opus']
  w.row = null
  expect(await run($, 'recheck')).not.toContain('could not be used')
})

test('/coremodel recheck explains an empty result', { options: { useHaiku: false, useSonnet: false, useOpus: false } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.modelRow = ['default', 'sonnet', 'opus']
  await start($)
  expect(await run($, 'recheck')).toContain('share no model')
})

test('/coremodel recheck with pickModel off names the effort only', { options: { pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  expect(await run($, 'recheck')).toContain('picks the effort only')
})

test('other failures leave the model alone', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'rate_limit' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
})

test('with pickModel off the pane shows no model buttons or model counts', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-opus' })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Opus/ })).toBe(undefined)
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

test('a not applied pick reads in Russian too', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Оставить «Среднее»'
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'xhigh', 'medium', 'почини авторизацию')
  expect(await has($, /^Очень высокое · auth bug · не применён$/)).toBe(true)
})

test('no model warning and no log line with the default switches', async ($, on) => {
  const w = world(on)
  await start($)
  expect(await has($, /models setting|настройк/)).toBe(false)
  expect(w.logs.length).toBe(0)
})

test('a model switched off in the settings has no pane button and is never picked', { options: { mode: 'auto', useHaiku: false } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-haiku' })).toBe(undefined)
  expect(await ui.find({ type: 'Button', key: 'model-sonnet' })).not.toBe(undefined)
  await ui.unmount()
})

test('/coremodel replies say what each mode does', async ($, on) => {
  world(on)
  await start($)
  expect(await run($, 'auto')).toBe('Mode: Auto. Asks only before Fable, Extra high, Max and a stronger model mid-chat.')
  expect(await run($, 'suggest')).toBe('Mode: Suggest. Never asks: suggests above the prompt, you press to switch.')
  expect(await run($, 'off')).toBe('Off. /coremodel on turns it back on.')
  expect(await run($, 'on')).toBe('On: Suggest.')
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

test('a subagent failing with model_not_found does not drop the held model', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'medium')
  await $.classic.StopFailure({ error: 'model_not_found', agent_id: 'a1' } as never)
  await step($, 'medium', 1)
  expect(w.models.at(-1)).toBe('opus')
  expect(await has($, /not available/)).toBe(false)
})

async function waitForQuestion(w: World) {
  for (let i = 0; w.asked.length === 0; i += 1) {
    if (i > 500) throw new Error('the question was never asked')
    await w.clock.settle()
  }
}

test('a level pressed in the pane while a question is open is not overridden by the late answer', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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
  w.row = null
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

test('session counts follow what was applied, not what the classifier asked for', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  w.answer = '{"level":"xhigh","model":"fable","why":"x"}'
  w.reply = [null, 'Extra high (recommended)']
  await start($)
  await submit($, 'build the whole app')
  await step($, 'medium')
  for (const surface of SURFACES) expect(await has($, /^Extra high 1$/, surface)).toBe(true)
})

test('footer shows the held pair on the button', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...MODE, surface })
    expect(String((await ui.find({ type: 'Button', key: 'pane' }))?.props.label)).toBe('CoreModel · Opus · High')
    await ui.unmount()
  }
})

test('every pane row keeps its caption apart from what follows', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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

test('the mode question and the kept count read in Russian', async ($, on) => {
  const w = world(on)
  w.row = null
  w.reply = 'Автоматически'
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'keep', 'medium', 'почини авторизацию')
  const text = await run($, '')
  expect(w.asked.at(-1)).toEqual(['Автоматически', 'Советовать', 'Выкл'])
  expect(text).toContain('Режим: «Автоматически»')
  expect(await has($, /^без изменений 1$/)).toBe(true)
})

test('/coremodel recheck says when every model is switched off in the settings', { options: { useHaiku: false, useSonnet: false, useOpus: false, useFable: false } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  expect(await run($, 'recheck')).toContain('switched off in the settings')
})

test('the pane names a classifier that keeps failing, and drops the line once a pick works', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
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

test('/coremodel undo takes back the last silent switch, after its band is gone too', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineFooter(on)
  w.row = null
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
  engineFooter(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'level-low')
  expect(await run($, 'undo')).toContain('Nothing to undo')
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('low')
})

test('in VS Code, where the band is not drawn, a silent switch is told in a toast with the undo command', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await $.session.start({ cwd: '/w', surface: 'vscode', isInteractive: true })
  await switchTo($, w, 'high', 'medium')
  expect(w.toasts.length).toBe(1)
  expect(w.toasts[0]).toContain('High')
  expect(w.toasts[0]).toContain('/coremodel undo')
})

test('on the terminal and the desktop a silent switch raises no toast: the band says it', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(w.toasts).toEqual([])
})

test('the pane draws its bold text with weight, not the deprecated bold', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.row = null
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  const t = await ui.find({ type: 'Text', text: /^Opus · High$/ })
  expect(t?.props.weight).toBe('semibold')
  await ui.unmount()
})
