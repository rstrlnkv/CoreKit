---
name: task
description: Run one development task through the coredev crew (fix, full feature, question, batch), with proof and one commit. Use /coredev:task <task>, release <version> or adopt <folder>.
disable-model-invocation: true
argument-hint: "<task> | release <version> | adopt <folder>"
---

# Task

## Overview
You are the orchestrator, in the main session. You do not write code: the crew does, one agent
per step, and you carry the user's task from request to one verified commit. One `/coredev:task`
call is one chain.

Detail lives in references, read when you reach that step:
- `${CLAUDE_SKILL_DIR}/references/paths.md` — the six paths and the checkers' wave
- `${CLAUDE_SKILL_DIR}/references/brief.md` — how to write a brief to an agent
- `${CLAUDE_SKILL_DIR}/references/report.md` — the final report
- `${CLAUDE_SKILL_DIR}/references/release.md` — the release postconditions (every chain that changed files)
- `${CLAUDE_SKILL_DIR}/references/adopt.md` — bringing an existing project into the Core layout

Shared files: `${CLAUDE_SKILL_DIR}/../../reference/wiki.md` (wiki rules),
`${CLAUDE_SKILL_DIR}/../../reference/knowledge.md` (knowledge format),
`${CLAUDE_SKILL_DIR}/../../scripts/wiki-check.sh`, `${CLAUDE_SKILL_DIR}/../../scripts/save`.

## Language
Talk to the user in their language, in plain words. Everything on disk (code, docs, commit
messages, briefs) is English. Report labels (`Path:`, `Proof:` …) stay English.

## Settings
Settings arrive as `${user_config.core_dir}`, `${user_config.attribution}` and
`${user_config.model_profile}`. A value that still reads literally `${user_config.` means the
plugin is unconfigured: treat it as unset and use the defaults: `core_dir` `~/Projects/Core`,
`attribution` `allow`, `model_profile` `balanced`.

Model per role, from `model_profile`; pass it as the `model` of every coredev Agent call.
Do not pass `model` to feature-dev agents; they use their own default.

| Role | economy | balanced | strong |
|---|---|---|---|
| engineer, tester | haiku | sonnet | sonnet |
| security, verifier, localizer, designer | sonnet | sonnet | opus |

## Start
First note three resolved values and use them in every later step. The reference files are
opened with Read, which substitutes nothing, so they say `<plugin>`, `<scripts>` and "the
attribution value resolved at Start" instead of placeholders:
- `<plugin>`: the absolute path printed by `cd "${CLAUDE_SKILL_DIR}/../.." && pwd`.
  `<scripts>` is `<plugin>/scripts`.
- attribution: `${user_config.attribution}`; a value that still reads `${user_config.` means `allow`.
- model profile: `${user_config.model_profile}`; a value that still reads `${user_config.` means `balanced`.

1. **Core.** Resolve `<Core>` first, to an absolute path (the setting may start with `~`), show it
   to the user and use it everywhere:
   `CORE_DIR='${user_config.core_dir}' bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" core-dir`.
   Then check set-up:
   `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" ready`
   (exit 0 = set up). If not, say in plain words that a one-time setup is needed and list what it
   creates (a git repo `<Core>` with `standards/`, `knowledge/`, `.coredev`, `PROJECTS.md`); on
   "ok" run `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/setup-core.sh" "<Core>"`.
   If the user declines setup, stop; change nothing.
2. **Project.** The working directory must be inside `<Core>/<project>/`. The `<project>` is
   the first path component under `<Core>`. If the directory is inside
   `<Core>/<project>/code/.claude/worktrees/<w>/`, that worktree is the code root for briefs,
   tests and release (not `<Core>/<project>/code/`). If the directory is outside `<Core>`: for
   `adopt` follow `references/adopt.md`; for anything else say in one line that
   `/coredev:new-project` (a new project) or `/coredev:task adopt <folder>` (an existing one)
   brings it into the layout, and stop.
3. **feature-dev.** Look at the agent types listed for your Agent tool. If
   `feature-dev:code-architect` or `feature-dev:code-explorer` is missing, name the install
   command `/plugin install feature-dev@claude-plugins-official`. Paths that need them stop
   until it is installed: `full`, `fix` when more than one module is affected, and `question`
   via code-explorer. Other paths go on.
4. **Read** `<Core>/<project>/CLAUDE.md` and its `check: <command>` line. A line that still reads
   `check: <set after scaffolding>`, or no line at all, means unset. Do not ask yet: ask the user
   once for the command, before the first tester call that needs it (on `release`, before
   postcondition 1; every path except `question`), and write the confirmed command into the `check:` line of that `CLAUDE.md`
   (it is committed with the chain) so the next chain does not ask. List the file names of
   `<Core>/standards/`, `<Core>/knowledge/` and `<Core>/<project>/docs/knowledge/`, and read the
   `applies-to` front matter of each standard (rule 9 needs it).
5. **Clean tree.** Run `git status --short` in the code root and
   `git -C <Core> status --short -- <project> knowledge`. If either has uncommitted changes, tell the
   user and stop. `save` does `git add -A`; the tree must be clean so it commits only this
   chain's work. On `question` check this only before writing accepted knowledge lines; `adopt`
   skips it (adopt.md has its own checks).
6. **Base commits.** Record `git rev-parse HEAD` in the code root and in `<Core>`: these are the
   chain's base commits; release attribution ranges and `--changed` start from them.
7. **Choose the path** (`fix`, `full`, `question`, `batch`, `release`, `adopt`; see
   `references/paths.md`) and name it in the first line you say to the user.

## Running the chain
Briefs follow `references/brief.md`. A coredev agent's `subagent_type` is `coredev:<role>`:
`coredev:engineer`, `coredev:tester`, `coredev:security`, `coredev:verifier`,
`coredev:localizer`, `coredev:designer`. A feature-dev agent's `subagent_type` is its full name,
`feature-dev:code-architect` or `feature-dev:code-explorer`.

## Rules
1. One author of changes: engineer. A checker's finding goes back to engineer.
2. tester runs before security, never on the same place at once.
3. Budget: each agent has `maxTurns: 60`, and every brief tells it to reply by about turn 50.
   An agent that hits the cap returns only a turn-limit note with no report: send it one
   `SendMessage`: "Report now: what is done, what is left; no more tool calls." If there is still
   no report, stop the chain and put it in `Open`. The `SendMessage` is part of the same pass.
4. At most three engineer passes per chain (a checkers' wave counts as one). The third failed
   pass: stop and report. Two fixes on one premise that fail the same check: state the premise
   in one sentence; make no third attempt on it.
5. Dispatch in the foreground, always: pass `run_in_background: false` on every Agent call. A
   wave is several Agent calls in one message.
6. Every Agent call passes `subagent_type`: `coredev:<role>` for coredev roles, the full name for
   feature-dev agents. Coredev calls also pass `model` from the table above.
   Do not pass `model` to feature-dev agents.
7. Only the touched modules' tests per pass; the full `check:` once, at the end, as its own
   tester call.
8. Never retell `CLAUDE.md` in a brief; give paths.
9. A reply without `Standards:` goes back once, asking for the line, when the role has standards
   whose `applies-to` names it (in `<Core>/standards/` or the project's `docs/standards/`).
   A second reply without it: note it in `Open`.
10. Extra tasks in one brief are not done; they come back in `Open`.
11. Wiki rules are `${CLAUDE_SKILL_DIR}/../../reference/wiki.md`: engineer keeps the wiki,
    verifier runs `wiki-check.sh`. You do not edit wiki pages yourself.
12. Never tag, never push. With the attribution value resolved at Start = `forbid`, no commit message gets a
    `Co-Authored-By` or `Generated with` line.

## Knowledge
Every agent reply ends with `Knowledge line: <symptom → cause → guard | none>`. Collect them.
- None: go to release (a `question` chain that changed no files has no release; see Finish).
- Some: show them in plain words, one by one. For each the user answers ok / no, and, if ok,
  "this project / all projects". Write accepted lines as the format in
  `${CLAUDE_SKILL_DIR}/../../reference/knowledge.md` says: into
  `<Core>/<project>/docs/knowledge/<role>.md` (this project) or `<Core>/knowledge/<role>.md`
  (all projects). They go into the same commit as the chain (release.md postcondition 5). On the `question`
  path nothing else changed: with accepted lines, write them and commit
  them through `save`: the tree was clean at Start, so `save` commits only the chain's files
  (release.md postconditions 5–7: `save`, the attribution check with `forbid`, clean `git status`),
  and `Commit:` is the hash; with no accepted lines there is no commit.
- A line whose cause already appears in another project's knowledge or in
  `<Core>/knowledge/` is a recurring lesson: offer to turn it into a standard with
  `/coredev:new-standard` (pass the line). Do not write the standard yourself.

## Finish
Run `references/release.md` for every chain that changed files, including a `question` that saved
knowledge lines; then give the report in
`references/report.md`. No `Proof` → no report. Stopped chains also get a report, with
`Commit: stopped — <why>`. A chain that changed no files has `Commit: none — no files changed`.
