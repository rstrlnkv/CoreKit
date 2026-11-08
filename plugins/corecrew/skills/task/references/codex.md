# Running the chain in Codex

In Codex (`bash "<scripts>/lib.sh" host` prints `codex`) follow `<plugin>/reference/codex-host.md` (writable
folders, approval outside the sandbox, questions, subagents) and this file instead of the Agent-tool parts of
SKILL.md. Everything else in SKILL.md, paths.md, brief.md and release.md holds. `<plugin>` and `<scripts>` are
resolved under Paths.

## Core access
In Start, **Core**: right after `<Core>` is resolved, check it as codex-host.md, section Writable folders, says
(`lib.sh core-writable "<Core>"`). Exit 1: the restart message, then stop.

## One crew step
Each step is one subagent, started as codex-host.md, section Subagents, says (fresh, no forked context):
- its name (where the tool takes one): `<role>_<n>` (`engineer_1`, `tester_2`; n counts the calls of that role in
  this chain);
- `model` and `reasoning_effort`: the words of `bash "<scripts>/lib.sh" role-model codex <model_profile> <role>`
  (`model_profile` as resolved at Start): the first is `model`, a second one `reasoning_effort`. Pass only what it
  prints; an empty line means pass neither (the subagent gets Codex's own default). The user picks their own models
  with `codex_model: <model> [<effort>]` (every role) or `codex_model_<role>: <model> [<effort>] | inherit` in the
  settings file (`lib.sh setting-path`); a line on stderr names a value that was skipped: tell the user;
- the message starts with "Read <plugin>/agents/<role>.md and act as that role; ignore its front matter." and then the
  brief (`references/brief.md`), with `<plugin>` filled in as an absolute path.

Then wait for its final answer. A wave (the checkers, paths.md) is several subagents started in one go, then one
wait for all of them. Dispatch is always waited for; never go on with a step still running. No `spawn_agent` tool:
stop the chain as codex-host.md says, with `Commit: stopped — no Codex subagents in this session`.

## No turn cap
Codex agents have no `maxTurns`. An agent that stops with no report gets one nudge (codex-host.md, Subagents): "Report
now: what is done, what is left; no more tool calls." and a wait. Still no report: stop the chain and put it in `Open`
(SKILL.md rule 3).

## Architect and explorer
`feature-dev` does not exist in Codex. A step that would use `feature-dev:code-architect` or
`feature-dev:code-explorer` is a subagent (role name `architect` or `explorer`, model from `role-model codex`) whose
message is "Read <skill>/references/codex-roles.md, section Architect (or Explorer), and act as it." followed by the brief.

## Read-only steps are checked, not enforced
A Codex subagent cannot be made read-only. Around each read-only step (security, verifier, localizer, designer, architect, explorer):
1. before the step record `bash "<scripts>/lib.sh" tree-state "<code root>"` and the same for `"<Core>"`;
2. after the answer arrives, run both again and compare. Ignored files are not covered.
3. A line that differs: stop the chain. Show `git status --short` of that tree, revert nothing, and put it in `Open` with the
   role and step. Exit 0 before and exit 1 after (or the reverse) is a change too: stop. Skip the tree only when both runs
   exit 1 (not a work tree).
Read-only steps keep the parent session's permissions, so the check is all there is; start Codex with the profile that
`bash "<scripts>/lib.sh" codex-profile` prints to keep secret files closed.
In a wave, compare once after all have answered.

## Commit in Codex
`save` writes to `.git`, which the sandbox keeps read-only: run it with approval to leave the sandbox (codex-host.md,
section Approval outside the sandbox). If approval is not possible, or `save` still prints `save: git could not write ...`,
report `Commit: stopped — Codex sandbox keeps .git read-only` with the files left uncommitted.
