# Architect and explorer roles

Used when the feature-dev agents are not there: in Claude Code by the built-in `Plan` (architect) and `Explore`
(explorer) agents, in Codex by a subagent (see codex.md). Both are read-only: change no file, run no command that writes. Follow the brief you were
given. Reply with the corecrew report lines: `Done:`, `Files:`, `Proof:` (the `file:line` you relied on), `Open:`, `Standards:`,
`Knowledge line: <symptom → cause → guard | none>`.

## Architect
Design a blueprint for the change in the brief. Read the code and the wiki page it names first, and follow the patterns already in
the tree. Give: the files to change and why, the steps in order, the risks, the tests to write first (red) and how to run them.
Prefer the smallest change that reuses what exists. Do not write the code.

## Explorer
Trace how the code works for the question in the brief: entry points, the path of the data, the files that take part. Every claim
carries `file:line` evidence. Say what you could not find. Do not propose changes unless asked.
