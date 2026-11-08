// The words CoreModel shows, in English. Every locale has the same keys (the type `Strings`): to add a
// language, copy this file, translate the values, and add it to LOCALES in ../policy.ts.
// Names of models are not translated; a `pair` is a model and an effort already joined ("Opus · High").
import type { Level } from '../../types'

export const en = {
  level: { low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' } as Record<Level, string>,
  mode: { auto: 'Auto', suggest: 'Suggest', off: 'Off' },
  modeHint: {
    auto: 'Asks only before Fable, Extra high, Max and a stronger model mid-chat',
    suggest: 'Never asks: suggests above the prompt, you press to switch',
    off: 'Changes nothing',
  },
  // Auto when CoreModel picks the effort only (pickModel off).
  autoEffortHint: 'Asks only before Extra high and Max',

  // the dialogs
  effortHeader: 'Effort',
  modelHeader: 'Model',
  effortQuestion: (level: string, an: boolean, why: string) => `This looks like ${an ? 'an' : 'a'} ${level} effort task${why ? `: ${why}` : ''}. Switch before Claude starts?`,
  firstModelQuestion: (model: string, why: string) => `This looks like work for ${model}${why ? `: ${why}` : ''}. Switch the model?`,
  recommended: (label: string) => `${label} (recommended)`,
  keep: (what: string) => `Keep ${what}`,
  keepLevel: (level: string) => `Keep ${level}`,
  keepAsIs: 'Keep it as it is',
  keepCurrentModel: 'Keep the current model',
  backToModel: '← Back to the model',
  switchTo: (model: string) => `Switch to ${model}`,
  cancel: 'Cancel',
  // The cost question: the lasting price first, then the one-off re-read.
  costHead: (model: string) => `Switch to ${model}?`,
  costMore: (ratio: string, from: string) => `From now on each reply costs about ${ratio}× ${from}.`,
  costLess: (ratio: string, from: string) => `From now on each reply costs about 1/${ratio} of ${from}, after this chat is re-read once.`,
  rereadSized: (k: number, money: string) => `Switching also re-reads this chat once: ≈ ${k}k tokens, about ${money} at API prices (on a subscription it counts toward your limits).`,
  reread: 'Switching also re-reads this chat once, which costs tokens.',
  because: (why: string) => `Because: ${why}.`,

  // the band, the transcript rows, the footer
  effortWord: 'Effort',
  was: (pair: string) => `was ${pair}`,
  backTo: (pair: string) => `Back to ${pair}`,
  suggests: 'CoreModel suggests',
  switchButton: 'Switch',
  keepButton: 'Keep',
  undoHint: 'undo: /coremodel undo',
  off: 'off',
  insteadOf: (from: string, to: string) => `${from} is not available, ${to} instead`,

  // the pane
  thisChat: 'This chat',
  shownLater: 'shown after your first message',
  setBy: 'Set by CoreModel for this chat',
  yourDefault: (pair: string) => `your default: ${pair}`,
  useDefault: 'Use my default',
  model: 'Model',
  effort: 'Effort',
  thisSession: 'This session',
  unchanged: (n: number) => `unchanged ${n}`,
  lastPick: 'Last pick',
  notApplied: 'not applied',
  unavailable: (model: string) => `${model} is not available — CoreModel will not pick it again this session (/coremodel recheck tries again)`,
  classifierDown: (reason: string) => `CoreModel cannot get an answer from its classifier (${reason}). Your prompts run unchanged. Details: claude --debug.`,

  // the /coremodel replies
  modeQuestion: (mode: string, pair: string) => `CoreModel: ${mode}. This chat: ${pair}. Which mode?`,
  modeIs: (mode: string, hint: string) => `Mode: ${mode}. ${hint}.`,
  chatIs: (pair: string) => `This chat: ${pair}.`,
  chatIsSet: (pair: string, yours: string) => `This chat: ${pair} (set by CoreModel${yours ? `; your default: ${yours}` : ''}).`,
  commands: 'Type /coremodel auto, suggest, off, on, panel, undo or recheck.',
  unknownPair: 'not known yet',
  modeOff: 'Off. /coremodel on turns it back on.',
  modeOn: (mode: string) => `On: ${mode}.`,
  paneOpen: 'The pane is open.',
  paneWaiting: (reason: string) => `The pane is waiting: ${reason}`,
  undone: (pair: string) => `Back to ${pair}.`,
  nothingToUndo: 'Nothing to undo: the last switch was taken back or changed since.',
  probeLogged: (n: number) => `CoreModel probe: ${n} rows written to the debug log (claude --debug).`,
  recheckEffortOnly: 'pickModel is off: CoreModel picks the effort only.',
  recheckAllOff: 'Every model is switched off in the settings, so CoreModel picks the effort only. Switch the ones you want on in the plugin settings.',
  recheckNone: "Nothing to pick: the models switched on in the settings and the account's model list share no model. Switch other models on in the plugin settings.",
  recheckModels: (names: string) => `Models CoreModel may pick: ${names}.`,
  recheckUnfiltered: " The account's model list could not be used, so nothing was filtered.",
  checking: 'checking model and effort…',
  checkingEffort: 'checking effort…',
}

export type Strings = typeof en
