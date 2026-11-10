# Architecture

A bird's-eye view of the repository for contributors. CoreKit is a marketplace (`corekit`) for
Claude Code and the Codex CLI that holds three independent plugins. Nothing here is compiled
except the TypeScript module of `coremodel`.

## Where things live

```
.claude-plugin/marketplace.json   the marketplace: lists the three plugins (Claude Code reads it)
.agents/plugins/marketplace.json  the Codex marketplace: corecrew and coremodel only (Codex reads it first)
plugins/corecrew/                 project workflow
  .claude-plugin/plugin.json      Claude Code manifest: name, version, settings (userConfig), icon
  .codex-plugin/plugin.json       Codex manifest: the same name, version and description, Codex listing fields
  assets/icon.png                 the plugin icon (SVG source in docs/icons/)
  skills/                         new-project, task, ship, new-standard (SKILL.md + references/)
    new-project/scripts/          scaffold.sh, merge-generated.sh, preflight.sh (scaffold.sh and
                                  preflight.sh source scripts/lib.sh)
    */agents/openai.yaml          Codex: keeps task, ship and new-standard out of implicit invocation
    task/references/codex.md      Codex: the task chain with Codex subagents
    task/references/architect-explorer.md  the architect and explorer roles when feature-dev is
                                  absent (Claude Code's Plan/Explore agents, and Codex)
  agents/                         engineer, tester, security, verifier, localizer, designer
  hooks/                          hooks.json and the five hook scripts, messages.sh for their texts
                                  and for the settings warnings of the lib.sh CLI
  scripts/                        the machinery in portable bash; each file's header says what it does
    lib.sh                        shared helpers: scripts and hooks source it, or run it as a command
    lib-*.sh                      the parts lib.sh sources: lib-paths.sh, lib-settings.sh, lib-layout.sh,
                                  lib-host.sh, lib-scaffold.sh, lib-json.sh; and, each for one subcommand
                                  only, lib-codex-profile.sh, lib-role-model.sh, lib-tree-state.sh
    shell-patch.sh                the check for a Codex patch handed to the shell (sourced by both guards)
    guard-lib.sh                  what both guards share: the refusal, the tokenizer call, the patch reader
    bash-lex.awk                  the one Bash tokenizer, for bashlex-guard-code.awk (the code guard: the
                                  files a command writes), bashlex-guard-secrets.awk (the secrets guard)
                                  and bashlex-readonly.awk (the read-only checker rule)
    patch-paths.awk               the paths of a Codex apply_patch patch, for both guards
    prepare.sh, setup-core.sh     a host and project brought up to date; the Core created or completed
    sync-tools.sh                 the scripts copied into the plugin's data folder (tools/)
    install-hooks.sh, git-hooks/  the git hook bodies with their two pattern lists, and the installer
                                  of the shims that run them
    save, undo-step, _locate.sh   one step saved or undone in both repos; _locate.sh finds the repos
                                  and checks that each can commit
    adopt.sh                      an existing project brought into the layout, in phases (preconditions,
                                  plan, stage, commit, move, finish); its rule readers are rule-block.awk
                                  and fold-rules.awk
    wiki-*.sh                     the wiki: pages, index, checks, migration from an older format
    wiki-check.awk                the checks of one wiki page, run by wiki-check.sh
    wiki-migrate.awk              one page converted to the current format, run by wiki-migrate.sh
    check-standard.sh             the checks of one standard file (new-standard): a script only one
                                  skill uses may stay here when the skill reaches it through `<scripts>`
  reference/                      texts the skills share: wiki.md and knowledge.md (the rules the
                                  agents follow), and these two:
    codex-host.md                 the Codex host reference that every skill follows in Codex
    older-formats.md              how a project made by an older version is brought up to date
  templates/                      what new-project, adopt, setup-core and wiki-migrate copy or fill in:
                                  CLAUDE.md.tmpl, code/, core/, docs/
plugins/coremodel/                model and effort picker
  hooks/                          the Claude Code module (TypeScript): register.tsx wires the hooks;
                                  session.ts the module variables, host.ts what the host says and
                                  the debug log, ask.ts the classifier call and its failures,
                                  hold.ts the held pair, the band and the pane presses, pick.ts the
                                  pick with its counts and transcript rows, actions.ts the band's
                                  buttons, command.ts /coremodel, views.tsx the footer, pane, rows
                                  and band; classifier.ts, models.ts, policy.ts and locales/ make no
                                  calls on `$` (a $.state key lives in the one file that uses it)
  codex/                          hint.sh and hooks.json: the Codex hint
  types/index.d.ts                the plugin's type contract (the host API types are written by
                                  Claude Code into .claude-plugin/types/, which git does not track)
plugins/coreopinion/              second opinion from GPT (Claude Code only)
  skills/second-opinion/          SKILL.md; scripts/: ask-gpt.sh (the Codex run), allowed-files.sh and
                                  secret-patterns.txt (the one secret list)
    agents/openai.yaml            Codex: keeps the skill out of Codex (coreopinion is Claude Code only)
scripts/commit-subjects.sh        the check of this repo's own commit subjects (CI job and optional commit-msg hook)
scripts/eval.sh                   runs one plugin's trigger evals on a copy it assembles (real model calls,
                                  not part of tests/run.sh)
evals/corecrew/, evals/coreopinion/  the trigger evals (does a skill start when it should); they live outside
                                  the plugins, so an install does not carry them
tests/                            bash tests, run by tests/run.sh; lib.sh gives each test a sandbox
                                  and the shared helpers (snap_tree: the one "nothing changed" snapshot);
                                  lib-hook.sh holds the hook-test helpers, builds hook input (hook_event)
                                  and asks a real Codex which hooks it loads (codex_hooks_list)
  coremodel/                      coremodel's module tests, outside the plugin so an install does not carry
                                  them: *.test.ts(x), one file per module or surface, run by
                                  `claude plugin test` on a copy that tests/test_coremodel.sh assembles;
                                  world.ts is the host beneath them and surfaces.tsx what they draw and
                                  press; quality.sh is the manual check of the classifier
docs/                             the upgrade guide (migration-0.3.md) and icon sources (icons/)
```

## Hosts

```
                     Claude Code                         Codex CLI
manifest             .claude-plugin/plugin.json          .codex-plugin/plugin.json
corecrew hooks       hooks/hooks.json (all five)         the same hooks/hooks.json
coremodel hooks      hooks/ (TypeScript module)          codex/hooks.json -> codex/hint.sh
coreopinion          yes                                 not supported
hook trust           on install                          after you enable them in /hooks
```

Each hook rule, by host (the test file holds the cases of both hosts):

| Rule | Claude Code | Codex | Test |
|---|---|---|---|
| session-start | yes | yes | tests/test_hook_session_start.sh, tests/test_session_start_golden.sh |
| one-suite | yes | yes | tests/test_hook_one_suite.sh |
| guard-code, file tools | Write, Edit, NotebookEdit | apply_patch | tests/test_hook_guard_code.sh |
| guard-code, Bash writes | yes | yes | tests/test_hook_guard_code.sh |
| read-only checker rule (guard-code) | everywhere | no: not for Codex subagents | tests/test_hook_readonly_agents.sh; Codex: tests/test_hook_guard_code.sh (`no ro_agent for a Codex agent_type`) |
| guard-secrets | Read, Grep, Glob, Edit, Write, NotebookEdit, Bash | apply_patch, Bash | tests/test_hook_guard_secrets.sh, tests/test_hook_guard_secrets_pins.sh (the single-rule pins) |
| shell-patch refusal (both guards) | no | guard-code in any folder, guard-secrets inside a project | tests/test_shell_patch.sh, tests/test_shell_patch_exec.sh |
| apply_patch that cannot be checked: over 100 paths, or the reader missing (both guards); an unreadable text that names an internal path (guard-code) | no | guard-code in any folder, guard-secrets inside a project | tests/test_hook_guard_code.sh, tests/test_hook_guard_secrets.sh |
| stop-remind | yes | yes | tests/test_stop_hook.sh |
| coremodel hint (codex/hint.sh) | no (the TypeScript module) | yes | tests/test_coremodel_codex.sh |

- **Manifests.** Each host reads its own manifest. The shared fields (name, version, description,
  licence) must match; `tests/test_manifest.sh` checks it. coremodel's Codex description differs
  on purpose: in Codex it only hints. A root `plugin.json` would make Codex skip the hooks, so there
  is none.
- **Hooks in Codex.** Codex fires PreToolUse for its shell (`Bash`) and for `apply_patch`; it has no
  read, search or list tools to hook. The guards therefore read `apply_patch` patches with
  `scripts/patch-paths.awk`. A rule that exists for one host runs only on that host: the refusal of
  a patch handed to the shell runs only in Codex, where guard-code refuses it in any folder and
  guard-secrets inside a project. The read-only checker rule acts everywhere in Claude Code and not
  for Codex subagents (see Codex sandbox below).
- **Hook trust.** Codex runs a plugin's hooks only after the person enables them in `/hooks`, and
  again after each update. `prepare.sh` says so until the session-start hook has run once.
- **Settings.** Claude Code passes the plugin options to the hooks. Codex has no options screen, so
  `lib.sh` also reads `~/.config/corecrew/settings`.
- **Codex sandbox.** Codex keeps `.git` read-only, so `save` asks for approval to run outside it.
  Codex subagents cannot be made read-only, so the read-only steps are checked before and after.

## How the parts fit

- **Skills** are the user's entry points (`/corecrew:task`, `/coreopinion:second-opinion`). They
  find their plugin folder first (`lib.sh plugin-root`), then call scripts from it.
- **Agents** are the roles `/corecrew:task` hands work to. The designer, localizer, security and
  verifier agents are read-only: in Claude Code a hook refuses their writes.
- **Hooks** (`plugins/corecrew/hooks/hooks.json`) run at session start, before tool calls and at
  stop. They guard secrets and the public code folder, keep one test suite running at a time and
  remind the agent to save. Outside a Core project the session-start hook (tools refresh, a warning
  for an invalid setting and a one-time "Core not set up" hint) acts in both hosts. Claude Code also
  runs the read-only checker rule there. In Codex the code guard also refuses, in any folder, a
  patch handed to the shell and a patch it cannot check (more than 100 files, a missing reader, or
  an unreadable patch that names an internal path); the rule-by-host table under Hosts has the rows.
  "Outside a Core project" means the session folder. The code guard judges the path written, so a
  write into a project's code folder is refused from any session folder. The secrets guard, the
  one-suite hook and the Stop reminder act only when the session folder is in a project.
- **Scripts** hold what is shared; a hook holds its own rule. What two hooks, or a hook and a
  script, share lives in `plugins/corecrew/scripts/` (`lib.sh` and its parts,
  `plugins/corecrew/scripts/guard-lib.sh`, `plugins/corecrew/scripts/shell-patch.sh`, the awk
  readers) or in `plugins/corecrew/hooks/messages.sh`. A script or hook sources `lib.sh`, and `lib.sh`
  sources its parts (`lib-*.sh`). The guards read a Bash command with awk, not with a shell: the
  code guard, the secrets guard and the read-only checker rule each with the one tokenizer
  `bash-lex.awk` and their own part (`bashlex-guard-code.awk`, `bashlex-guard-secrets.awk`,
  `bashlex-readonly.awk`). `sync-tools.sh` copies the scripts into
  the plugin's data folder (`tools/` under `~/.claude/plugins/data/corecrew-<marketplace>/` in
  Claude Code and `~/.codex/plugins/data/corecrew-<marketplace>/` in Codex, `$CODEX_HOME` when
  set), the one place git hooks run them from, so a plugin update reaches the git hooks without
  reinstalling them.
- **Git hooks.** `scripts/git-hooks/` holds the hook bodies and the two pattern lists.
  `install-hooks.sh` writes a shim into the code repo (pre-commit, pre-push) and into the Core
  (pre-push: the GitHub repo must be private); the shim runs the body from the tools copy. The code
  repo hooks refuse what `scripts/git-hooks/blocked-patterns` lists, except what `allowed-patterns` lists
  (the `.env` templates). The names are listed in
  [SECURITY.md](SECURITY.md#known-limits-of-the-hooks).
- **Texts and languages.** A text a hook prints, or one a person reads with no model in between,
  lives in its plugin's message table in every language: `plugins/corecrew/hooks/messages.sh`
  (`msg`, the languages in `MSG_LANGS`) and `plugins/coremodel/hooks/locales/`. The output of a
  script a skill runs is English protocol; the model relays it in the person's language. Named
  exceptions stay English: the git hooks and the output of `install-hooks.sh`, coremodel's Codex
  hint (`plugins/coremodel/codex/hint.sh`) and the read-only checker's refusal, which only a
  subagent reads (`MSG_EN_ONLY` in messages.sh). Manifests are English.
  `tests/test_hook_messages.sh` allows Cyrillic in shipped plugin code only in those tables (and in
  comments and in the example prompts of coremodel's classifier, which no person reads).
- **The Core.** The private repo (`~/Projects/Core` by default) holds the standards, knowledge and
  each project's `CLAUDE.md` and `docs/` wiki. The code lives in its own repo beside it; a
  gitignored `CLAUDE.local.md` link in the code folder loads the private `CLAUDE.md`.

## Invariants

- Internal files never enter a code repo. `CLAUDE.md`, `AGENTS.md` and `.claude/` are kept out by
  the code guard and by the git hooks. Secret files are kept out of commits and pushes by the git
  hooks; the secrets guard only refuses to read or write `.env` files and `~/.ssh` inside a project
  (the names: [SECURITY.md](SECURITY.md#known-limits-of-the-hooks)). The wiki (`docs/`) is kept out only by the code guard,
  which is best effort. Under `docs/` the git hooks block only its `superpowers/` folder, where
  planning plugins write their drafts; the rest of `docs/` passes, because a project may publish docs there.
- The host's permissions and sandbox are the security boundary; the hooks are a best-effort second
  line (see [SECURITY.md](SECURITY.md#threat-model)).
- Scripts run on macOS bash 3.2 with BSD tools, without `jq`; `tests/test_portability.sh` checks it.
- The hook budgets (the programs each hook starts per call) are pinned in `tests/test_hook_cost.sh`;
  the test is the source.
- Scripts never overwrite or delete a user's files; a failed step leaves them as they were.
- Tests run in a sandbox (own `HOME`, `CORE_DIR`) and never touch the real Core, `~/.claude` or `~/.codex`.
- No plugin depends on another: each installs alone. `tests/test_manifest.sh` fails when a file of
  one plugin names a path into another. coremodel's Codex hint may read corecrew's settings file,
  as data only.
