import type { Band, Lang, Level } from '../types'
import type { ModelKey } from './models'

/** How long a band stays above the prompt. */
export const BAND_MS = 15_000

/** The prompt waiting for its pick at the turn's first request. */
export type Held = { text: string; gen: number; lang: Lang; turn?: string }

// Module variables start over on a reload; what must outlive one is in $.state or $.store.
export const session = {
  // Bumped on every prompt, so a pick for an older prompt is dropped.
  gen: 0,
  nextBand: 1,
  // Bumped when the person changes the hold themselves (a pane press, Back): a pick that began
  // earlier is dropped, so its late answer never overrides their newer choice.
  touched: 0,
  // The prompt waiting for its pick at the turn's first request. `turn` is the turn that was
  // running when it was typed (it waits in the queue behind that turn); absent when the chat was idle.
  held: null as Held | null,
  // The chosen level, put on every main-chat request until the person moves the menu. It lives in
  // this chat only: the app's own effort setting is never written. `base` is the menu's level when
  // the hold began.
  hold: null as { level: Level; base: string } | null,
  // The chosen model, held the same way; `base` is the request's own model when the hold began.
  modelHold: null as { key: ModelKey; base: string } | null,
  // The level the last main-chat request ran at.
  seen: '' as Level | '',
  // The model the last main-chat request named (the person's own unless held).
  seenModel: '',
  // Models this account refused in this session: never picked again until a new session.
  unavailable: new Set<ModelKey>(),
  // The models the account lists in /config (the Model row), read again before every pick and at a new
  // session; null when the row says nothing usable. Never stored: a model that appears later is seen.
  listed: null as ModelKey[] | null,
  // The menu's own effort as the last main-chat request carried it.
  asked: '',
  // The language of the words, read at the session start and again on every prompt (see currentLang).
  lastLang: 'en' as Lang,
  // Where the session draws: VS Code draws neither the band nor the footer, so a switch is told in a toast.
  surface: '',
  // The last silent switch, for /coremodel undo after its band is gone.
  lastUndo: null as Band | null,
}
