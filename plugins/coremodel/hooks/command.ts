import type { Register } from 'claude-code'

import { undoChange, undoTarget } from './actions'
import { chatState, heldPair, setMode } from './hold'
import { allowedModels, currentMode, log, pickOn, PLUGIN, refreshListed } from './host'
import { enabledModels, MODELS } from './models'
import { type Mode, MODES, texts } from './policy'
import { session } from './session'

/** /coremodel: the mode, the pane, undo, recheck and the hidden probe; with no argument, the mode question. */
export const drawCommand: Register = (on, options) => {
  on('command.run', { command: 'coremodel' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    const t = texts(session.lastLang)
    if (arg === 'auto' || arg === 'suggest' || arg === 'off' || arg === 'on') return { text: await setMode($, options, arg) }
    if (arg === 'panel') {
      const r = await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      if (r.isPlaced) return { text: t.paneOpen }
      // The engine's reason is for the debug log; the person gets a plain sentence.
      await log($, 'pane not shown', r.reason)
      return { text: r.reason.startsWith('no-surface') ? t.paneNoSurface : t.paneWaiting }
    }
    if (arg === 'undo') {
      const b = session.lastUndo
      if (!b || !(await undoChange($, b))) return { text: t.nothingToUndo }
      const to = undoTarget(b)
      return { text: t.undone(t.pair(to.model, to.level)) }
    }
    if (arg === 'recheck') {
      // Models dropped after model_not_found come back, and the account's list is read again.
      session.unavailable.clear()
      await refreshListed($)
      $.ui.invalidate('ui.render')
      const names = allowedModels(options).map(k => MODELS[k].name)
      return { text: t.recheck(names, enabledModels(options).length, session.listed !== null, pickOn(options)) }
    }
    if (arg === 'probe') {
      // A diagnostic, left out of the command's hint: what /config offers, to see whether it lists the
      // models this account can use. Reads only, and writes to the debug log, never to the chat.
      let rows: Awaited<ReturnType<typeof $.config.list>> = []
      try {
        rows = await $.config.list()
      } catch (err) {
        await log($, 'probe', `no rows (${err instanceof Error ? err.message : String(err)})`)
        return { text: t.probeLogged(0) }
      }
      const line = (r: (typeof rows)[number]) => {
        const opts = r.options ? ` · options: ${r.options.slice(0, 16).join(', ')}${r.options.length > 16 ? ', …' : ''}` : ''
        return `${r.key} · ${r.label} · ${r.kind} · value: ${String(r.value)}${opts}`
      }
      await log($, 'probe', rows.length ? `${rows.length} rows\n${rows.map(line).join('\n')}` : 'no rows')
      return { text: t.probeLogged(rows.length) }
    }
    const mode = await currentMode($, options)
    // pickModel off: the level only, as everywhere else.
    const { nowModel: model, nowLevel: level, isHeld, defaultModel, defaultLevel } = chatState(await heldPair($), options)
    const yours = t.pair(defaultModel, defaultLevel)
    if (!arg) {
      let answer = ''
      try {
        const picked = await $.ui.ask(t.modeQuestionFor(mode, model, level), { options: MODES.map(m => t.modeName(m)), header: 'CoreModel' })
        answer = MODES.find(m => t.modeName(m) === picked) ?? ''
      } catch {
        // Dismissed: say where things stand, change nothing.
      }
      if ((MODES as readonly string[]).includes(answer)) return { text: await setMode($, options, answer as Mode) }
    }
    return { text: t.status(mode, pickOn(options), model, level, isHeld, yours) }
  })
}
