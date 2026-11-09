import type { EngineInterface } from 'claude-code'

import type { Band, Level } from '../types'
import { applyLevel, applyModel, clearBand, confirmCost, releaseLevel, releaseModel } from './hold'
import { isEmptyChat } from './host'
import { type ModelKey, toModel } from './models'
import { applied, keptPrompt } from './pick'
import { session } from './session'

/**
 * Switch on a suggestion: the person's yes, held from the next request. Mid-chat a stronger model
 * still gets the cost question first; a No there keeps the model and takes the effort.
 */
export async function acceptSuggestion($: EngineInterface, b: Band): Promise<void> {
  session.touched += 1
  await clearBand($, b)
  const nowModel = session.modelHold?.key ?? toModel(session.seenModel)
  let modelTo = b.model && b.model !== nowModel ? b.model : null
  if (modelTo && !(await isEmptyChat($)) && !(await confirmCost($, modelTo, nowModel, b.why))) modelTo = null
  const nowLevel = session.hold?.level ?? session.seen
  const levelTo = b.level && b.level !== nowLevel ? b.level : null
  if (!modelTo && !levelTo) return keptPrompt($, true)
  if (modelTo) await applyModel($, modelTo, '')
  if (levelTo) await applyLevel($, levelTo, '')
  await applied($, { level: levelTo, from: levelTo ? nowLevel : '', model: modelTo, fromModel: modelTo ? nowModel : '', why: b.why, lang: b.lang })
}

/** Keep on a suggestion: nothing changes; the prompt counts as unchanged. */
export async function declineSuggestion($: EngineInterface, b: Band): Promise<void> {
  await clearBand($, b)
  await keptPrompt($, true)
}

/** Takes back what a silent switch changed, part by part; a part the person changed since stays. True when anything went back. */
export async function undoChange($: EngineInterface, b: Band): Promise<boolean> {
  const undo = b.undo
  if (!undo) return false
  session.touched += 1
  let done = false
  if (undo.model && b.model && session.modelHold?.key === b.model) {
    if (undo.model === 'release') await releaseModel($)
    else await applyModel($, undo.model, session.modelHold.base)
    done = true
  }
  if (undo.level && b.level && session.hold?.level === b.level) {
    if (undo.level === 'release') await releaseLevel($)
    else await applyLevel($, undo.level, session.hold.base)
    done = true
  }
  if (session.lastUndo?.id === b.id) session.lastUndo = null
  await clearBand($, b)
  return done
}

/** What an undo of `b` goes back to: a model and a level, each named or empty. */
export function undoTarget(b: Band): { model: ModelKey | '' | undefined; level: Level | '' | undefined } {
  return {
    model: b.undo?.model === 'release' ? b.fromModel : b.undo?.model,
    level: b.undo?.level === 'release' ? b.from : b.undo?.level,
  }
}
