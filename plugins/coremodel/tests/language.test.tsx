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
  expect((await paneTexts($)).texts).toContain('Этот чат')
})

// The words follow the host, never the prompt: a Ukrainian or a Russian prompt on an English host stays English.
test('in auto a Cyrillic prompt does not turn the words Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}', 'виправ авторизацію')
  await pick($, w, '{"level":"keep","why":"x"}', 'почини авторизацию')
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · ' + texts('en').mode.auto)
  expect(p.buttons['mode-suggest']).toBe(texts('en').mode.suggest)
  expect(p.texts).toContain(texts('en').thisChat)
  expect(p.texts).not.toContain(texts('ru').thisChat)
})

test('in auto the host language setting picks Russian', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}', 'fix the login')
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · Автоматически')
  expect(p.buttons['mode-suggest']).toBe('Советовать')
  expect(p.texts).toContain('Этот чат')
})

test('the language setting wins over the host language', { options: { mode: 'auto', language: 'en' } }, async ($, on) => {
  const w = world(on)
  w.hostLanguage = 'russian'
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}')
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · ' + texts('en').mode.auto)
  expect(p.texts).toContain(texts('en').thisChat)
})

test('the language setting ru wins over an English host', { options: { mode: 'auto', language: 'ru' } }, async ($, on) => {
  const w = world(on)
  await start($)
  await pick($, w, '{"level":"keep","why":"x"}')
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · Автоматически')
  expect(p.texts).toContain('Этот чат')
})

// 0.7.0 kept the last prompt's language under the store key `lang`. It stays in the store, untouched and unread.
test('a language stored by 0.7.0 is ignored', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on, { lang: 'ru' })
  await start($)
  const p = await paneTexts($)
  expect(p.texts[0]).toBe('CoreModel · ' + texts('en').mode.auto)
  expect(p.texts).toContain(texts('en').thisChat)
})

// The failure path: a host whose settings cannot be read gets English, a debug line and no toast; the pick still runs.
test('an unreadable host setting falls back to English and the pick still runs', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  engineParts(on)
  w.settingsThrows = true
  await start($)
  await pick($, w, OPUS_HIGH)
  expect((await band($)).texts.some(t => /^✓ CoreModel: Opus · High \(was Sonnet · Medium\)/.test(t))).toBe(true)
  expect((await paneTexts($)).texts).toContain(texts('en').thisChat)
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
  expect(p.buttons['mode-auto']).toBe('● Автоматически')
  expect(p.texts).toContain('Выбрано CoreModel для этого чата · ваш выбор по умолчанию: Sonnet · Среднее')
  expect(p.buttons.release).toBe('Вернуть мой выбор')
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

test('a not applied pick reads in Russian too', { options: { mode: 'auto' } }, async ($, on) => {
  const w = world(on)
  w.reply = 'Оставить «Среднее»'
  w.hostLanguage = 'russian'
  await start($)
  await switchTo($, w, 'xhigh', 'medium', 'почини авторизацию')
  expect(await has($, /^Очень высокое · auth bug · не применён$/)).toBe(true)
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
