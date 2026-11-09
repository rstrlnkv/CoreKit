import type { Register, RenderChildren } from 'claude-code'

import { acceptSuggestion, declineSuggestion, undoChange, undoTarget } from './actions'
import { classifierFault, FAIL_SHOW } from './ask'
import { LEVELS } from './classifier'
import { chatState, currentBand, heldPair, paneChoice, paneModel, setMode } from './hold'
import { allowedModels, currentMode, log, pickOn, PLUGIN } from './host'
import { LADDER, MODELS } from './models'
import { placedMarks, sessionStats } from './pick'
import { MODES, texts } from './policy'
import { session } from './session'

const RULE = '─'.repeat(40)
// The width of the captions in the pane's rows, in cells: the longest caption of the language, plus one,
// so every row's value starts in the same column.
const captionWidth = (t: ReturnType<typeof texts>) =>
  Math.max(...[t.thisChat, t.model, t.effort, t.thisSession, t.lastPick].map(c => c.length)) + 1

/** What CoreModel draws: the footer button, the pane, the transcript rows and the band above the prompt. */
export const drawViews: Register = (on, options) => {
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
