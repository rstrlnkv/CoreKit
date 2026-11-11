---
name: bloat-audit
description: Use when the user asks what can be deleted, merged or simplified across a whole repository — "what can we delete", "find duplicates", "audit for bloat", in any language. Ranks duplicates, hand-written standard library, one-user abstractions, unused settings and dead code; changes nothing. Not for the current diff: that is /simplify.
allowed-tools: Read, Grep, Glob, Bash
---

# Bloat audit

## Paths
This skill's folder is `${CLAUDE_SKILL_DIR}`; call it `<skill>`. Claude Code fills in that absolute
path before you read it. Codex leaves the text as written: then read `reference/codex-host.md` in the
plugin folder (two folders above the folder of the SKILL.md path Codex gave for this skill), find and
check `<skill>` as its section Skill folder says, and follow that file for the rest of this skill.
Then run `bash "<skill>/../../scripts/lib.sh" plugin-root`. It prints `<plugin>`, the absolute plugin
folder; `<scripts>` is `<plugin>/scripts`. Write every later command and every Read path with these
filled in as absolute paths. If the command fails, or you cannot give `<skill>` as an absolute path,
stop, tell the user the corecrew folder was not found, and do not guess a path.

## Scope
A read-only pass over one repository: the git repository of the current folder, or a folder the user
names. It changes nothing: no edits, no commits, no installs, no build or test run that writes into
the tree. Any repository works; it does not need a Core.

To know whether this is a corecrew project, resolve `<Core>`:
`CORE_DIR='${user_config.core_dir}' bash "<scripts>/lib.sh" core-dir`, then run
`CORE_DIR="<Core>" bash "<scripts>/lib.sh" project-of "<repo>"`. It prints the project name, or exits 1
when the repository is not in a project. Both only read. In a project, also read
`<Core>/<name>/CLAUDE.md` for the map.

Audit the tracked files (`git ls-files`). Leave out what nobody writes by hand: vendored code, lock
files, generated code, build output and test fixtures. When the repository is too big for one pass,
audit the largest modules first and name in the report what was not covered.

## Order
1. **Map first.** Read `CLAUDE.md` or `AGENTS.md`, the README, the build manifest and the directory
   layout. Write down the modules and where the project keeps shared code. A duplicate without that
   map cannot say where the one copy should live.
2. **Look for five kinds, each with a command (`git grep`, a count), not by eye:**
   - **duplicated logic**: the same function body, rule or constant in several places; search for
     distinctive lines and names;
   - **reinvented standard library or platform**: a hand-written date, path, JSON, retry, sort or
     cache helper that the language, the framework or the OS already provides;
   - **an abstraction with one user**: an interface, protocol, factory or wrapper with exactly one
     implementation and one caller;
   - **configuration nobody changes**: an option, flag or setting read in one place and only ever
     set to its default;
   - **dead code**: no caller left. Search every use before you say so: a use by reflection, by a
     built string, from a script, a manifest or a test counts.
3. **Verify each finding** with the command that proves it: the call sites counted, the standard
   function named, the one implementation shown. Drop a finding you could not verify, or mark it
   `assumption`.
4. **Rank** by the lines that would go away against the risk of the change; among equals, the lowest
   risk first.

## Report
Write the report in the user's language. One line per finding:

`<file:line> — <what> → <what replaces it or where it moves> — <lines saved> — <risk>`

Then the total lines saved, the three findings worth doing first, and what the audit did not cover.

Never propose to cut what guards trust boundaries, data loss, security, accessibility or
localization, even when it looks unused or duplicated: name it as kept on purpose if it came up.

## After the report
Stop and wait. Fix nothing until the user picks findings. In a corecrew project, each picked finding
is a task: offer `/corecrew:task <finding>`, so the change gets its test and its checks. Elsewhere,
ask whether to make the change here.
