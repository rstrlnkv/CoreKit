# Running the chain in Codex

Run `bash "<scripts>/lib.sh" host`. It prints `claude` or `codex`; `codex` means follow this file instead of the Agent-tool parts
of SKILL.md. Everything else in SKILL.md, paths.md, brief.md and release.md holds. `<plugin>` and `<scripts>` are resolved under Paths.

## Core access (Start, step 1)
Codex writes only inside the working folder and `--add-dir` folders. Right after `<Core>` is resolved run
`bash "<scripts>/lib.sh" core-writable "<Core>"`. Exit 0: go on. Exit 1: tell the user in plain words that Codex cannot write
to `<Core>` and must be restarted with `codex --add-dir "<Core>"`, then stop. The probe file it makes is removed at once.

## One crew step
Each step is one `spawn_agent` call:
- `task_name`: `<role>_<n>` (`engineer_1`, `tester_2`; n counts the calls of that role in this chain);
- `fork_turns`: `"none"` (the agent starts clean; the brief is all it knows);
- `model` and `reasoning_effort`: the two words of `bash "<scripts>/lib.sh" role-model codex <model_profile> <role>`
  (`model_profile` as resolved at Start);
- the message starts with "Read <plugin>/agents/<role>.md and act as that role; ignore its front matter." and then the brief
  (`references/brief.md`), with `<plugin>` filled in as an absolute path.

Then `wait_agent` until the final answer arrives: it returns which agents have updates, and the final answer comes as a message. On a timeout
wait again (`timeout_ms` up to 3600000). A wave (the checkers, paths.md) is several `spawn_agent` calls in one go,
then `wait_agent` for all of them. Dispatch is always waited for; never go on with a step still running.

## No turn cap
Codex agents have no `maxTurns`. An agent that stops with no report gets one `followup_task`: "Report now: what is done, what is
left; no more tool calls." and a `wait_agent`. Still no report: stop the chain and put it in `Open` (SKILL.md rule 3).

## Architect and explorer
`feature-dev` does not exist in Codex, so Start step 3 is skipped. A step that would use `feature-dev:code-architect` or
`feature-dev:code-explorer` is a `spawn_agent` (role name `architect` or `explorer`, model from `role-model codex`) whose message is
"Read <skill>/references/codex-roles.md, section Architect (or Explorer), and act as it." followed by the brief.

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
