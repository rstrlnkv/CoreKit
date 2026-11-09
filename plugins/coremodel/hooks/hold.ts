// The model and level held on main-chat requests ($.state override), the band above the prompt
// ($.state band), and the presses that change them: the mode, the pane, the cost question.
import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import type { Band, Level } from '../types'
import { toLevel } from './classifier'
import { chatTokens, isEmptyChat, log, pickOn } from './host'
import { type ModelKey, toModel } from './models'
import { type Mode, texts } from './policy'
import { BAND_MS, session } from './session'

const override = atom({ plugin: 'coremodel', key: 'override' } as const, null)

const band = atom({ plugin: 'coremodel', key: 'band' } as const, null)

/** Switches to `level` by holding it on this chat's requests. */
export async function applyLevel($: EngineInterface, level: Level, base: string): Promise<void> {
  session.hold = { level, base }
  await syncOverride($)
}

/** Switches to `key` by holding it on this chat's requests. */
export async function applyModel($: EngineInterface, key: ModelKey, base: string): Promise<void> {
  session.modelHold = { key, base }
  await syncOverride($)
}

/** What the drawings read: the held pair, or null when nothing is held. */
async function syncOverride($: EngineInterface): Promise<void> {
  const pair = { model: session.modelHold?.key ?? null, level: session.hold?.level ?? null }
  await update($, override, () => (pair.model || pair.level ? pair : null))
}

/** Lets go of the held level: the chat runs at the menu's level again. */
export async function releaseLevel($: EngineInterface): Promise<void> {
  session.hold = null
  // The pane reads `seen`: after a release it is the menu's level, not the one just let go.
  session.seen = toLevel(session.asked) || session.seen
  await syncOverride($)
}

/** Lets go of the held model: the chat runs on the person's own model again. */
export async function releaseModel($: EngineInterface): Promise<void> {
  session.modelHold = null
  await syncOverride($)
}

/** Lets go of both parts (off, Release, a new session). */
export async function releaseHold($: EngineInterface): Promise<void> {
  session.hold = null
  session.seen = toLevel(session.asked) || session.seen
  session.modelHold = null
  await syncOverride($)
}

/**
 * What the chat runs at, from the held pair: each held part, else what the last request showed.
 * "Your default" names only the held parts, as the chat's own menu sets them. The model only while
 * CoreModel picks it.
 */
export function chatState(pair: { model: ModelKey | null; level: Level | null } | null, options: { pickModel?: unknown }) {
  const withModel = pickOn(options)
  const nowModel: ModelKey | '' = withModel ? (pair?.model ?? toModel(session.seenModel)) : ''
  const nowLevel: Level | '' = pair?.level ?? session.seen
  const defaultModel: ModelKey | '' = withModel && pair?.model ? toModel(session.seenModel) : ''
  const defaultLevel: Level | '' = pair?.level ? toLevel(session.asked) : ''
  return { nowModel, nowLevel, isHeld: !!(pair?.model || pair?.level), defaultModel, defaultLevel }
}

/** Takes `b` down unless a newer band has replaced it. */
export async function clearBand($: EngineInterface, b: Band): Promise<void> {
  await update($, band, cur => (cur && cur.id === b.id ? null : cur))
}

/**
 * Puts `b` above the prompt for BAND_MS: a silent switch with its undo, or a suggestion. VS Code draws
 * no band, so there it is said in a toast, a silent switch with the undo command.
 */
export async function showBand($: EngineInterface, b: Band) {
  if (b.undo) session.lastUndo = b
  await update($, band, () => b)
  if (session.surface === 'vscode') {
    const t = texts(b.lang)
    try {
      $.ui.toast(
        b.suggest
          ? `${t.suggests} ${t.change(b.model, '', b.level, '', b.why)}`
          : `CoreModel: ${t.change(b.model, b.fromModel, b.level, b.from, b.why)}${b.undo ? ` · ${t.undoHint}` : ''}`,
      )
    } catch {
      // The transcript row still says it.
    }
  }
  void (async () => {
    await $.clock.sleep(BAND_MS)
    await clearBand($, b)
  })().catch(err => log($, 'band', err))
}

/** The cost question before a switch to `key` mid-chat; true on the person's yes. */
export async function confirmCost($: EngineInterface, key: ModelKey, nowModel: ModelKey | '', why: string): Promise<boolean> {
  const t = texts(session.lastLang)
  const yes = t.switchToModel(key)
  try {
    const answer = await $.ui.ask(t.costQuestion(key, nowModel, await chatTokens($), why), { options: [yes, nowModel ? t.keepModel(nowModel) : t.cancel], header: t.modelHeader })
    return answer === yes
  } catch {
    return false
  }
}

/** Sets the mode as `/coremodel <mode>` does; returns the reply. */
export async function setMode($: EngineInterface, options: { mode?: unknown; pickModel?: unknown }, arg: Mode | 'on'): Promise<string> {
  const t = texts(session.lastLang)
  let text: string
  if (arg === 'auto' || arg === 'suggest') {
    await $.store.set('mode', arg)
    await $.store.set('lastMode', arg)
    // A suggestion of the other mode has no place any more.
    await update($, band, cur => (cur?.suggest && arg === 'auto' ? null : cur))
    text = t.modeSet(arg, pickOn(options))
  } else if (arg === 'off') {
    await $.store.set('mode', 'off')
    await releaseHold($)
    await update($, band, () => null)
    text = t.modeOff
  } else {
    const last = await $.store.get('lastMode')
    const mode: Mode = last === 'auto' || last === 'suggest' ? last : options.mode === 'suggest' ? 'suggest' : 'auto'
    await $.store.set('mode', mode)
    text = t.modeOnFor(mode)
  }
  $.ui.invalidate('ui.render')
  return text
}

/**
 * A level the person picks in the pane (null: Use my default). It is their newest choice, so the band
 * goes, and the hold takes the menu's level from the next request as its base.
 */
export async function paneChoice($: EngineInterface, level: Level | null): Promise<void> {
  session.touched += 1
  if (level) await applyLevel($, level, '')
  else await releaseHold($)
  await update($, band, () => null)
}

/**
 * A model the person presses in the pane. Mid-chat the cost question comes first;
 * the press itself is their yes, so no other question follows.
 */
export async function paneModel($: EngineInterface, key: ModelKey): Promise<void> {
  session.touched += 1
  const nowModel = session.modelHold?.key ?? toModel(session.seenModel)
  if (key === nowModel) return
  if (!(await isEmptyChat($)) && !(await confirmCost($, key, nowModel, ''))) return
  await applyModel($, key, '')
  await update($, band, () => null)
}

/** The held pair the drawings read, or null when nothing is held. */
export async function heldPair($: EngineInterface) {
  return read($, override)
}

/** The band above the prompt, or null. */
export async function currentBand($: EngineInterface) {
  return read($, band)
}

/** Takes the band down, whatever it is. */
export async function dropBand($: EngineInterface): Promise<void> {
  await update($, band, () => null)
}
