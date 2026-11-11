// The language of the words: the setting, the host, never the prompt.
import { expect, test } from 'claude-code/testing'

import { texts } from '../hooks/policy'
import { ABOVE, band, engineParts, has, OPUS_HIGH, pane, paneTexts, pick, run, switchTo } from './surfaces'
import { start, world } from './world'

test('the language setting wins over the prompt', { options: { mode: 'auto', language: 'ru' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  await start($)
  await pick($, w, OPUS_HIGH)
  expect((await band($)).texts.some(t => /^✓ CoreModel: Opus · Высокое \(было Sonnet · Среднее\)/.test(t))).toBe(true)
  expect((await paneTexts($)).texts).toContain('Выбор CoreModel')
})

// The words follow the host, never the prompt: a Ukrainian or a Russian prompt on an English host stays English.
test('in auto a Cyrillic prompt does not turn the words Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}', 'виправ авторизацію')
  await pick($, w, '{"level":"keep","why":"x"}', 'почини авторизацию')
  const p = await paneTexts($)
  expect(p.modes[0]).toBe(texts('en').mode.auto)
  expect(p.modes[1]).toBe(texts('en').mode.suggest)
  expect(p.texts).toContain(texts('en').inClaude)
  expect(p.texts).not.toContain(texts('ru').inClaude)
})

test('in auto the host language setting picks Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}', 'fix the login')
  const p = await paneTexts($)
  expect(p.modes[0]).toBe('Автоматически')
  expect(p.modes[1]).toBe('Советовать')
  expect(p.texts).toContain('В Claude выбрано')
})

test('the language setting wins over the host language', { options: { mode: 'auto', language: 'en' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}')
  const p = await paneTexts($)
  expect(p.modes[0]).toBe(texts('en').mode.auto)
  expect(p.texts).toContain(texts('en').inClaude)
})

test('the language setting ru wins over an English host', { options: { mode: 'auto', language: 'ru' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}')
  const p = await paneTexts($)
  expect(p.modes[0]).toBe('Автоматически')
  expect(p.texts).toContain('В Claude выбрано')
})

// 0.7.0 kept the last prompt's language under the store key `lang`. It stays in the store, untouched and unread.
test('a language stored by 0.7.0 is ignored', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on, { lang: 'ru' })
  await start($)
  const p = await paneTexts($)
  expect(p.modes[0]).toBe(texts('en').mode.auto)
  expect(p.texts).toContain(texts('en').inClaude)
})

// The failure path: a host whose settings cannot be read gets English, a debug line and no toast; the pick still runs.
test('an unreadable host setting falls back to English and the pick still runs', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.settingsThrows = true
  await start($)
  await pick($, w, OPUS_HIGH)
  expect((await band($)).texts.some(t => /^✓ CoreModel: Opus · High \(was Sonnet · Medium\)/.test(t))).toBe(true)
  expect((await paneTexts($)).texts).toContain(texts('en').pickedBy)
  expect(w.logs.some(l => l.includes('language'))).toBe(true)
  expect(w.logSinks.every(s => s === 'debug')).toBe(true)
  expect(w.toasts).toEqual([])
})

test('the Russian pane and band', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.hostLanguage = 'russian'
  await start($)
  await pick($, w, '{"level":"high","model":"opus","why":"ошибка входа"}', 'почини авторизацию')
  const p = await paneTexts($)
  expect(p.modes).toEqual(['Автоматически', 'Советовать', 'Выкл'])
  expect(p.mode).toBe('auto')
  expect(p.texts.slice(1, 4)).toEqual(['Выбор CoreModel', 'Opus · Высокое', 'В Claude выбрано: Sonnet · Среднее'])
  expect(p.buttons.release).toBe('↺ Сбросить')
  expect(p.texts).toContain('Модель')
  expect(p.texts).toContain('Усилие')
  expect(p.texts).toContain('За сессию')
  expect((await band($)).buttons[0]?.label).toBe('Вернуть Sonnet · Среднее')
})

test('a Russian prompt gives the line in Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Усилие Высокое \(было Среднее\)/ })) !== undefined).toBe(true)
  await ui.unmount()
})

test('the pane speaks Russian after a Russian prompt', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'high', 'medium', 'почини авторизацию')
  expect(await has($, /^Выбор CoreModel$/)).toBe(true)
  expect(await has($, /^Sonnet · Высокое$/)).toBe(true)
  expect(await has($, /^В Claude выбрано: Среднее$/)).toBe(true)
  expect(await has($, /^Усилие$/)).toBe(true)
  expect(await has($, /^За сессию$/)).toBe(true)
  const ui = await pane($)
  const levels = (await ui.findAll({ type: 'Button' })).filter(b => String(b.key).startsWith('level-'))
  expect(levels.map(b => String(b.props.label))).toEqual(['Низкое', 'Среднее', 'Высокое', 'Очень высокое', 'Максимальное'])
  await ui.unmount()
})

test('the mode question and the kept count read in Russian', async ($, on) => {
  const w = world(on)
  w.reply = 'Автоматически'
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'keep', 'medium', 'почини авторизацию')
  const text = await run($, '')
  expect(w.asked.at(-1)).toEqual(['Автоматически', 'Советовать', 'Выкл'])
  expect(text).toContain('Режим: «Автоматически»')
  expect(await has($, /^без изменений 1$/)).toBe(true)
})
