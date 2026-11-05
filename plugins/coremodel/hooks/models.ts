// The models CoreModel picks from, their prices, and the cost of a model switch mid-chat.
// No calls on `$` here. Prices: Anthropic API, $ per million input tokens (spec §3).

import type { ModelKey } from '../types'

export type { ModelKey }

/** Weakest to strongest. */
export const LADDER: readonly ModelKey[] = ['haiku', 'sonnet', 'opus', 'fable']

export const MODELS: Record<ModelKey, { id: string; name: string; input: number }> = {
  haiku: { id: 'claude-haiku-5-5', name: 'Haiku', input: 0.1 },
  sonnet: { id: 'claude-sonnet-5-5', name: 'Sonnet', input: 2 },
  opus: { id: 'claude-opus-5-5', name: 'Opus', input: 4 },
  fable: { id: 'claude-fable-5-1', name: 'Fable', input: 10 },
}

/** A cache write (5-minute TTL) costs this many times the input price, on every model. */
const WRITE = 1.25

/** A model key from a key, a name ("Fable 5.1") or an id the engine reports; '' for any other model. */
export function toModel(v: unknown): ModelKey | '' {
  if (typeof v !== 'string') return ''
  const t = v.trim().toLowerCase().replace(/\[.*\]$/, '')
  for (const k of LADDER) {
    const m = MODELS[k]
    if (t === k || t === m.id || t === m.name.toLowerCase() || t.startsWith(`${m.name.toLowerCase()} `)) return k
  }
  return ''
}

/** True when `a` sits above `b` on the ladder; false when `b` is unknown. */
export function stronger(a: ModelKey, b: ModelKey | ''): boolean {
  return b !== '' && LADDER.indexOf(a) > LADDER.indexOf(b)
}

/** The settings key of the switch for a model: useHaiku, useSonnet, useOpus, useFable. */
export function switchKey(k: ModelKey): string {
  return `use${MODELS[k].name}`
}

/**
 * The models switched on in the plugin settings, weakest first. Every switch is on by default; only an
 * explicit off (false, or the words false, off, no, 0) turns one off. All four off means no model is
 * ever picked (the effort still is).
 */
export function enabledModels(options: Readonly<Record<string, unknown>>): ModelKey[] {
  return LADDER.filter(k => {
    const v = options[switchKey(k)]
    if (v === false) return false
    return !(typeof v === 'string' && ['false', 'off', 'no', '0'].includes(v.trim().toLowerCase()))
  })
}

/**
 * The models an account can use, from the choices of the /config Model row (aliases such as
 * `sonnet`, `fable[1m]`, ids; words like `default`, `best` and `opusplan` name no model). Null when
 * the row says nothing usable (absent, empty, no known model): then nothing is filtered.
 */
export function detectModels(options: readonly string[] | undefined): ModelKey[] | null {
  if (!options) return null
  const found = options.map(o => toModel(o))
  const keys = LADDER.filter(k => found.includes(k))
  return keys.length ? keys : null
}

/**
 * What a switch to `to` costs once, in dollars at API prices: the chat is written to the new
 * model's cache. Null when the chat size is unknown.
 */
export function switchUsd(tokens: number | undefined, to: ModelKey): number | null {
  if (!tokens || tokens <= 0) return null
  return (tokens * MODELS[to].input * WRITE) / 1_000_000
}
