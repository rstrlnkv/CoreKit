// The classifier: the model prompt that picks an effort level, and the parser of its answer.
// No calls on `$` here, so the rules can change without touching the hooks.
import type { Level } from '../types'

export type Pick = { level: Level | 'keep'; why: string }

const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

/** Reads a level in any spelling the model may use ("Extra high", "x-high"); '' for anything else. */
export function toLevel(v: unknown): Level | '' {
  if (typeof v !== 'string') return ''
  const t = v.toLowerCase().replace(/[^a-z]/g, '')
  const level = t === 'extrahigh' ? 'xhigh' : t
  return (LEVELS as readonly string[]).includes(level) ? (level as Level) : ''
}

// quality.sh cuts the text between the marker lines: keep the template one plain literal.
// TEMPLATE-START
export const TEMPLATE = `Pick the effort level Claude Code should spend on one prompt. Claude Code is an agent: it reads files, runs commands and changes code, and it also does office work such as writing, documents and analysis. Effort is how much Claude reads, checks and thinks before it acts, and how much it decides on its own. It is not how capable Claude is. More effort costs time and tokens; too little on hard work means missed bugs and wrong answers.

Walk down this ladder and take the first rung that fits:

1. keep: the prompt only approves, answers a question Claude asked, picks an option, or says to carry on (yes, ok, go ahead, do it, option 2, да, давай, продолжай, ок).
2. low: quick, conversational or mechanical work that is easy to check at a glance, where a mistake is cheap.
   Code: explain a snippet or an error message, rename something, fix a typo, change one line of config or text, run a command, a git step, a question about a tool or a flag.
   Office: brainstorm, rewrite a passage, translate a short text, summarise briefly, sort or tag a list, sketch an outline, answer a simple question.
3. medium: ordinary work with a clear path. When unsure, choose medium.
   Code: a contained feature, or a fix whose cause is known, in one or two files; tests for a given function; a small script; documentation; work that follows a pattern the code already has.
   Office: everyday writing, repurposing content, a meeting summary with decisions and next steps, a report in a fixed format, quick research before a call.
4. high: a hidden mistake would be costly, or the way forward is unclear.
   Code: a bug whose cause is unknown, failing or flaky tests, changes across many files, refactoring, anything touching security, authentication, payments, data migrations, production deploys, concurrency or deleting data, code review, performance work, designing an API or a schema.
   Office: reconciling numbers across sources, open-ended analysis (why did sales drop), reviewing a contract for risk, fact-checking, working through long documents, verifying earlier work.
5. xhigh: a long, hard and critical job handed over to run alone. All three must hold.
   Code: a whole feature or app built end to end, a large migration or rewrite, a multi-step plan carried out unattended, a deep security audit.
   Office: a full research report from many sources, a long agreement reviewed before signing, an investor deck that has to be right the first time.
6. max: only when the prompt itself asks for the deepest, most careful work possible and says it is critical. Otherwise xhigh.

Keep in mind:
- Length is not difficulty. Long work that only follows rules stays low or medium.
- A short prompt can hide a lot of work ("fix the login", "почини авторизацию"). Judge what the work needs, not how many words ask for it. Claude's last reply gives the context.
- The prompt can be in any language.

The chat runs at: {{NOW}}

Claude's last reply, cut short:
<reply>
{{REPLY}}
</reply>

The prompt:
<prompt>
{{PROMPT}}
</prompt>

Answer with JSON only: {"level": "low|medium|high|xhigh|max|keep", "why": "the reason in at most 12 plain words, in the language of the prompt"}`
// TEMPLATE-END

/** The model prompt for one pick. The person's text is spliced in, never read as a pattern. */
export function buildPrompt(i: { prompt: string; lastReply: string; now: Level | '' }): string {
  const fill = (s: string, ph: string, v: string) => s.split(ph).join(v)
  // The person's text goes in last, so a placeholder written in it stays as written.
  let out = fill(TEMPLATE, '{{NOW}}', i.now || 'unknown')
  const [head, tail] = out.split('{{REPLY}}') as [string, string]
  const [mid, end] = tail.split('{{PROMPT}}') as [string, string]
  out = head + (i.lastReply.slice(0, 600) || '(none, this is the first prompt)') + mid + i.prompt.slice(0, 4000) + end
  return out
}

function cleanWhy(raw: string): string {
  return raw
    .replace(/\s*[—–]\s*/g, ', ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 90)
}

/** The first JSON object of the model's answer as a pick; null when there is none or its level is unknown. */
export function parseAnswer(text: string): Pick | null {
  const m = /\{[\s\S]*?\}/.exec(text)
  if (!m) return null
  let j: { level?: unknown; why?: unknown }
  try {
    j = JSON.parse(m[0]) as typeof j
  } catch {
    return null
  }
  const why = typeof j.why === 'string' ? cleanWhy(j.why) : ''
  if (typeof j.level === 'string' && j.level.trim().toLowerCase() === 'keep') return { level: 'keep', why }
  const level = toLevel(j.level)
  return level ? { level, why } : null
}
