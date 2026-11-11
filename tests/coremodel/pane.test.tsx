// The pane: its layout, captions and the lines it shows.
import { expect, test } from 'claude-code/testing'

import { engineParts, has, OPUS_HIGH, PANE, pane, paneTexts, pick, pressPane, run, selectMode, SURFACES, switchPair, switchTo } from './surfaces'
import { start, step, submit, world } from './world'

/** The texts after `caption`, up to the next caption in `stops`. */
function section(texts: string[], caption: string, stops: string[]) {
  const from = texts.indexOf(caption)
  if (from < 0) return []
  const rest = texts.slice(from + 1)
  const end = rest.findIndex(t => stops.includes(t))
  return end < 0 ? rest : rest.slice(0, end)
}

test('the pane opens with its name and the mode list, then CoreModel\'s pick and what Claude has', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    // the rules are checked on their own below
    const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text)).filter(t => !/^─+$/.test(t))
    expect(texts[0]).toBe('CoreModel')
    const mode = await ui.find({ type: 'Select', key: 'mode' })
    expect(mode?.props.value).toBe('auto')
    expect((mode?.props.options as { value: string; label: string }[]).map(o => [o.value, o.label])).toEqual([
      ['auto', 'Auto'],
      ['suggest', 'Suggest'],
      ['off', 'Off'],
    ])
    expect(texts.slice(1, 4)).toEqual(["CoreModel's pick", 'Opus · High', 'In Claude: Sonnet · Medium'])
    expect(String((await ui.find({ type: 'Button', key: 'release' }))?.props.label)).toBe('↺ Reset')
    // the mode hint and the old captions are gone
    expect(texts.some(t => /Asks only|This chat|Set by|your default|Last pick/.test(t))).toBe(false)
    expect(await ui.find({ type: 'Button', key: 'mode-auto' })).toBe(undefined)
    await ui.unmount()
  }
})

test('the pair is the heading of the pane, drawn with weight', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await pane($)
  const t = await ui.find({ type: 'Text', text: /^Opus · High$/ })
  expect(t?.props.size).toBe('heading')
  expect(t?.props.weight).toBe('semibold')
  await ui.unmount()
})

test('with nothing held the card names what Claude has and offers no reset', async ($, on) => {
  world(on)
  await start($)
  await step($, 'medium')
  const p = await paneTexts($)
  expect(p.texts.slice(1, 3)).toEqual(['In Claude', 'Sonnet · Medium'])
  expect(p.buttons.release).toBe(undefined)
  expect(p.texts.some(t => /CoreModel's pick/.test(t))).toBe(false)
})

test('a fresh pane shows a dash for the pair and no stray session block', async ($, on) => {
  world(on)
  await start($)
  for (const surface of SURFACES) {
    const p = await paneTexts($, surface)
    expect(p.texts.slice(1, 3)).toEqual(['In Claude', '—'])
    expect(p.texts).not.toContain('This session')
    expect(p.texts.some(t => /^─+$/.test(t))).toBe(false)
  }
})

test('the model row comes before the effort scale', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await pane($)
  const keys = (await ui.findAll({ type: 'Button' })).map(b => String(b.key))
  expect(keys.indexOf('model-haiku')).toBeLessThan(keys.indexOf('level-low'))
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  expect(texts.indexOf('Model')).toBeLessThan(texts.indexOf('Effort'))
  await ui.unmount()
})

test('the effort scale: five segments across the width, filled up to the current level', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    expect((await ui.find({ type: 'Box', key: 'scale' }))?.props.flexDirection).toBe('row')
    const cells = await Promise.all(['low', 'medium', 'high', 'xhigh', 'max'].map(l => ui.find({ type: 'Box', key: `scale-${l}` })))
    // each segment stretches, so the scale fills its block on any width (seen live on the desktop: a row of
    // fixed buttons ran past the pane's edge)
    expect(cells.map(c => c?.props.flexGrow)).toEqual([1, 1, 1, 1, 1])
    const colours = cells.map(c => c?.props.backgroundColor)
    expect(typeof colours[0]).toBe('string')
    expect(new Set(colours.slice(0, 3)).size).toBe(1)
    expect(new Set(colours.slice(3)).size).toBe(1)
    expect(colours[3]).not.toBe(colours[0])
    await ui.unmount()
  }
})

test('the levels are pressed by name under the scale: a row that wraps, the current one marked in words', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    const row = await ui.find({ type: 'Box', key: 'levels' })
    expect(row?.props.flexWrap).toBe('wrap')
    const levels = (await ui.findAll({ type: 'Button' })).filter(b => String(b.key).startsWith('level-'))
    expect(levels.map(b => String(b.key))).toEqual(['level-low', 'level-medium', 'level-high', 'level-xhigh', 'level-max'])
    // a desktop draws a Button's label, not its children: the label is what the person reads
    expect(levels.map(b => String(b.props.label))).toEqual(['Low', 'Medium', '● High', 'Extra high', 'Max'])
    expect(levels.map(b => b.props.dimColor)).toEqual([true, true, undefined, true, true])
    // no glyph cells are left from the old scale
    expect((await ui.findAll({ type: 'Text' })).some(t => /[▰▱]/.test(String(t.text)))).toBe(false)
    await ui.unmount()
  }
})

test('the selected model is marked in words and by colour', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  const p = await paneTexts($)
  expect(p.buttons['model-opus']).toBe('● Opus')
  expect(p.buttons['model-sonnet']).toBe('Sonnet')
  const ui = await pane($)
  expect((await ui.find({ type: 'Button', key: 'model-opus' }))?.props.variant).toBe('primary')
  expect((await ui.find({ type: 'Button', key: 'model-sonnet' }))?.props.variant).toBe(undefined)
  await ui.unmount()
})

test('the mode order is Auto, Suggest, Off everywhere', async ($, on) => {
  const w = world(on)
  await start($)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(((await ui.find({ type: 'Select', key: 'mode' }))?.props.options as { value: string }[]).map(o => o.value)).toEqual(['auto', 'suggest', 'off'])
  await ui.unmount()
  w.reply = null
  await run($, '')
  expect(w.asked.at(-1)).toEqual(['Auto', 'Suggest', 'Off'])
})

test('a mode picked in the list is the mode', { options: { mode: 'auto' } }, async ($, on) => {
  world(on)
  await start($)
  await selectMode($, 'suggest')
  const ui = await pane($)
  expect((await ui.find({ type: 'Select', key: 'mode' }))?.props.value).toBe('suggest')
  await ui.unmount()
  expect(await run($, 'x')).toContain('Suggest')
})

test('the session splits into a model group and an effort group, each with its own bars', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  // a pick counts only when it changes something: Reset between the picks lets each one count
  await switchPair($, w, 'opus', 'low')
  await pressPane($, 'release')
  await switchTo($, w, 'high', 'medium')
  await pressPane($, 'release')
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const p = await paneTexts($, surface)
    const s = section(p.texts, 'This session', [])
    // each group holds only its own names; most used first, not in the order picked
    expect(section(s, 'Model', ['Effort'])).toEqual(['Opus', '1'])
    expect(section(s, 'Effort', [])).toEqual(['High', '2', 'Low', '1'])
    // the bars are boxes sized in shares of the group's width, the longest full: text bars ran past the
    // edge on the desktop and hid the count
    const ui = await pane($, surface)
    const bar = async (key: string) => (await ui.find({ type: 'Box', key }))?.props
    expect((await bar('session-models-Opus-bar'))?.width).toBe('100%')
    expect((await bar('session-levels-High-bar'))?.width).toBe('100%')
    expect((await bar('session-levels-Low-bar'))?.width).toBe('50%')
    expect(typeof (await bar('session-levels-Low-bar'))?.backgroundColor).toBe('string')
    expect((await bar('session-levels-Low-track'))?.flexGrow).toBe(1)
    await ui.unmount()
  }
})

test('rules divide the card, the session and the warnings, as in the concept', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  for (const surface of SURFACES) {
    const p = await paneTexts($, surface)
    const rule = (t: string) => /^─+$/.test(t)
    const pair = p.texts.indexOf('Sonnet · High')
    expect(rule(p.texts[pair + 1])).toBe(true)
    expect(p.texts[pair + 2]).toBe('In Claude: Medium')
    expect(rule(p.texts[p.texts.indexOf('This session') - 1])).toBe(true)
    const ui = await pane($, surface)
    const rules = (await ui.findAll({ type: 'Text' })).filter(t => rule(String(t.text)))
    expect(rules.length).toBe(2)
    expect(rules.every(r => r.props.dimColor === true && r.props.wrap === undefined)).toBe(true)
    // one line that clips the rest at the pane's edge: a truncated text ends in an ellipsis on the terminal
    for (const key of ['now-rule', 'session-rule']) {
      const b = await ui.find({ type: 'Box', key })
      expect(b?.props.height).toBe(1)
      expect(b?.props.overflow).toBe('hidden')
    }
    await ui.unmount()
  }
})

test('the session group boxes wrap: side by side when wide, stacked when narrow', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  for (const surface of SURFACES) {
    const ui = await pane($, surface)
    for (const key of ['top', 'session-groups']) {
      const b = await ui.find({ type: 'Box', key })
      expect(b?.props.flexDirection).toBe('row')
      expect(b?.props.flexWrap).toBe('wrap')
    }
    // a base width, not a minimum: a block holding a wrapping row would otherwise claim the whole
    // line and push its neighbour down even in a wide pane (seen live in the terminal)
    for (const key of ['now', 'choose', 'session-models', 'session-levels']) {
      const b = await ui.find({ type: 'Box', key })
      expect(b?.props.flexGrow).toBe(1)
      expect(typeof b?.props.width).toBe('number')
      expect(b?.props.minWidth).toBe(undefined)
    }
    await ui.unmount()
  }
})

test('the kept count stands in the session header, apart from both groups', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Keep Medium'
  await start($)
  await switchTo($, w, 'xhigh', 'medium')
  await switchTo($, w, 'keep', 'medium', 'ok')
  const p = await paneTexts($)
  const s = p.texts.indexOf('This session')
  expect(p.texts[s + 1]).toBe('unchanged 2')
  // Prompts the person kept are not counted as picks.
  expect(p.texts).not.toContain('Extra high')
  expect(p.texts.some(t => /not applied/.test(t))).toBe(false)
})

test('with pickModel off the pane shows no model buttons or model counts', { options: { mode: 'auto', pickModel: 'off' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchPair($, w, 'opus', 'high')
  const ui = await pane($)
  expect(await ui.find({ type: 'Button', key: 'model-opus' })).toBe(undefined)
  expect(await ui.find({ type: 'Box', key: 'session-models' })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Opus/ })).toBe(undefined)
  expect(await ui.find({ type: 'Text', text: /Fable/ })).toBe(undefined)
  expect((await ui.find({ type: 'Text', text: /^High$/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('the pane names what Claude has only once a request shows it', async ($, on) => {
  world(on)
  await start($)
  await pressPane($, 'level-high')
  expect(await has($, /^CoreModel's pick$/)).toBe(true)
  expect(await has($, /In Claude/)).toBe(false)
  await step($, 'medium')
  expect(await has($, /^In Claude: Medium$/)).toBe(true)
})

test('with only the model held, the pane and /coremodel name the same default: the held part', async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.reply = 'nothing'   // the mode question is dismissed: the reply says where things stand
  await start($)
  await step($, 'medium')
  await pressPane($, 'model-opus')
  expect(await has($, /^In Claude: Sonnet$/)).toBe(true)
  expect(await run($, '')).toContain('set by CoreModel; your default: Sonnet)')
})

test('after Reset the pane shows the menu level at once', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  expect(await has($, /^Sonnet · High$/)).toBe(true)
  await pressPane($, 'release')
  expect(await has($, /^Sonnet · Medium$/)).toBe(true)
  expect(await has($, /^Sonnet · High$/)).toBe(false)
})

test('session counts follow what was applied, not what the classifier asked for', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.answer = '{"level":"xhigh","model":"fable","why":"x"}'
  w.reply = [null, 'Extra high (recommended)']
  await start($)
  await submit($, 'build the whole app')
  await step($, 'medium')
  for (const surface of SURFACES) {
    const p = await paneTexts($, surface)
    expect(section(p.texts, 'This session', [])).toEqual(['Effort', 'Extra high', '1'])
  }
})

test('the warnings are short: a model that is not available, a classifier that keeps failing', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  for (let i = 0; i < 2; i += 1) {
    w.answers = [{ fail: true }, { fail: true }]
    await submit($, 'fix the login')
    await step($, 'medium')
  }
  expect(await has($, /^⚠ The classifier is not answering · claude --debug$/)).toBe(true)
  w.answers = ['{"level":"high","why":"auth bug"}']
  await submit($, 'fix the login')
  await step($, 'medium')
  expect(await has($, /classifier/)).toBe(false)
})

test('the pane draws no picture: the bars are text on every surface', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.findAll({ type: 'Svg' })).toHaveLength(0)
  await ui.unmount()
})
