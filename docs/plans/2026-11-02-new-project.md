# new-project Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `new-project` Claude Code skill in CoreKit: scripts, templates, references, SKILL.md, tests and evals.

**Architecture:** Deterministic work (folders, templates, git, hooks) lives in bash scripts with bash tests; judgment work (interview, analysis, stack choice) lives in SKILL.md + references. Scripts read `CORE_DIR` (default `~/Projects/Core`) so tests run against a temp folder.

**Tech Stack:** bash 3.2+ (macOS default), git, gh, jq-free JSON parsing (python3 fallback not allowed — use `grep`/`sed`), Markdown.

**Spec:** `docs/specs/2026-11-02-new-project-design.md`

## Global Constraints
- All code, comments, Markdown and commit messages in English.
- Scripts are POSIX-friendly bash, no non-default dependencies on macOS; invoked as `bash scripts/x.sh` in prose.
- Never overwrite an existing file; never delete user files.
- Project name regex: `^[a-z][a-z0-9-]{1,38}[a-z0-9]$`.
- GitHub repos: `Core` (always `--private`) and `<name>` (`--private` unless the user explicitly chose public); every `gh repo create` needs explicit user approval.
- Claude is launched in `Core/<name>/code/`; `code/.claude/settings.local.json` holds the absolute `Core/<name>` path in `permissions.additionalDirectories`.
- Rule `paths:` patterns use the form `code/**/<dir>/**`.
- Commit trailer format: `Step-Id: YYYYMMDD-HHMMSS`.
- Every task ends with a commit in CoreKit.

## Review Focus
1. Name with uppercase, spaces, Cyrillic or leading digit → scaffold refuses with a clear message (Task 1).
2. Re-running scaffold on an existing project → no file changed, exit 0 with "skipped" lines (Task 1).
3. `save` from inside a worktree under `code/.claude/worktrees/` → commits the worktree branch and the project docs, not Core root (Task 3).
4. `save` when only one repo has changes, or none → one commit, or "nothing to save", never an empty commit (Task 3).
5. `gh` missing or not logged in at Core pre-push → push blocked with an explanation (fail closed) (Task 2).

---

### Task 1: Test harness, templates and `scaffold.sh`

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/test_scaffold.sh`
- Create: `skills/new-project/scripts/scaffold.sh`
- Create: `skills/new-project/templates/` — `CLAUDE.md.tmpl`, `docs/INDEX.md.tmpl`, `docs/brief.md.tmpl`, `docs/architecture.md.tmpl`, `docs/decisions/001-stack-and-architecture.md.tmpl`, `rules/tests.md.tmpl`, `code/gitignore-common`, `code/settings.local.json.tmpl`, `code/worktreeinclude`, `core/gitignore`, `core/README.md`, `core/PROJECTS.md`

**Interfaces:**
- Produces: `bash scaffold.sh --name <name> [--dry-run]` → creates `$CORE_DIR/<name>/{CLAUDE.md,docs/...,.claude/rules/tests.md,code/}` and inits `$CORE_DIR` repo if missing; prints `created <path>` / `skipped <path>`; exit 2 on invalid name. Placeholders `{{NAME}}`, `{{PROJECT_DIR}}`, `{{DATE}}` replaced with `sed`.
- Produces: `tests/lib.sh` with `assert_file`, `assert_no_file`, `assert_contains <file> <text>`, `assert_exit <code> <cmd...>`, `new_sandbox` (temp `CORE_DIR`).

- [ ] Step 1: Write `tests/test_scaffold.sh`: valid name creates every file above; every docs page starts with `---` and has `title:`, `description:`, `status:`, `files:`, `related:`, `updated:`; CLAUDE.md contains `../docs/INDEX.md` and no line starting with `@`; `settings.local.json` contains the absolute project path; names `MyApp`, `my app`, `проект`, `1app` → exit 2; second run → only `skipped` lines and identical checksums; `--dry-run` → nothing on disk.
- [ ] Step 2: `bash tests/run.sh` → FAIL (scaffold.sh missing).
- [ ] Step 3: Write templates (English) and `scaffold.sh`.
- [ ] Step 4: `bash tests/run.sh` → PASS.
- [ ] Step 5: Commit `feat: scaffold script and project templates`.

### Task 2: Git hooks and `install-hooks.sh`

**Files:**
- Create: `skills/new-project/hooks/pre-commit-code`, `pre-push-code`, `pre-push-core`, `skills/new-project/scripts/install-hooks.sh`, `tests/test_hooks.sh`

**Interfaces:**
- Consumes: Task 1 sandbox layout.
- Produces: `bash install-hooks.sh <project_dir>` installs code hooks into `<project_dir>/code/.git/hooks/` and `pre-push-core` into `$CORE_DIR/.git/hooks/` (idempotent, `chmod +x`). Blocked patterns (one shared list in `hooks/blocked-patterns`): `(^|/)CLAUDE(\.local)?\.md$`, `^\.claude/`, `^docs/superpowers/`, `(^|/)\.env($|\.)` except `.env.example`, `\.pem$`, `\.key$`.

- [ ] Step 1: Tests: committing `CLAUDE.md`, `.claude/x`, `.env`, `a.pem` in code → rejected with message naming the file; `.env.example` and `src/main.dart` → accepted; push of a commit made with `--no-verify` containing `CLAUDE.md` → pre-push rejects (use a local bare remote); Core pre-push with stub `gh` on PATH printing `false` → rejected, printing `true` → accepted, `gh` absent → rejected.
- [ ] Step 2: Run → FAIL.
- [ ] Step 3: Implement hooks and installer.
- [ ] Step 4: Run → PASS.
- [ ] Step 5: Commit `feat: protective git hooks`.

### Task 3: `save` and `undo-step`

**Files:**
- Create: `skills/new-project/core-bin/save`, `core-bin/undo-step`, `tests/test_save_undo.sh`
- Modify: `scaffold.sh` — copy `core-bin/*` to `$CORE_DIR/bin/` if missing.

**Interfaces:**
- Consumes: `install-hooks.sh` (Task 2).
- Produces: `save "<message>" [--push]` — run anywhere inside `code/` or its worktree; finds code root via `git rev-parse --show-toplevel`, main checkout via `--git-common-dir`, project dir = parent of main checkout; commits code (worktree branch if in a worktree) and `git -C $CORE_DIR add <name>/` with identical message + `Step-Id:` trailer; reinstalls missing hooks; prints `saved code`, `saved docs`, or `nothing to save`. `undo-step [STEP_ID]` — default = latest Step-Id across both repos; `git revert --no-edit` each matching commit; prints which repos were reverted.

- [ ] Step 1: Tests: changes in both → two commits with same Step-Id; only docs changed → one commit; nothing → `nothing to save`, no commit; run from `code/.claude/worktrees/w1` → commit on the worktree branch, Core commit contains only `<name>/`; `undo-step` restores both files and history keeps 4 commits; `undo-step` for a step present in one repo → reverts that repo only; `--push` with local bare remotes pushes both.
- [ ] Step 2: Run → FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run → PASS.
- [ ] Step 5: Commit `feat: save and undo-step commands`.

### Task 4: Stop hook reminder

**Files:**
- Create: `skills/new-project/hooks/stop-remind.sh`, `tests/test_stop_hook.sh`
- Modify: `templates/code/settings.local.json.tmpl` — add `hooks.Stop` calling `bash {{PROJECT_DIR}}/../bin/../.. ` → exact command: `bash "$CORE_DIR_ABS/bin/stop-remind.sh"` (scaffold copies the script to `$CORE_DIR/bin/`).

**Interfaces:**
- Consumes: hook JSON on stdin (`cwd`, `stop_hook_active`).
- Produces: exit 2 + stderr `Uncommitted changes in <repos>. Run save "<message>".` when dirty and `stop_hook_active` is not `true`; else exit 0.

- [ ] Step 1: Tests: dirty code → exit 2 with message; clean → 0; `"stop_hook_active": true` → 0.
- [ ] Step 2: Run → FAIL. Step 3: Implement. Step 4: Run → PASS.
- [ ] Step 5: Verify against https://code.claude.com/docs/en/hooks that Stop input contains `stop_hook_active` and exit 2 feeds stderr to Claude; adjust if not.
- [ ] Step 6: Commit `feat: stop hook reminder`.

### Task 5: `preflight.sh`

**Files:**
- Create: `skills/new-project/scripts/preflight.sh`, `tests/test_preflight.sh`

**Interfaces:**
- Produces: `bash preflight.sh [--name <name>]` → lines `OK|WARN|FAIL <check> <hint>`; checks git, gh, `gh auth status`, ASCII `$HOME` and `$CORE_DIR`; with `--name`: folder free and `gh repo view <name>` not found. Exit 1 if any FAIL.

- [ ] Step 1: Tests with stub `gh`: all OK; missing gh → FAIL; `HOME=/tmp/Роман` → WARN; existing folder → FAIL; stub `gh repo view` success → FAIL.
- [ ] Step 2–4: FAIL → implement → PASS.
- [ ] Step 5: Commit `feat: preflight checks`.

### Task 6: References

**Files:**
- Create: `skills/new-project/references/interview.md`, `analysis.md`, `stacks.md`

**Interfaces:**
- Produces: `stacks.md` table — stack, platforms, when to pick, generator command (non-interactive), build-check command, pitfalls. Stacks: Flutter, SwiftUI (XcodeGen), Tauri, web (Vite), Telegram bot (Python), CLI (Python). `analysis.md` — criteria list, option-card format, research-subagent prompt, approval order.

- [ ] Step 1: Research subagent verifies each generator command and flag against official docs (Flutter `--project-name`/`--org`/`--platforms`, `create-tauri-app` non-interactive flags, XcodeGen `project.yml`, Vite template flag); record URLs.
- [ ] Step 2: Write the three files (each < 200 lines, ToC if > 100).
- [ ] Step 3: Commit `docs: interview, analysis and stack references`.

### Task 7: SKILL.md (RED → GREEN)

**Files:**
- Create: `skills/new-project/SKILL.md`, `evals/evals.json`, `new-project-workspace/iteration-1/...` (not committed)

- [ ] Step 1 (RED): Run 2 scenarios without the skill in cloud `claude -p` subagents ("new Flutter app for 4 platforms", "small Mac menu-bar utility"); record failures (stack picked without analysis, no Core layout, internal files in code repo, no approvals).
- [ ] Step 2 (GREEN): Write SKILL.md (< 500 lines; frontmatter `name: new-project`, description = triggering conditions only, multilingual triggers); flow by `stage:`; links to references and scripts via `bash scripts/...`.
- [ ] Step 3: Rerun scenarios with the skill (CORE_DIR sandbox, `--dry-run` for GitHub); generate eval viewer (`generate_review.py --static`) for the user.
- [ ] Step 4: Fix gaps from user feedback; rerun.
- [ ] Step 5: Commit `feat: new-project SKILL.md`.

### Task 8: Trigger description optimization

- [ ] Step 1: 20 trigger queries (10 should / 10 near-miss, mixed languages) in `evals/trigger-evals.json`; user reviews.
- [ ] Step 2: `python -m scripts.run_loop --eval-set ... --skill-path skills/new-project --model claude-opus-5-5 --max-iterations 5`.
- [ ] Step 3: Apply `best_description`; commit `feat: tuned skill description`.

### Task 9: `install.sh` and end-to-end check

**Files:**
- Create: `install.sh`, update `README.md` (install + Cowork upload note), `tests/test_install.sh`

**Interfaces:**
- Produces: `bash install.sh` copies `skills/*` into `${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/`, replacing only skill folders it owns, prints installed path.

- [ ] Step 1: Test with `CLAUDE_SKILLS_DIR` sandbox → files present, rerun idempotent. Step 2–4: FAIL → implement → PASS.
- [ ] Step 5: End-to-end: `CORE_DIR=<sandbox>` scaffold `test-new-project` (stack: none), install hooks, edit + `save`, `undo-step`, attempt committing CLAUDE.md in code → blocked.
- [ ] Step 6: Write user check instructions (Mac: install, run "новый проект" in a fresh Claude Code session, verify GitHub privacy, build).
- [ ] Step 7: Commit `feat: installer and end-to-end check`.
