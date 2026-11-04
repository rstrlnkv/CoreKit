export type Level = 'low' | 'medium' | 'high' | 'xhigh' | 'max'

/** The models CoreModel picks from, weakest to strongest. */
export type ModelKey = 'haiku' | 'sonnet' | 'opus' | 'fable'

/** The line above the prompt after a switch. */
export type Band = {
  /** Changes with every new band, so an old timer never clears a newer one. */
  id: number
  level: Level
  /** The level before the switch; '' when it was not known. */
  from: Level | ''
  /** The classifier's short reason. */
  why: string
  /** The language of the prompt the band answers. */
  lang: 'ru' | 'en'
  /** What the undo button does: hold this level, drop the hold, or no button (null). */
  undo: Level | 'release' | null
}

/** One switch, drawn as a row in the transcript. */
export type Mark = { level: Level; from: Level | ''; why: string; lang: 'ru' | 'en' }

/** What this session's picks came to. */
export type Stats = {
  /** Readable picks per level. */
  picks: Record<Level, number>
  /** Prompts whose level stayed: a keep pick, the same level, a Keep answer or a dismissed question. */
  kept: number
  /** The last readable pick. */
  last: { level: Level; why: string } | null
  /** How many marks were placed; the next mark's id is `mark-<marks + 1>`. */
  marks: number
}

declare module 'claude-code' {
  interface PluginState {
    'coremodel': {
      band: Band | null
      /** The level put on every main-chat request when the effort setting could not take it. */
      override: { model: ModelKey | null; level: Level | null } | null
      /** The transcript rows placed for switches, by row id. */
      marks: Record<string, Mark>
      /** Null until something is counted. */
      stats: Stats | null
    }
  }
}
