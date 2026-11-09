import type { Register, RenderChildren } from 'claude-code'

import { acceptSuggestion, declineSuggestion, undoChange, undoTarget } from './actions'
import { classifierFault, FAIL_SHOW } from './ask'
import { LEVELS, toLevel } from './classifier'
import { chatState, currentBand, heldPair, paneChoice, paneModel, releaseLevel, releaseModel, setMode } from './hold'
import { allowedModels, currentLang, currentMode, log, pickOn, PLUGIN, refreshListed } from './host'
import { enabledModels, LADDER, MODELS, requestModel, toModel } from './models'
import { newChat, placedMarks, runPick, sessionStats } from './pick'
import { type Mode, MODES, texts } from './policy'
import { session } from './session'

const RULE = '─'.repeat(40)
// The width of the captions in the pane's rows, in cells: the longest caption of the language, plus one,
// so every row's value starts in the same column.
const captionWidth = (t: ReturnType<typeof texts>) =>
  Math.max(...[t.thisChat, t.model, t.effort, t.thisSession, t.lastPick].map(c => c.length)) + 1

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

  // The footer slot: the engine's own mode words, then a button that carries CoreModel's state and
  // opens and closes the pane (no chat command, so a running turn is not interrupted).
  on('ui.render', { component: 'SessionMode' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(session.lastLang)
    const { nowModel, nowLevel, isHeld } = chatState(await heldPair($), options)
    const mode = await currentMode($, options)
    // While a model or level is set, both parts are named: the part not set is what the chat last showed.
    const state = mode === 'off' ? t.off : isHeld ? t.pair(nowModel, nowLevel) : ''
    const isUp = (await $.ui.panes()).some(p => p.id === PLUGIN)
    const toggle = async () => {
      if ((await $.ui.panes()).some(p => p.id === PLUGIN)) await $.ui.close({ id: PLUGIN })
      else await $.ui.open({ id: PLUGIN, title: 'CoreModel' })
      $.ui.invalidate('ui.render')
    }
    return (
      <Box gap="sm">
        {e.props.modes.length ? <Text dimColor>{e.props.modes.join(' & ')}</Text> : null}
        <Button key="pane" label={state ? `CoreModel · ${state}` : 'CoreModel'} variant={isUp ? 'primary' : undefined} onPress={() => void toggle().catch(err => log($, 'pane', err))} />
      </Box>
    )
  })

  // A hook's filter is read from literals in its own file, so the pane id is spelled out here.
  on('ui.render', { component: 'Pane', requestId: 'coremodel' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(session.lastLang)
    const mode = await currentMode($, options)
    const { nowModel, nowLevel, isHeld, defaultModel, defaultLevel } = chatState(await heldPair($), options)
    const s = await sessionStats($)
    const fault = await classifierFault($)
    const allowed = allowedModels(options)
    // pickModel off: effort only.
    const withModel = pickOn(options)
    const act = (what: string, f: () => Promise<unknown>) => () => {
      f().catch(err => log($, what, err))
    }
    // A selected button says so in its words, not by colour alone; the colour stays as a second cue.
    const mark = (label: string, isOn: boolean) => (isOn ? `● ${label}` : label)
    const nowPair = t.pair(nowModel, nowLevel)
    const yours = t.pair(defaultModel, defaultLevel)
    const caption = captionWidth(t)
    const row = (key: string, label: string, body: RenderChildren) => (
      <Box key={key} flexDirection="row" gap="sm">
        <Box key={`${key}-caption`} minWidth={caption}>
          <Text dimColor>{label}</Text>
        </Box>
        {body}
      </Box>
    )
    const rule = (key: string) => (
      <Text key={key} dimColor wrap="truncate-end">
        {RULE}
      </Text>
    )
    // The session in one line: models, then efforts, then the prompts left as they were.
    const sessionLine = s
      ? [
          ...(withModel ? LADDER.filter(m => s.models[m] > 0).map(m => `${MODELS[m].name} ${s.models[m]}`) : []),
          ...LEVELS.filter(l => s.picks[l] > 0).map(l => `${t.levelName(l)} ${s.picks[l]}`),
          ...(s.kept > 0 ? [t.unchanged(s.kept)] : []),
        ].join(' · ')
      : ''
    // The last pick, only when it says something the chat does not: it was not applied, or it differs.
    const last = s?.last
    const lastPair = last ? t.pair(withModel && last.model ? last.model : '', last.level) : ''
    const showLast = !!last && (!!last.declined || last.level !== nowLevel || (withModel && !!last.model && last.model !== nowModel))
    const lastLine = last ? [lastPair, last.why, last.declined ? t.notApplied : ''].filter(Boolean).join(' · ') : ''
    return (
      <Box flexDirection="column" gap="sm">
        <Box key="mode" flexDirection="column" gap="xs">
          <Text weight="semibold">{`CoreModel · ${t.modeName(mode)}`}</Text>
          <Box key="modes" flexWrap="wrap" gap="xs">
            {MODES.map(m => (
              <Button key={`mode-${m}`} label={mark(t.modeName(m), m === mode)} variant={m === mode ? 'primary' : undefined} onPress={act('mode', () => setMode($, options, m))} />
            ))}
          </Box>
          <Text dimColor>{t.modeHintFor(mode, withModel)}</Text>
        </Box>
        {rule('d1')}
        <Box key="now" flexDirection="column" gap="xs">
          {row('chat', t.thisChat, nowPair ? <Text weight="semibold">{nowPair}</Text> : <Text dimColor>{t.shownLater}</Text>)}
          {isHeld ? <Text dimColor>{yours ? `${t.setBy} · ${t.yourDefault(yours)}` : t.setBy}</Text> : null}
          {isHeld ? (
            <Box key="release-row">
              <Button key="release" label={t.useDefault} onPress={act('release', () => paneChoice($, null))} />
            </Box>
          ) : null}
          {fault && fault.count >= FAIL_SHOW ? <Text key="fault" color="warning">{`⚠ ${t.classifierDown(fault.reason)}`}</Text> : null}
          {[...session.unavailable].map(m => (
            <Text key={`unavailable-${m}`} color="warning">{`⚠ ${t.unavailableModel(m)}`}</Text>
          ))}
        </Box>
        {withModel && allowed.length
          ? row(
              'choose-model',
              t.model,
              <Box key="models" flexWrap="wrap" gap="xs" flexShrink={1}>
                {allowed.map(m => (
                  <Button key={`model-${m}`} label={mark(MODELS[m].name, m === nowModel)} variant={m === nowModel ? 'primary' : undefined} onPress={act('model', () => paneModel($, m))} />
                ))}
              </Box>,
            )
          : null}
        {row(
          'choose',
          t.effort,
          <Box key="levels" flexWrap="wrap" gap="xs" flexShrink={1}>
            {LEVELS.map(l => (
              <Button key={`level-${l}`} label={mark(t.levelName(l), l === nowLevel)} variant={l === nowLevel ? 'primary' : undefined} onPress={act('level', () => paneChoice($, l))} />
            ))}
          </Box>,
        )}
        {sessionLine || showLast ? rule('d2') : null}
        {sessionLine ? row('session', t.thisSession, <Text>{sessionLine}</Text>) : null}
        {showLast ? row('last', t.lastPick, <Text>{lastLine}</Text>) : null}
      </Box>
    )
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== PLUGIN) return next(e)
    const m = (await placedMarks($))[e.props.id]
    if (!m) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{texts(m.lang).markPair(m.model, m.fromModel, m.level, m.from, m.why)}</Text>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const b = await currentBand($)
    if (!b || e.props.hasSurvey) return next(e)
    const rest = await next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const t = texts(b.lang)
    // A press on an old band, or after the person changed it: their own choice stands.
    const current = async () => {
      const cur = await currentBand($)
      return !!cur && cur.id === b.id
    }
    if (b.suggest) {
      const what = t.change(b.model, '', b.level, '', b.why)
      return (
        <Box flexDirection="column">
          {rest}
          <Box gap="sm">
            <Text wrap="truncate-end">{`${t.suggests} ${what}`}</Text>
            <Button key="switch" hotkey="1" label={t.switchButton} onPress={() => void (async () => (await current()) && acceptSuggestion($, b))().catch(err => log($, 'switch', err))} />
            <Button key="keep" hotkey="2" label={t.keepButton} onPress={() => void (async () => (await current()) && declineSuggestion($, b))().catch(err => log($, 'keep', err))} />
          </Box>
        </Box>
      )
    }
    const back = undoTarget(b)
    return (
      <Box flexDirection="column">
        {rest}
        <Box gap="sm">
          <Text wrap="truncate-end">{`✓ CoreModel: ${t.change(b.model, b.fromModel, b.level, b.from, b.why)}`}</Text>
          {b.undo ? <Button key="undo" hotkey="1" label={t.backTo(t.pair(back.model, back.level))} onPress={() => void (async () => (await current()) && undoChange($, b))().catch(err => log($, 'undo', err))} /> : null}
        </Box>
      </Box>
    )
  })
}
