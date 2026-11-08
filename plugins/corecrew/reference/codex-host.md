# corecrew in Codex

Read this when a corecrew skill runs in Codex: Codex left the skill folder placeholder of the skill's
Paths section as written, and `bash "<scripts>/lib.sh" host` prints `codex`. Everything else in the
skill holds; this file says what is different in Codex. Keep it in mind for the whole skill.

## Skill folder
Codex does not fill in the skill folder. `<skill>` is the directory of the SKILL.md path Codex gave
for this skill (`(file: …/SKILL.md)` in the skills list, or the path of the skill block it loaded; a
path that starts with a root alias such as `r1/` starts with the folder listed under "Skill roots").
Check it before you run anything: `<skill>` must lie inside a
`plugins/cache/<marketplace>/corecrew/<version>/skills/` folder, its text must have no `..` component,
and it must contain no `"`, `$` or backtick. Any marketplace name and any version match; for example
`~/.codex/plugins/cache/corekit/corecrew/0.9.2/skills/task` (the home folder in place of `~`) passes.
If it fails that, ask the user and run nothing. Then go on with the skill's Paths section
(`lib.sh plugin-root`). This file is `<skill>/../../reference/codex-host.md`.

## Settings and skill names
Codex has no options screen. The settings live in the settings file, whose path
`bash "<scripts>/lib.sh" setting-path` prints (`~/.config/corecrew/settings` by default; lines `key: value`, keys
`core_dir`, `attribution`, `model_profile`, `ui_language`, and for the crew `codex_model` and
`codex_model_<role>`). Run the skill's commands as written: a `user_config` placeholder in them
stays literal in Codex, and the scripts treat it as unset and read the settings file.

Codex calls a skill `$corecrew:<skill>`. Where a skill says `/corecrew:<skill>` (to the user, or in a
hint), say `$corecrew:<skill>`. task, ship and new-standard start only when the user names them.

Where a skill tells the user to open or restart Claude Code in a folder (`cd <folder> && claude`),
say instead: open Codex there with `cd "<folder>" && codex --add-dir "<Core>"`. The private
`CLAUDE.md` loads in Codex through the folder's `AGENTS.md` link, also only in a new session.

## Writable folders
Codex writes only inside the folder it was started in and the folders given with `--add-dir`.
corecrew writes into the Core, and new-project also into `<Projects>` (the folder that holds the
Core: the new code folder goes there). Right after `<Core>` is resolved run
`bash "<scripts>/lib.sh" core-writable "<Core>"`; new-project checks `"<Projects>"` instead, since the
Core may not exist yet. Exit 0: go on. Exit 1: tell the user in plain words that Codex cannot write
there, and that they must restart Codex from the same folder with `codex --add-dir "<Core>"`
(new-project: `codex --add-dir "<Projects>"`); then stop. The probe file is removed at once. A
`<Projects>` folder that does not exist yet: ask the user to create it, then restart the same way.

## Approval outside the sandbox
The Codex sandbox keeps `.git` read-only and has no network. Run these as commands that ask for
approval to leave the sandbox (escalated permissions), and let the user approve each:
- anything that writes to git: `save`, `undo-step`, `setup-core.sh`, `scaffold.sh`,
  `install-hooks.sh`, `adopt.sh`, and `git init`, `add`,
  `commit`, `merge`, `tag` or `fetch . <branch>:<branch>`;
- anything that needs the network: `gh` (preflight's `gh auth status` too), `git push`,
  `git fetch`, package installs and project generators (`npm create`, `npm install`,
  `flutter create`, `uv add`, ...).

Approval applies to one step. When it is not possible (a non-interactive `codex exec`), only the step
that needs it stops: do every other step that does not need its result as usual; report the stopped
step, and any step that needed its result, as not done and why. In
`task` that is the commit: the chain runs to the end, the files stay uncommitted, and the report says
`Commit: stopped — Codex sandbox keeps .git read-only`. Never look for a way around the sandbox.
`save` printing `save: git could not write ...` means it ran inside the sandbox: run it again with
approval.

## Questions
Codex has no AskUserQuestion tool. Ask in plain chat instead: at most three questions in one message,
each with numbered options, the recommended one marked, and a note that the user may answer in their
own words. Then end your turn and wait for the answer. If Codex offers a `request_user_input` tool,
you may use it the same way.

## Subagents
Codex has no Agent tool. A subagent is started with `spawn_agent`, and it must start clean: it gets
none of this conversation, so its message holds the whole brief. Codex has two tool sets; use the
one you have:
- multi-agent v1 (Codex's default; `spawn_agent` takes `fork_context`, and there are `send_input`,
  `wait_agent` and `close_agent`): pass `fork_context: false` and `message`, plus `model` and
  `reasoning_effort` when the skill gives them. A nudge is `send_input`. Call `close_agent` once
  its final answer is in.
- multi-agent v2 (`spawn_agent` takes `task_name`, and there are `followup_task` and `wait_agent`):
  pass `task_name` (the name the skill gives, else a short one such as `research`),
  `fork_turns: "none"` and `message`, plus `model` and `reasoning_effort` when given. A nudge is
  `followup_task`.

Then call `wait_agent` until the final answer arrives; on a timeout, wait again (`timeout_ms` up to
3600000). Several subagents at once: spawn them all, then wait for all of them. Never go on while a
subagent whose answer you need still runs.

No `spawn_agent` tool at all: say in plain words that this step needs Codex subagents, which this
session does not offer (the Codex feature `multi_agent` controls them; check that it is on in
`codex features list`, then start a new session). A step whose skill names a fallback for a failed
subagent (a research step) uses that fallback; any other step stops there. Do not do a crew role's
work yourself instead.
