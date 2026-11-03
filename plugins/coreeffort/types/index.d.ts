export type Level = 'low' | 'medium' | 'high' | 'xhigh' | 'max'

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
}

declare module 'claude-code' {
  interface PluginState {
    'coreeffort': {
      band: Band | null
      /** The level put on every main-chat request when the effort setting could not take it. */
      override: Level | null
    }
  }
}
