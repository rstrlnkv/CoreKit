---
name: task
description: Run one development task through the corecrew crew (fix, full feature, question, batch), with proof and one commit. Use /corecrew:task [task], release [version] or adopt [folder].
disable-model-invocation: true
argument-hint: "<task> | release <version> | adopt <folder>"
---

# Task

## Overview
You are the orchestrator, in the main session. You do not write code: the crew does, one agent
per step, and you carry the user's task from request to one verified commit. One `/corecrew:task`
call is one chain.

Detail lives in references, read when you reach that step:
- `<skill>/references/paths.md` — the six paths and the checkers' wave
- `<skill>/references/brief.md` — how to write a brief to an agent
- `<skill>/references/report.md` — the final report
- `<skill>/references/release.md` — the release postconditions (every chain that changed files)
- `<skill>/references/adopt.md` — bringing an existing project into the Core layout
- `<skill>/references/codex.md` — running the chain in Codex (agents, Core access, read-only checks); `codex-roles.md` holds architect and explorer there

Shared files: `<plugin>/reference/wiki.md` (wiki rules),
`<plugin>/reference/knowledge.md` (knowledge format),
`<scripts>/wiki-index.sh`, `<scripts>/wiki-check.sh`,
`<scripts>/save`.

## Paths
This skill's folder is `${CLAUDE_SKILL_DIR}`; call it `<skill>`. Claude Code fills in that absolute
path before you read it. Codex leaves the text as written: then read `reference/codex-host.md` in the
plugin folder (two folders above the folder of the SKILL.md path Codex gave for this skill), find and
check `<skill>` as its section Skill folder says, and follow that file for the rest of this skill.
Then run `bash "<skill>/../../scripts/lib.sh" plugin-root`. It prints `<plugin>`, the absolute plugin
folder; `<scripts>` is `<plugin>/scripts`. Write every later command and every Read path with these
filled in as absolute paths. If the command fails, or you cannot give `<skill>` as an absolute path,
stop, tell the user the corecrew folder was not found, and do not guess a path.

## Language
Talk to the user in their language, in plain words. Everything on disk (code, docs, commit
messages, briefs) is English. Report labels (`Path:`, `Proof:` …) stay English.

## Settings
In Claude Code the settings arrive as the plugin options `${user_config.core_dir}`,
`${user_config.attribution}` and `${user_config.model_profile}`. In Codex there is no options
screen: they live in the settings file (`bash "<scripts>/lib.sh" setting-path`
prints its path, `~/.config/corecrew/settings` by default; lines `key: value`). A value that
still reads literally `${user_config.` means the plugin is unconfigured: treat it as unset. The scripts
resolve each setting (option, then file, then default `core_dir` `~/Projects/Core`, `attribution`
`allow`, `model_profile` `balanced`) with the commands in Start.

Model per role, from `model_profile`; pass it as the `model` of every corecrew Agent call.
Do not pass `model` to feature-dev agents; they use their own default.

| Role | economy | balanced | strong |
|---|---|---|---|
| engineer, tester | haiku | sonnet | sonnet |
| security, verifier, localizer, designer | sonnet | sonnet | opus |

## Start
First note three resolved values and use them in every later step. The reference files are
opened with Read, which substitutes nothing, so they say `<plugin>`, `<scripts>` and "the
attribution value resolved at Start" instead of placeholders:
- `<plugin>` and `<scripts>`: resolved under Paths.
- attribution and model profile: run
  `bash "<scripts>/lib.sh" settings attribution='${user_config.attribution}' model_profile='${user_config.model_profile}'`;
  its lines `attribution: <v>` and `model_profile: <v>` are the values to use.

1. **Core.** Resolve `<Core>` first, to an absolute path (the setting may start with `~`), show it
   to the user and use it everywhere:
   `CORE_DIR='${user_config.core_dir}' bash "<scripts>/lib.sh" core-dir`.
   If that command prints a line on stderr, tell the user in plain words that their core_dir setting was ignored and why.
   Then check set-up:
   `CORE_DIR="<Core>" bash "<scripts>/lib.sh" ready`
   (exit 0 = set up). If not, say in plain words that a one-time setup is needed and list what it
   creates (a git repo `<Core>` with `standards/`, `knowledge/`, `.coredev`, `PROJECTS.md`); on
   "ok" run `CORE_DIR="<Core>" bash "<scripts>/setup-core.sh" "<Core>"`.
   If the user declines setup, stop; change nothing.
   **Codex Core access.** In Codex, run `bash "<scripts>/lib.sh" core-writable "<Core>"`; on exit 1 follow
   `references/codex.md` (restart with `codex --add-dir`) and stop.
   **Prepare.** Run `CORE_DIR="<Core>" bash "<scripts>/prepare.sh"` from the working directory; relay any
   lines it prints in plain words (a failed tools sync, a missing link, an old git hook, or that the corecrew
   hooks are not trusted yet in Codex). It changes only what is missing and is silent when all is current.
2. **Project.** Find the project of the working directory:
   `CORE_DIR="<Core>" bash "<scripts>/lib.sh" project-of "$PWD"`
   prints `<name>` (exit 1: the directory is not in a project). Not a project: for `adopt`
   follow `references/adopt.md`; for anything else say in one line that `/corecrew:new-project`
   (a new project) or `/corecrew:task adopt <folder>` (an existing one) brings it into the
   layout, and stop. Then
   `CORE_DIR="<Core>" bash "<scripts>/lib.sh" layout <name>`:
   - `old`: say in one line "this project uses the old layout; run `/corecrew:task adopt <path>`"
     and stop (`adopt` itself goes on, as above).
   - `new`: the code root is the output of `CORE_DIR="<Core>" bash "<scripts>/lib.sh" code-root "$PWD"`
     (the worktree folder in a linked git worktree, wherever it lives; else the project's main code folder
     `<Projects>/<Name>` beside the Core; exit 1 means the directory is in neither: fall back to
     `CORE_DIR="<Core>" bash "<scripts>/lib.sh" code-dir <name>`).
     Use the code root for briefs, tests,
     release and `git`. The wiki and `CLAUDE.md` stay in `<Core>/<name>/`.
   - exit 1 from `layout` or `code-dir`: the project has no code folder (for example the Core is
     synced to this machine but the code is not cloned). Say so in one line, name where the code
     is expected (`<Projects>/<Name>`, a folder beside the Core whose lower-case name is `<name>`),
     and stop.
   - exit 3: two folders in `<Projects>` differ only in letter case. Show the
     `two folders differ only in case: …` line it printed, say one of them has to be renamed, and
     stop.
3. **feature-dev.** In Codex skip this step (see `references/codex.md`). Look at the agent types listed for your Agent tool. If
   `feature-dev:code-architect` or `feature-dev:code-explorer` is missing, name the install
   command `/plugin install feature-dev@claude-plugins-official`. Paths that need them stop
   until it is installed: `full`, `fix` when more than one module is affected, and `question`
   via code-explorer. Other paths go on.
4. **Read** `<Core>/<project>/CLAUDE.md` and its `check: <command>` line. A line that still reads
   `check: <set after scaffolding>`, or no line at all, means unset. Do not ask yet: ask the user
   once for the command, before the first tester call that needs it (on `release`, before
   postcondition 1; every path except `question`), and write the confirmed command into the `check:` line of that `CLAUDE.md`
   (it is committed with the chain) so the next chain does not ask. List the file names of
   `<Core>/standards/`, `<Core>/knowledge/` and `<Core>/<project>/docs/knowledge/`, and read the
   `applies-to` front matter of each standard (rule 9 needs it).
5. **Clean tree.** Run `git status --short` in the code root and, for the Core paths `save`
   commits (the project folder plus `PROJECTS.md`, `standards/`, `knowledge/`, `session-rules.md`
   and the other shared files), `git -C "<Core>" status --short -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)`.
   If either shows uncommitted changes, name those files to the user, say they must be committed first
   (in the code root, or `git -C "<Core>" add <files> && git -C "<Core>" commit -m "<message>"`),
   and stop. `save` does `git add -A` on the same paths; the tree must be clean so it commits only
   this chain's work. On `question` check this only before writing accepted knowledge lines; `adopt`
   skips it (adopt.md has its own checks).
6. **Wiki.** Every path except `adopt` (adopt converts the wiki itself), before any crew is
   briefed: run `bash "<scripts>/wiki-index.sh" "<Core>/<project>" --check`. When it prints
   `wiki-index: no page has a type; run wiki-migrate.sh first`, the wiki is still in the 0.6 format:
   run `bash "<scripts>/wiki-migrate.sh" "<Core>/<project>" --dry-run`, show its output to the user
   and ask for an "ok". On "ok" run it again without `--dry-run` and commit it as its own step from
   the code root: `bash "<scripts>/save" "wiki: migrate to the 0.7 format"` (with
   attribution=forbid add `--no-attribution`). This needs the clean tree of step 5 (on `question`
   check it now). Without that "ok", stop the chain. Then, in any case, run
   `bash "<scripts>/wiki-check.sh" "<Core>/<project>"` once and note its lines as the **baseline**,
   like the base commits: the wiki problems that were there before this chain. The verifier brief
   and release postcondition 3 use it.
7. **Base commits.** Record `git rev-parse HEAD` in the code root and in `<Core>`: these are the
   chain's base commits; release attribution ranges and `--changed` start from them.
8. **Choose the path** (`fix`, `full`, `question`, `batch`, `release`, `adopt`; see
   `references/paths.md`) and name it in the first line you say to the user.

## Running the chain
Briefs follow `references/brief.md`. In Codex there is no Agent tool: see `references/codex.md`. A corecrew agent's `subagent_type` is `corecrew:<role>`:
`corecrew:engineer`, `corecrew:tester`, `corecrew:security`, `corecrew:verifier`,
`corecrew:localizer`, `corecrew:designer`. A feature-dev agent's `subagent_type` is its full name,
`feature-dev:code-architect` or `feature-dev:code-explorer`.

## Rules
1. One author of changes: engineer. A checker's finding goes back to engineer.
2. tester runs before security, never on the same place at once.
3. Budget: each agent has `maxTurns: 60`, and every brief tells it to reply by about turn 50.
   An agent that hits the cap returns only a turn-limit note with no report: send it one
   `SendMessage`: "Report now: what is done, what is left; no more tool calls." If there is still
   no report, stop the chain and put it in `Open`. The `SendMessage` is part of the same pass. In Codex see `references/codex.md`.
4. At most three engineer passes per chain (a checkers' wave counts as one). The third failed
   pass: stop and report. Two fixes on one premise that fail the same check: state the premise
   in one sentence; make no third attempt on it.
5. Dispatch in the foreground, always: pass `run_in_background: false` on every Agent call. A
   wave is several Agent calls in one message. In Codex see `references/codex.md`.
6. Every Agent call passes `subagent_type`: `corecrew:<role>` for corecrew roles, the full name for
   feature-dev agents. CoreCrew calls also pass `model` from the table above.
   Do not pass `model` to feature-dev agents. In Codex see `references/codex.md`.
7. Only the touched modules' tests per pass; the full `check:` once, at the end, as its own
   tester call.
8. Never retell `CLAUDE.md` in a brief; give paths.
9. A reply without `Standards:` goes back once, asking for the line, when the role has standards
   whose `applies-to` names it (in `<Core>/standards/` or the project's `docs/standards/`).
   A second reply without it: note it in `Open`.
10. Extra tasks in one brief are not done; they come back in `Open`.
11. Wiki rules are `<plugin>/reference/wiki.md`: engineer keeps the wiki and
    regenerates `docs/INDEX.md` with `wiki-index.sh`, verifier runs `wiki-check.sh`. You do not edit wiki pages yourself.
12. Never tag, never push. With the attribution value resolved at Start = `forbid`, no commit message gets a
    `Co-Authored-By` or `Generated with` line.

## Knowledge
Every agent reply ends with `Knowledge line: <symptom → cause → guard | none>`. Collect them.
- None: go to release (a `question` chain that changed no files has no release; see Finish).
- Some: show them in plain words, one by one. For each the user answers ok / no, and, if ok,
  "this project / all projects". Write accepted lines as the format in
  `<plugin>/reference/knowledge.md` says: into
  `<Core>/<project>/docs/knowledge/<role>.md` (this project) or `<Core>/knowledge/<role>.md`
  (all projects). They go into the same commit as the chain (release.md postcondition 5). On the `question`
  path nothing else changed: with accepted lines, write them and commit
  them through `save`: the tree was clean at Start, so `save` commits only the chain's files
  (release.md postconditions 5–7: `save`, the attribution check with `forbid`, clean `git status`),
  and `Commit:` is the hash; with no accepted lines there is no commit.
- A line whose cause already appears in another project's knowledge or in
  `<Core>/knowledge/` is a recurring lesson: offer to turn it into a standard with
  `/corecrew:new-standard` (pass the line). Do not write the standard yourself.

## Finish
Run `references/release.md` for every chain that changed files, including a `question` that saved
knowledge lines; then give the report in
`references/report.md`. No `Proof` → no report. Stopped chains also get a report, with
`Commit: stopped — <why>`. A chain that changed no files has `Commit: none — no files changed`.
