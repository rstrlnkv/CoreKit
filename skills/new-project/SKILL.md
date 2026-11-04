---
name: new-project
description: Use when the user wants to start a new app, program, bot, website or other software project from scratch — phrases like "новый проект", "new project", "давай сделаем приложение", "start a new app", "хочу сделать бота" — before any project folder or code exists. Not for adding features to an existing project, and not for creating projects in Jira, Notion or other tools.
---

# New project

## Overview
Turns an idea into a project that follows one standard: interview → analysis → recorded
decisions → scaffold → GitHub → build check. **Core principle:** internal files (CLAUDE.md,
docs/, .claude/) live in a private docs repo and physically never sit inside the code repo,
so a public code repo cannot leak them.

Scripts live in this skill's `scripts/` and in the plugin's `scripts/`. Run them with `bash` and
pass the Core location: `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/scripts/<script>"`.

## Language
- Talk to the user in their language (from their Claude settings or instructions; otherwise the
  language they write in), in plain words; explain a term the first time you use it.
- Write **everything on disk in English**: code, comments, every Markdown file, commit messages.
  After writing a document, show a 2–4 line summary of it in chat in the user's language.

## Settings
Claude Code asks for the plugin options when the plugin is enabled. The Core setting is
`${user_config.core_dir}`. A value that still reads literally `${user_config.` means the plugin is
unconfigured: treat it as unset; the scripts then use the default `~/Projects/Core`. Below,
`<Core>` means the absolute Core path resolved once in stage 0 (when resuming at a later stage,
resolve it first the same way), `<CoreName>` its last path component, `<Projects>` its parent folder (where the code repos live), `<prefix>` the app id prefix
stored in `<Core>/.coredev`:
`CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" get app-id-prefix`
(empty until the user has given one).

## Layout (do not improvise another one)
```
<Core>/                          private GitHub repo <CoreName> (default ~/Projects/Core)
  .coredev, PROJECTS.md, README.md, standards/, knowledge/
  <name>/CLAUDE.md, docs/
<Projects>/<name>/               beside the Core (<Projects> = parent of <Core>): separate git repo "<name>";
                                 Claude Code is launched here; CLAUDE.local.md -> <Core>/<name>/CLAUDE.md
```

## Stages
Progress lives in `stage:` in `<Core>/<name>/docs/brief.md`. If the user mentions a project that
already has a brief, read it and resume at the next stage instead of starting over.

| stage | next step |
|-------|-----------|
| (none) | 0 Preflight, 1 Interview, 2 Name |
| interviewed | 3 Analysis |
| decided | 4 Scaffold |
| scaffolded | 5 GitHub, 6 Verify |
| ready | 7 Offer a plan |

Suggest a fresh session between "decided" and "scaffold" when the conversation is long.

## Steps
A stage advances only when its step really succeeded. If a generator, build or `gh` command
cannot run (tool missing, error), stop at the current stage, explain in plain words what to
install or fix, and give the exact command; do not mark the stage done.

**0. Core and preflight.** First resolve `<Core>` once, to an absolute path (the setting may
start with `~`), and use that path in every command below:
`CORE_DIR='${user_config.core_dir}' bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" core-dir`.
Then check that the Core is set up:
`CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" ready`
(exit 0 = set up; it means `<Core>/.coredev` has a `schema:` line). If it fails, tell the user in
plain words that a one-time setup is needed and list what it creates in `<Core>`: a git repo
(only on this computer; nothing goes to GitHub), `.gitignore`, `README.md`, `PROJECTS.md`,
`standards/README.md`, `knowledge/README.md` and `.coredev`, in one commit "Set up Core". Existing
files are never overwritten. Wait for their "ok", then run
`CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/setup-core.sh" "<Core>"`.
Then preflight: `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh"`.
Explain any FAIL in plain words with the fix; WARN about
non-Latin paths means Android/Flutter builds may break — say so. Stop on FAIL.

**1. Interview.** Follow `references/interview.md`: 2–3 questions per AskUserQuestion call.
Never ask the user to pick a stack.

**2. Name.** Propose a name (Latin, lowercase, hyphens, 3–40 chars) and a one-sentence purpose
in English. Get approval (the app id prefix is not needed yet; it is asked in stage 4). `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --name <name>` — stop if taken. Then
`CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/scripts/scaffold.sh" --name <name> --purpose "<purpose>"` creates the folders, both git
repos and the docs skeleton. Fill `docs/brief.md` with the answers (English), set
`stage: interviewed`.

**3. Analysis.** Follow `references/analysis.md` and `references/stacks.md`: constraints → 2–3
scored stack options with one recommendation → research subagent verifies them → architecture.
Get approval for each part. Write `docs/architecture.md` and
`docs/decisions/001-stack-and-architecture.md`; add a line to `docs/INDEX.md` for every new page
(see Wiki); set `stage: decided`.

**4. Scaffold.** First the app id prefix: if the chosen stack uses `<org>` in
`references/stacks.md` and `<prefix>` (see Settings) is empty, ask for it (`com.<their-name>`,
never invent it) and save it with
`CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" set app-id-prefix <prefix>`.
This runs on every entry to stage 4, so it also happens when resuming at `decided`. Generate the app with the stack's command from `references/stacks.md` **in a temp
dir**, then `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/scripts/merge-generated.sh" <tmp>/<folder> "<Projects>/<name>"`. Never run a
generator with `--force`/`--overwrite` in the code folder. Fill the Build/Test/Run and Stack sections of
`CLAUDE.md` (leave the `check:` line for stage 6). `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/install-hooks.sh" "<Core>/<name>"`. Then from `<Projects>/<name>`:
`bash "${CLAUDE_SKILL_DIR}/../../scripts/save" "Scaffold <stack> project"`. Set `stage: scaffolded`.

**5. GitHub.** Ask separately before each repo is created, naming it and its visibility:
- docs repo (once): `gh repo create <CoreName> --private --source "<Core>" --push`
- code: `gh repo create <name> --private --source "<Projects>/<name>" --push`; use `--public`
  only if the user said "public" in the interview.

**6. Verify.** Run the stack's check command from `references/stacks.md` (from `<Projects>/<name>`). Once the
first build and that command succeed, replace the placeholder line `check: <set after scaffolding>`
in `<Core>/<name>/CLAUDE.md` with the real single command, e.g. `check: flutter test` (the one
test/check command, run in `<Projects>/<name>`; hooks and the verifier read it). Then run
`bash "${CLAUDE_SKILL_DIR}/../../scripts/wiki-check.sh" "<Core>/<name>"` and fix every
`wiki-check:` line it prints (silent = green). Set `stage: ready` and `save "Ready"`. Report in the user's language: what was created and where; how to open it
(`cd <Projects>/<name> && claude`); how to check it themselves; what may break.

**7. Offer a plan.** Offer a v1 plan with `superpowers:writing-plans`, saved to
`../docs/superpowers/plans/`. Do not write app features in this skill.

## Wiki
The docs are a wiki; the rules are in `${CLAUDE_SKILL_DIR}/../../reference/wiki.md` (read it before
writing pages). In short: `docs/INDEX.md` has one map line per page, pages carry the six
front-matter fields, and `wiki-check.sh` must stay green. Whenever a page is added (a feature page
under `docs/features/`, any other page), add its map line to `docs/INDEX.md` in the same step. A new
decision is a new file `docs/decisions/NNN-<slug>.md` plus a map line. `docs/knowledge/`,
`docs/standards/` and `docs/superpowers/` are outside the wiki checks. The format of
`docs/knowledge/` is in `${CLAUDE_SKILL_DIR}/../../reference/knowledge.md`.

## Red flags — stop
| Thought | Reality |
|---------|---------|
| "One repo is simpler" | CLAUDE.md and docs in the code repo leak the moment it is public. Use the layout. |
| "The stack is obvious" | Show 2–3 scored options anyway; the user approves, not you. |
| "I'll write the first features now" | This skill ends at a building empty project + optional plan. |
| "Docs in the user's language are friendlier" | Files are English; summaries in chat are in their language. |
| "The user said ok earlier, I'll create the repo" | Each `gh repo create` needs its own approval. |
| "Faster to use --force in the code folder" | It deletes `.claude/` and `.gitignore`. Generate in a temp dir. |

## Quick reference
Every `…` below stands for `CORE_DIR="<Core>"`.
| Need | Command |
|------|---------|
| App id prefix | `… bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" get\|set app-id-prefix [<prefix>]` |
| Check tools / name | `… bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" [--name <name>]` |
| Core set up? / set up | `… bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" ready` · `… bash "${CLAUDE_SKILL_DIR}/../../scripts/setup-core.sh" "<Core>" [--dry-run]` |
| Create skeleton | `… bash "${CLAUDE_SKILL_DIR}/scripts/scaffold.sh" --name <name> --purpose "<text>" [--dry-run]` |
| Copy generated app | `… bash "${CLAUDE_SKILL_DIR}/scripts/merge-generated.sh" <generated> <code>` |
| Protective hooks | `… bash "${CLAUDE_SKILL_DIR}/../../scripts/install-hooks.sh" <project_dir>` |
| Save / undo a step | `bash "${CLAUDE_SKILL_DIR}/../../scripts/save" "<msg>" [--push]` · `bash "${CLAUDE_SKILL_DIR}/../../scripts/undo-step"` |
