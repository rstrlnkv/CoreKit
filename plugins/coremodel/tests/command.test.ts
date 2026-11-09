// /coremodel: its replies, the mode question, panel and the hidden probe.
import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { texts } from '../hooks/policy'
import { engineParts, MODE, run, switchPair, switchTo } from './surfaces'
import { row, start, step, submit, world } from './world'

// The world without its own ui.open answer, so a test can answer it (a hook registers once per event).
function withoutOpen(on: On): On {
  return ((name: string, ...rest: unknown[]) => (name === 'ui.open' ? undefined : (on as (...a: unknown[]) => unknown)(name, ...rest))) as On
}

test('/coremodel reports the mode and the level the chat runs at', async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.reply = 'High (recommended)'
  await start($)
  expect(await run($, '')).toContain('suggest')
  await switchTo($, w, 'high', 'medium')
  expect(await run($, '')).toContain('High')
})

test('/coremodel auto, suggest, off and on store the mode over the setting', { options: { mode: 'suggest' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
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
  engineParts(on)
  await start($)
  await switchTo($, w, 'high', 'medium')
  await run($, 'off')
  await step($, 'medium', 1)
  expect(w.efforts.at(-1)).toBe('medium')
  const ui = await $.ui.mount({ ...MODE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Effort High/ })).toBe(undefined)
  await ui.unmount()
})

test('/coremodel panel opens the pane', async ($, on) => {
  const w = world(on)
  await start($)
  await run($, 'panel')
  expect(w.opened).toEqual([{ id: 'coremodel', title: 'CoreModel' }])
})

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

test('/coremodel probe writes the /config rows to the debug log, never to the chat', async ($, on) => {
  const w = world(on)
  w.row = row()
  engineParts(on)
  await start($)
  const out = await run($, 'probe')
  expect(out).not.toContain('effortLevel')
  expect(w.logs.some(l => l.includes('effortLevel') && l.includes('Low, Medium, High, Extra high, Max'))).toBe(true)
  expect(w.logSinks.every(s => s === 'debug')).toBe(true)
  expect(w.set.length).toBe(0)
})

test('/coremodel probe says so when the rows cannot be read', async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await run($, 'probe')
  expect(w.logs.some(l => l.includes('no rows'))).toBe(true)
})

test('/coremodel names the model and the level, in the host language', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
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
  engineParts(on)
  w.reply = 'nothing'
  await start($)
  await switchTo($, w, 'high', 'medium')
  const out = await run($, '')
  expect(out).toContain('High')
  expect(out).not.toContain('Sonnet')
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
