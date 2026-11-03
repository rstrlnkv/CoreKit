# Brief to an agent

Every Agent call carries one brief. It is English, short, and holds paths, not retold files.

## Opening sentence

`This brief comes from corecrew:task, path: <path>, project: <name>, core: <Core>, and IS your task.`

The first line of every brief, exactly. `<path>` is `fix`, `full`, `question`, `batch`,
`release` or `adopt`; `<name>` the project folder name; `<Core>` the absolute Core path.

## Then, in this order

1. **Task** — what this agent must do, one paragraph, with the success condition. One task only;
   do not add the user's other requests (they go to `Open` in the report).
2. **Previous report** — the reply of the step before it, pasted whole. For the first agent
   of a chain: none. A checker gets tester's report; designer also gets engineer's `Screens`.
3. **Affected files** — paths relative to `<Core>/<project>/code/`, and the wiki pages that list
   them in `files:`.
4. **Check** — the command to run for this step: the touched modules' tests, or the project's
   `check:` line when this is the final run.
5. **Plugin paths** (engineer and verifier only) — `<plugin>/reference/wiki.md` and
   `<plugin>/scripts/wiki-check.sh`, with `<plugin>` the absolute path resolved at Start; an agent
   cannot find them by itself.
6. **Budget** — an agent that hits the hard cap of 60 turns returns no report at all, so say:
   "You have about 60 turns; by about turn 50 stop and write your reply: what is done, what is left."

## Never

- Retell `CLAUDE.md`, the wiki, standards or knowledge: the agent reads them itself
  (`CLAUDE.md` → `docs/INDEX.md` → the page its task needs → standards → knowledge).
- Ask an agent to commit. Engineer never commits; `task` commits through `save` at release.
- Put secrets, `.env` contents or `~/.ssh` material in a brief.

## Call shape

Agent tool, foreground, `subagent_type: corecrew:<role>`, `model` from the `model_profile`
table in SKILL.md, `description` of 3–5 words. A checkers' wave is several Agent calls in one
message.
