// What the host says: the account's model list, the mode, the language, the chat's size; and the debug log.
import type { EngineInterface } from 'claude-code'

import type { Lang } from '../types'
import { detectModels, enabledModels, type ModelKey } from './models'
import { hostLang, type Mode, MODES, settingLang } from './policy'
import { session } from './session'

export const PLUGIN = 'coremodel'

/** Reads the /config Model row again; any failure means "no verdict" (nothing is filtered). */
export async function refreshListed($: EngineInterface): Promise<void> {
  try {
    const row = (await $.config.list()).find(r => r.key === 'model')
    session.listed = detectModels(row?.options)
  } catch {
    session.listed = null
  }
}

/** The models CoreModel may pick: switched on in the settings, listed by the account, minus those that failed. */
export function allowedModels(options: Readonly<Record<string, unknown>>): ModelKey[] {
  return enabledModels(options).filter(k => (session.listed === null || session.listed.includes(k)) && !session.unavailable.has(k))
}

/** A line in Claude Code's debug log (`claude --debug`); never in the transcript, never a file. */
export async function log($: EngineInterface, what: string, err: unknown) {
  try {
    $.ui.log(`${PLUGIN}: ${what}: ${err instanceof Error ? err.message : String(err)}`, { to: 'debug' })
  } catch {
    // Nowhere left to report it.
  }
}

/** The mode: what /coremodel stored wins over the setting. */
export async function currentMode($: EngineInterface, options: { mode?: unknown }): Promise<Mode> {
  const stored = await $.store.get('mode')
  if (MODES.includes(stored as Mode)) return stored as Mode
  return MODES.includes(options.mode as Mode) ? (options.mode as Mode) : MODES[0]!
}

/** The chat's size as the last response read it; undefined when Claude Code does not say. */
export async function chatTokens($: EngineInterface): Promise<number | undefined> {
  try {
    return (await $.session.usage()).context.tokens
  } catch {
    return undefined
  }
}

/** True before Claude's first reply in this chat. */
export async function isEmptyChat($: EngineInterface): Promise<boolean> {
  return !(await $.session.messages()).some(m => m.role === 'assistant')
}

/** True unless the plugin setting `pickModel` is off: then CoreModel picks the effort only. */
export function pickOn(options: { pickModel?: unknown }): boolean {
  return options.pickModel !== 'off'
}

/**
 * The language of the words: the plugin's own setting when it names one, else Claude Code's
 * `language` setting, else English. Never the text of a prompt. A host that cannot answer (an
 * older Claude Code, unreadable settings) gets English and a debug line; the prompt goes on.
 */
export async function currentLang($: EngineInterface, options: { language?: unknown }): Promise<Lang> {
  const fixed = settingLang(options.language)
  if (fixed) return fixed
  try {
    return hostLang(await $.settings.read({ key: 'language' }))
  } catch (err) {
    await log($, 'language', err)
    return 'en'
  }
}
