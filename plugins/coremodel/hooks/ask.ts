// The classifier call: a second try when the first hangs or fails, the cut by an Esc, and the
// failures in a row ($.state failure).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, ModelCompleteResult } from 'claude-code'

import type { Lang, Level } from '../types'
import { buildPrompt, parseAnswer } from './classifier'
import { texts } from './policy'

const failure = atom({ plugin: 'coremodel', key: 'failure' } as const, null)

// Classifier failures in a row before the person is told: one is often a passing API hiccup.
export const FAIL_SHOW = 2

// The classifier answers in about 2 s; the whole pick waits CLASSIFY_MS at most, and a second
// call starts when the first has not answered in HEDGE_MS.
const CLASSIFY_MS = 8_000
const HEDGE_MS = 3_000

/** An Esc on the turn cut the classifier: the person stopped it, nothing is broken. */
export class Cut extends Error {}

/** One more classifier failure in a row; the second one is told once, in a toast. */
export async function failed($: EngineInterface, lang: Lang, reason: string): Promise<void> {
  let inRow = 0
  await update($, failure, cur => {
    inRow = (cur?.count ?? 0) + 1
    return { count: inRow, reason }
  })
  if (inRow === FAIL_SHOW) {
    try {
      $.ui.toast(texts(lang).classifierDown(reason))
    } catch {
      // The pane still says it.
    }
  }
}

/** The first call that answers; when none does, the last failure (a call that throws counts as one). */
function firstAnswered(calls: Promise<ModelCompleteResult>[]): Promise<ModelCompleteResult> {
  return new Promise((resolve, reject) => {
    let left = calls.length
    const failed = (settle: () => void) => {
      left -= 1
      if (left === 0) settle()
    }
    for (const c of calls) {
      c.then(
        r => (r.isAnswered ? resolve(r) : failed(() => resolve(r))),
        err => failed(() => reject(err)),
      )
    }
  })
}

export async function classify($: EngineInterface, text: string, now: Level | '', model: string) {
  const messages = await $.session.messages()
  let lastReply = ''
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const m = messages[i]!
    if (m.role === 'assistant' && m.text.trim()) {
      lastReply = m.text
      break
    }
  }
  const prompt = buildPrompt({ prompt: text, lastReply, now })
  const ask = (timeoutMs: number, stop: AbortController) =>
    $.model.complete({ model, prompt, maxTokens: 120, effort: 'low', timeoutMs }, { signal: stop.signal })
  // A call sometimes hangs with no reply (seen on a chat's first prompt, beside the title request):
  // a second one starts after HEDGE_MS, the first answer of the two is used, the other is cut.
  // A call that fails outright before that (a 529, a throw) is tried once more at once; an Esc
  // ('aborted') is not a failure to retry.
  const first = new AbortController()
  const second = new AbortController()
  const began = await $.clock.now()
  type Done = { r: ModelCompleteResult } | { err: unknown }
  const a = ask(CLASSIFY_MS, first)
  const aDone: Promise<Done> = a.then(r => ({ r }), err => ({ err }))
  // A sleep that fails never fires the second call early: the first one is simply waited for.
  const hedge = $.clock.sleep(HEDGE_MS).then(() => 'hedge' as const, () => new Promise<never>(() => {}))
  const early = await Promise.race([aDone, hedge])
  const retry = async (): Promise<ModelCompleteResult> => ask(Math.max(1_000, CLASSIFY_MS - ((await $.clock.now()) - began)), second)
  let r: ModelCompleteResult
  let tried = false
  if (early === 'hedge') {
    tried = true
    r = await firstAnswered([a, ask(CLASSIFY_MS - HEDGE_MS, second)])
  } else if ('r' in early && (early.r.isAnswered || early.r.reason === 'aborted')) {
    r = early.r
  } else {
    tried = true
    r = await retry()
  }
  first.abort()
  second.abort()
  if (!r.isAnswered) {
    // An Esc on the turn cuts both calls too, sooner: only the full wait is a timeout.
    const waited = (await $.clock.now()) - began
    if (tried && r.reason === 'aborted' && waited >= CLASSIFY_MS) throw new Error(`classifier timed out after ${CLASSIFY_MS / 1000} s (two tries)`)
    if (r.reason === 'aborted') throw new Cut('classifier gave no answer: aborted')
    const status = 'status' in r && r.status ? ` ${r.status}` : ''
    throw new Error(`classifier gave no answer: ${r.reason}${status}`)
  }
  const pick = parseAnswer(r.text)
  if (!pick) throw new Error(`classifier answer not readable: ${r.text.slice(0, 200)}`)
  return pick
}

/** A pick that worked: the failures in a row start over. */
export async function pickWorked($: EngineInterface): Promise<void> {
  if (await read($, failure)) await update($, failure, () => null)
}

/** The classifier failures in a row and the last reason, for the pane; null once a pick works. */
export async function classifierFault($: EngineInterface) {
  return read($, failure)
}
