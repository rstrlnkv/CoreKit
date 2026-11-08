// The classifier: the model prompt that picks an effort level, and the parser of its answer.
// No calls on `$` here, so the rules can change without touching the hooks.
import type { Level } from '../types'
import { type ModelKey, toModel } from './models'

export type Pick = { level: Level | 'keep'; model: ModelKey | ''; why: string }

/** Weakest to strongest. */
export const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh', 'max']

/** Reads a level in any spelling the model may use ("Extra high", "x-high"); '' for anything else. */
export function toLevel(v: unknown): Level | '' {
  if (typeof v !== 'string') return ''
  const t = v.toLowerCase().replace(/[^a-z]/g, '')
  const level = t === 'extrahigh' ? 'xhigh' : t
  return (LEVELS as readonly string[]).includes(level) ? (level as Level) : ''
}

// quality.sh cuts the text between the marker lines: keep the template one plain literal.
// TEMPLATE-START
export const TEMPLATE = `Pick the effort level and the model for one prompt sent to Claude Code. Claude Code is an agent: it reads files, runs commands and changes code, and it also does office work such as writing, documents and analysis.

These are two separate choices:
- Effort is how much Claude reads, checks and thinks before it acts, and how much it decides on its own. It follows the price of a mistake and how unclear the way forward is. More effort costs time and tokens; too little on hard work means missed bugs and wrong answers.
- The model is how hard the thinking itself is. Haiku is fast and cheap, Sonnet is the everyday model, Opus is stronger, Fable is the strongest and slowest.
A hard question with a short answer can take a strong model at low effort. Careful work along a clear path can take a lighter model at high effort.

First decide if it is keep. Keep means the prompt brings no new work: it only approves, answers a question Claude asked, picks one of the options Claude offered (even a big one: Claude has weighed it already), or says to carry on (yes, ok, go ahead, do it, option 2, да, давай, продолжай, ок). A bare approval is keep even with no last reply. Keep needs something to answer: when Claude only described a finding and asked nothing, a short command such as "fix it" or "почини" is the work it names, not keep. A question the person asks, or a request for work Claude did not propose, is new work and never keep, even on the first prompt of a chat. When new work rides along with the approval ("да, и ещё почини X"), judge that work.

Otherwise walk down the effort ladder and take the first rung that fits:
1. low: quick, conversational or mechanical work that is easy to check at a glance, where a mistake is cheap.
   Code: explain a snippet or an error message, rename something, fix a typo, change one line of config or text, run a command, a git step, a question about a tool or a flag.
   Office: brainstorm, rewrite a passage, translate a short text, summarise briefly, sort or tag a list, sketch an outline, answer a simple question.
2. medium: ordinary work with a clear path. When unsure, choose medium.
   Code: a contained feature, or a fix whose cause is known, in one or two files; tests for a given function; a small script; documentation; work that follows a pattern the code already has.
   Office: everyday writing, repurposing content, a meeting summary with decisions and next steps, a report in a fixed format, quick research before a call.
3. high: a hidden mistake would be costly, or the way forward is unclear.
   Code: a bug whose cause is unknown, failing or flaky tests, a crash log or a stack trace that asks why, changes across many files, refactoring, anything touching security, authentication, payments, data migrations, production deploys, concurrency or deleting data, code review, performance work, designing an API or a schema.
   Office: reconciling numbers across sources, open-ended analysis (why did sales drop), reviewing a contract for risk, fact-checking, working through long documents, verifying earlier work.
4. xhigh: a long, hard and critical job handed over to run alone. All three must hold.
   Code: a whole feature or app built end to end, a large migration or rewrite, a multi-step plan carried out unattended, a deep security audit.
   Office: a full research report from many sources, a long agreement reviewed before signing, an investor deck that has to be right the first time.
5. max: only when the prompt itself asks for the deepest, most careful work possible and says it is critical. Otherwise xhigh.

Then pick the model on its own ladder, stopping at the first match:
- haiku: the answer is known or the work is mechanical: a fact or how-to question, explaining a snippet or an error message, a rename, a typo, a one-line change, a command to run, a short text to write, rewrite or translate.
- sonnet (also when unsure): ordinary building or writing with a clear path, including careful work that follows written steps.
- opus: judgement or diagnosis: an unknown cause, a choice between options with trade-offs (even when the answer is short), design, review, risk, many files, analysis across sources.
- fable: long, critical work handed off to run alone, or the prompt asks for the deepest work and says it is critical.
For keep, name the model the work needs anyway.

Keep in mind:
- Length is not difficulty. Long work that only follows rules stays low or medium.
- A short prompt can hide a lot of work ("fix the login", "почини авторизацию"). Judge what the work needs, not how many words ask for it. Claude's last reply gives the context.
- Asking Claude to think well about a small thing makes it neither critical nor hard: pick the level and the model the small thing needs.
- The prompt can be in any language.

Examples:
- "what does git stash pop do?": low, haiku
- "в каком файле настраивается логгер?": low, haiku
- "add pagination to the users list, the same way the orders list has it": medium, sonnet
- "итоговая сумма в корзине иногда на копейку не сходится": high, opus
- "Kafka or RabbitMQ for our notifications? one paragraph": low, opus
- "выкати релиз на прод по чек-листу из DEPLOY.md": high, sonnet
- "build the whole booking service from the approved spec, work on your own until it is done": xhigh, fable
- last reply "Run the migration now?", prompt "yes": keep

The chat runs at: {{NOW}}

Claude's last reply, cut short:
<reply>
{{REPLY}}
</reply>

The prompt:
<prompt>
{{PROMPT}}
</prompt>

Answer with JSON only, the reason first: {"why": "the deciding reason in at most 12 plain words, in the language of the prompt", "level": "low|medium|high|xhigh|max|keep", "model": "haiku|sonnet|opus|fable"}`
// TEMPLATE-END

const PROMPT_MAX = 4000
const PROMPT_SIDE = 2000

/** A long prompt keeps its head and its tail: the error or the question is often at the end. */
function cutMiddle(text: string): string {
  if (text.length <= PROMPT_MAX) return text
  return `${text.slice(0, PROMPT_SIDE)}\n[…]\n${text.slice(-PROMPT_SIDE)}`
}

/** The model prompt for one pick. The person's text is spliced in, never read as a pattern. */
export function buildPrompt(i: { prompt: string; lastReply: string; now: Level | '' }): string {
  const fill = (s: string, ph: string, v: string) => s.split(ph).join(v)
  // The person's text goes in last, so a placeholder written in it stays as written.
  let out = fill(TEMPLATE, '{{NOW}}', i.now || 'unknown')
  const [head, tail] = out.split('{{REPLY}}') as [string, string]
  const [mid, end] = tail.split('{{PROMPT}}') as [string, string]
  out = head + (i.lastReply.slice(0, 600) || '(none, this is the first prompt)') + mid + cutMiddle(i.prompt) + end
  return out
}

function cleanWhy(raw: string): string {
  return raw
    .replace(/\s*[—–]\s*/g, ', ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 90)
    .trim()
    // The texts add their own punctuation after the reason.
    .replace(/[.。…]+$/, '')
}

/** The first `{…}` of the text that parses as JSON; braces inside a string do not count. */
function firstObject(text: string): { level?: unknown; model?: unknown; why?: unknown } | null {
  for (let from = text.indexOf('{'); from !== -1; from = text.indexOf('{', from + 1)) {
    let depth = 0
    let inString = false
    for (let i = from; i < text.length; i += 1) {
      const c = text[i]!
      if (inString) {
        if (c === '\\') i += 1
        else if (c === '"') inString = false
      } else if (c === '"') inString = true
      else if (c === '{') depth += 1
      else if (c === '}') {
        depth -= 1
        if (depth === 0) {
          try {
            const v = JSON.parse(text.slice(from, i + 1)) as unknown
            if (v && typeof v === 'object') return v as { level?: unknown; model?: unknown; why?: unknown }
          } catch {
            // Not JSON: try the next brace.
          }
          break
        }
      }
    }
  }
  return null
}

/** The first JSON object of the model's answer as a pick; null when there is none or its level is unknown. */
export function parseAnswer(text: string): Pick | null {
  const j = firstObject(text)
  if (!j) return null
  const why = typeof j.why === 'string' ? cleanWhy(j.why) : ''
  // Only a bare model word counts here: a key the ladder names.
  const word = typeof j.model === 'string' ? j.model.trim().toLowerCase() : ''
  const model = word === toModel(word) ? toModel(word) : ''
  if (typeof j.level === 'string' && j.level.trim().toLowerCase() === 'keep') return { level: 'keep', model, why }
  const level = toLevel(j.level)
  return level ? { level, model, why } : null
}
