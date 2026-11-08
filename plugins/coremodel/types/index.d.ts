export type Level = 'low' | 'medium' | 'high' | 'xhigh' | 'max'

/** The models CoreModel picks from, weakest to strongest. */
export type ModelKey = 'haiku' | 'sonnet' | 'opus' | 'fable'

/** The line above the prompt: a silent switch with its undo, or (Suggest) a pick the person may take. */
export type Band = {
  /** Changes with every new band, so an old timer never clears a newer one. */
  id: number
  /** The level the switch moved to; null when only the model changed. */
  level: Level | null
  /** The level before the switch; '' when it was not known. */
  from: Level | ''
  /** The classifier's short reason. */
  why: string
  /** The language of the prompt the band answers. */
  lang: 'ru' | 'en'
  /** The model the switch moved to, and from; absent when the model did not change. */
  model?: ModelKey | null
  fromModel?: ModelKey | ''
  /** What the undo button restores per part: a level or model to hold, or 'release'; null: no button. */
  undo: { level?: Level | 'release'; model?: ModelKey | 'release' } | null
  /** A suggestion: `model` and `level` are what it offers (null: that part stays); Switch holds them. */
  suggest?: boolean
}

/** One switch, drawn as a row in the transcript. */
export type Mark = { level: Level | null; from: Level | ''; model?: ModelKey | null; fromModel?: ModelKey | ''; why: string; lang: 'ru' | 'en' }

/** What this session's picks came to. */
export type Stats = {
  /** Readable picks per level. */
  picks: Record<Level, number>
  /** Prompts left as they were: a keep pick, the same pair, a Keep answer, a dismissed question or a model question left alone. */
  kept: number
  /** The last readable pick. */
  last: { level: Level; why: string; model?: ModelKey; /** The person kept what they had. */ declined?: boolean } | null
  /** Readable picks per model; absent in counts stored before 0.4.0. */
  models?: Record<ModelKey, number>
  /** How many marks were placed; the next mark's id is `mark-<marks + 1>`. */
  marks: number
}

declare module 'claude-code' {
  interface PluginState {
    'coremodel': {
      band: Band | null
      /** The held pair the drawings read: the model and level put on every main-chat request, or null. */
      override: { model: ModelKey | null; level: Level | null } | null
      /** The transcript rows placed for switches, by row id. */
      marks: Record<string, Mark>
      /** Null until something is counted. */
      stats: Stats | null
      /** Classifier calls that failed in a row, and the last reason; null once a pick works. */
      failure: { count: number; reason: string } | null
    }
  }
}
