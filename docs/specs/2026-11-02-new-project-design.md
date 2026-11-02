---
title: new-project skill — design spec
description: What the "new project" skill does, folder layout, git workflow, protection of internal files, interview, stack analysis and verification. Read before changing the skill.
status: approved
files: [skills/new-project/]
related: []
updated: 2026-11-02
---

# `new-project` skill — design spec

## 1. Goal
When the user asks to start a new project, Claude runs an interview, analyzes platforms,
stack and architecture, agrees every decision with the user, and scaffolds the project to one
standard. Result: all projects share the same layout, and internal files (CLAUDE.md, docs/,
.claude/) physically cannot end up in a public repository.

The user may not read code. The skill talks to the user in their language (§2), in plain
words, explains terms on first use, presents each decision and waits for explicit approval.

## 2. Language policy
- **English:** all code, code comments, identifiers, every Markdown file (CLAUDE.md, docs/,
  .claude/rules/, README, ADRs, specs, SKILL.md and its references) and git commit messages.
- **User's language:** conversation with the user only. Taken from the user's Claude settings
  or instructions (user preferences, project instructions, CLAUDE.md); if none is set, the
  language the user writes in. When a document is written, show a short summary of it in chat
  in the user's language.
- **App UI languages:** chosen in the interview; UI strings live in localization files,
  never hard-coded.

## 3. Folder layout
```
~/Projects/                       ← whole path must be ASCII (non-ASCII breaks Android/Flutter)
  CoreKit/                        ← skills and templates (this repo)
  Core/                           ← private GitHub repo `Core`
    README.md, PROJECTS.md        ← PROJECTS.md: one line per project
    bin/save, bin/undo-step       ← shared git commands (§6)
    hooks/                        ← hook sources installed into both repos
    <project-name>/
      CLAUDE.md
      docs/INDEX.md, brief.md, architecture.md, features/, decisions/, superpowers/
      .claude/rules/*.md
      code/                       ← separate repo `<project-name>`; ignored by Core
        .claude/settings.local.json   (local only)
        .claude/worktrees/            (local only)
```
Project name: Latin, lowercase, hyphen-separated, no spaces. The skill proposes the name.

**Claude is launched in `code/`.** Verified on Claude Code 2.1.316 (2026-11-02):
- CLAUDE.md and `.claude/rules/` (with and without `paths:`) in the parent folder load;
- they also load inside a native worktree at `code/.claude/worktrees/<name>/`;
- auto memory, permission approvals and worktrees are per project (keyed to the code repo);
- writing to the parent folder needs `permissions.additionalDirectories` with the **absolute**
  path of `Core/<project-name>` in `code/.claude/settings.local.json` (absolute, so it also
  works from worktrees; copied there via `.worktreeinclude`).
Rationale against alternatives: symlinks pointing outside the working dir need approval and
drop `paths:` rules (https://code.claude.com/docs/en/memory); launching in `Core/<project>`
makes Core the session's repo, so worktrees, memory and commits would target Core
(https://code.claude.com/docs/en/worktrees).

## 4. Triggers
Fires on a request to start a new app/project in any language, e.g. "new project",
"start a new app", "новый проект", "создай проект".
Does not fire on: a new project in another tool ("new project in Jira/Notion"), creating a task,
adding a feature to an existing project, questions about an existing project.
Auto-invocation stays on; every side effect on GitHub requires explicit approval (§5).

## 5. Flow
Progress is stored in `stage:` in the front matter of `docs/brief.md`; on a new run the skill
resumes from that stage. Suggest splitting into two sessions: "decide" (steps 1–3) and
"build" (steps 4–7).

0. **Preflight (tools only).** git, gh + `gh auth status`; ~/Projects/Core exists (else create
   and init); whole target path and `$HOME` are ASCII — warn otherwise.
1. **Interview**, 2–3 questions at a time (AskUserQuestion): what it does and for whom;
   platforms; type (app, utility, bot, website); v1 features (3–7) and "later"; data
   (device/cloud, sign-in, offline); external services (APIs, payments, notifications);
   design (style, dark theme, UI languages); will the code be public; definition of done.
2. **Name and folder.** Agree the name; check `Core/<name>` and `gh repo view <name>` are free
   (stop and ask if not); create `Core/<name>/docs/brief.md` (English) with `stage: interviewed`.
3. **Analysis** — the skill runs it itself (method in references/analysis.md; do NOT invoke
   `superpowers:brainstorming`, whose hard gate would take over the flow):
   - platform constraints (iOS needs a Mac, Xcode and an Apple Developer account; Windows
     builds need Windows, etc.);
   - 2–3 stack options scored on: platform coverage, offline, native look and feel, how well
     AI agents write this stack, community, cost, build complexity; one recommendation;
   - one research subagent verifies the options against official docs (current versions,
     platform support, known issues) and returns links;
   - architecture: components, data storage and sync, external services, risks.
   Each part is approved by the user. Result: `docs/architecture.md`,
   `docs/decisions/001-stack-and-architecture.md`, `docs/INDEX.md`; `stage: decided`.
4. **Scaffold** (`scripts/scaffold.sh`, never overwrites existing files): CLAUDE.md, rules,
   docs pages from templates; `code/` via the stack's non-interactive generator command from
   references/stacks.md; code `.gitignore`; `code/.claude/settings.local.json`;
   `.worktreeinclude`; hooks; line in PROJECTS.md; first `save`. `stage: scaffolded`.
5. **GitHub** (each `gh repo create` asked separately):
   - `Core`: create once with `--private` if missing;
   - `<name>`: `--private` by default; `--public` only if the interview explicitly said so.
6. **Verify:** build/run the empty project with the stack's command; `stage: ready`. Report in
   the user's language: what was created, how to check it, what may break.
7. **Optional:** v1 implementation plan via `superpowers:writing-plans` (output to
   `../docs/superpowers/plans/`).

## 6. Git workflow
Two repos per project: `Core` (all internal docs) and `<name>` (code).
- **`Core/bin/save "<message>" [--push]`** — commits `code/` and `Core/<name>/` with the same
  message and a shared trailer `Step-Id: <timestamp>`; skips a repo with no changes; reinstalls
  missing hooks; `--push` pushes both (Core push is preceded by the privacy check).
- **`Core/bin/undo-step [<Step-Id>]`** — reverts the last (or given) step in both repos with
  `git revert` (history kept, the undo itself can be undone).
- **Stop hook** (in `code/.claude/settings.local.json`): if either repo has uncommitted changes,
  remind Claude to run `save`; respects `stop_hook_active` to avoid loops.
- **Branches:** `main` only; worktree branches are merged back when the work is finished.
- **Worktrees:** native, under `code/.claude/worktrees/`. Subagents in worktrees do not edit
  docs/ (shared across worktrees); the main session updates docs after merging.
- **Superpowers output:** specs and plans go to `../docs/superpowers/` (rule in CLAUDE.md).

## 7. Protecting internal files (five layers)
1. Internal files live outside the code repo.
2. Code `.gitignore` (versioned): CLAUDE.md, CLAUDE.local.md, `.claude/`, `docs/superpowers/`,
   `.env*`, `*.pem`, `*.key`.
3. Code pre-commit hook blocks those files and explains what to do.
4. Code pre-push hook re-checks pushed commits (catches `--no-verify`).
5. Core pre-push hook blocks the push unless `gh api repos/OWNER/Core --jq .private` is true.
`Core/.gitignore`: `*/code/`, `.env*`, `.DS_Store`.

## 8. Project CLAUDE.md (up to ~150 lines)
Purpose (1–2 sentences), stack, build/test/run commands (run in code/), folder layout, link to
`../docs/INDEX.md` as plain text (no @-import). Rules:
- all code, comments and Markdown in English; talk to the user in their language;
- after each working step run `save`; on request `undo-step` / `save --push`;
- after changing a feature, update its page in docs/features/ and its `updated` field;
- a new architectural decision → a new docs/decisions/NNN-*.md;
- specs and plans → `../docs/superpowers/`; never edit docs from a worktree;
- never read .env or ~/.ssh.

## 9. Wiki
Every docs/ page starts with YAML front matter: title, description (what is inside and when
to read it), status, files, related, updated. INDEX.md has one line per file. Rules in
`.claude/rules/*.md` use `paths:` relative to the project folder written as `code/**/<dir>/**`
so they also match inside worktrees.

## 10. Skill contents (CoreKit)
```
skills/new-project/
  SKILL.md                     ← short: flow, stages, links to references
  references/interview.md      ← interview questions
  references/analysis.md       ← analysis method and criteria, research-subagent prompt
  references/stacks.md         ← stack options with tested non-interactive generator commands
                                 (Flutter: --project-name/--org; Tauri: non-interactive flags;
                                 SwiftUI: XcodeGen)
  templates/                   ← CLAUDE.md, docs/*, rules/*, gitignore/*, settings.local.json
  scripts/scaffold.sh          ← idempotent; --dry-run (no GitHub); CORE_DIR override
  scripts/install-hooks.sh, core-bin/save, core-bin/undo-step, hooks/*
install.sh                     ← copies skills/* to ~/.claude/skills/
```
Install note: Cowork does not read `~/.claude/skills/`; to use the skill there, upload it
to the claude.ai account (https://code.claude.com/docs/en/skills).

## 11. Out of scope for v1
Migrating existing projects (`adopt-project`), updating old projects when templates change,
PowerShell versions of the scripts.

## 12. Verification
- Baseline: run the test prompts without the skill and record what goes wrong (writing-skills).
- Evals (skill-creator): fires on 8+ phrases, does not fire on 8+ near-miss phrases;
  2 scenarios (Flutter for 4 platforms; a Mac-only utility); viewer for human review.
- Dry run with `CORE_DIR` pointing to a test folder: layout, front matter, hooks block
  CLAUDE.md in code/, `save`/`undo-step` work in both repos, Stop hook reminds.
- GitHub and a real build — the user checks on the Mac following the instructions.
