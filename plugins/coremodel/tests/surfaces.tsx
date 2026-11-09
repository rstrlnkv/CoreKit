// What the tests draw and press: the places CoreModel renders into, the engine's own parts beside
// them, and the helpers that mount, read and press them. The world beneath is in world.ts.
import type { On } from 'claude-code'

import { step, submit, type Eng, type World } from './world'

export const SURFACES = ['terminal', 'desktop'] as const
export const ABOVE = { plugin: 'coremodel', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 6, bodyColumns: 80, scroll: { offset: 0, bodyRows: 6 }, view: {} } } as const
export const MODE = { plugin: 'coremodel', component: 'SessionMode', props: { modes: ['default'] } } as const
export const PANE = {
  plugin: 'coremodel',
  component: 'Pane',
  requestId: 'coremodel',
  props: { title: 'CoreModel', isFocused: false, bodyColumns: 40, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const
export const SPIN = { plugin: 'coremodel', component: 'Spinner', props: { word: 'Thinking', message: null, suffix: '…', mode: 'thinking' } } as const
export const MID = 'an earlier answer'
export const OPUS_HIGH = '{"level":"high","model":"opus","why":"auth bug"}'

/** The engine's own parts: what draws when the plugin leaves a slot alone. */
export function engineParts(on: On) {
  on('ui.render', { component: 'SessionMode' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{(e.props as { modes: readonly string[] }).modes.join(' | ')}</Text>
  })
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('ui.render', { component: 'Spinner' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    const p = e.props as { word: string; suffix: string }
    return <Text>{p.word + p.suffix}</Text>
  })
}

/** `/coremodel <args>`; its reply. */
export async function run($: Eng, args: string) {
  const r = await $.command.run({ command: 'coremodel', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as never)
  return (r as { text?: string }).text ?? ''
}

/** One prompt whose classifier answers `answer`, run at `effort`. */
export async function pick($: Eng, w: World, answer: string, text = 'fix the login', effort = 'medium', model?: string) {
  w.answer = answer
  await submit($, text)
  await step($, effort, 0, undefined, model)
}

/** A pick of `level` alone, from `from`. */
export async function switchTo($: Eng, w: World, level: string, from: string, text = 'fix the login') {
  await pick($, w, `{"level":"${level}","why":"auth bug"}`, text, from)
}

/** A pick of a model and a level, from medium. */
export async function switchPair($: Eng, w: World, model: string, level: string, why = 'auth bug') {
  await pick($, w, `{"level":"${level}","model":"${model}","why":"${why}"}`)
}

/** The band above the prompt: its texts and buttons. */
export async function band($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...ABOVE, surface })
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  const buttons = (await ui.findAll({ type: 'Button' })).map(b => ({ key: String(b.key), label: String(b.props.label), hotkey: b.props.hotkey }))
  await ui.unmount()
  return { texts, buttons }
}

export async function pressBand($: Eng, key: string) {
  const ui = await $.ui.mount({ ...ABOVE, surface: 'desktop' })
  await ui.press({ key })
  await ui.unmount()
}

/** The band's undo button, or undefined. */
export async function undoButton($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...ABOVE, surface })
  const b = await ui.find({ type: 'Button', key: 'undo' })
  await ui.unmount()
  return b
}

export async function pressUndo($: Eng) {
  await pressBand($, 'undo')
}

/** The pane, mounted: the caller unmounts it. */
export async function pane($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  return $.ui.mount({ ...PANE, surface })
}

/** The pane's texts, and its button labels by key. */
export async function paneTexts($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await pane($, surface)
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  const buttons = Object.fromEntries((await ui.findAll({ type: 'Button' })).map(b => [String(b.key), String(b.props.label)]))
  await ui.unmount()
  return { texts, buttons }
}

/** True when a text of the pane matches `text`. */
export async function has($: Eng, text: RegExp, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await pane($, surface)
  const found = await ui.find({ type: 'Text', text })
  await ui.unmount()
  return found !== undefined
}

export async function pressPane($: Eng, key: string) {
  const ui = await pane($)
  await ui.press({ key })
  await ui.unmount()
}

/** The footer button's label and the footer's texts. */
export async function footer($: Eng, surface: 'terminal' | 'desktop' = 'desktop') {
  const ui = await $.ui.mount({ ...MODE, surface })
  const label = String((await ui.find({ type: 'Button', key: 'pane' }))?.props.label)
  const texts = (await ui.findAll({ type: 'Text' })).map(t => String(t.text))
  await ui.unmount()
  return { label, texts }
}

/** A transcript row placed by `plugin`. */
export function placed(id: string, plugin = 'coremodel') {
  return { plugin: 'coremodel', component: 'Placed', props: { id, plugin } } as const
}
