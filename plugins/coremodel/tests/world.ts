import { mock } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { ConfigRow, On } from 'claude-code'

// The world beneath the plugin, answered from memory. `answer` is the classifier's next reply;
// `reply` the person's answer to the question (null = dismissed); `row` the config menu's effort row.
export type World = {
  answer: string | Error | { isAnswered: false } | Promise<string>
  /**
   * Per-call answers, taken in order before `answer`: a text at once, or one that comes `after` ms
   * on the mocked clock; with no text the call hangs until its own timeoutMs cuts it, or until
   * `after` ms when `cut` (an Esc on the turn).
   */
  answers: (string | { after: number; text?: string; cut?: boolean })[]
  /** The timeoutMs of each classifier call. */
  timeouts: (number | undefined)[]
  /** One answer for every question, or a queue answered in order (an empty queue dismisses). */
  reply: string | null | Promise<string | null> | (string | null)[]
  questions: string[]
  headers: string[]
  tokens: number | undefined
  models: (string | undefined)[]
  row: ConfigRow | null
  lastReply: string
  model: string[]
  prompts: string[]
  asked: string[][]
  set: unknown[]
  logs: string[]
  efforts: (string | number | undefined)[]
  placed: string[]
  opened: unknown[]
  clock: ReturnType<typeof mock.clock>
}

export function row(value = 'Medium', isLocked = false): ConfigRow {
  return {
    key: 'effortLevel',
    label: 'Effort',
    kind: 'choice',
    value,
    options: ['Low', 'Medium', 'High', 'Extra high', 'Max'],
    provider: { kind: 'user' } as never,
    isLocked,
  }
}

export function world(on: On, store: Record<string, unknown> = {}): World {
  const w: World = {
    answer: '{"level":"high","why":"auth bug"}',
    answers: [],
    timeouts: [],
    reply: null,
    questions: [],
    headers: [],
    tokens: undefined,
    models: [],
    row: row(),
    lastReply: '',
    model: [],
    prompts: [],
    asked: [],
    set: [],
    logs: [],
    efforts: [],
    placed: [],
    opened: [],
    clock: mock.clock(on),
  }
  mock.store(on, store)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text, origin: e.origin }))
  mock.env(on, { HOME: '/fake-home' })
  on('command.register', (_, e) => ({ value: { command: e.name } }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('ui.place', (_, e) => {
    w.placed.push((e as { id: string }).id)
    return { value: { isPlaced: true } } as never
  })
  on('ui.open', (_, e) => {
    w.opened.push(e)
    return { value: { isPlaced: true } } as never
  })
  on('ui.invalidate', () => ({ value: undefined }) as never)
  on('session.messages', () => ({ value: w.lastReply ? [{ role: 'assistant', text: w.lastReply, toolUses: [] }] : [] }) as never)
  on('fs.exists', () => ({ value: false }) as never)
  on('fs.read', () => ({ value: '' }) as never)
  on('fs.write', (_, e) => {
    w.logs.push(`${e.path}\n${e.text}`)
    return { value: undefined } as never
  })
  on('classic.StopFailure', () => ({}) as never)
  on('classic.SessionStart', () => ({}) as never)
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: w.tokens, window: 1_000_000 }, rateLimits: [] } }) as never)
  on('config.list', () => ({ value: w.row ? [w.row] : [] }) as never)
  on('config.set', (_, e) => {
    w.set.push(e)
    return { value: (e as { value: unknown }).value } as never
  })
  on('model.complete', async (_, e) => {
    w.model.push(e.model)
    w.prompts.push(e.prompt)
    w.timeouts.push(e.timeoutMs)
    const next = w.answers.shift()
    if (typeof next === 'object') {
      await w.clock.sleep(next.text === undefined && !next.cut ? (e.timeoutMs ?? 10_000) : next.after)
      if (next.text === undefined) return { value: { isAnswered: false, reason: 'aborted', usage: {} } } as never
      return { value: { isAnswered: true, text: next.text, usage: {} } } as never
    }
    const a = next ?? (await w.answer)
    if (a instanceof Error) throw a
    if (typeof a !== 'string') return { value: { isAnswered: false, reason: 'api-error', status: null } } as never
    return { value: { isAnswered: true, text: a, usage: {} } } as never
  })
  on('tool.call', { tool: 'AskUserQuestion' }, async (_, e) => {
    const qs = (e as unknown as { questions: { question: string; header?: string; options: { label: string }[] }[] }).questions
    w.asked.push(qs[0]!.options.map(o => o.label))
    w.questions.push(qs[0]!.question)
    w.headers.push(qs[0]!.header ?? '')
    const r = Array.isArray(w.reply) ? (w.reply.length ? w.reply.shift()! : null) : await w.reply
    if (r === null) return { deny: 'dismissed' }
    return { result: { questions: qs, answers: { [qs[0]!.question]: r } } } as never
  })
  on('turn.step', async function* (_, e) {
    w.efforts.push(e.effort)
    w.models.push(e.model)
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  return w
}

export type Eng = Engine

export async function start($: Eng) {
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
}

export async function submit($: Eng, text: string, kind: 'composer' | 'bridge' | 'sdk' = 'composer') {
  await $.prompt.submit({ text, wait: false, origin: { kind } as never })
}

export async function step($: Eng, effort: string | undefined, index = 0, agentId?: string, model = 'claude-sonnet-5-5') {
  const s = $.turn.step({ turnId: 't', index, model, effort: effort as never, messageCount: 1, agentId })
  for await (const _ of s) void _
  await s.result
}

