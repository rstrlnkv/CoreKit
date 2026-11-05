---
title: Project layout — code beside Core, private files in Core
description: Target on-disk layout of a corecrew project (code repo in <Projects>/<Name>, private files in <Core>/<name>), how a session finds its Core folder, what new-project and adopt do, migration from <Core>/<name>/code, and the list of files to change. Read before changing project location logic in scripts, hooks or skills.
status: implemented (corecrew 0.5.0); section 8 checks are for a live session
files: [scripts/lib.sh, scripts/_locate.sh, scripts/adopt.sh, scripts/install-hooks.sh, scripts/wiki-check.sh, scripts/setup-core.sh, hooks/, skills/new-project/, skills/task/, reference/wiki.md, tests/]
related: [docs/specs/2026-11-03-coredev-design.md, docs/specs/2026-11-02-new-project-design.md]
updated: 2026-11-04
---

# Project layout — code beside Core, private files in Core

> **Paths (2026-11-05, corecrew 0.6.0).** The plugin lives in `plugins/corecrew/`: every path in this
> spec that names `skills/`, `agents/`, `hooks/`, `reference/`, `scripts/` or `.claude-plugin/plugin.json`
> is relative to that folder. `tests/`, `docs/` and `.claude-plugin/marketplace.json` stay at the repo root.

## 1. Why
Today a project's code repo lives inside the private Core, at `<Core>/<name>/code/`, so that
Claude Code, launched in `code/`, loads the private `CLAUDE.md` and `.claude/rules/` from the
parent folder. `adopt` therefore moves the whole repo folder into Core. The owner's rule is
different: **Core holds only what must not be in a project's (possibly public) repo; the code
stays in the projects folder.** One project folder in `<Projects>` = one folder in `<Core>`.

This replaces section 4.3 and parts of 9.1, 11 and 14 of `2026-11-03-coredev-design.md` and
section 3 of `2026-11-02-new-project-design.md`; where they disagree, this spec wins.

## 2. Decisions
| # | Decision | Why |
|---|---|---|
| L1 | One layout for all projects, new and adopted. | No two modes to support. |
| L2 | The code repo is `<Projects>/<Name>`; `<Projects>` is the parent folder of `<Core>` (default `~/Projects`). | The owner keeps every project as a folder in `~/Projects`. |
| L3 | Private files are `<Core>/<name>/`, `<name>` = `<Name>` in lower case. The link is by name only; nothing is stored. | The owner's "one folder in Projects = one folder in Core"; nothing to keep in sync. |
| L4 | The private `CLAUDE.md` reaches the session through `<Projects>/<Name>/CLAUDE.local.md`, a symlink (absolute target) to `<Core>/<name>/CLAUDE.md`, gitignored. The plugin creates and repairs it. | The only tested way that loads (§7). |
| L5 | Private by default: `CLAUDE.md`, `AGENTS.md`, the wiki `docs/` (INDEX, brief, architecture, decisions, features), `docs/knowledge/`, `docs/superpowers/`, and any internal notes (`notes/`). Exceptions stay public via `public-docs:` in `CLAUDE.md`. | Owner's choice. |
| L6 | No `.claude/rules/` files. Rules are a "Rules" section of the private `CLAUDE.md` (path-specific ones say which files they cover). | Rules in Core never load (§7); copies would drift. |
| L7 | `adopt` moves no folder, except a project still in the old layout (`<Core>/<name>/code`), which it moves to `<Projects>/<name>`. A folder that is not directly in `<Projects>` is refused. | The repo stays where the user keeps it. |
| L8 | Outside a project (§4) no hook blocks or changes anything (D17 restated). | Other folders in `~/Projects` (Brain, archives) are not projects. |

## 3. Layout
```
<Projects>/                         = parent of <Core>, e.g. ~/Projects
  Core/                             <Core>: private git repo
    .coredev                        schema: 2
    PROJECTS.md  README.md  .gitignore  standards/  knowledge/  session-rules.md
    <name>/                         lower-case project name
      CLAUDE.md                     instructions, "check: <command>", "public-docs: <paths>", Rules section
      AGENTS.md                     when the project has one
      docs/INDEX.md brief.md architecture.md decisions/ features/
      docs/knowledge/<role>.md
      docs/superpowers/             specs and plans from sessions
      notes/                        any internal notes
      .claude/                      only tracked .claude/ files an adopted repo had (not loaded; §5.2)
  <Name>/                           the code repo; Claude Code is launched here
    CLAUDE.local.md -> <Core>/<name>/CLAUDE.md     symlink, gitignored, made by the plugin
    .claude/settings.local.json     permissions.additionalDirectories: [<Core>/<name>] (absolute)
    .claude/worktrees/<w>/          native worktrees; they load ../../CLAUDE.local.md as a parent file
    .worktreeinclude                lists .claude/settings.local.json
    .gitignore                      CLAUDE.md, CLAUDE.local.md, AGENTS.md, .claude/, docs/superpowers/, .env, .env.*
```
`PROJECTS.md` line: `- <name> — <purpose> — <Name>/` (the code folder relative to `<Projects>`).
Names: `<name>` is 3–40 lower-case Latin letters, digits and hyphens; `<Name>` is the same up
to letter case. `core`, `standards`, `knowledge` are not project names. The `Core` folder
itself is never a project.

## 4. Finding the project from a path (`lib.sh`)
`project_of <path>` (replaces today's check "inside `<Core>/<project>/`"):
1. Canonical path (`canon_dir`). Inside `<Core>`: today's rule (a top-level folder with
   `CLAUDE.md` or `code/`, not `standards`/`knowledge`/dot-folders) — print `<name>`.
2. Otherwise take the first path component under `<Projects>` as `<Name>`; none → not a project.
   This covers worktrees under `<Name>/.claude/worktrees/<w>/` without calling git.
3. `<name>` = lower case of `<Name>`; a project when `<Core>/<name>/CLAUDE.md` exists.
Hooks stay git-free and network-free. New helpers: `PROJECTS_DIR` (set by `load_settings`, parent of
`CORE_DIR`), `code_dir_of <name>` (the folder in `<Projects>` whose lower-case name is `<name>`, else
`<Core>/<name>/code`; two case-only matches → error "two folders differ only in case"), `layout_of <name>` (`new` | `old`).
`_locate.sh` (save, undo-step, stop-remind) uses git as today for the main checkout of a
worktree, then the same rule instead of "parent folder named `code` inside the Core repo".

## 5. Commands

### 5.1 `new-project`
Checks `<Projects>/<name>` and `<Core>/<name>` are both free (and `gh repo view <name>`).
Creates `<Core>/<name>/` from templates (no `.claude/rules/`; the old `rules/tests.md`
template text becomes the Rules section of `CLAUDE.md.tmpl`), the code repo at
`<Projects>/<name>`, the symlink, `settings.local.json`, `.worktreeinclude`, `.gitignore`, git
hook shims, the `PROJECTS.md` line, first `save`. `CLAUDE.md.tmpl` names Core paths in full
(`<Core>/<name>/docs/INDEX.md`, `<Core>/<name>/docs/superpowers/`), never `../docs/`.

### 5.2 `task adopt <folder>`
1. Refusals (all before any change; exit 2, one line): today's list, plus
   `not in <Projects>: move the folder to <Projects>/<Name> first` when the folder is not a
   direct child of `<Projects>` (and not an old-layout `<Core>/<name>/code`), and
   `target exists: <Projects>/<name>` for an old-layout move.
2. Copy the private set (L5) minus `public-docs:` paths to `<Core>/<name>/`. Tracked
   `.claude/rules/*.md` are appended to `CLAUDE.md` under `## Rules`, one subsection per file
   with its `paths:` as "Applies to: …". Other tracked `.claude/` files go to
   `<Core>/<name>/.claude/` and the report says they no longer load. One revertible commit in
   the repo removes them and appends the missing ignore lines (user lines untouched).
3. Old layout only: `mv <Core>/<name>/code <Projects>/<name>` (same disk, refuse otherwise);
   repair worktrees; fold `<Core>/<name>/.claude/rules/*.md` (0.4 and older wrote `tests.md`)
   into `CLAUDE.md` the same way, keeping the files.
4. Symlink, `settings.local.json` (`additionalDirectories` = `<Core>/<name>`), hook shims,
   wiki map and missing pages, `PROJECTS.md` line, commit "Adopt <name>" in Core;
   `wiki-check.sh` green.
5. Report: the folder is unchanged (or the new path, old layout); restart Claude Code in it so
   the symlink loads.

### 5.3 `task` (all paths)
Start step 2 uses `project_of` on the working directory. The code root is the worktree root
when inside `<Name>/.claude/worktrees/<w>/`, else `<Projects>/<Name>`. Old layout → one line:
"this project uses the old layout; run `/corecrew:task adopt <path>`", and stop (except adopt).

### 5.4 Hooks
- `session-start.sh`: in a project, ensures the symlink: missing → create; a symlink to the
  right file → nothing; a regular file or a symlink elsewhere → leave it, print one line with
  the fix. Hook paths checked: `<code root>/.git/hooks/*`, `<Core>/.git/hooks/pre-push`.
- `guard-code.sh`: blocks `CLAUDE.md`, `AGENTS.md`, `docs/**` (except `public-docs:`),
  `.claude/**` (except `settings.local.json`, `worktrees/**`) inside `<Projects>/<Name>/**` of a
  project, worktrees included. Paths are compared after resolving symlinks, so an edit through
  `CLAUDE.local.md` lands in Core and is allowed. Messages say "the code folder", not `code/`.
- `guard-secrets.sh`, `one-suite.sh`, `stop-remind.sh`: same, through the new `project_of`.
- git hooks: unchanged (`blocked-patterns` already blocks `CLAUDE.local.md`).

## 6. Migration
- `.coredev` `schema: 2`. `setup-core.sh` on schema 1 only bumps the schema and adds missing
  files; it never moves a project and never edits the user's `.gitignore` lines (`*/code/` stays
  harmless).
- Old-layout projects are moved one by one with `task adopt <Core>/<name>/code` (§5.2.3). Today
  only `test-coredev` (the hand-made test fixture, D8) is in that layout; the fixture is rebuilt
  in the new layout.
- CoreKit itself: after release, `task adopt ~/Projects/CoreKit --public-docs docs/` —
  `CLAUDE.md` moves to `<Core>/corekit/`, `docs/` stays public. Its first interactive session
  is the check in §8.
- Version: corecrew 0.5.0 (layout change), CHANGELOG entry; README "Layout" section rewritten.

## 7. Evidence (Claude Code 2.1.318, `claude -p`, 2026-11-04)
Sandbox `<S>/Projects/<Repo>` (git repo, `CLAUDE.local.md` and `.claude/` ignored), private
files in `<S>/Projects/Core/foo/`:
- `CLAUDE.local.md` symlink to `Core/foo/CLAUDE.md`: loaded, in the main checkout and in a
  worktree at `.claude/worktrees/w`.
- `CLAUDE.local.md` with `@<abs>/Core/foo/CLAUDE.md`: not loaded (external import needs a
  one-time approval dialog; `-p` has none).
- `.claude/rules` symlink to `Core/foo/.claude/rules`: not loaded. Docs: an external symlink is
  an external import, and after approval only rules without `paths:` load.
- `permissions.additionalDirectories` + `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`
  (in settings `env` or the shell): not loaded. Docs: `additionalDirectories` grants file
  access only; only `--add-dir` loads configuration.
- Control: real files in `.claude/rules/` (always-on and `paths:`) load.
- After implementation (0.5.0, `claude -p --plugin-dir`): a project made by `scaffold.sh` loads
  `<Core>/<name>/CLAUDE.md` through the symlink in the main session and in a general-purpose
  subagent it launched (check 2 below: done).

## 8. Open checks (during implementation)
1. Interactive session in a trusted folder: the symlinked `CLAUDE.local.md` loads with no
   dialog (check with `/context`). If a dialog appears, the user approves it once per project;
   note it in the adopt report.
2. A subagent sees the `CLAUDE.local.md` content — done (§7).
3. Desktop-app worktrees (created by the app, not `git worktree add`) load the parent symlink.
If check 1 fails outright, stop and revisit L4 with the owner before going on.

## 9. What changes
**scripts/**
- `lib.sh`: `project_of` per §4; new `PROJECTS_DIR`, `code_dir_of`, `layout_of`, `link_local_claude`; `projects_entry`
  line format; `valid_project_name` reserved names; CLI `project-of <path>`, `code-dir <name>`, `layout <name>`.
- `_locate.sh`: locate by §4; error texts without `Core/<name>/code`.
- `adopt.sh`: §5.2 (no move except old layout; refuse outside `<Projects>`; rules into
  `CLAUDE.md`; symlink; `settings.local.json`); header comment.
- `install-hooks.sh`: code repo from `code_dir_of`, not `<P>/code`.
- `wiki-check.sh`: changed pages may also be given as `<Core>/<name>/docs/…` (absolute); `docs/…` and
  `../docs/…` keep working; `release.md` passes `docs/…`.
- `setup-core.sh`: schema 2; Core `README.md` template text.

**hooks/**: `session-start.sh` (symlink, hook paths, old-layout line), `guard-code.sh` (§5.4),
`guard-secrets.sh`, `one-suite.sh`, `stop-remind.sh` (new `project_of`), `messages.sh` (texts
that say `code/`, en and ru).

**skills/**
- `new-project/SKILL.md`, `scripts/scaffold.sh`, `scripts/merge-generated.sh`: code at
  `<Projects>/<name>`; symlink; no `rules/`.
- `new-project/templates/`: `CLAUDE.md.tmpl` (full Core paths, Rules section), drop
  `rules/tests.md.tmpl`, `code/gitignore-common` (+ `CLAUDE.local.md`), `core/README.md`,
  `core/gitignore` (no `*/code/` for new Cores), `references/stacks.md` (`code/` wording).
- `task/SKILL.md` Start step 2; `references/adopt.md` (§5.2); `references/brief.md` (paths
  relative to the code root); `references/release.md` (`../docs/` prefix); `references/paths.md`
  if it names `code/`.
- `reference/wiki.md`: `files:` relative to the code root; `--changed` form.

**tests/**: every file that builds `<Core>/<p>/code` (19 files: `fixtures/make-test-coredev.sh`,
`test_adopt.sh`, `test_fixture.sh`, `test_hook_guard_code.sh`, `test_hook_guard_secrets.sh`,
`test_hook_messages.sh`, `test_hook_one_suite.sh`, `test_hook_session_start.sh`, `test_hooks.sh`,
`test_lib_json.sh`, `test_manifest.sh`, `test_merge_generated.sh`, `test_no_personal.sh`,
`test_review_fixes.sh`, `test_save_undo.sh`, `test_scaffold.sh`, `test_setup_core.sh`,
`test_stop_hook.sh`, `test_undo_edges.sh`). `new_sandbox` gains a `<Projects>` folder beside
`CORE_DIR`. New tests: `project_of` cases (§4: code root, worktree, case mismatch, two-case
clash, non-project folder in `<Projects>`, old layout, inside Core); symlink create / leave /
repair in session-start; adopt refuses outside `<Projects>`, moves nothing, folds rules,
migrates old layout; guard-code allows an edit through the symlink.

**docs and release**: README "Layout", CLAUDE.md of this repo (`Layout` mentions), the two older
specs get a line pointing here, CHANGELOG 0.5.0, `plugin.json` 0.5.0.

## 10. Out of scope
A `projects_dir` setting separate from `core_dir` (add when someone needs code outside the
Core's parent); code folders outside `<Projects>`; syncing rule files; Windows.
