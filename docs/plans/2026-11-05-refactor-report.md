---
title: CoreKit refactor — report (2026-11-05)
description: What the unattended run did, what was verified and how, what was not, and what needs the owner.
status: done
updated: 2026-11-05
---

# Report

## Morning summary

- **State:** green. `bash tests/run.sh` ALL TESTS PASSED, `claude plugin validate .` passes (warnings: no icon, root CLAUDE.md), `claude plugin test plugins/coremodel` 157/157. Branch `claude/corekit-refactor-468d43`; nothing merged into `main`, nothing pushed.
- **Needs your "ок":** merge and push. The branch holds `main` d0882e7, the four fix branches of the CoreModel testing session (merged locally in the order base, race-fixes, pane-button, coreopinion, corecrew-guards-docs, no conflicts) and 6 commits of this run. Versions: corecrew 0.5.2, coremodel 0.4.4, coreopinion 0.2.0.
- **Needs your hands (a live Claude Code):** see "Not verified".

## What was done

| Phase | Result |
|---|---|
| G gate | The five sessions were idle and clean; branches merged locally. |
| 0 baseline | Measured, equal to the handoff's numbers. Versions and CHANGELOG heads agree. |
| 1 inventory | Folded into `2026-11-05-findings.md` (every promise of hooks, guards, references, scripts checked against a run or a test; script callers and stale names grepped). A separate table was not worth its size. |
| 2 docs | `2026-11-05-docs-gaps.md`: manifests, skills, agents, hooks verified against the current docs; 3 gaps fixed, the rest decided. |
| 3–4 audit | Adversarial batteries on both guards and timing of every hook in a sandbox. Found: nested-shell bypass (fixed), unseen interpreters (named, not closable), one-suite re-run stall (low, left), hint shown to the model only (fixed). |
| 5 seamlessness | `2026-11-05-ux-findings.md`: invisible outside a project, silent in one, one restart on the first session of a project. |
| 6 fix and clean | 2 fixes with tests first, README (requirements, what the hooks do and their limit), banners on four finished plans, release 0.5.2. |
| 7 final | Tests and validate green; clean install in a fresh `HOME`: marketplace add, install of all three plugins (versions 0.5.2, 0.4.4, 0.2.0 read), uninstall of corecrew. |

Commits of this run (no `Co-Authored-By`, owner's rule): the plan, the hint fix, the lexer fix, the test correction, the release.

## Not verified (needs a live Mac session)

- That the `systemMessage` hint appears in the terminal and the desktop app.
- The first-session restart line, the Stop hook's `stop_hook_active`, and the hooks inside real subagents.
- The coremodel footer button and pane (handoff), CoreOpinion against real Codex (handoff).
- `claude plugin eval`: not run (real model calls); `evals/` is not in its format.
- Stack generators (Flutter, XcodeGen, Tauri, Vite) were never run for real.

## Open for you

1. `~/.claude/settings.json`: `models: "hauki, sonnet, opus"` is a typo; Haiku is never picked.
2. Add the pane-button line to the coremodel 0.4.4 CHANGELOG entry; add the version line to the two plugin READMEs (findings P1, P5).
3. Decide on `tests/fixtures/wiki-*/CLAUDE.md` (9 files the hooks block after adopt) before adopting CoreKit itself.
4. Optional: an icon (`.claude-plugin/icon.png`) before any directory submission; trigger evals in the `claude plugin eval` format.
