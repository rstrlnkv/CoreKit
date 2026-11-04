# CoreKit

Claude Code skills, published as the `corecrew` plugin in the `corekit` marketplace
(the public GitHub repo `CoreKit`).
The main skill is `new-project`: an interview, stack and architecture analysis, and a project
skeleton whose internal docs live in a private repo (`~/Projects/Core/<project>/`) while the
code lives in a separate nested repo (`<project>/code/`).

Requirements source: docs/specs/2026-11-03-coredev-design.md (read before changing the
plugin) and docs/specs/2026-11-02-new-project-design.md (the `new-project` skill). Plans: docs/plans/.

## Layout
```
.claude-plugin/
  plugin.json          name "corecrew", version lives here, userConfig
  marketplace.json     marketplace "corekit"; plugin "corecrew"; renames
skills/
  new-project/         as today; uses scripts/setup-core.sh; wiki templates
  task/                SKILL.md; references/: paths.md, brief.md, report.md, release.md, adopt.md
  new-standard/        SKILL.md; references/template.md
agents/                engineer tester security verifier localizer designer
hooks/
  hooks.json           five hooks, explicit timeouts
  session-start.sh one-suite.sh guard-code.sh guard-secrets.sh stop-remind.sh
reference/
  wiki.md              wiki rules
  knowledge.md         knowledge format
scripts/               all machinery, portable bash
  lib.sh               read settings, parse hook JSON without jq, locate <Core> and project
  setup-core.sh        create or upgrade the Core skeleton
  adopt.sh             move an existing project into the layout
  wiki-check.sh        wiki checks
  check-standard.sh    standard file checks
  save, undo-step      one step = code + docs commit / revert
  bash-lex.awk, bashlex-*.awk   the Bash tokenizer shared by guard-code and guard-secrets, and their parts
  git-hooks/           pre-commit-code, pre-push-code, pre-push-core, blocked-patterns
tests/                 bash: lib.sh, test_*.sh, run.sh, fixtures/
evals/                 trigger evals (new-project)
plugins/coremodel/    a second plugin (TypeScript hooks module); spec docs/specs/2026-11-04-effort-picker-design.md;
                       own CHANGELOG; tests: `claude plugin test plugins/coremodel` (run by tests/test_coremodel.sh)
plugins/coreopinion/   a third plugin: skill second-opinion (GPT via `codex exec --sandbox read-only`);
                       own README and CHANGELOG; tests: tests/test_coreopinion.sh
CHANGELOG.md, README.md
```
No top-level `bin/` (claude.ai and Cowork refuse plugins that have one). Spec section 4.1 is the
target tree; some parts arrive in later phases of docs/plans/.

## Commands
```bash
bash tests/run.sh          # all tests; no network, prints ALL TESTS PASSED
bash tests/test_hooks.sh   # one file
claude plugin validate .   # plugin and marketplace manifests
```
Tests run in a temp sandbox via `new_sandbox` (sets `CORE_DIR`);
they never touch the real `~/Projects/Core` or `~/.config`. Stub `gh` on `PATH` instead of
calling GitHub.

## Rules
- **TDD:** write a failing test in `tests/` first, watch it fail, then write the code.
  A bug fix starts with a test that reproduces the bug.
- **Portable bash:** scripts must run on macOS bash 3.2 with BSD utilities. Do not use
  `sed -i`, `mapfile`/`readarray`, `${x,,}`/`${x^^}`, `grep -P`, `declare -A`, `local -n`.
  Write to a temp file and `mv` instead of in-place edits. No `jq`: parse JSON with
  `grep`/`sed`. Quote paths; they may contain spaces. tests/test_portability.sh enforces
  this; add a pattern there when you find a new non-portable construct.
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
