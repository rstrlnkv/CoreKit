# CoreKit

Claude Code skills, published as the `corekit` plugin (github.com/rstrlnkv/CoreKit).
The main skill is `new-project`: an interview, stack and architecture analysis, and a project
skeleton whose internal docs live in a private repo (`~/Projects/Core/<project>/`) while the
code lives in a separate nested repo (`<project>/code/`).

Requirements source: docs/specs/2026-11-02-new-project-design.md (read before changing the
skill). Implementation plan: docs/plans/2026-11-02-new-project.md.

## Layout
```
.claude-plugin/          plugin.json (version lives here), marketplace.json
skills/new-project/
  SKILL.md               flow and stages; links to references and scripts
  references/            interview, analysis method, stack table with generator commands
  scripts/               scaffold, preflight, configure, install-hooks, merge-generated
  core-bin/              save, undo-step, stop-remind.sh — copied to Core/bin/
  hooks/                 git hooks copied to Core/hooks/ and installed into both repos
  templates/             CLAUDE.md, docs/*, rules/*, code/* and core/* templates
tests/                   bash tests: lib.sh helpers, test_*.sh, run.sh
evals/                   trigger evals for the skill description
install.sh               manual install: copies skills/* to ~/.claude/skills/
CHANGELOG.md, README.md
```

## Commands
```bash
bash tests/run.sh          # all tests; no network, prints ALL TESTS PASSED
bash tests/test_hooks.sh   # one file
claude plugin validate .   # plugin and marketplace manifests
```
Tests run in a temp sandbox via `new_sandbox` (sets `CORE_DIR`, `NEW_PROJECT_CONFIG`);
they never touch the real `~/Projects/Core` or `~/.config`. Stub `gh` on `PATH` instead of
calling GitHub.

## Rules
- **TDD:** write a failing test in `tests/` first, watch it fail, then write the code.
  A bug fix starts with a test that reproduces the bug.
- **Portable bash:** scripts must run on macOS bash 3.2 with BSD utilities. Do not use
  `sed -i`, `mapfile`/`readarray`, `${x,,}`/`${x^^}`, `grep -P`, `declare -A`, `local -n`.
  Write to a temp file and `mv` instead of in-place edits. No `jq`: parse JSON with
  `grep`/`sed`. Quote paths; they may contain spaces.
- **Never overwrite or delete user files** in scripts; scaffold is idempotent and prints
  `created`/`skipped`.
- **Releases:** bump `version` in .claude-plugin/plugin.json and add an entry to
  CHANGELOG.md (newest first, `## X.Y.Z — YYYY-MM-DD`) in the same change.
- After any change run `bash tests/run.sh` and `claude plugin validate .`.
- **Language:** all files, code, comments and commit messages in English; talk to the user
  in their language, in plain words.
- Reference the spec and plan as plain text paths, never as `@`-imports.
- Commit after each working step; work on a branch, never commit to `main` directly.
- Never read `.env` files or `~/.ssh`.
