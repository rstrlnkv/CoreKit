---
title: CoreKit seamlessness review (2026-11-05)
description: Where corecrew shows up, how loud it is, and what a new user meets first. Measured in a sandbox, not in a live Claude Code session.
status: done
updated: 2026-11-05
---

# Seamlessness review

Lens: the product should appear only where it is needed, and say one useful thing when it does.

## Where it appears

| Place | Behaviour | Verdict |
|---|---|---|
| Any folder that is not a Core project | Every hook exits at once (guard-secrets 33 ms, guard-code 19 ms, one-suite 32 ms, measured). Session-start prints nothing once the Core is set up. | Good: invisible. |
| First session on a machine, Core not set up | One person-facing line (systemMessage since this run), once. | Fixed this run; before, the model alone saw it and the marker recorded it as shown. |
| Inside a Core project | Session-start prints 5 short lines (project, docs index, save/undo, standards) plus the owner's `session-rules.md`. Guards stay silent unless they block. | Good. Re-emitted on `clear` and `compact` by design. |
| `task`, `new-standard` | `disable-model-invocation: true`: they run only when typed. | Good: never fire by themselves. |
| `new-project` | Fires on phrases like "новый проект" / "start a new app". | Fine; no negative cases are evaluated (see E1). |

## Noise and friction

| ID | Finding | Decision |
|---|---|---|
| U1 | First session in a new-layout project asks to restart ("linked CLAUDE.local.md; restart the session to load it"). This is the only moment the product asks the person to act. Claude Code reads `CLAUDE.local.md` at session start, so the hook cannot avoid it. | Keep; the line is correct and appears once per project. Re-check wording in a live session. |
| U2 | `one-suite` can hold a re-run of a test for up to the 10 s grace after the previous one started (see findings C5). | Low; left as is, documented. |
| U3 | Bash guards block the direct reads and, since this run, `bash -c`/`sh -c`/`eval` strings; they cannot see `python -c`, `node -e`, `find -exec`, `git show REV:.env`, `dd`, `curl @file`. The block message says what to do instead. | The limit is named in the hook header; say it in the README too (done below). |
| U4 | Block messages: secrets and code guards name the path and what to do instead; one-suite says "run the same command again". | Good: one or two plain sentences each. |

## Context cost

SKILL.md files 6–11 KB (loaded only when the skill runs), each agent 3–4 KB, references loaded on demand, the skills' descriptions 170–429 characters in the always-loaded listing. Nothing to cut.

## Evals

| ID | Finding | Decision |
|---|---|---|
| E1 | `evals/evals.json` has two positive `new-project` cases in the skill-creator format. `claude plugin eval` does not read that format, and there are no "should not trigger" cases and none for `task`, `new-standard` or `second-opinion`. | Not done: converting needs real model calls (cost) and a live Claude Code; listed for the owner. A first step is one `evals/new-project-trigger/` case with `prompt.md` and `graders/`. |
