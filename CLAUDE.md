# CoreKit

Claude Code skills, published as the `corecrew` plugin in the `corekit` marketplace
(the public GitHub repo `CoreKit`).
The main skill is `new-project`: an interview, stack and architecture analysis, and a project
skeleton whose internal docs live in a private repo (`~/Projects/Core/<project>/`) while the
code lives in its own repo beside the Core (`~/Projects/<Name>/`); the private `CLAUDE.md` is
loaded through a gitignored `CLAUDE.local.md` link in the code folder. Layout spec:
docs/specs/2026-11-04-project-layout-design.md (old projects keep `<Core>/<name>/code/`).

Requirements source: docs/specs/2026-11-03-coredev-design.md (read before changing the
plugin; its layout part is superseded by the layout spec above) and
docs/specs/2026-11-02-new-project-design.md (the `new-project` skill). Plans: docs/plans/.

## Layout
```
.claude-plugin/
  marketplace.json     marketplace "corekit": corecrew, coremodel, coreopinion; renames
plugins/corecrew/      the corecrew plugin (moved here in 0.6.0; before, the repo root was the plugin)
  .claude-plugin/plugin.json   name "corecrew", version lives here, userConfig
  .claude-plugin/icon.png      listing icon of every plugin (1024 px); sources: docs/icons/<plugin>.svg
  skills/
    new-project/       uses scripts/setup-core.sh; wiki templates
    task/              SKILL.md; references/: paths.md, brief.md, report.md, release.md, adopt.md
    new-standard/      SKILL.md; references/template.md
  agents/              engineer tester security verifier localizer designer
  hooks/
    hooks.json         five hooks, explicit timeouts
    session-start.sh one-suite.sh guard-code.sh guard-secrets.sh stop-remind.sh
    messages.sh        every hook text, in the ui_language setting
  reference/
    wiki.md            wiki rules
    knowledge.md       knowledge format
  scripts/             all machinery, portable bash
    lib.sh             read settings, parse hook JSON without jq, locate <Core> and project
    _locate.sh         find the plugin root and the Core for scripts run by hand
    setup-core.sh      create or upgrade the Core skeleton
    install-hooks.sh   install the git hooks into a code repo and the Core
    sync-tools.sh      sync the tools the Core uses from the plugin
    adopt.sh           move an existing project into the layout
    wiki-check.sh      wiki checks
    check-standard.sh  standard file checks
    save, undo-step    one step = code + docs commit / revert
    bash-lex.awk, bashlex-*.awk   the Bash tokenizer shared by guard-code (also the read-only
                       checkers' rule) and guard-secrets, and their parts
    git-hooks/         pre-commit-code, pre-push-code, pre-push-core, blocked-patterns
  evals/               trigger evals: `claude plugin eval plugins/corecrew --ablation none --no-publish`
                       (real model calls, about $0.80 a run; not part of tests/run.sh)
plugins/coremodel/     a second plugin (TypeScript hooks module); spec docs/specs/2026-11-04-coremodel-design.md;
                       own CHANGELOG; tests: `claude plugin test plugins/coremodel` (run by tests/test_coremodel.sh;
                       without the `claude` CLI it is skipped and run.sh names it after PASSED)
plugins/coreopinion/   a third plugin: skill second-opinion (GPT via `codex exec` with a narrow read-only
                       permission profile, in scripts/ask-gpt.sh); own README and CHANGELOG; tests: tests/test_coreopinion.sh;
                       trigger evals in evals/ like corecrew's
tests/                 bash: lib.sh ($PLUGIN is plugins/corecrew), test_*.sh, run.sh, fixtures/;
                       test_docs_paths.sh checks that every repo path a README names exists
docs/migration-*.md    upgrade guides for users of older versions (0.2, 0.3)
CHANGELOG.md, README.md   corecrew's changelog and the repo README
```
No top-level `bin/` (claude.ai and Cowork refuse plugins that have one). Spec section 4.1 is the
tree this layout follows.

## Commands
```bash
bash tests/run.sh          # all tests; no network, prints ALL TESTS PASSED
bash tests/test_hooks.sh   # one file
claude plugin validate .                   # the marketplace manifest
claude plugin validate plugins/corecrew    # one plugin (also plugins/coremodel, plugins/coreopinion)
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
- **Test isolation:** tests run under `new_sandbox` (own HOME, XDG, GIT_CONFIG_GLOBAL;
  tests/test_isolation.sh checks it). Never run `git config --global`/`--system` or write to
  `~/.claude`, `~/.codex` or the real `~/Projects` from a test or an agent; for a manual check
  use `GIT_CONFIG_GLOBAL=$(mktemp)`.
- **Risky code:** a script that moves or deletes user files (adopt, undo-step, save) needs a
  test of the failure path: a failed step leaves the user's files as they were
  (tests/test_adopt.sh does this). A guard or blocker needs a test that a legitimate action
  passes. A hook never polls in a tight loop: wait with `sleep` and a limit, as one-suite.sh does.
- **Releases:** bump `version` in plugins/corecrew/.claude-plugin/plugin.json and add an entry to
  CHANGELOG.md (newest first, `## X.Y.Z — YYYY-MM-DD`) in the same change.
- After any change run `bash tests/run.sh` and `claude plugin validate .` (and the plugin you changed).
- **Language:** all files, code, comments and commit messages in English; talk to the user
  in their language, in plain words.
- Reference the spec and plan as plain text paths, never as `@`-imports.
- Commit after each working step; work on a branch, never commit to `main` directly.
- Never read `.env` files or `~/.ssh`.
