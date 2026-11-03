import { mock } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { ConfigRow, On } from 'claude-code'

// The world beneath the plugin, answered from memory. `answer` is the classifier's next reply;
// `reply` the person's answer to the question (null = dismissed); `row` the config menu's effort row.
export type World = {
  answer: string | Error | { isAnswered: false }
  reply: string | null | Promise<string | null>
  row: ConfigRow | null
  lastReply: string
  model: string[]
  prompts: string[]
  asked: string[][]
  set: unknown[]
  logs: string[]
  efforts: (string | number | undefined)[]
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
    reply: null,
    row: row(),
    lastReply: '',
    model: [],
    prompts: [],
    asked: [],
    set: [],
    logs: [],
    efforts: [],
    clock: mock.clock(on),
  }
  mock.store(on, store)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text, origin: e.origin }))
  mock.env(on, { HOME: '/fake-home' })
  on('command.register', (_, e) => ({ value: { command: e.name } }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('ui.invalidate', () => ({ value: undefined }) as never)
  on('session.messages', () => ({ value: w.lastReply ? [{ role: 'assistant', text: w.lastReply, toolUses: [] }] : [] }) as never)
  on('fs.exists', () => ({ value: false }) as never)
  on('fs.read', () => ({ value: '' }) as never)
  on('fs.write', (_, e) => {
    w.logs.push(`${e.path}\n${e.text}`)
    return { value: undefined } as never
  })
  on('config.list', () => ({ value: w.row ? [w.row] : [] }) as never)
  on('config.set', (_, e) => {
    w.set.push(e)
    return { value: (e as { value: unknown }).value } as never
  })
  on('model.complete', (_, e) => {
    w.model.push(e.model)
    w.prompts.push(e.prompt)
    const a = w.answer
    if (a instanceof Error) throw a
    if (typeof a !== 'string') return { value: { isAnswered: false, reason: 'api-error', status: null } } as never
    return { value: { isAnswered: true, text: a, usage: {} } } as never
  })
  on('tool.call', { tool: 'AskUserQuestion' }, async (_, e) => {
    const qs = (e as unknown as { questions: { question: string; options: { label: string }[] }[] }).questions
    w.asked.push(qs[0]!.options.map(o => o.label))
    const r = await w.reply
    if (r === null) return { deny: 'dismissed' }
    return { result: { questions: qs, answers: { [qs[0]!.question]: r } } } as never
  })
  on('turn.step', async function* (_, e) {
    w.efforts.push(e.effort)
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

export async function step($: Eng, effort: string, index = 0, agentId?: string) {
  const s = $.turn.step({ turnId: 't', index, model: 'm', effort: effort as never, messageCount: 1, agentId })
  for await (const _ of s) void _
  await s.result
}

