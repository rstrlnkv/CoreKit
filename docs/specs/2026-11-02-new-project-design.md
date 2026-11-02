---
title: new-project skill — design spec
description: What the "new project" skill does, folder layout, protection of internal files, interview, stack analysis and verification. Read before changing the skill.
status: draft
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

The user may not read code. The skill talks to the user in their language (see §2), in plain
words, explains terms on first use, presents each decision and waits for explicit approval.

## 2. Language policy
- **English:** all code, code comments, identifiers, every Markdown file (CLAUDE.md, docs/,
  .claude/rules/, README, ADRs, specs, SKILL.md and its references) and git commit messages.
- **User's language:** conversation with the user only. The language is taken from the user's
  Claude settings or instructions (user preferences, project instructions, CLAUDE.md);
  if none is set, use the language the user writes in. Interview answers are written to
  `brief.md` in English.
- **App UI languages:** chosen in the interview; UI strings live in localization files,
  never hard-coded.

## 3. Folder layout (private workspace with nested code repo)
Rationale: symlinks pointing outside the project break path-scoped rules (`paths:`) and are
skipped in Cowork, while CLAUDE.md is loaded from every parent directory
(https://code.claude.com/docs/en/memory). Five approaches were compared on 2026-11-02;
this one is the only one that is native to Claude Code, works on Windows, keeps one private
repo, and keeps the code repo free of internal files.

```
~/Projects/                      ← Latin only: non-ASCII paths break Android/Flutter builds
  CoreKit/                       ← this repo: skills and templates
  Core/                          ← ONE private GitHub repo `core`
    README.md, PROJECTS.md       ← PROJECTS.md: one line per project
    <project-name>/              ← Claude Code is launched here
      CLAUDE.md
      docs/INDEX.md, brief.md, architecture.md, features/, decisions/
      .claude/rules/*.md
      code/                      ← separate git repo with the code; ignored by Core
```
Project name: Latin, lowercase, hyphen-separated, no spaces. The skill proposes the name.

## 4. Triggers
Fires on a request to start a new app/project in any language, e.g. "new project",
"start a new app", "новый проект", "создай проект".
Does not fire on: a new project in another tool ("new project in Jira/Notion"), creating a task,
adding a feature to an existing project, questions about an existing project.

## 5. Flow
0. **Preflight.** git, gh (+ `gh auth status`), ~/Projects/Core exists (create and init if not),
   project name is free (if the folder or GitHub repo exists — stop and ask).
   Stack tooling is checked after the stack is chosen (step 3).
1. **Interview**, 2–3 questions at a time (AskUserQuestion), topics:
   what it does and for whom; platforms; type (app, utility, bot, website); v1 features (3–7)
   and "later"; data (device/cloud, sign-in, offline); external services (APIs, payments,
   notifications); design (style, dark theme, UI languages); will the code be public;
   definition of done. After each block, answers are appended to `docs/brief.md` so the
   interview can be resumed later.
2. **Analysis** via `superpowers:brainstorming` (fallback without Superpowers:
   references/analysis.md):
   - platform constraints (iOS needs a Mac, Xcode and an Apple Developer account; Windows
     builds need Windows, etc.);
   - 2–3 stack options scored on: platform coverage, offline, native look and feel, how well
     AI agents write this stack, community, cost, build complexity;
   - one research subagent checks the options against official documentation (current
     versions, platform support, known issues) and returns links;
   - architecture: components, data storage and sync, external services, risks.
   The user approves each part explicitly. The user does not pick the stack — the skill
   recommends one and explains why.
3. **Record decisions:** `docs/architecture.md`, `docs/decisions/001-stack.md`,
   `002-architecture.md` (ADRs), update `docs/INDEX.md`. Check stack tooling.
4. **Scaffold:** folders and files from templates/, `code/` via the stack's official generator
   (e.g. `flutter create`), stack-specific `.gitignore`, hooks, `git init` in code/,
   a line in Core/PROJECTS.md.
5. **Git and GitHub:**
   - commit to `core` and to `code/`;
   - `core`: if missing on GitHub — `gh repo create core --private`; Core pre-push hook blocks
     the push unless `gh api repos/OWNER/core --jq .private` is true;
   - `code/`: `--private` by default; public only if the interview explicitly says so.
6. **Verify:** build/run the empty project with the stack's command; report in plain words in the
   user's language what was created, how to check it, and what may break.
7. **Optional:** v1 implementation plan via `superpowers:writing-plans`.

## 6. Protecting internal files
- Internal files live outside the code repo — nothing to leak.
- `code/.git/hooks/pre-commit` blocks committing CLAUDE.md, CLAUDE.local.md, AGENTS.md,
  docs/superpowers/, .claude/, .env*, *.pem, *.key, and explains what to do.
- `Core/.gitignore`: `*/code/`, `.env*`, `.DS_Store`.
- Hooks in .git/hooks are not versioned: `scripts/install-hooks.sh` installs them; the skill
  checks they are present.

## 7. Project CLAUDE.md (up to ~150 lines)
Purpose (1–2 sentences), stack, build/test/run commands (run from code/), folder layout,
rules, link to `docs/INDEX.md` as plain text (no @-import). Rules:
- all code, comments and Markdown in English; talk to the user in their language
  (from Claude settings or instructions; otherwise the language they write in);
- after changing a feature, update its page in docs/features/ and its `updated` field;
- a new architectural decision → a new docs/decisions/NNN-*.md;
- after each working step — two commits: in `code/` and in `Core` (command given);
- never read .env or ~/.ssh.

## 8. Wiki
Every docs/ page starts with YAML front matter: title, description (what is inside and when
to read it), status, files, related, updated. INDEX.md has one line per file.
Rules in `.claude/rules/*.md` use `paths:` relative to the project folder, e.g. `code/test/**`
for tests.md.

## 9. Skill contents (CoreKit)
```
skills/new-project/
  SKILL.md                    ← short: the flow and links to references
  references/interview.md     ← interview questions
  references/analysis.md      ← analysis criteria, fallback without Superpowers, subagent prompt
  references/stacks.md        ← starting stack options and generator commands
  templates/                  ← CLAUDE.md, docs/*, rules/*, gitignore/*
  scripts/scaffold.sh         ← creates the structure from templates
  scripts/install-hooks.sh, hooks/pre-commit-code, hooks/pre-push-core
install.sh                    ← copies skills/* to ~/.claude/skills/
```

## 10. Out of scope for v1
Migrating existing projects to the standard (an `adopt-project` skill), updating old projects
when templates change, PowerShell versions of the scripts for Windows.

## 11. Verification
- Evals (skill-creator): fires on 8+ phrases, does not fire on 8+ unrelated phrases;
  2 scenarios (Flutter for 4 platforms; a Mac-only utility).
- Dry run on `~/Projects/Core/test-new-project`: layout, YAML front matter, hook blocks
  CLAUDE.md in code/, both commits exist.
- GitHub and a real build — the user checks on the Mac following the instructions.
