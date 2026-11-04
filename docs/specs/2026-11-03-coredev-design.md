---
title: coredev plugin — design spec
description: Requirements for renaming the corekit plugin to coredev and adding plugin settings, task (with release and adopt), new-standard, six agents, wiki and knowledge rules, and plugin hooks. Read before changing any of them.
status: draft
files: [.claude-plugin/plugin.json, .claude-plugin/marketplace.json, skills/, agents/, hooks/, reference/, scripts/, tests/]
related: [docs/specs/2026-11-02-new-project-design.md]
updated: 2026-11-03
---

# `coredev` plugin — design spec

## 1. Goal

One Claude Code plugin, `coredev`, in the `corekit` marketplace (repo `rstrlnkv/CoreKit`), that
any person can install to develop projects the same way every time, and whose crew gets better
from project to project:

- **CoreSkills** (`skills/`): `new-project`, `task`, `new-standard`.
- **CoreCrew** (`agents/`): engineer, tester, security, verifier, localizer, designer.
- **CoreHooks** (`hooks/hooks.json`): automation and guardrails.

**Principle: the user's Core holds only the user's data; all machinery lives in the plugin.**
The plugin carries nothing personal — no standards, no session rules, no paths, no project
names. What a user decides is either a plugin setting (§5) or a file in their Core.

Install: `/plugin marketplace add rstrlnkv/CoreKit`, then `/plugin install coredev@corekit`.
Three commands: `/coredev:new-project`, `/coredev:task <task>`, `/coredev:new-standard`.

The old crew (`github.com/rstrlnkv/CoreCrew`, read-only) is a source of lessons, not of files.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The orchestrator is a skill (`task`) in the main session, not a subagent. | The old `lead` subagent re-read everything on every step and was most of the cost; in the main session it can talk to the user. |
| D2 | Six agents; localizer stays separate from designer. Old `product`, `architect`, `lead`, `release` are not agents. | Owner's choice; architect/explorer come from feature-dev (D3), lead and release are `task` (D1, §10). |
| D3 | coredev uses one other plugin, `feature-dev` (`code-architect`, `code-explorer`). It is not declared as a hard dependency: a hard dependency stops coredev loading when feature-dev comes from claude.ai sync or another marketplace; `task` checks for it at start. superpowers is not a dependency. | No duplicate roles. superpowers' brainstorming may only hand over to writing-plans, and its session hook pulls work away from the chain. |
| D4 | Commit attribution is a setting (`attribution`: `allow` or `forbid`). With `forbid`, release checks there are no `Co-Authored-By` / `Generated with` lines. The owner sets `forbid`. | A personal rule must not be hard-coded in a universal plugin. |
| D5 | Knowledge lines are shown in the `task` report and written only after the user's "ok", with a choice "this project / all projects". | The user does not read code; the report is where they approve. |
| D6 | Only `task` and `new-standard` are command-only (`disable-model-invocation: true`); `new-project` triggers by meaning as today. Setup and release are not commands: they run inside `new-project` / `task`. | Fewer commands to remember; no per-turn description cost; no fights with other planning skills. |
| D7 | `guard-code` blocks internal files inside every `<Core>/<project>/code/`, public or private, without network. | A repo that becomes public later must not already hold leaked files. |
| D8 | The end-to-end test project `<Core>/test-coredev/` is hand-made and minimal (no GitHub). | Fast, cheap, deterministic. |
| D9 | Standards are plain files read by path. Each agent reply carries a `Standards:` line; `task` returns a reply without it once. | Owner's choice; the line makes skipped reading visible. |
| D10 | The plugin ships no standards. All standards are the user's, in `<Core>/standards/`; the plugin helps write them (`new-standard`). | Universal plugin; nothing to go stale. |
| D11 | coredev works only inside the Core layout. A project outside it is brought in by `/coredev:task adopt <folder>` (v1). | The layout keeps internal files out of code repos; people with existing code must not be refused. |
| D12 | Setup is the plugin's `userConfig` (asked by Claude Code when the plugin is enabled) plus a skeleton step that `new-project` and `task` run when Core is missing. | No plugin-install hook event exists; Claude Code already provides settings prompts and storage. |
| D13 | Wiki rules are part of the plugin (`reference/wiki.md`). engineer keeps the wiki; verifier and `wiki-check.sh` check it; release refuses a red wiki. | Agents must create and keep the wiki map correctly from the start. |
| D14 | Session rules are the user's file `<Core>/session-rules.md`, printed at session start. | Same principle as D10. |
| D15 | Knowledge has two levels: per project and for all projects (`<Core>/knowledge/`). A lesson that recurs is offered as a standard. | Lessons from one project must reach the crew in the next one. |
| D16 | Scripts (`save`, `undo-step`, git hook bodies) are not copied into Core. The plugin keeps a stable copy in its data folder and refreshes it on version change. | Copies in Core never updated. |
| D17 | Outside `<Core>` no hook blocks or changes anything; session-start only refreshes the plugin's own tools and shows the one-time "Core not found" hint. | A plugin must not change behaviour in the user's unrelated folders. |

## 3. Language policy

- Everything on disk is English: code, comments, Markdown, commit messages, agent files.
- Skills and agents talk to the user in the user's language (from their settings or
  instructions, otherwise the language they write in), in plain words.
- Report field labels (`Path:`, `Proof:` …) stay English so tests can check them.

## 4. Layout

### 4.1 The plugin (this repo, public)
```
.claude-plugin/
  plugin.json          name "coredev", version 0.2.0, userConfig (§5); no `dependencies` (D3)
  marketplace.json     marketplace "corekit"; plugin "coredev"; renames {"corekit": "coredev"}
skills/
  new-project/         as today; uses scripts/setup-core.sh; wiki templates per §8
  task/                SKILL.md; references/: paths.md, brief.md, report.md, release.md, adopt.md
  new-standard/        SKILL.md; references/template.md
agents/                engineer tester security verifier localizer designer
hooks/
  hooks.json           five hooks (§14), explicit timeouts
  session-start.sh one-suite.sh guard-code.sh guard-secrets.sh stop-remind.sh
reference/
  wiki.md              wiki rules (§8)
  knowledge.md         knowledge format (§12)
scripts/               all machinery, portable bash
  lib.sh               read settings, parse hook JSON without jq, locate <Core> and project
  setup-core.sh        create or upgrade the Core skeleton (§5.2)
  adopt.sh             move an existing project into the layout (§11)
  wiki-check.sh        wiki checks (§8.3)
  check-standard.sh    standard file checks (§7.3)
  save, undo-step      one step = code + docs commit / revert (moved from new-project/core-bin)
  git-hooks/           pre-commit-code, pre-push-code, pre-push-core, blocked-patterns
tests/                 bash: lib.sh, test_*.sh, run.sh, fixtures/
evals/                 trigger evals (new-project)
```
No top-level `bin/` (claude.ai and Cowork refuse plugins that have one). `install.sh` is removed.
No symlinks or copies into project trees, no `@`-imports. Skills reach plugin files through
`${CLAUDE_SKILL_DIR}/../../<path>`.

### 4.2 The plugin's data folder (`${CLAUDE_PLUGIN_DATA}`, kept across updates)
```
~/.claude/plugins/data/coredev-corekit/
  tools/               stable copies of scripts/save, undo-step, lib.sh, git-hooks/*
  tools/VERSION        plugin version the copies came from, and a checksum of their content
  state/               markers (e.g. "Core-missing hint shown once")
```
`session-start.sh` refreshes `tools/` when the version or the content checksum in `VERSION`
differs from the plugin's (or the copy was edited). It never replaces a non-empty `tools/` that has
no `VERSION` (not ours): it reports it and leaves it. Git hooks
installed in repos are two-line shims that run `tools/git-hooks/<name>`; if that file is missing
they block with a message that names the fix ("start Claude Code once with coredev enabled") and
how to remove the shim.

### 4.3 The user's Core (private)
```
<Core>/                              git repo; private on GitHub if pushed
  .coredev                           "schema: 1" — layout version (§15)
  PROJECTS.md  README.md  .gitignore
  standards/<name>.md                the user's standards (§7)
  knowledge/<role>.md                lessons for all projects (§12)
  session-rules.md                   optional (§14.1)
  <project>/CLAUDE.md                includes one line "check: <command>"
  <project>/docs/INDEX.md, brief.md, architecture.md, decisions/, features/
  <project>/docs/knowledge/<role>.md lessons for this project
  <project>/docs/standards/<name>.md optional project exceptions
  <project>/.claude/rules/
  <project>/code/                    the code: its own git repo; Claude Code is launched here
```
Existing `Core/bin/` and `Core/hooks/` from 0.1.x are left as they are (user files); nothing new
is written there.

## 5. Settings and setup

### 5.1 Plugin settings (`userConfig` in `plugin.json`)
Claude Code asks them when the plugin is enabled; the user changes them later in `/plugin` →
Installed → coredev → Configure options.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `core_dir` | directory | `~/Projects/Core` | where Core lives |
| `attribution` | string, options `allow` / `forbid` | `allow` | D4 |
| `model_profile` | string, options `economy` / `balanced` / `strong` | `balanced` | models per role (§13.3) |

Hooks read them as `CLAUDE_PLUGIN_OPTION_<KEY>`; skills and agents as `${user_config.<key>}`.
Scripts get values as arguments from the skill. `APP_ID_PREFIX` stays a `new-project` question,
saved in `<Core>/.coredev` as `app-id-prefix:` (per user, rarely needed).

Found in phase 1 (live check, Claude Code 2.1.316, `claude -p --plugin-dir`, unconfigured):
`${user_config.*}` placeholders stay literal in skill text (`${CLAUDE_SKILL_DIR}` is
substituted), and hooks get no `CLAUDE_PLUGIN_OPTION_*`. Scripts therefore treat a value that
still contains the literal `${user_config.` as unset (`load_settings`: option, then default).
Skills single-quote the placeholder in shell commands (`CORE_DIR='${user_config.core_dir}' bash …`):
a double-quoted literal is a "bad substitution" in bash and zsh. Files a skill opens with Read get
nothing substituted, so `task` notes the resolved values (plugin folder, attribution, model
profile) once at Start and its reference files use `<plugin>`, `<scripts>` and those values.
The data folder id under `--plugin-dir` is `coredev-inline` (installed from the marketplace:
`coredev-corekit`). A plugin with a hard dependency does not load when the dependency comes from
claude.ai sync (`feature-dev@synced`): "unmet dependency" (D3).

To confirm when installed from the marketplace: that `${user_config.*}` is substituted once the
plugin is configured; `~` expansion in a `directory` default; that a CLI install (which does not
prompt) falls back to the defaults.

### 5.2 Core skeleton (`scripts/setup-core.sh <core_dir>`)
Run by `new-project` and `task` when `<core_dir>/.coredev` is missing, after showing the user
what will be created and getting "ok". Creates `<Core>` as a git repo with the top level of
§4.3, `standards/README.md` (what a standard is; `/coredev:new-standard` makes one),
`knowledge/README.md`, `.coredev`, and commits. Idempotent: prints `created`/`skipped` per item,
never overwrites a user file, never creates a GitHub repo without a separate approval. On an
older Core it only adds what is missing and updates `.coredev` (§15).

## 6. Rename and migration

- `plugin.json` name `coredev`, version `0.2.0`; `marketplace.json` lists `coredev` with
  `"renames": {"corekit": "coredev"}`. Verified: renames migrate marketplace installs; for a
  git-hosted marketplace each user runs `/plugin install coredev@corekit` once; users get new
  commits only when `version` changes; auto-update is off by default for third-party
  marketplaces.
- Plugin-name mentions (`corekit` plugin, `/corekit:`) in README, CLAUDE.md, skills, tests become
  `coredev`; marketplace and repo names stay. CHANGELOG gets a 0.2.0 entry.
- `docs/migration-0.2.md`, for an existing user (the owner's two machines):
  1. update the marketplace and install `coredev@corekit`; if corekit came through claude.ai
     sync, disable it there (exact steps verified in phase 1);
  2. set the three settings (owner: `attribution` = `forbid`);
  3. remove the old manual skill copy `~/.claude/skills/new-project` if it has the `.corekit`
     marker;
  4. remove the `Stop` hook block from each existing `code/.claude/settings.local.json` (the
     plugin ships it now);
  5. re-install git hooks as shims (session start prints the command when it finds an old hook);
  6. move personal rules into `<Core>/session-rules.md`; turn on auto-update for the `corekit`
     marketplace in `/plugin` → Marketplaces;
  7. restart Claude Code.

## 7. Standards (the user's)

### 7.1 Format (`skills/new-standard/references/template.md`)
`<Core>/standards/<name>.md`, English, at most 120 lines:
```
---
name: <kebab-case>
description: <one line: what it rules and when an agent needs it>
applies-to: [<roles that must read it>]   engineer tester security verifier localizer designer release
updated: YYYY-MM-DD
---
# <Title>
## Rule            numbered, one rule per line, imperative
## Why             one line per rule: the failure it prevents
## How to check    per rule number: `n. <command> → <expected output>` or `n. no guard — <risk>`
## Exceptions      or "none"
## Sources         what the rules rest on
```

### 7.2 Lookup
An agent that needs standard `<name>` reads `<Core>/<project>/docs/standards/<name>.md` if it
exists, otherwise `<Core>/standards/<name>.md`; none → `Standards: none in Core` for it.

### 7.3 `/coredev:new-standard [topic | knowledge line]`
1. Interviews the user one question at a time (what must always be true, what went wrong, which
   roles need it). Started from a knowledge line (§12.3), the draft is pre-filled from it.
2. Asks for optional sources (e.g. the owner's old CoreCrew development standard) and reads them.
3. Sends one research subagent (general-purpose, web) for current best practice; cited in
   `## Sources`.
4. Shows the draft in the user's language; on "ok" writes `<Core>/standards/<name>.md` (an
   existing standard: shows `diff -u` and needs a second "ok" before overwriting), runs
   `scripts/check-standard.sh <file>` (front matter, five sections in order, a check per rule,
   known roles, no leftover placeholders or comments, at most 120 lines; exit 0/1 with a list) until it is silent, then commits only
   that file in Core: `git -C <Core> add standards/<name>.md && git -C <Core> commit -m "Add
   standard <name>"` (`Update standard <name>` for an existing one). Not through `save`: `save`
   needs a project. Never pushes.
5. Never writes into the plugin.

### 7.4 The owner's first standards (phase 2, in the owner's Core, not in CoreKit)
- `versioning` — from the old development standard §2: build number = commit count, refuse when
  the history cannot be counted; tags `vMAJOR.MINOR.PATCH[-dev.N]`; never re-tag. No project names.
- `about-screen` — built from the interview (no old standard exists).

## 8. Wiki

### 8.1 Rules (`reference/wiki.md`)
- `docs/INDEX.md` is the map: one line per page, `- [Title](path.md) — what it is for.`
  A reader reads the map, then one page.
- One subject per page; flat folders (`features/`, `decisions/`). A page over ~8 KB without
  `##` headings is a defect.
- Pages start with front matter `title`, `description`, `status`, `files`, `related`, `updated`.
  `files:` lists code paths (relative to `code/`) the page describes.
- One reference form: `docs/<page>.md § <exact heading>`. Headings are unique within a page.
  "See above" or "this document" are defects.
- No history (git has it), no dated measurements, no number without the command that prints
  it, no copy of another page or of `CLAUDE.md`. One home per fact.
- A new architectural decision → a new `decisions/NNN-<slug>.md`.
- Outside the wiki checks: `docs/knowledge/`, `docs/standards/`, `docs/superpowers/`.
- A user standard `<Core>/standards/wiki.md`, if present, wins over this file.

### 8.2 Who does what
- Every agent reads `CLAUDE.md`, then `docs/INDEX.md`, then the page its task needs.
- engineer is the only author of wiki edits: when a change touches a code file it updates every
  page whose `files:` lists it (content and `updated`), adds a map line for a new page and a
  decision file for a new decision.
- verifier runs `wiki-check.sh`; release refuses to commit when it is red.
- `new-project` and adopt create a wiki that passes `wiki-check.sh` (a test enforces it).

### 8.3 `scripts/wiki-check.sh <project-dir> [--changed <file>...]`
Prints `wiki-check: <file>: <problem>` per failure; exit 0/1:
1. every wiki page has the six front matter fields;
2. `INDEX.md` links exactly the wiki pages on disk;
3. every link and every `§ heading` reference in `docs/` and `CLAUDE.md` resolves;
4. no heading appears twice within one page;
5. no page over 8 KB without `##` headings;
6. with `--changed`: a changed code file listed in some page's `files:` while that page is not
   among the changed files → `drift`.
Tests: one good fixture wiki, one broken fixture per check, and a fresh `new-project` wiki.

## 9. `task` — the orchestrator (`/coredev:task <task>`)

### 9.1 Start
1. Resolve Core from `${user_config.core_dir}`; no `.coredev` there → setup (§5.2).
2. Resolve the project: the working directory must be inside `<Core>/<project>/`. Otherwise:
   the adopt path goes to §11; any other task gets one line offering `/coredev:new-project` or
   `/coredev:task adopt <folder>`.
3. Check that `feature-dev:code-architect` and `feature-dev:code-explorer` are in the agent
   list; missing → name the install command; paths that need them stop.
4. Read `CLAUDE.md` (with its `check:` line); list names in `<Core>/standards/`,
   `<Core>/knowledge/`, `docs/knowledge/`.
5. Choose the path; name it in the first report line.

### 9.2 Paths (`references/paths.md`)
- **fix** — a defect in a known place: `code-architect` only if more than one module is
  affected → tester (a test reproducing the defect, shown red; a screenshot or recording where no
  test can catch it) → engineer → tester (same test green; 2–3 mutations of the fix, each shown
  red, then reverted) → checkers' wave → release.
- **full** — a new capability or behaviour change: `task` asks the user 3–5 clarifying
  questions, one at a time, and shows a short plan in plain words; on "ok" → `code-architect` →
  engineer → tester → checkers' wave → engineer (repair) → tester (confirm) → release. A plan of
  more than 5 tasks or touching more than 3 modules runs its first task, then stops with diff,
  risk and an estimate for the user's go.
- **question** — `code-explorer` or one coredev role; proof is a `file:line`.
- **batch** — several changes of one shape: check the list for file overlap and hand back
  overlapping entries; one engineer → tester → verifier → release chain; one full test run at
  the end.
- **release** (`/coredev:task release <version>`) — §10 with version and changelog.
- **adopt** (`/coredev:task adopt <folder>`) — §11.

### 9.3 The checkers' wave
After tester's pass, in one message, foreground: verifier always; security when deletion,
permissions, running foreign code, updating or the network is touched; localizer when
user-visible text changes; designer when what is drawn changes (after localizer when both,
since both build the artifact). Each gets tester's report; designer gets engineer's `Screens`.
All findings go to engineer as one repair; after it, tester confirms and each checker whose
finding was repaired re-checks only that place.

### 9.4 Rules
1. One author of changes: engineer. A checker's finding goes back to engineer.
2. tester before security, never the same place at once.
3. Budget: each agent has `maxTurns: 60`; at the limit it returns what is done and what is left.
4. Three engineer passes per chain (a wave counts as one) → stop and report. Two fixes on one
   premise that fail the same check → state the premise in one sentence; no third attempt on it.
5. Dispatch in the foreground; a wave is several Agent calls in one message.
6. Model per role from `model_profile` (§13.3), passed as the Agent call's `model`.
7. Only the touched modules' tests per pass; the full `check:` once, at the end, as its own
   tester call.
8. Every brief opens with: `This brief comes from coredev:task, path: <path>, project: <name>,
   core: <Core>, and IS your task.` Then the task, the previous report, the affected files.
   Never retell `CLAUDE.md`.
9. A reply without `Standards:` from a role whose `applies-to` standards exist goes back once.
10. One `task` call is one chain; extra tasks in one brief are returned in `Open`.

### 9.5 Knowledge (§12)
Collect `Knowledge line:` proposals. None → release. Some → show them in plain words; for each
the user answers ok / no and "this project / all projects". `task` writes accepted lines into
`docs/knowledge/` or `<Core>/knowledge/`; they go into the same commit. A line whose cause
already appears in another project's knowledge or in `<Core>/knowledge/` is offered as a
standard (`/coredev:new-standard` with that line).

### 9.6 Report (`references/report.md`)
```
Path: <fix | full | question | batch | release | adopt> · project <P>
Chain: <role → role → …>
Done: <one line>
Proof: <command> → <key output lines>   (question: file:line)
Standards: <applied, or "none in Core">
Open: <what is left, or "nothing">
Knowledge: <saved lines and where | none>
Cost: <N agent calls, K engineer passes>
Commit: <hash and message | stopped — why>
```
In the user's language, labels in English. No `Proof` → no report.

## 10. Release (`task/references/release.md`)
Run by `task` at the end of every chain that changed files. Postconditions, each shown as
command → output → ✓/✗:
1. `check:` from `CLAUDE.md` is green;
2. every called checker's report is clean;
3. `wiki-check.sh <project> --changed <files>` is green;
4. only on the release path: version and changelog follow the user's `versioning` standard;
   none → ask the user;
5. commit through `save`: code and docs as one step, message in English (what and why);
6. with `attribution=forbid`: `git log --format=%B <range> | grep -icE '^[[:space:]]*(co-authored-by:|(🤖[[:space:]]*)?generated with)'` → `0`;
7. `git status --short` clean in `code/` and in the Core paths `save` commits (`lib.sh core-paths
   <project>`: the project folder and the shared files; `task` Start checks the same set).
One ✗ → stop; the finding goes to engineer; no second cycle. Never tags, never pushes.

## 11. Adopt (`/coredev:task adopt <folder>`, `scripts/adopt.sh`)
1. Inspect: the folder must be a git repo with a clean tree; read its name, `CLAUDE.md`,
   `AGENTS.md`, `docs/`, `.claude/`. Show the plan in plain words; wait for "ok".
2. Create `<Core>/<name>/`; copy `CLAUDE.md`, `AGENTS.md`, `docs/` and `.claude/` (except
   `settings.local.json` and `worktrees/`) there, then remove them from the repo in one commit
   (revertible). The same commit appends to the repo's `.gitignore` the coredev lines of the
   new-project template it lacks (`CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.claude/`, `docs/superpowers/`,
   `.env`, `.env.*` and the `.env` template exceptions); user lines are never changed or removed. Docs the user wants to keep public stay in the repo and are listed in
   `<Core>/<name>/CLAUDE.md` as `public-docs: <paths>` (`guard-code` allows them).
3. Move the repo folder to `<Core>/<name>/code` (`mv`; history unchanged). Refuse if the target
   exists. Print the old and new paths.
4. Add `check:` to `CLAUDE.md` (detected, confirmed by the user), create the wiki map and missing
   pages per §8, `docs/knowledge/`, install git hook shims, add the `PROJECTS.md` line, commit in
   Core.
5. `wiki-check.sh` green; report with the new folder to open Claude Code in.

## 12. Knowledge (`reference/knowledge.md`)

### 12.1 Where
- `<Core>/<project>/docs/knowledge/<role>.md` — this project;
- `<Core>/knowledge/<role>.md` — all projects.

### 12.2 Format
Each `<role>.md` ≤ 80 lines, four sections: How proof is made here · Where things are · What has
broken here · What you must not do here. A family of cases gets `<role>/<Family>.md`, one case
per line: `symptom → cause → guard address | no guard`, optionally tagged with a stack, e.g.
`[swift]`. The role file links it: `- [Family](<role>/Family.md): symptom → cause`.

### 12.3 Life cycle
Agents propose (`Knowledge line:`); the user approves and chooses the level (§9.5); `task`
writes. Agents read the project file, then the all-projects file, skipping lines tagged with
another stack. A lesson that recurs becomes a standard through `new-standard`.

## 13. Agents (`agents/<role>.md`, ≤ 60 lines each)

### 13.1 Template
```
---
name: <role>
description: <one short line: the question it answers and when to call it>
model: <the balanced-profile default>
tools: <only what the role needs>
disallowedTools: Agent
maxTurns: 60
---
## Question
## What to show
## What to read first
## How you work
## What not to do
## Reply format
```
- No user paths, project names, platform or dates; paths come in the brief (§9.4.8).
- What to read first: `CLAUDE.md` → `docs/INDEX.md` → the page the task needs → its standards
  (§7.2) → `docs/knowledge/<role>.md`, then `<Core>/knowledge/<role>.md` ("no knowledge" if none).
- How you work keeps the shared practice in 2–3 lines: runs in the foreground and waited for; a
  refused test run is retried, never polled; logs go to a file, read by range; independent
  checks in one Bash call.
- Answer in the user's language; write files in English.
- Every reply format ends with `Standards: <name — the rule applied, quoted | none needed |
  none in Core>` and `Knowledge line: <symptom → cause → guard | none>`.

### 13.2 Roles
| Agent | Tools | Essence |
|---|---|---|
| engineer | Read, Edit, Write, Grep, Glob, Bash | The only author of changes, wiki included (§8.2). Shortest code that does it the way the project does it; red test first. Proof = command + output. Never commits; never weakens a check. Reports `Screens` for UI work. |
| tester | Read, Edit, Write, Grep, Glob, Bash | Writes only checks. Fix path: red first, then green + 2–3 mutations. A test that passes on empty returns is hollow. Feeds the inputs nobody fed. |
| security | Read, Grep, Glob, Bash | From dangerous operations to their inputs; a finding needs a path input → effect, otherwise "Not checked". |
| verifier | Read, Grep, Glob, Bash | Resolves every address, number, quotation and conditional in the change's prose by a command; runs `wiki-check.sh`; lists what the change left dead. |
| localizer | Read, Grep, Glob, Bash | Reads text back out of the built artifact, key by key, language by language. |
| designer | Read, Grep, Glob, Bash | Measures the rendered screen (size, contrast, hit area, states); at most 6 images per call; starts from engineer's `Screens`. |

### 13.3 Model profiles
| Role | economy | balanced | strong |
|---|---|---|---|
| engineer, tester | haiku | sonnet | sonnet |
| security, verifier, localizer, designer | sonnet | sonnet | opus |

`task` passes the model on each Agent call; the frontmatter `model` is the balanced default.

### 13.4 To verify in phase 4
`maxTurns`, `disallowedTools` and a per-call `model` for plugin agents; the exact
`subagent_type` (`coredev:engineer` expected). If `maxTurns` is not honoured, the brief carries a
budget sentence instead.

## 14. Hooks (`hooks/hooks.json`)
Portable bash 3.2, BSD tools, no jq; input JSON on stdin; explicit `timeout` per hook. Plugin
hooks also fire inside subagents (verified). **Outside `<Core>` every hook exits 0 at once, except the two session-start items marked below
(D17).** Guards block with exit 2 and a message naming the right place; a hook that cannot parse
its input lets the call through, except where noted.

1. **session-start.sh** — `SessionStart` (startup, resume, clear, compact):
   - refreshes `${CLAUDE_PLUGIN_DATA}/tools/` when the version changed (§4.2) — this runs
     everywhere, since it touches only the plugin's own folder;
   - Core missing → once per machine (marker in `state/`; this also runs everywhere): `coredev: Core not found at <path> —
     /coredev:new-project or /coredev:task adopt <folder> will set it up`;
   - inside `<Core>/<project>/`: project name; paths of `docs/INDEX.md` and of the `save` /
     `undo-step` tools; standard names in one line; `<Core>/session-rules.md` if present; layout
     notes from §15 if `.coredev` is older; an old non-shim git hook → the re-install command.
2. **one-suite.sh** — `PreToolUse` Bash: a test run waits while another runs on the machine, then
   is refused with "run the same command again". Runners: swift test, xcodebuild test, npm/npx
   test, vitest, gradlew test, pytest, cargo test, flutter test, go test, `*tests?.sh`. Quoted
   text and heredoc bodies ignored; no `pgrep` → let through. The wait limit stays under the
   hook's `timeout`.
3. **guard-code.sh** — `PreToolUse` Write|Edit|MultiEdit|NotebookEdit (+ Bash, best effort): blocks
   `CLAUDE.md`, `AGENTS.md`, `docs/**`, `.claude/**` inside any `<Core>/<project>/code/**`, worktrees
   included; allows `.claude/settings.local.json`, `.claude/worktrees/**` and `public-docs:`
   paths (§11). Paths compared after resolving `..` and case-folding. Bash: `>`, `>>`, `cp`,
   `mv`, `tee`, `touch` targets; not complete — the git pre-commit hook stays the last layer.
4. **guard-secrets.sh** — `PreToolUse` Read|Grep|Glob|Edit|MultiEdit|Write|NotebookEdit|Bash: blocks `.env`, `.env.*`
   (allows `.env.example`, `.env.sample`, `.env.template`) and `~/.ssh/**`. Bash: best effort on
   command words with an explicit path; a recursive grep over a folder is not caught. Fails
   closed when the path matches but the JSON is odd.
5. **stop-remind.sh** — `Stop`: the existing "save the step" reminder, moved into the plugin;
   `new-project` stops writing it into `settings.local.json`.

Windows: hooks need Git for Windows (Git Bash); full support is a later subproject.

## 15. Updates
- Plugin updates arrive when `version` changes (auto-update on, or `/plugin` → Update now).
- An update never touches the user's data: Core, standards and knowledge stay as they are.
- Machinery refreshes itself (§4.2).
- `.coredev` holds the layout `schema`. When a new plugin version expects a newer schema, session
  start lists what to add (e.g. "add `check:` to <project>/CLAUDE.md") and `setup-core.sh` adds
  only what is missing. A stricter check never blocks old projects until the user agrees:
  release reports old-schema wiki problems as warnings.

## 16. Testing and done
- `bash tests/run.sh` green, one test file per part: `test_rename.sh`, `test_settings.sh`
  (userConfig), `test_setup_core.sh`, `test_adopt.sh`, `test_wiki_check.sh`,
  `test_new_standard.sh` (+ `check-standard.sh` fixtures), `test_task_skill.sh` (paths, report
  labels, release and adopt references, flags), `test_agents.sh` (≤ 60 lines, six sections,
  frontmatter, `Agent` disallowed, checkers without Edit/Write, closing lines), one
  `test_hook_<name>.sh` per hook (JSON fixtures, inside and outside Core, from a subagent),
  `test_tools_refresh.sh`, `test_no_personal.sh` (no home paths; no names from
  `$CORE_DIR/PROJECTS.md` when present — the list itself never enters the repo).
- `claude plugin validate .` green.
- `claude --plugin-dir .` loads: three commands, six `coredev:*` agents, the settings prompt.
- Installs from the marketplace on a clean Claude Code config, with feature-dev installed.
- End to end: `<Core>/test-coredev/` (hand-made: `CLAUDE.md` with `check:`, a wiki passing
  `wiki-check`, `code/` with a tiny bash script, its test and a planted bug);
  `/coredev:task fix <bug>` returns the §9.6 report with proof and a commit without attribution.
- Hand-over: exact install and update commands for Mac and Windows; what the owner commits to Core.

## 17. Phases (stop after each for the owner's check)
1. **Foundation:** rename and renames; `userConfig`; move scripts to `scripts/`;
   data-folder tools and git hook shims; `setup-core.sh`; `install.sh` removed; migration note.
2. **Wiki, knowledge, standards:** `reference/wiki.md`, `reference/knowledge.md`,
   `wiki-check.sh`, new-project wiki templates; `new-standard`; the owner's `versioning` and
   `about-screen` in their Core.
3. **task:** paths, brief, report, release, adopt.
4. **Agents:** the six agents and model profiles.
5. **Hooks:** five hooks; the owner's session rules into `<Core>/session-rules.md`.
6. **End to end:** `test-coredev`, adopt on a throwaway repo, marketplace install, hand-over.

## 18. Out of scope (next subprojects)
- Syncing machine settings (`settings.json` for Mac and Windows, personal `~/.claude/CLAUDE.md`).
- Windows / PowerShell support.
- The old crew's `ship` and `bloat-audit` skills, journal and autosync.

## 19. Risks
- A feature-dev rename breaks `full` and `question`; caught by `task`'s start check, not by tests.
- Bash guards are best effort (§14.3, §14.4); git hooks remain the last layer.
- Agents may skip reading standards; the `Standards:` line makes it visible, not impossible.
- `userConfig` behaviour for claude.ai-synced installs is not documented; checked in phase 1.
- Uninstalling coredev leaves git hook shims that block commits until coredev is enabled again
  or the shims are removed; their message says how.
