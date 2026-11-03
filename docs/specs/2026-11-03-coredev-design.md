---
title: coredev plugin — design spec
description: Requirements for renaming the corekit plugin to coredev and adding setup, task, release, new-standard, six agents, a wiki check and plugin hooks. Read before changing any of them.
status: draft
files: [.claude-plugin/plugin.json, .claude-plugin/marketplace.json, skills/, agents/, hooks/, reference/, tests/]
related: [docs/specs/2026-11-02-new-project-design.md]
updated: 2026-11-03
---

# `coredev` plugin — design spec

## 1. Goal

One Claude Code plugin, `coredev`, published in the `corekit` marketplace (repo
`rstrlnkv/CoreKit`), that any person can install to develop projects the same way every time:

- **CoreSkills** (`skills/`): procedures — `setup`, `new-project`, `task`, `release`,
  `new-standard`.
- **CoreCrew** (`agents/`): six subagents — engineer, tester, security, verifier, localizer,
  designer.
- **CoreHooks** (`hooks/hooks.json`): automation and guardrails.

The plugin is **universal**: it carries nothing personal — no standards, no session rules, no
user paths, no project names. Everything a user decides lives in that user's private docs repo
(`<Core>`). The old crew (`github.com/rstrlnkv/CoreCrew`, read-only) is a source of lessons,
not of files.

Install: `/plugin marketplace add rstrlnkv/CoreKit`, then `/plugin install coredev@corekit`.
Commands: `/coredev:setup`, `/coredev:new-project`, `/coredev:task`, `/coredev:release`,
`/coredev:new-standard`.

## 2. Decisions taken in brainstorming

| # | Decision | Why |
|---|---|---|
| D1 | The orchestrator is a skill (`task`) running in the main session, not a subagent. | The old `lead` subagent re-read everything on every step and was most of the cost; in the main session it can also talk to the user. |
| D2 | Six agents: engineer, tester, security, verifier, localizer, designer. localizer stays separate from designer. | Owner's choice. Old `product`, `architect`, `lead`, `release` are not agents (D3, D1, §10). |
| D3 | coredev depends on the `feature-dev` plugin (`code-architect`, `code-explorer`) and `superpowers` (`brainstorming` and friends). `task` checks they are present. | No duplicate roles; fewer descriptions in context. |
| D4 | No `Co-Authored-By` / `Generated with` lines in commits or PRs. `release` checks it. | Rule of the old development standard §7, kept by the owner. |
| D5 | Knowledge lines are shown in the `task` report; they are written and committed only after the user's "ok". | The user does not read code; the report is where they approve. |
| D6 | `task`, `release`, `setup`, `new-standard` run only by command (`disable-model-invocation: true`). | They have side effects; their descriptions cost nothing per turn; avoids competing with superpowers' brainstorming. |
| D7 | `guard-code` blocks internal files inside **every** `<Core>/<project>/code/`, public or private, without network. | A repo that becomes public later must not already hold leaked files. |
| D8 | The end-to-end test project `<Core>/test-coredev/` is hand-made and minimal (no GitHub). | Fast, cheap, deterministic; a failure points at `task`. |
| D9 | Standards are plain files, read by path (no `skills:` preloading). Each agent reply carries a `Standards:` line; `task` returns a reply without it once. | Owner's choice (approach B); the line makes skipped reading visible. |
| D10 | The plugin ships **no standards**. All standards are the user's, in `<Core>/standards/`. The plugin only helps write them (`new-standard`). | Universal plugin; no copies to go stale. |
| D11 | coredev works only inside the Core layout. Outside it, `task` refuses and points to `/coredev:new-project`. Adopting an existing project is a later subproject. | The layout is what keeps internal files out of code repos. |
| D12 | Core is created on first run by `/coredev:setup`; a SessionStart hook only notices that setup is missing. | There is no plugin-install hook event (verified, hooks reference); a hook cannot ask questions. |
| D13 | The wiki rules are part of the plugin (`reference/wiki.md`); engineer keeps the wiki, verifier and `wiki-check` check it, `release` refuses a red wiki. | The owner wants agents to create and keep the wiki map correctly from the start. |
| D14 | Session rules are the user's file `<Core>/session-rules.md`, printed by the SessionStart hook. The owner's old rules move there. | Same principle as D10. |

## 3. Language policy

- Everything on disk is English: code, comments, Markdown, commit messages, agent files.
- Skills and agents talk to the user in the user's language (from their settings or
  instructions, otherwise the language they write in), in plain words.
- Field labels of reports (`Path:`, `Proof:` …) stay English so tests can check them.

## 4. Layout

### 4.1 The plugin (this repo, public)
```
.claude-plugin/
  plugin.json          name "coredev", version 0.2.0 (version lives here)
  marketplace.json     marketplace "corekit"; plugin "coredev"; renames {"corekit": "coredev"}
skills/
  setup/               SKILL.md, scripts/ (config, core skeleton)
  new-project/         as today, minus the Core creation moved to setup
  task/                SKILL.md, references/paths.md, references/report.md, references/brief.md
  release/             SKILL.md
  new-standard/        SKILL.md, references/template.md, scripts/check-standard.sh
agents/                engineer.md tester.md security.md verifier.md localizer.md designer.md
hooks/
  hooks.json
  session-start.sh one-suite.sh guard-code.sh guard-secrets.sh wiki-hook.sh stop-remind.sh
  lib.sh               shared: read config, parse hook JSON without jq, locate project
reference/
  wiki.md              wiki rules (§8)
  knowledge.md         knowledge file format (§12)
scripts/
  wiki-check.sh        deterministic wiki checks (§8.3)
tests/                 bash; lib.sh, test_*.sh, run.sh; fixtures/
evals/                 trigger evals (new-project only)
```
`install.sh` is removed: the plugin delivers skills, agents and hooks. No symlinks or copies
into project trees, no `@`-imports in any `CLAUDE.md`.

### 4.2 The user's Core (private, created by `setup`)
```
<Core>/                              git repo, private on GitHub if pushed
  PROJECTS.md  README.md  .gitignore
  bin/                               save, undo-step (for manual use; see §13.6)
  hooks/                             git hook sources (as today)
  standards/<name>.md                the user's standards, all of them (§7)
  session-rules.md                   optional; printed at session start (§13.1)
  <project>/CLAUDE.md
  <project>/docs/INDEX.md, brief.md, architecture.md, decisions/, features/
  <project>/docs/knowledge/<role>.md, <role>/<Family>.md   (§12)
  <project>/.claude/rules/
  <project>/code/                    the code: its own git repo; Claude Code is launched here
```

## 5. Configuration and setup

- Config file `~/.config/coredev/config`, lines `KEY=VALUE`: `PROJECTS_DIR` (default
  `~/Projects`), `CORE_NAME` (default `Core`), `APP_ID_PREFIX` (asked by new-project when
  needed). `CORE_DIR` = `PROJECTS_DIR/CORE_NAME`. Env override for tests: `COREDEV_CONFIG`,
  `CORE_DIR`.
- If the new file is missing, the old `~/.config/new-project/config` is read (migration).
  `setup` writes the new file.
- `/coredev:setup` (once per machine): asks where projects live and the Core name, shows the
  plan, creates `<Core>` as a git repo with the skeleton of §4.2 (`standards/` with a
  `README.md` saying what a standard is and that `/coredev:new-standard` makes one), installs
  the Core git hooks, commits. Idempotent: on an existing Core it prints `created`/`skipped`
  per item and never overwrites a user file. It never creates a GitHub repo without a
  separate approval.
- `new-project` calls the same setup scripts when Core is missing, instead of its own copy.

## 6. Rename and migration (phase 1)

- `plugin.json` name `coredev`, version `0.2.0`; `marketplace.json` lists `coredev` and adds
  `"renames": {"corekit": "coredev"}`. Verified (marketplace docs): renames migrate users
  automatically, but for a git-hosted marketplace each user runs
  `/plugin install coredev@corekit` once; users get new commits only when `version` changes.
- Every mention of `corekit` as a plugin name or `/corekit:` command in README, CLAUDE.md,
  CHANGELOG (new entry), skills, tests becomes `coredev`; the marketplace and repo names stay.
- `docs/migration-0.2.md` — a short note for an existing user (the owner's two machines):
  1. `/plugin marketplace update corekit`, then `/plugin install coredev@corekit`;
  2. remove the old manual copy: `rm -rf ~/.claude/skills/new-project` (only if it has the
     `.corekit` marker);
  3. remove the `Stop` hook block from each existing `code/.claude/settings.local.json`
     (the plugin now ships it, §13.6);
  4. hide attribution: add `"attribution": {"commit": "", "pr": ""}` to
     `~/.claude/settings.json` (key verified in the settings index; the exact value form is
     verified in phase 1 before writing the note).
  5. restart Claude Code.

## 7. Standards (user-defined)

### 7.1 What a standard is
A Markdown file `<Core>/standards/<name>.md`, English, at most ~120 lines, following
`skills/new-standard/references/template.md`:
```
---
name: <kebab-case>
description: <one line: what it rules and when an agent needs it>
applies-to: [<roles that must read it, e.g. engineer, release>]
updated: YYYY-MM-DD
---
# <Title>
## Rule            numbered, one rule per line, imperative
## Why             one line per rule: the failure it prevents
## How to check    per rule: a command and the expected output, or "no guard" (a stated risk)
## Exceptions      or "none"
## Sources         what the rules rest on (research links, the user's old documents)
```
### 7.2 Lookup order
An agent that needs standard `<name>` reads, first found wins:
1. a project exception: `<Core>/<project>/docs/standards/<name>.md`;
2. `<Core>/standards/<name>.md`.
None found → the reply says `Standards: none in Core` for it.

### 7.3 `/coredev:new-standard`
1. Asks the topic; interviews the user one question at a time (what must always be true,
   what went wrong before, which roles need it).
2. Asks for optional sources (an old document of the user, e.g. the old CoreCrew
   development standard) and reads them.
3. Sends one research subagent (general-purpose, web) to check current best practice for
   the topic; its findings are cited in `## Sources`.
4. Shows the draft in the user's language; on "ok" writes the file, runs
   `check-standard.sh <file>` (must be green), and commits it through `save` in Core.
5. Never writes a standard into the plugin.

`check-standard.sh`: front matter fields present; all five sections in order; every rule has
a `How to check` entry; no line over 200 chars; file under 120 lines. Exit 0/1 with a list.

### 7.4 The owner's first two standards (phase 2)
Made with `new-standard` into the owner's `<Core>/standards/`:
- `versioning` — ported from the old development standard §2 (build number = commit count,
  refuse when history cannot be counted; tags `vMAJOR.MINOR.PATCH[-dev.N]`; never re-tag).
  Project names (Helm, Mafia) are dropped.
- `about-screen` — no old standard exists; built from the interview.
They are committed in Core, not in CoreKit.

## 8. Wiki

### 8.1 Rules (`reference/wiki.md`)
- `docs/INDEX.md` is the map: one line per page,
  `- [Title](path.md) — purpose; § Heading A, § Heading B.` naming **every** `##` heading of
  that page, so a reader reads the map and then one page.
- One subject per page; folders flat (`features/`, `decisions/`, `knowledge/`). A page over
  ~8 KB without `##` headings is a defect.
- Every page starts with front matter: `title`, `description`, `status`, `files`, `related`,
  `updated` (existing new-project format). `files:` lists code paths (relative to `code/`)
  the page describes.
- One reference form: `docs/<page>.md § <exact heading>`. Headings are unique across the wiki.
  "See above", "this document" are defects.
- No history (git has it), no dated measurements, no number without the command that prints
  it, no copy of another page or of `CLAUDE.md`. One home per fact.
- A new architectural decision → new `decisions/NNN-<slug>.md`.
- A user standard in `<Core>/standards/wiki.md`, if present, wins over this file.

### 8.2 Who does what
- Every agent's "What to read first" starts with `CLAUDE.md`, then `docs/INDEX.md`, then the
  one page its task needs.
- engineer is the only author of wiki edits too: when a change touches a code file, it updates
  every page whose `files:` lists it (content and `updated`), adds a map line for a new page,
  adds a decision file for a new decision.
- verifier runs `wiki-check.sh` and resolves the prose claims (§11.2).
- `release` refuses to commit when `wiki-check.sh` is red.
- `new-project` creates a wiki that passes `wiki-check.sh` (map lines name headings;
  `docs/knowledge/` exists). A test enforces it.

### 8.3 `scripts/wiki-check.sh <project-dir> [--changed <file>...]`
Checks, each failure printed as `wiki-check: <file>: <problem>`:
1. every `docs/**/*.md` has the six front matter fields;
2. `INDEX.md` links exactly the pages on disk (none missing, none extra; `knowledge/` pages
   and `superpowers/` excluded);
3. every link and every `§ heading` reference in `docs/` and `CLAUDE.md` resolves;
4. each map line names every `##` heading of its page;
5. no `##` heading appears twice across the wiki;
6. no page over 8 KB without `##` headings;
7. with `--changed`: a changed code file listed in some page's `files:` while that page is
   not among the changed files → `drift`.
Portable bash 3.2, no jq. Tests: one good fixture wiki and one broken fixture per check.

## 9. `task` — the orchestrator (`/coredev:task <task>`)

### 9.1 Start
1. Resolve the project: the working directory must be inside `<Core>/<project>/`; otherwise
   refuse in one line and offer `/coredev:new-project` (D11).
2. Check dependencies: the agent types `feature-dev:code-architect`,
   `feature-dev:code-explorer` and the `superpowers:brainstorming` skill are in the session's
   lists. Missing → name them and the install command; paths that need them stop.
3. Read `CLAUDE.md`; list (names only) `<Core>/standards/`, `docs/knowledge/`.
4. Choose the path; name it in the first report line.

### 9.2 Paths (`references/paths.md`)
- **fix** — a defect in a known place: `code-architect` only if more than one module is
  affected → tester (a test reproducing the defect, shown red; a screenshot/recording where no
  test can catch it) → engineer → tester (same test green; 2–3 mutations of the fix, each shown
  red, then reverted) → checkers' wave → release.
- **full** — a new capability or a behaviour change: a short `superpowers:brainstorming` with
  the user in the main session → `code-architect` → engineer → tester → checkers' wave →
  engineer (repair) → tester (confirm) → release. A plan of more than 5 tasks or touching more
  than 3 modules runs its first task only, then stops with diff, risk and an estimate for the
  user's go.
- **question** — `code-explorer` or one coredev role; no chain; proof is a `file:line`.
- **batch** — several changes of one shape: check the list for file overlap first and hand
  back overlapping entries; one engineer → tester → verifier → release chain for the whole
  list; one full test run at the end.

### 9.3 The checkers' wave
After tester's pass, in one message, foreground: verifier always; security when deletion,
permissions, running foreign code, updating or the network is touched; localizer when
user-visible text changes; designer when what is drawn changes (designer after localizer when
both, because both build the artifact). Every checker gets tester's report; designer gets
engineer's `Screens` line. All findings go to engineer as one repair. After a repair, tester
confirms and each checker whose finding was repaired re-checks only that place.

### 9.4 Rules (each paid for in the old crew)
1. One author of changes: engineer. A checker's finding goes back to engineer.
2. tester before security, never the same place at once.
3. Budget: every brief ends with "after 60 tool calls return what is done and what is left";
   agents also carry `maxTurns` (§11.1).
4. Three engineer passes per chain (a wave counts as one) → stop and report to the user. Two
   fixes on one premise that fail the same check → write the premise in one sentence, no third
   attempt on it.
5. Dispatch every agent in the foreground (`run_in_background: false`); a wave is several
   Agent calls in one message.
6. Only the tests of touched modules per pass; the full suite once, at the end, as its own
   tester call.
7. Every brief opens with: `This brief comes from coredev:task, path: <path>, project:
   <project>, core: <Core>, standards: <Core>/standards, and IS your task.` Then the task, the
   previous report, the affected files. Do not retell `CLAUDE.md`.
8. A reply without the `Standards:` line, from a role whose needed standards exist, goes back
   once with "read <files> and reply again".
9. One `task` call is one chain. A brief with several tasks: run the first, return the rest in
   `Open`.

### 9.5 Knowledge and commit
- Collect the agents' `Knowledge line:` proposals. None → go to release.
- Some → show the report with the lines in plain words and ask "ok?". On "ok" `task` writes
  them into `docs/knowledge/` (format §12) and they go into the same commit; on "no" they are
  dropped.

### 9.6 Report (`references/report.md`), in the user's language, labels in English
```
Path: <full | fix | question | batch> · project <P>
Chain: <role → role → …>
Done: <one line>
Proof: <command> → <key output lines>   (question: file:line)
Standards: <applied standards, or "none in Core">
Open: <what is left, or "nothing">
Knowledge: <lines saved after ok | none>
Cost: <N agent calls, K engineer passes>
Commit: <hash and message | stopped — why>
```
No `Proof` → no report.

## 10. `release` (`/coredev:release`)
A procedure run by `task` in the main session at the end of a chain that changed files, or by
the user. Postconditions, each shown as command → output → ✓/✗:
1. the project's check command from `CLAUDE.md` is green;
2. every called checker's report is clean;
3. `wiki-check.sh <project> --changed <files>` is green;
4. version and changelog — only when the task is a release, following the user's
   `versioning` standard if present; none → ask the user;
5. commit through the plugin's own `save` (`skills/new-project/core-bin/save`, not the Core
   copy): code and docs as one step, message in English saying what and why;
6. `git log --format=%B <range> | grep -icE 'co-authored-by|generated with'` → `0`;
7. `git status --short` clean in `code/` and in the project's Core folder.
One ✗ → stop, the finding goes to engineer; no second cycle. Never tags, never pushes.

## 11. Agents (`agents/<role>.md`, ≤ 60 lines each)

### 11.1 Template
```
---
name: <role>
description: <one short line: the question it answers and when to call it>
model: sonnet | opus
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
- No user paths, no project names, no platform, no dates. Paths come in the brief (§9.4.7).
- "What to read first": `CLAUDE.md` → `docs/INDEX.md` → the page the task needs → the
  standards it needs (§7.2) → `docs/knowledge/<role>.md` if present ("no knowledge" otherwise).
- "How you work" keeps the shared practice in 2–3 lines: runs in the foreground and waited
  for; a refused test run (one-suite) is retried, never polled; logs go to a file and are read
  by range; independent checks in one Bash call.
- Answer in the user's language; write files in English.
- Every reply format ends with `Standards: <name — the rule applied, quoted | none needed |
  none in Core>` and `Knowledge line: <symptom → cause → guard | none>`.

### 11.2 Roles
| Agent | Model | Tools | Essence |
|---|---|---|---|
| engineer | sonnet | Read, Edit, Write, Grep, Glob, Bash | The only author of changes, wiki included (§8.2). Shortest code that does it the way the project does it; red test first. Proof = check command + output. Never commits; never weakens a check. Reports `Screens` for UI work. |
| tester | sonnet | Read, Edit, Write, Grep, Glob, Bash | Writes only checks. On fix: red first, then green + 2–3 mutations. A test that passes on empty returns is hollow. Inputs nobody fed: empty, huge, twice, mid-operation, no permission, no network. |
| security | opus | Read, Grep, Glob, Bash | From dangerous operations to their inputs. A finding needs a path input → effect; otherwise "Not checked". Does not repeat tester. |
| verifier | opus | Read, Grep, Glob, Bash | Every address, number, quotation and conditional in the change's prose resolved by a command; runs `wiki-check.sh`; lists what the change left dead. |
| localizer | opus | Read, Grep, Glob, Bash | Reads text back out of the built artifact, key by key, language by language; source is not proof. |
| designer | opus | Read, Grep, Glob, Bash | Measures the rendered screen (size, contrast, hit area, states); at most 6 images per call; starts from engineer's `Screens`. |

Models are families, not versions. Reply formats follow the old crew's (Knowledge/Done/Files/
Proof/Open; Findings/Not checked/Verdict …), adapted to §11.1.

### 11.3 To verify in phase 3
`maxTurns` and `disallowedTools` for plugin agents (not listed as ignored in the sub-agents
docs, not confirmed either); the exact `subagent_type` string (`coredev:engineer` expected).

## 12. Knowledge (`reference/knowledge.md`)
- `<Core>/<project>/docs/knowledge/<role>.md`, ≤ 80 lines, four sections: How proof is made
  here · Where things are · What has broken here · What you must not do here.
- A family of cases gets its own page `docs/knowledge/<role>/<Family>.md`, one case per line:
  `symptom → cause → guard address | no guard`. The role file links it:
  `- [Family](<role>/Family.md): symptom → cause`.
- Written only by `task` after the user's "ok" (§9.5). Agents only propose.

## 13. Hooks (`hooks/hooks.json`)
All hooks: portable bash 3.2, BSD tools, no jq; read the hook JSON from stdin; fast; plugin
hooks also fire inside subagents (verified, hooks docs). Guards block with exit 2 and a
stderr message that names the right place. A hook that cannot parse its input lets the call
through (a stuck guard stopping every call is worse), except where noted.

1. **session-start.sh** — `SessionStart` (startup, resume, clear, compact). Prints, short:
   - Core not configured or missing → `coredev: not set up — offer /coredev:setup`;
   - inside `<Core>/<project>/`: project name, path of `docs/INDEX.md`, path of
     `<Core>/standards/` and one line per standard (`name — description`);
   - `<Core>/session-rules.md` if present (the owner's old rules move there in phase 4).
2. **one-suite.sh** — `PreToolUse` Bash. Port of the old hook: a test run waits (up to 480 s)
   while another runs on the machine, then is refused with "run the same command again".
   Runners: swift test, xcodebuild test, npm/npx test, vitest, gradlew test, pytest, cargo test,
   flutter test, go test, `*tests?.sh`. Quoted text and heredoc bodies ignored. Without
   `pgrep`, lets everything through.
3. **guard-code.sh** — `PreToolUse` Write|Edit|NotebookEdit (+ Bash, best effort). Blocks
   `CLAUDE.md`, `docs/**`, `.claude/**` inside any `<Core>/<project>/code/**`, worktrees
   included; allows `.claude/settings.local.json` and `.claude/worktrees/**` themselves.
   Paths are compared after resolving `..` and case-folding (macOS). Bash: blocks `>`, `>>`,
   `cp`, `mv`, `tee`, `touch` targets matching the same rule; not complete — the code repo's
   git pre-commit hook stays the last layer.
4. **guard-secrets.sh** — `PreToolUse` Read|Grep|Glob|Edit|Write|Bash. Blocks `.env`,
   `.env.*` (allows `.env.example`, `.env.sample`, `.env.template`) and `~/.ssh/**`. Bash: best
   effort on command words (`cat`, `source`, `.`, `less`, `head`, `tail`, `grep` with an
   explicit path); a recursive grep over a folder is not caught. Fails closed when the path
   matches but the JSON is odd.
5. **wiki-hook.sh** — `PostToolUse` Write|Edit on `<Core>/<project>/docs/**`: runs
   `wiki-check.sh` for that page and the map; problems go back to Claude (exit 2 stderr). Never
   blocks anything else.
6. **stop-remind.sh** — `Stop`: the existing "save the step" reminder, moved from per-project
   `settings.local.json` into the plugin; fires only inside a Core project. `new-project` stops
   writing it into `settings.local.json`.

Windows: hooks need Git for Windows (Git Bash); full Windows support is a later subproject.

## 14. Testing and done

- `bash tests/run.sh` green, with a test file per new part: `test_rename.sh`, `test_setup.sh`,
  `test_task_skill.sh` (structure, paths, report labels, flags), `test_release_skill.sh`,
  `test_new_standard.sh` (+ `check-standard.sh` fixtures), `test_agents.sh` (≤ 60 lines, six
  sections, frontmatter, `Agent` disallowed, checkers without Edit/Write, `Standards:` and
  `Knowledge line:` in reply format), `test_wiki_check.sh`, one `test_hook_<name>.sh` per hook
  (JSON fixtures, including from inside a subagent), `test_no_personal.sh` (no `/Users/`,
  `rstrlnkv` outside manifests/README/LICENSE, no project names from the owner's list).
- `claude plugin validate .` green.
- `claude --plugin-dir .` loads: `/coredev:task` etc. listed, agents listed as `coredev:*`.
- The plugin installs from the marketplace on a clean Claude Code config.
- End to end: `<Core>/test-coredev/` (hand-made: `CLAUDE.md`, `docs/` passing `wiki-check`,
  `code/` with a tiny bash script, its test and a planted bug); `/coredev:task fix <bug>`
  runs fix → returns the §9.6 report with proof and a commit without attribution.
- Final hand-over: exact install and update commands for Mac and Windows, and the list of
  what the owner commits to Core.

## 15. Phases (stop after each for the owner's check)
1. **Rename + setup:** manifests, renames, docs, tests; `setup` extracted from new-project;
   config move; `install.sh` removed; migration note.
2. **CoreSkills:** `new-standard` (+ template, `check-standard.sh`); with it, the owner's
   `versioning` and `about-screen` in their Core; `reference/wiki.md`, `reference/knowledge.md`,
   `wiki-check.sh`, new-project wiki templates; `task`; `release`.
3. **CoreCrew:** the six agents.
4. **CoreHooks:** the six hooks; the owner's session rules moved to `<Core>/session-rules.md`.
5. **End to end:** `test-coredev`, marketplace install check, hand-over.

## 16. Out of scope (next subprojects)
- Syncing machine settings (`settings.json` for Mac and Windows, personal `~/.claude/CLAUDE.md`).
- Windows / PowerShell support.
- `adopt` — moving an existing project into the Core layout.
- The old crew's `ship` and `bloat-audit` skills, journal and autosync.
- Updating Core copies of `bin/` and `hooks/` automatically.

## 17. Risks
- Dependence on feature-dev and superpowers names: a rename there breaks `full`; caught by
  `task`'s start check, not by tests (no network).
- Bash guards are best effort (§13.3, §13.4); the git hooks remain the last layer.
- Agents may skip reading standards; the `Standards:` line makes it visible, not impossible.
