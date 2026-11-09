// The hooks: what CoreModel does on each event; the work lives in the modules beside this file.
// Each $.state key is declared in the one file that reads and writes it (ask, hold, pick): the
// host's scan reads a state source only from a const of its own file.
import type { Register } from 'claude-code'

import { toLevel } from './classifier'
import { drawCommand } from './command'
import { releaseLevel, releaseModel } from './hold'
import { currentLang, log, refreshListed } from './host'
import { MODELS, requestModel, toModel } from './models'
import { newChat, runPick } from './pick'
import { session } from './session'
import { drawViews } from './views'

export const register: Register = (on, options) => {

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'composer' && e.origin.kind !== 'bridge') {
      // That prompt takes the next turn; an older one waiting is not it.
      session.held = null
      return next(e)
    }
    const text = e.text.trim()
    if (!text || text.startsWith('/')) {
      // A prompt of ours is not the next turn's any more.
      session.held = null
      return next(e)
    }
    session.gen += 1
    session.lastLang = await currentLang($, options)
    const mine = { text, gen: session.gen, lang: session.lastLang, ...(e.turnId ? { turn: e.turnId } : {}) }
    session.held = mine
    const r = await next(e)
    // Refused beneath us: no turn will come of it.
    if (r.drop !== undefined && session.held === mine) session.held = null
    return r
  }).catch(($, e, next) => next(e))

  // A turn that ends with a prompt still waiting (blocked, Esc'd before its first request) leaves
  // nothing for the next turn; only a prompt queued behind this very turn stays.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && session.held && session.held.turn !== e.turnId) session.held = null
    return next(e)
  })

  // Every main-chat request: release a hold the menu moved past, run a waiting pick, put the level on.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) return yield* next(e)
    // A model without effort carries none; the level part then sleeps.
    const hasEffort = typeof e.effort === 'string'
    if (hasEffort) {
      session.asked = e.effort as string
      // A level picked in the pane before any request learns the menu's level here.
      if (session.hold && session.hold.base === '') session.hold = { ...session.hold, base: session.asked }
      if (session.hold && session.asked !== session.hold.base) await releaseLevel($)
    }
    session.seenModel = e.model
    if (session.modelHold && session.modelHold.base === '') session.modelHold = { ...session.modelHold, base: e.model }
    // The person chose another model with /model: their choice stands.
    if (session.modelHold && e.model !== session.modelHold.base) await releaseModel($)
    if (session.held && e.index === 0) {
      const h = session.held
      session.held = null
      try {
        await runPick($, options, h, hasEffort ? (session.hold?.level ?? toLevel(session.asked)) : '', hasEffort ? session.asked : '', session.modelHold?.key ?? toModel(e.model), e.model, hasEffort)
      } catch (err) {
        await log($, 'pick', err)
      }
    }
    const want = hasEffort ? (session.hold?.level ?? null) : null
    const was = session.seen
    session.seen = want ?? (toLevel(session.asked) || session.seen)
    if (session.seen !== was) $.ui.invalidate('ui.render')
    // The request's context suffix (`[1m]`) stays on the held model: a long chat must still fit.
    const model = session.modelHold ? requestModel(session.modelHold.key, e.model) : e.model
    if ((!want || want === e.effort) && model === e.model) return yield* next(e)
    return yield* next({ ...e, effort: want ?? e.effort, model })
  })

  // A model the account cannot use: the turn fails with model_not_found, naming no model, so the
  // held one is the one refused. Drop it for this session, once, instead of failing every request.
  on('classic.StopFailure', async ($, e, next) => {
    // A subagent's failure says nothing about the main chat's model.
    if (e.error === 'model_not_found' && session.modelHold && e.agent_id === undefined) {
      const key = session.modelHold.key
      session.unavailable.add(key)
      await releaseModel($)
      await log($, 'model', `${MODELS[key].name} is not available: ${e.error_details ?? e.error}`)
      $.ui.invalidate('ui.render')
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // /clear, /resume and a fork start another chat in this process, and session.start does not run
  // for them; the module's own variables would carry the hold into the new chat. A compacted chat
  // is the same chat and keeps it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') await newChat($, true)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.start', async ($, e, next) => {
    session.surface = e.surface ?? ''
    // The language: the plugin's setting, else the host's. A `lang` that 0.7.0 stored is left alone and unread.
    session.lastLang = await currentLang($, options)
    session.unavailable.clear()
    await refreshListed($)
    // A new session, or a reload of this module, starts with no held level: drop what $.state kept.
    await newChat($, false)
    await $.command.register({
      name: 'coremodel',
      description: 'CoreModel: show what the chat runs at, set the mode (auto, suggest, off, on), open the pane (panel), take back the last switch (undo); recheck reads the account\'s model list again',
      argumentHint: '[auto|suggest|off|on|panel|undo|recheck]',
    })
    return next(e)
  })

  drawCommand(on, options)
  drawViews(on, options)
}
