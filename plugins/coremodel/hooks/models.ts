// The models CoreModel picks from, their prices, and the cost of a model switch mid-chat.
// No calls on `$` here. Prices: Anthropic API, $ per million input tokens (spec §3).

export type ModelKey = 'haiku' | 'sonnet' | 'opus' | 'fable'

/** Weakest to strongest. */
export const LADDER: readonly ModelKey[] = ['haiku', 'sonnet', 'opus', 'fable']

export const MODELS: Record<ModelKey, { id: string; name: string; input: number; read: number }> = {
  haiku: { id: 'claude-haiku-5-5', name: 'Haiku', input: 0.1, read: 0.1 },
  sonnet: { id: 'claude-sonnet-5-5', name: 'Sonnet', input: 2, read: 0.05 },
  opus: { id: 'claude-opus-5-5', name: 'Opus', input: 4, read: 0.05 },
  fable: { id: 'claude-fable-5-1', name: 'Fable', input: 10, read: 0.025 },
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

/** The `models` setting as ladder-ordered keys; unknown words are dropped, nothing left means all four. */
export function parseModels(setting: unknown): ModelKey[] {
  const words = typeof setting === 'string' ? setting.split(',').map(w => toModel(w)) : []
  const picked = LADDER.filter(k => words.includes(k))
  return picked.length ? picked : [...LADDER]
}

/**
 * What a switch from `from` to `to` costs, in replies read from the cache on `from`: the chat is
 * written to the new model's cache once. Null when the chat size or the current model is unknown.
 */
export function switchCost(tokens: number | undefined, from: ModelKey | '', to: ModelKey): number | null {
  if (!tokens || tokens <= 0 || !from) return null
  const write = tokens * MODELS[to].input * WRITE
  const read = tokens * MODELS[from].input * MODELS[from].read
  return Math.max(1, Math.ceil(write / read))
}
