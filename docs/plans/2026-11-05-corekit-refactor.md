---
title: CoreKit refactor — run plan for an unattended session
description: Ordered plan to audit and clean corecrew and the shared docs while the owner is away; what to touch, what to leave to the parallel plugin session, stop rules, and the report.
status: approved — starts when phase G opens (all four sub-sessions finished)
updated: 2026-11-05
---

# CoreKit refactor — run plan

Goal: everything declared works, nothing stale remains, and the product is seamless — it shows
up only where needed (fewest questions, shortest messages, no noise). This plan is the
acceptance lens for every phase: *would a new user notice this, and is the notice useful?*

## Ground rules (unattended run)

- Work only on this branch (`claude/corekit-refactor-468d43`). Never commit to `main`.
- **No merge, no push, no `gh` writes.** The owner says "ок" when back.
- One commit per working step; commit messages in English, **no `Co-Authored-By` line** (owner's rule).
- TDD (CLAUDE.md): a failing test first, watch it fail, then the code. A bug fix starts with a test that reproduces it.
- Portable bash (3.2), no `jq`, no `sed -i`; `tests/test_portability.sh` must stay green.
- Never delete user files in scripts. Repo cleanup is fine; history keeps everything.
- After every change: `bash tests/run.sh` and `claude plugin validate .`. A red result stops the phase.
- Never read `.env` files or `~/.ssh`.

## Scope split with the parallel session

The owner runs a parallel session that checks the plugins live.

| Owner of the code | Paths |
|---|---|
| **This session** | `skills/`, `agents/`, `hooks/`, `scripts/`, `reference/`, `tests/` (except coremodel/coreopinion tests), `evals/`, root `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `docs/` |
| **Parallel session** | `plugins/coremodel/`, `plugins/coreopinion/` and their tests |

This session does **not edit** the plugin paths. Anything found there goes to
`docs/plans/2026-11-05-findings-plugins.md` (one line each: file, symptom, evidence), for the
parallel session to pick up. If both sessions need `CLAUDE.md` or the root `README.md`, this
session edits them last (phase 6) after rebasing.

## Phase G — Start gate (do nothing until it opens)

The plan starts only after the four sub-sessions of "CoreModel плагин проверка" have finished.
Their work touches the same files (`corecrew-fixes` edits guards and docs, which are in this
session's scope), so starting earlier would collide.

| Sub-session (name) | Branch |
|---|---|
| coreopinion-fixes | `claude/coreopinion-send-scope-97d906` |
| coremodel-pane | `claude/coremodel-pane-button-024083` |
| coremodel-fixes | `claude/coremodel-race-fixes-bc43c2` |
| corecrew-fixes | `claude/corecrew-guards-docs-559407` |

Gate check (every ~30 minutes, with `list_sessions`): all four have `isRunning: false`, and the
parent "CoreModel плагин проверка" is not running a turn either. Do not start while any of them runs.

When the gate opens, pick the base:

1. If the four branches are already merged into `main` (`git branch --merged main`) → base is `main`.
2. If not (the owner has not said "ок" to merge yet) → do **not** touch `main`. Merge the four branches
   into this refactor branch only, locally, one at a time, in the order above, and note it in the
   report. A merge conflict is a stop rule: report it and wait for the owner.

Handoff received from the parent session (2026-11-05, nothing merged or pushed by it): the four
branches are cut from `claude/coremodel-plugin-testing-46ad1d` (= `origin/main` d0882e7 plus 4
unpushed CoreModel 0.4.3 commits), so in case 2 the merge order is **that base first, then
race-fixes, pane-button, coreopinion-send-scope, corecrew-guards-docs**. The parent reports the
combined tree as green: `claude plugin test plugins/coremodel` 157/157, `bash tests/run.sh` all
passed, `claude plugin validate .` passes (warnings: root CLAUDE.md, no icon); versions corecrew
0.5.1, coremodel 0.4.4, coreopinion 0.2.0. Phase 0 re-measures this instead of trusting it; any
difference is a finding. Known and left for the owner, not for this plan: the pane-button branch
has no CHANGELOG line (belongs in the coremodel 0.4.4 entry; the plugin path is out of this
session's scope), and the footer button and the pane were not checked in the live app.

If a sub-session ends with uncommitted changes or a failing test run in its worktree, do not "fix"
it: write it into the report and base the work on the commits only.

## Phase 0 — Baseline (read-only)

1. Bring the branch to the base chosen in phase G (`main` is also ahead by the coremodel 0.4.2 fixes). Use the app's sync-with-base-branch tool for `main`; resolve conflicts if any.
2. `bash tests/run.sh`, `claude plugin validate .`, record the result as the baseline.
3. Check version consistency: `.claude-plugin/plugin.json`, `marketplace.json`, both plugins' manifests, the top CHANGELOG entries, README mentions.
4. Note the minimum Claude Code version each component needs.

Stop rule: a red baseline is reported and fixed first, in its own commit, before anything else.

## Phase 1 — Inventory: declared → verified

Build `docs/plans/2026-11-05-inventory.md`: a table of every promise (skills, agents, hooks, scripts,
manifests) with its source (spec section, README line, `description`) and what verifies it
(test file, live run, nothing). "Nothing" rows are the work list for phases 3–4.
Sources: `docs/specs/2026-11-03-coredev-design.md`, `2026-11-02-new-project-design.md`,
`2026-11-04-project-layout-design.md`, README, plugin descriptions.

## Phase 2 — Check against Anthropic's documentation

Fetch the current docs for plugins, marketplaces, skills, subagents, hooks, `userConfig`.
Compare with: manifest fields, skill/agent frontmatter, `description` wording (it drives
triggering), hook events, output format, exit codes, timeouts, `${CLAUDE_PLUGIN_ROOT}` use,
progressive disclosure (SKILL.md size vs `references/`). Record each gap as: what the docs say,
what we do, severity. Also check for newer features worth using (`claude plugin eval`, new hook
events). Output: `docs/plans/2026-11-05-docs-gaps.md`. No code changes yet.

## Phase 3 — Functional audit

*Behaviour.* In a throwaway sandbox (`new_sandbox`, scratchpad; never the real `~/Projects/Core`):

- `new-project`: scaffold, layout, `CLAUDE.local.md` link, idempotent re-run (`created` / `skipped`).
- `task`: paths full, fix, adopt, release (`references/*.md` match what the scripts do).
- `new-standard` and `check-standard.sh`; `wiki-check.sh`.
- All five hooks with realistic JSON on stdin: session-start, one-suite, guard-code, guard-secrets, stop-remind. Check output shape, exit code, time per call.
- Agents: each description matches the tools it has (read-only agents really have no Edit/Write).

*Functions.* Every function in `scripts/lib.sh` and each script: callers, untested branches, dead
code. Tokenizer `bash-lex.awk` and `bashlex-*.awk`: feed hostile commands (quotes, heredocs,
`$()`, backticks, env prefixes, `sudo`, chains).

Output: add a "result" column to the inventory; every mismatch becomes a numbered finding.

## Phase 4 — Weak spots

- Environment: paths with spaces, no `git`, no `gh`, offline, fresh `HOME`, Linux utilities where practical.
- Guards: bypasses of guard-code and guard-secrets, false positives, and whether a blocked person is told why and how to proceed.
- Upgrade: project created by an older version (old layout `<Core>/<name>/code/`), run session-start, `adopt`.
- Public-repo privacy: no personal paths, emails, tokens; `blocked-patterns` catches them.
- Tests: tests that cannot fail (assert nothing), flaky ones, uncovered branches from phase 3.
- Open items from memory: the 9 `tests/fixtures/wiki-*/CLAUDE.md` that hooks block after adopt (decide: rename to `CLAUDE.md.in` or similar); stack generators never run for real (document the status honestly instead of implying they were run).

## Phase 5 — Seamlessness review

Measure and judge, with numbers where possible:

- First run: steps from install to a working result; number of questions in the `new-project` interview and which can be defaulted or derived.
- Noise: characters injected into context by each hook per session and per tool call; frequency of blocks.
- Triggering: extend `evals/` to `task`, `new-standard`, and (if cheap) `second-opinion`; both Russian and English phrasings, plus negative cases.
- Context cost: size of each `SKILL.md`, agent file, `reference/` file; move rarely-needed text to `references/`.
- Wording: each message states what happened, why, and what to do next, in one or two plain sentences.

Output: `docs/plans/2026-11-05-ux-findings.md` with proposed fixes ranked by (impact for a new user) / (effort).

## Phase 6 — Fix and clean (TDD, one commit per item)

Order: baseline failures → correctness bugs → guard gaps → docs-gap fixes → UX fixes → cleanup.

Cleanup list to verify before deleting:

- `docs/specs/2026-11-04-effort-picker-design.md` and `docs/plans/2026-11-04-effort-picker.md`, `docs/plans/2026-11-04-coreeffort-interface.md`: superseded by `2026-11-04-coremodel-design.md` / `2026-11-04-coremodel.md`. Delete or mark `status: superseded` with a pointer; check inbound references first (`grep -r`).
- `CLAUDE.md` layout block: coremodel line points to the old spec; fix to `docs/specs/2026-11-04-coremodel-design.md`. Re-check the layout tree against the real tree.
- Dead functions and unused scripts found in phase 3; stale README sentences; duplicated rules between README, CLAUDE.md and specs (keep one source, link elsewhere).

Release rule: if user-visible behaviour changes, bump `version` in `.claude-plugin/plugin.json` and add a
`CHANGELOG.md` entry (`## X.Y.Z — YYYY-MM-DD`, newest first) in the same change.

## Phase 7 — Final check

1. `bash tests/run.sh` and `claude plugin validate .` green.
2. Clean-install rehearsal: fresh `HOME` in the scratchpad, add the local marketplace, install `corecrew`, run session-start, then remove it. Record what worked and what could not be tested.
3. `git log --oneline main..HEAD`, `git status` clean.
4. Final report in `docs/plans/2026-11-05-refactor-report.md`: what changed (commit list), what was verified and how, what was not verified and why, remaining findings (own and plugins'), decisions needed from the owner.

## Stop rules

Stop and write the situation into the report, instead of guessing, when:

- a fix would change the meaning of a spec (not only its wording);
- a deletion is not covered by an obvious replacement;
- a test needs network, a real `~/Projects/Core`, `~/.ssh` or `.env`;
- the same phase fails twice;
- something outside the scope split above must change.

## Morning summary (what the owner reads first)

Top of the final report: three lines — *state* (green or not), *needs your "ок"* (merge, push, any
spec-level decision), *needs your hands* (anything that required the real Mac, e.g. live Claude
Code checks of hooks or plugin install).
