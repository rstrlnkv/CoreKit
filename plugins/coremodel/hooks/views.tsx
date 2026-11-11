import type { Register } from 'claude-code'

import { acceptSuggestion, declineSuggestion, undoChange, undoTarget } from './actions'
import { classifierFault, FAIL_SHOW } from './ask'
import { LEVELS } from './classifier'
import { chatState, currentBand, heldPair, paneChoice, paneModel, setMode } from './hold'
import { allowedModels, currentMode, log, pickOn, PLUGIN } from './host'
import { LADDER, MODELS } from './models'
import { placedMarks, sessionStats } from './pick'
import { type Mode, MODES, texts } from './policy'
import { session } from './session'

// The narrowest a block of the pane may be, in cells: two blocks side by side need twice this (and a
// gap), so a pane narrower than that stacks them. The session groups wrap the same way at GROUP.
const BLOCK = 28
const GROUP = 20
// The longest session bar, in cells; the others are drawn to scale, at least one cell.
const BAR = 10
// A cell of the effort scale: filled up to the current level.
const FILLED = '▰'
const EMPTY = '▱'

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
  // The layout: the name and the mode list; then two blocks that sit side by side in a wide pane and
  // stack in a narrow one (the pair, the model and effort controls); then the session, a model group
  // and an effort group that wrap the same way; then the warnings.
  on('ui.render', { component: 'Pane', requestId: 'coremodel' }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Button, Text } = ui
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
    const nowPair = t.pair(nowModel, nowLevel)
    const yours = t.pair(defaultModel, defaultLevel)
    const caption = (text: string) => <Text dimColor>{text}</Text>
    // A surface with no Select (the mobile app) gets the modes as buttons, the selected one marked in words.
    const modes =
      'Select' in ui ? (
        <ui.Select key="mode" value={mode} options={MODES.map(m => ({ value: m, label: t.modeName(m) }))} onSelect={v => act('mode', () => setMode($, options, v as Mode))()} />
      ) : (
        <Box key="modes" flexWrap="wrap" gap="xs">
          {MODES.map(m => (
            <Button key={`mode-${m}`} label={m === mode ? `● ${t.modeName(m)}` : t.modeName(m)} variant={m === mode ? 'primary' : undefined} onPress={act('mode', () => setMode($, options, m))} />
          ))}
        </Box>
      )
    // The pair: CoreModel's pick with Reset and what Claude has under it, or what Claude has alone.
    const now = (
      <Box key="now" flexDirection="column" gap="xs" flexGrow={1} minWidth={BLOCK} borderStyle="round" paddingX={1}>
        {caption(isHeld ? t.pickedBy : t.inClaude)}
        <Box key="pair" flexDirection="row" flexWrap="wrap" gap="sm" justifyContent="space-between" alignItems="center">
          {nowPair ? <Text size="heading" weight="semibold">{nowPair}</Text> : <Text size="heading" dimColor>—</Text>}
          {isHeld ? <Button key="release" label={t.reset} onPress={act('release', () => paneChoice($, null))} /> : null}
        </Box>
        {isHeld && yours ? <Text dimColor>{t.inClaudeIs(yours)}</Text> : null}
      </Box>
    )
    // The effort scale: one button per level, named by its label, drawn as a cell filled up to the current level.
    const at = nowLevel ? LEVELS.indexOf(nowLevel) : -1
    const choose = (
      <Box key="choose" flexDirection="column" gap="sm" flexGrow={1} minWidth={BLOCK}>
        {withModel && allowed.length ? (
          <Box key="choose-model" flexDirection="column" gap="xs">
            {caption(t.model)}
            <Box key="models" flexWrap="wrap" gap="xs">
              {allowed.map(m => (
                <Button key={`model-${m}`} label={m === nowModel ? `● ${MODELS[m].name}` : MODELS[m].name} variant={m === nowModel ? 'primary' : undefined} onPress={act('model', () => paneModel($, m))} />
              ))}
            </Box>
          </Box>
        ) : null}
        <Box key="choose-level" flexDirection="column" gap="xs">
          {caption(t.effort)}
          <Box key="levels" flexDirection="row">
            {LEVELS.map((l, i) => (
              <Box key={`level-${l}-cell`} flexGrow={1}>
                <Button key={`level-${l}`} label={t.levelName(l)} plain variant={l === nowLevel ? 'primary' : undefined} onPress={act('level', () => paneChoice($, l))}>
                  {i <= at ? FILLED : EMPTY}
                </Button>
              </Box>
            ))}
          </Box>
        </Box>
      </Box>
    )
    // One group of the session: the most used first, a bar of up to BAR cells to scale, the count.
    const group = (key: string, title: string, rows: [string, number][]) => {
      if (!rows.length) return null
      const most = Math.max(...rows.map(r => r[1]))
      const width = Math.max(...rows.map(r => r[0].length)) + 1
      return (
        <Box key={key} flexDirection="column" gap="xs" flexGrow={1} minWidth={GROUP}>
          <Text weight="semibold">{title}</Text>
          {[...rows]
            .sort((a, b) => b[1] - a[1])
            .map(([name, n]) => (
              <Box key={`${key}-${name}`} flexDirection="row" gap="sm">
                <Box key={`${key}-${name}-name`} minWidth={width}>
                  <Text>{name}</Text>
                </Box>
                <Text dimColor>{'█'.repeat(Math.max(1, Math.round((n / most) * BAR)))}</Text>
                <Text tabular>{String(n)}</Text>
              </Box>
            ))}
        </Box>
      )
    }
    const models = s && withModel ? group('session-models', t.model, LADDER.filter(m => s.models[m] > 0).map(m => [MODELS[m].name, s.models[m]])) : null
    const levels = s ? group('session-levels', t.effort, LEVELS.filter(l => s.picks[l] > 0).map(l => [t.levelName(l), s.picks[l]])) : null
    const kept = s && s.kept > 0 ? s.kept : 0
    const warnings = [
      ...(fault && fault.count >= FAIL_SHOW ? [t.classifierSilent] : []),
      ...[...session.unavailable].map(m => t.unavailableModel(m)),
    ]
    return (
      <Box flexDirection="column" gap="md">
        <Box key="head" flexDirection="row" flexWrap="wrap" gap="sm" justifyContent="space-between" alignItems="center">
          <Text weight="semibold">CoreModel</Text>
          {modes}
        </Box>
        <Box key="top" flexDirection="row" flexWrap="wrap" gap="md">
          {now}
          {choose}
        </Box>
        {models || levels || kept ? (
          <Box key="session" flexDirection="column" gap="xs">
            <Box key="session-head" flexDirection="row" gap="sm" justifyContent="space-between">
              {caption(t.thisSession)}
              {kept ? caption(t.unchanged(kept)) : null}
            </Box>
            <Box key="session-groups" flexDirection="row" flexWrap="wrap" gap="md">
              {models}
              {levels}
            </Box>
          </Box>
        ) : null}
        {warnings.map(w => (
          <Text key={`warn-${w}`} color="warning">{`⚠ ${w}`}</Text>
        ))}
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
