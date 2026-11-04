# Project layout (code beside Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A corecrew project's code repo lives in `<Projects>/<Name>` and only its private files in `<Core>/<name>`; every script, hook and skill finds the project that way, and `adopt` stops moving repos.

**Architecture:** One detection rule in `scripts/lib.sh` (`project_of`, `code_dir_of`, `layout_of`) that every hook, `save`/`undo-step`, `install-hooks`, `adopt` and the skills use. The old layout (`<Core>/<name>/code`) keeps working, reported as `old`, so tasks can land one by one with the suite green; `adopt` is the only way out of it. The private `CLAUDE.md` reaches the session through a gitignored `CLAUDE.local.md` symlink that `scaffold`, `adopt` and `session-start` create.

**Tech Stack:** bash 3.2 + BSD utilities, git, Markdown; Claude Code plugin (skills, hooks).

**Spec:** docs/specs/2026-11-04-project-layout-design.md (section numbers below are the spec's). Background: docs/specs/2026-11-03-coredev-design.md.

## Global Constraints

- Portable bash per CLAUDE.md (no `sed -i`, `mapfile`, `${x,,}`, `grep -P`, `declare -A`, `local -n`, no `jq`; temp file + `mv`; quote every path). `tests/test_portability.sh` stays green.
- Never overwrite or delete a user file; idempotent steps print `created` / `skipped`. A symlink is never written over an existing file or a different symlink.
- `<Projects>` = parent folder of `<Core>` (`dirname "$CORE_DIR"`). `<name>` = lower case of `<Name>`; `<name>` matches `valid_project_name` and is not `core`, `standards`, `knowledge`.
- Symlink: `<Projects>/<Name>/CLAUDE.local.md` → absolute `<Core>/<name>/CLAUDE.md`.
- `PROJECTS.md` line for the new layout: `- <name> — <purpose> — <Name>/`.
- Hooks stay git-free and network-free; outside a project they exit 0 and print nothing (L8).
- Tests run in `new_sandbox` (`CORE_DIR=$SANDBOX/Projects/Core`, so `<Projects>` = `$SANDBOX/Projects`); never touch the real `~/Projects`.
- TDD: failing test first, watch it fail, then code. After every task: `bash tests/run.sh` → `ALL TESTS PASSED`, `claude plugin validate .` → passes.
- Commit after each task on branch `claude/corecrew-layout-b6a6a9`, repo style (`feat:`, `fix:`, `test:`, `docs:`), English. Never push, never merge without the owner's "ок".
- Release: corecrew `0.5.0` in `.claude-plugin/plugin.json` and `## 0.5.0 — <date>` at the top of CHANGELOG.md, in the same commit (Task 10).
- Talk to the owner in Russian; after each task say how to check it and what may break.

## Review Focus

1. A code folder name in another letter case than its Core folder (`CoreKit` ↔ `corekit`), and on a case-sensitive disk two folders `Foo` and `foo` — detection finds the one, refuses the two with a plain line. Tests in Task 1.
2. A session in a worktree `<Projects>/<Name>/.claude/worktrees/<w>/` — same project, same code root rules, `save` commits the worktree. Tests in Tasks 1, 2, 6.
3. `CLAUDE.local.md` already a real file, or a symlink to somewhere else, or a dangling symlink after Core moved — never overwritten; session-start says what to fix. Tests in Tasks 4, 7.
4. Folders in `<Projects>` that are not projects (`Brain`, `Claude outputs` with a space, the Core itself) — every hook stays silent and lets everything through. Tests in Tasks 1, 6, 7.
5. `adopt` of a folder outside `<Projects>`, of an old-layout `<Core>/<name>/code` whose target exists, and of a repo with tracked `.claude/rules/` — refuse with nothing changed, or fold the rules into `CLAUDE.md`. Tests in Task 8.

---

### Task 1: Detection helpers in `lib.sh`

**Files:**
- Modify: `scripts/lib.sh` (`load_settings`, `project_of` ~line 207, `valid_project_name` ~276, `projects_entry` ~348, `rel_core` ~270, CLI ~363)
- Modify (callers of `projects_entry`, value unchanged for now): `skills/new-project/scripts/scaffold.sh`, `scripts/adopt.sh`, `tests/fixtures/make-test-coredev.sh`
- Create: `tests/test_lib_layout.sh`

**Interfaces:**
- Produces:
  - `load_settings` also sets `PROJECTS_DIR` (= `dirname "$CORE_DIR"`).
  - `project_of <path>` → prints `<name>`, exit 0, or exit 1. Inside `<Core>`: today's rule unchanged. Outside: first component under `$PROJECTS_DIR` is `<Name>`; a project when `lc <Name>` passes `valid_project_name` and `$CORE_DIR/<name>/CLAUDE.md` exists.
  - `code_dir_of <name>` → prints the main code folder: the one folder in `$PROJECTS_DIR` (not the Core) whose lower-case name is `<name>`; else `$CORE_DIR/<name>/code` if it is a directory; exit 1 if neither; exit 3 with stderr `two folders differ only in case: <A>, <B>` if two match.
  - `layout_of <name>` → prints `new` or `old` (from `code_dir_of`), exit 1 when no code folder.
  - `valid_project_name` also refuses `core`, `standards`, `knowledge`.
  - `projects_entry <name> <purpose> <entry>` → line `- <name> — <purpose> — <entry>` (third argument required).
  - `rel_core <path>` → for a path outside `$CORE_DIR` under `$PROJECTS_DIR`, prints `../<rest>`.
  - CLI: `lib.sh project-of <path>`, `lib.sh code-dir <name>`, `lib.sh layout <name>`.

- [ ] **Step 1: Write `tests/test_lib_layout.sh`** with a sandbox holding `Projects/Core/foo/CLAUDE.md`, `Projects/Foo/` (git repo), `Projects/Foo/.claude/worktrees/w/`, `Projects/Brain/`, `Projects/Claude outputs/`, `Projects/Core/old/CLAUDE.md` + `Projects/Core/old/code/`. Assert: `project_of Projects/Foo` → `foo`; `…/Foo/src/x` → `foo`; `…/Foo/.claude/worktrees/w` → `foo`; `Projects/Brain` and `Projects/Claude outputs` → exit 1; `Projects/Core` → exit 1; `Projects/Core/old/code` → `old`; `Projects` → exit 1; `code_dir_of foo` → `$SANDBOX/Projects/Foo`; `layout_of foo` → `new`; `layout_of old` → `old`; `code_dir_of none` → exit 1; `valid_project_name core` → exit 1; `projects_entry foo "x" "Foo/"` writes `- foo — x — Foo/`. Case clash: if `mkdir Projects/foo` succeeds as a second folder (case-sensitive disk), `code_dir_of foo` exits 3 with `two folders differ only in case`; otherwise skip with a note.
- [ ] **Step 2: Run** `bash tests/test_lib_layout.sh` → FAIL (`code_dir_of` not found).
- [ ] **Step 3: Implement** the Produces list in `scripts/lib.sh`; `code_dir_of` loops `"$PROJECTS_DIR"/*/` comparing `lc "$(basename …)"`, skipping `$CORE_DIR`. Update the three `projects_entry` callers to pass `"$NAME/code/"`.
- [ ] **Step 4: Run** `bash tests/test_lib_layout.sh` → PASS; `bash tests/run.sh` → ALL TESTS PASSED.
- [ ] **Step 5: Commit** `feat: lib.sh finds projects beside the Core (project_of, code_dir_of, layout_of)`.

### Task 2: `save` / `undo-step` locate the new layout

**Files:**
- Modify: `scripts/_locate.sh`
- Test: `tests/test_save_undo.sh` (add a new-layout section), `tests/test_undo_edges.sh` (one worktree case)

**Interfaces:**
- Consumes: `project_of`, `code_dir_of` (Task 1).
- Produces: `locate` sets `CODE`, `MAIN`, `PROJECT` (=`<Core>/<name>`), `NAME`, `CORE`, `CORE_PATHS` for both layouts. New layout: `CORE` comes from the `MAIN/CLAUDE.local.md` symlink target (`dirname` twice) when it points to `…/<name>/CLAUDE.md`; otherwise from `load_settings` (`CORE_DIR` env, plugin option, default). Error text: `Run this inside a project's code folder.` / `This folder is not a corecrew project (<Projects>/<Name> with <Core>/<name>/CLAUDE.md).`

- [ ] **Step 1: Write the tests** — new-layout sandbox (`Projects/Foo` repo, `Projects/Core/foo/` in the Core repo, symlink): `save "step"` from `Projects/Foo` prints `saved code` and `saved docs`, both repos get the same `Step-Id`; from a worktree under `Projects/Foo/.claude/worktrees/w` it commits the worktree; with `CORE_DIR` unset and the symlink present it still finds the Core; `undo-step` reverts both. `save` from `Projects/Brain` (git repo) exits 1 with the new error text.
- [ ] **Step 2: Run** → FAIL (`not a new-project layout`).
- [ ] **Step 3: Implement** in `_locate.sh`: keep today's old-layout branch first; else source `lib.sh` (it sits next to `_locate.sh` in both the plugin and the tools copy), resolve `CORE`, `NAME="$(project_of "$MAIN")"`.
- [ ] **Step 4: Run** the two test files → PASS; full suite green.
- [ ] **Step 5: Commit** `feat: save and undo-step work with code beside the Core`.

### Task 3: `install-hooks.sh` uses the code folder from `code_dir_of`

**Files:**
- Modify: `scripts/install-hooks.sh` (lines ~2, 59–63)
- Test: `tests/test_hooks.sh`

**Interfaces:**
- Consumes: `code_dir_of`. Argument stays `<project_dir>` = `<Core>/<name>`; the code repo is `code_dir_of <name>`. Error: `No git repo at <code folder>`.

- [ ] **Step 1: Test** — new layout: `install-hooks.sh "$CORE_DIR/foo"` puts shims (`# corecrew hook shim`) in `Projects/Foo/.git/hooks/pre-commit`, `pre-push` and `Core/.git/hooks/pre-push`; no code folder → exit 1 with `No git repo at`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS, suite green.
- [ ] **Step 5: Commit** `feat: install-hooks finds the code repo beside the Core`.

### Task 4: `new-project` scaffolds the new layout

**Files:**
- Modify: `skills/new-project/scripts/scaffold.sh`, `skills/new-project/scripts/merge-generated.sh` (comments, target folder), `skills/new-project/SKILL.md` (layout block ~line 38, stages 4–7 paths), `skills/new-project/references/stacks.md` (`code/` wording), `scripts/lib.sh` (`project_docs_manifest`: drop the rules line; new `link_local_claude`)
- Modify templates: `CLAUDE.md.tmpl` (full Core paths, Rules section, "Commands (run in the code folder)", Layout lines per spec §3), `core/README.md`, `core/gitignore` (drop `*/code/`)
- Delete: `skills/new-project/templates/rules/tests.md.tmpl` (its rule text goes into the CLAUDE.md template's Rules section as "Tests (`**/test/**`, `**/tests/**`, `*_test.*`, `*.test.*`): …")
- Test: `tests/test_scaffold.sh`, `tests/test_merge_generated.sh`

**Interfaces:**
- Produces: `link_local_claude <code_dir> <core_project_dir>` → creates the symlink, prints `created ../<Name>/CLAUDE.local.md`; prints `skipped …` when the same symlink exists; exit 1 with `CLAUDE.local.md exists and is not a link to <target>; leave it or remove it yourself` when a file or another link is there. Uses `ln -s`; never `-f`.
- scaffold: code repo at `$PROJECTS_DIR/<name>` (refuse exit 2 `target exists: <path>` when that folder exists and is not empty), `.gitignore`, `.claude/settings.local.json` (`additionalDirectories` = `<Core>/<name>`), `.worktreeinclude`, symlink, `projects_entry <name> <purpose> "<name>/"`.

- [ ] **Step 1: Tests** — scaffold `--name my-app`: `Projects/my-app/.git` exists; `Projects/Core/my-app/code` does not; `Projects/my-app/CLAUDE.local.md` is a symlink whose `readlink` is `$CORE_DIR/my-app/CLAUDE.md`; `Projects/Core/my-app/.claude/rules` does not exist; `CLAUDE.md` contains `$CORE_DIR/my-app/docs/INDEX.md`, `## Rules`, and no `../docs/`; PROJECTS.md has `- my-app — … — my-app/`; Core `.gitignore` lacks `*/code/`; second run prints only `skipped`; a real file `CLAUDE.local.md` placed first is kept byte-for-byte and the run exits 1 with the message above; `--dry-run` creates nothing. merge-generated copies into `Projects/my-app`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (templates, scaffold, SKILL.md text: Claude Code is launched in `<Projects>/<name>`; GitHub step unchanged). **Step 4: Run** → PASS; `tests/test_no_personal.sh` and the suite green.
- [ ] **Step 5: Commit** `feat: new-project puts the code in <Projects>/<name> and links CLAUDE.local.md`.

### Task 5: Test fixture in the new layout

**Files:**
- Modify: `tests/fixtures/make-test-coredev.sh` (code at `$PROJECTS_DIR/test-coredev`, symlink, PROJECTS.md entry `test-coredev/`; last output line = the code folder)
- Test: `tests/test_fixture.sh`

- [ ] **Step 1: Test** — after the fixture: `Projects/test-coredev/add.sh` and `tests/run.sh` exist, one commit; `Projects/Core/test-coredev/CLAUDE.md` has `check: bash tests/run.sh`; `wiki-check.sh "$CORE_DIR/test-coredev"` exit 0; `layout_of test-coredev` → `new`; refuses when either folder exists.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS, suite green.
- [ ] **Step 5: Commit** `test: build the test-coredev fixture beside the Core`.

### Task 6: `guard-code` and messages for the new layout

**Files:**
- Modify: `hooks/guard-code.sh` (`check_path`, header comment), `hooks/messages.sh` (`guard_code_blocked`, `guard_code_public`, en and ru: "the code folder" / "папке кода" instead of `code/`)
- Test: `tests/test_hook_guard_code.sh`, `tests/test_hook_messages.sh`

**Interfaces:**
- Consumes: `project_of`, `layout_of`, `code_dir_of`. Code root: old → `<Core>/<p>/code` (today); new → `code_dir_of <p>`. Everything after the code root goes through today's worktree loop and rules unchanged. Block message targets `<Core>/<p>/<relative path>`.

- [ ] **Step 1: Tests** (new layout, JSON on stdin as the existing tests do): Write `Projects/Foo/CLAUDE.md` → exit 2, stderr names `$CORE_DIR/foo/CLAUDE.md`; `Projects/Foo/docs/x.md` → 2; same inside `.claude/worktrees/w/` → 2; `Projects/Foo/.claude/settings.local.json` → 0; `Projects/Foo/src/a.sh` → 0; Edit of `Projects/Foo/CLAUDE.local.md` (the symlink) → 0 (resolves into Core); a `public-docs: docs/` line → `docs/x.md` → 0; `Projects/Brain/CLAUDE.md` → 0; Bash `echo x > docs/a.md` with cwd `Projects/Foo` → 2. ru message has no `code/`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS, old-layout tests still pass, suite green.
- [ ] **Step 5: Commit** `feat: guard-code protects code folders beside the Core`.

### Task 7: `session-start` (symlink, old layout) and the other hooks

**Files:**
- Modify: `hooks/session-start.sh` (section 3), `hooks/messages.sh` (new keys `local_link_created`, `local_link_wrong`, `old_layout`, en and ru)
- Test: `tests/test_hook_session_start.sh`, `tests/test_hook_guard_secrets.sh`, `tests/test_hook_one_suite.sh`, `tests/test_stop_hook.sh` (one new-layout case each)

**Interfaces:**
- Consumes: `project_of`, `layout_of`, `code_dir_of`, `link_local_claude` (Task 4).
- Produces: in a new-layout project, session-start calls `link_local_claude`; created → prints `local_link_created` (`corecrew: linked CLAUDE.local.md to <target>; restart the session to load it`); exit 1 → prints `local_link_wrong` with the path and the fix (`ln -s "<target>" "<code>/CLAUDE.local.md"` after moving the file away). Old layout → prints `old_layout` (`corecrew: this project still lives in <Core>/<p>/code; run /corecrew:task adopt <that path> to move it to <Projects>/<p>`). Stale-hook check reads `<code_dir_of>/.git/hooks/*`.

- [ ] **Step 1: Tests** — new layout without symlink: output has `linked CLAUDE.local.md`, symlink exists; second run: no link line; real file present: file unchanged, output names the fix; dangling symlink to an old Core path: unchanged, output names the fix; old layout: `old_layout` line; `Projects/Brain`: empty stdout. guard-secrets blocks `Projects/Foo/.env` read; one-suite waits in `Projects/Foo`; stop-remind reminds in `Projects/Foo` with dirty code.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS, suite green.
- [ ] **Step 5: Commit** `feat: session-start links CLAUDE.local.md and names old-layout projects`.

### Task 8: `adopt` keeps the repo in place

**Files:**
- Modify: `scripts/adopt.sh` (header, refusals, copy set, rules folding, move only for old layout, symlink, settings, PROJECTS.md, last line `open: <code folder>`), `skills/task/references/adopt.md`
- Test: `tests/test_adopt.sh` (rewrite the move cases; keep refusal cases)

**Interfaces:**
- Consumes: `project_of`, `code_dir_of`, `layout_of`, `link_local_claude`, `projects_entry`.
- Produces: refusals (exit 2, nothing changed) add `not in <Projects>: move the folder to <Projects>/<Name> first` and, for an old-layout source, `target exists: <Projects>/<name>`. Name = `lc basename` (or `--name`). Rules folding: each tracked `.claude/rules/<f>.md` is appended to the Core `CLAUDE.md` as `### <f>` under `## Rules` (created at the end if missing), with `Applies to: <paths, comma-separated>` when it has `paths:`, front matter dropped. Other tracked `.claude/` files go to `<Core>/<name>/.claude/` and the dry-run and report list them under `kept in Core, no longer loaded`. `settings.local.json` in the code folder: created from the template when missing, else left as is with a `warning:` line naming the `additionalDirectories` entry to add.

- [ ] **Step 1: Tests** — `Projects/Foo` repo with tracked `CLAUDE.md`, `docs/a.md`, `.claude/rules/t.md` (`paths: ["src/**"]`), `.claude/commands/x.md`: after adopt, `Projects/Foo` still exists at the same path (inode or `pwd -P` unchanged), `git log -1` is `Move internal Claude files to Core`, `CLAUDE.md` gone from the repo, `Projects/Core/foo/CLAUDE.md` contains `### t` and `Applies to: src/**`, `Projects/Core/foo/.claude/commands/x.md` exists, symlink present, PROJECTS.md `- foo — … — Foo/`, Core commit `Adopt foo`, `wiki-check` exit 0, last line `open: $SANDBOX/Projects/Foo`. `--public-docs docs/` keeps `docs/a.md` in the repo. Refusals: a repo in `$SANDBOX/elsewhere/Bar` → `not in`; old layout `Core/old/code` with `Projects/old` present → `target exists`; both leave `tree_sum` unchanged. Old layout move: `Core/old/code` → `Projects/old`, worktree repaired, symlink made, Core commit.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** script and `adopt.md` (report: folder unchanged; restart Claude Code in it so `CLAUDE.local.md` loads; list "kept in Core, no longer loaded"). **Step 4: Run** → PASS, suite green.
- [ ] **Step 5: Commit** `feat: adopt keeps the repo where it is and moves only old-layout code`.

### Task 9: `task` skill, wiki rules and wiki-check paths

**Files:**
- Modify: `skills/task/SKILL.md` (Start step 2 per spec §5.3, step 5 `git status` in the code root), `skills/task/references/brief.md` (paths relative to the code root), `skills/task/references/release.md` (changed wiki pages passed as `docs/<page>.md`, no `../docs/`), `skills/task/references/paths.md` (if it names `code/`), `reference/wiki.md` (`files:` relative to the code root; `--changed` forms), `scripts/wiki-check.sh` (header; accept `<Core>/<name>/docs/<page>.md` absolute as a wiki page too; keep `../docs/` and `docs/` working)
- Test: `tests/test_task_skill.sh`, `tests/test_wiki_check.sh`

- [ ] **Step 1: Tests** — `test_task_skill.sh` greps: SKILL.md Start step 2 mentions `lib.sh" project-of`, `<Projects>/<Name>`, `old layout` and no longer says `must be inside <Core>/<project>/`; brief.md has no `<Core>/<project>/code/`; release.md has no `../docs/`. `test_wiki_check.sh`: `--changed "$CORE_DIR/p/docs/features/x.md"` counts as updating that page.
- [ ] **Step 2: Run** → FAIL. **Step 3: Edit.** **Step 4: Run** → PASS, suite green.
- [ ] **Step 5: Commit** `feat: task skill and wiki tools follow the code folder beside the Core`.

### Task 10: Schema 2, docs, release 0.5.0

**Files:**
- Modify: `scripts/lib.sh` (`COREDEV_SCHEMA=2`), `scripts/setup-core.sh` (`core_ready` is true for schema 1, so today it prints `skipped .coredev`; add: a schema number below `COREDEV_SCHEMA` → rewrite only the schema line, keep the other lines, print `updated .coredev`; never edit `.gitignore` lines), `README.md` (Layout section ~line 100 per spec §3; adopt no longer moves), `CLAUDE.md` of this repo (Layout mentions of `code/`), `docs/specs/2026-11-03-coredev-design.md` and `docs/specs/2026-11-02-new-project-design.md` (one line under the title: "Layout superseded by docs/specs/2026-11-04-project-layout-design.md"), `CHANGELOG.md` (`## 0.5.0 — <date>`), `.claude-plugin/plugin.json` (`0.5.0`)
- Test: `tests/test_setup_core.sh`, `tests/test_manifest.sh`, `tests/test_hook_session_start.sh` (layout note for schema 1)

- [ ] **Step 1: Tests** — setup-core on a schema-1 Core: `.coredev` reads `schema: 2`, `.gitignore` byte-identical, prints `updated .coredev`; manifest test expects `0.5.0` and CHANGELOG first `## ` line `## 0.5.0 — `; README contains `<Projects>/<name>` wording and no `my-app/code/`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Edit.** **Step 4: Run** → `bash tests/run.sh` ALL TESTS PASSED; `claude plugin validate .` passes.
- [ ] **Step 5: Commit** `feat: corecrew 0.5.0 — code lives beside the Core`.

### Task 11: Live checks and the owner's migration (spec §6, §8) — with the owner

Not code; each step only after the owner's "ок", reported in Russian.
- [ ] **Step 1:** `claude -p --plugin-dir .` in a sandbox project made by `scaffold.sh`: `CLAUDE.local.md` content is in context; a corecrew subagent sees it (spec §8.2). Record the result in the spec §7.
- [ ] **Step 2:** The owner opens an interactive session in that sandbox folder (trust prompt is theirs) and runs `/context`: the symlinked file is listed, no import dialog (spec §8.1). If a dialog appears, note it in `adopt.md`'s report step; if the file does not load, stop and go back to the spec's L4 with the owner.
- [ ] **Step 3:** A desktop-app worktree of the sandbox project loads it too (spec §8.3).
- [ ] **Step 4:** After merge and plugin update, on the owner's "ок": `/corecrew:task adopt ~/Projects/Core/test-coredev/code` (old layout → `~/Projects/test-coredev`), then `/corecrew:task adopt ~/Projects/CoreKit` with public docs `docs/`.
