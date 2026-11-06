# Architecture

A bird's-eye view of the repository for contributors. CoreKit is a Claude Code marketplace
(`corekit`) that holds three independent plugins. Nothing here is compiled except the TypeScript
module of `coremodel`.

## Where things live

```
.claude-plugin/marketplace.json   the marketplace: lists the three plugins
plugins/corecrew/                 project workflow
  .claude-plugin/plugin.json      name, version, settings (userConfig)
  skills/                         new-project, task, ship, new-standard (SKILL.md + references/)
  agents/                         engineer, tester, security, verifier, localizer, designer
  hooks/                          hooks.json and the five hook scripts, messages.sh for their texts
  scripts/                        the machinery in portable bash: lib.sh, setup-core.sh, install-hooks.sh,
                                  sync-tools.sh, adopt.sh, save, undo-step, wiki-*.sh, git-hooks/
  reference/                      wiki.md and knowledge.md: the rules the agents follow
  evals/                          trigger evals
plugins/coremodel/                model and effort picker: hooks/ (TypeScript module), tests/, types/
plugins/coreopinion/              second opinion from GPT: skills/second-opinion/ (SKILL.md, scripts/ask-gpt.sh), evals/
tests/                            bash tests, run by tests/run.sh; lib.sh gives each test a sandbox
docs/                             upgrade guides (migration-*.md) and icon sources
```

## How the parts fit

- **Skills** are the user's entry points (`/corecrew:task`, `/coreopinion:second-opinion`).
  They tell Claude what to do and call scripts through the plugin folder they resolve first (`lib.sh plugin-root`) or the plugin tools.
- **Agents** are the roles `/corecrew:task` hands work to. The designer, localizer, security and
  verifier agents are read-only: a hook refuses their writes.
- **Hooks** (`plugins/corecrew/hooks/hooks.json`) run at session start, before tool calls and at
  stop. They guard secrets and the public code folder, keep one test suite running at a time and
  remind Claude to save. Outside a Core project two things act: the session-start hook
  (it refreshes the plugin's tools and, once per machine, prints a "Core not set up" hint) and the
  read-only checker rule of the code guard; every other hook exits at once and prints nothing.
- **Scripts** hold the logic, so hooks stay thin. At session start `sync-tools.sh` copies them into
  the plugin's data folder (`~/.claude/plugins/data/corecrew-corekit/tools`), the one place git
  hooks run them from; a plugin update therefore reaches git hooks without reinstalling them.
- **Git hooks** (`scripts/git-hooks/`) are installed by `install-hooks.sh` into the code repo
  (pre-commit, pre-push: no internal files in public history) and into the Core (pre-push: the
  GitHub repo must be private).
- **The Core folder.** The private repo (`~/Projects/Core` by default) holds the standards,
  knowledge and each project's `CLAUDE.md` and `docs/` wiki. The code lives in its own repo beside
  it; a gitignored `CLAUDE.local.md` link in the code folder loads the private `CLAUDE.md`.

## Invariants

- Internal files (agent instructions, the wiki) never enter a code repo; two guards and two git
  hooks enforce it.
- Scripts run on macOS bash 3.2 with BSD tools, without `jq`; `tests/test_portability.sh` checks it.
- Scripts never overwrite or delete a user's files; a failed step leaves them as they were.
- Tests run in a sandbox (own `HOME`, `CORE_DIR`) and never touch the real Core or `~/.claude`.
- `coremodel` and `coreopinion` do not depend on `corecrew` or on each other.
