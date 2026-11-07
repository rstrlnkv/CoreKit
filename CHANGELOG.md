# Changelog

Every entry starts with a badge: **NEW** is a new capability, **FIX** is a defect fixed, **UPD** is a change to existing behaviour, documentation or internal work.

## 0.8.0 — 2026-11-06
- **NEW** Git worktrees are found wherever they live (Codex keeps them outside `<Projects>`): `lib.sh worktree_of` reads the
  `.git` file of the worktree (`gitdir: <main>/.git/worktrees/<name>`, the main `.git` folder must exist; no git process), and
  `project_of` falls back to it, so `guard-code`, `guard-secrets`, `one-suite` and `stop-remind` are active in such a worktree.
  `guard-code` takes the worktree folder as the code root there. A normal clone outside `<Projects>`, a submodule, a dangling
  or forged `.git` file stay inert. New `lib.sh code-root <path>` prints the code root (the worktree folder, or the main code folder).
  A worktree is trusted only when its main folder knows it (`<main>/.git/worktrees/<name>/gitdir` names `<worktree>/.git`) and the main
  folder is the project's own code folder, so a forged `.git` file in a downloaded folder, in `docs/` or in `.claude/` never moves the guard
  root, gets no links from `prepare.sh` and makes no project. A worktree placed inside the main code folder (`<code>/other/wt`) is its own root
  for `guard-code`, except one placed in `docs/` or `.claude/`, which keeps the main folder's root; a worktree whose main folder was renamed is not judged
  (limit, ADR 005). `code-root` prints a root that holds the folder asked about (a forged gitfile or `core.worktree` cannot point elsewhere), except from `<Core>/<name>/`, where it prints the main code folder.
- **FIX** Several `prepare.sh` or `sync-tools.sh` runs at once no longer report a false "link to somewhere other" or "tools not refreshed" and
  leave no `tools.new.*` behind: a link another run just made counts as skipped, and the tools swap takes a lock folder `<tools>.lock`
  (a dead owner's lock is taken over by an atomic rename, so only one waiter wins; no lock within 10 s: "tools busy", exit 0).
- **UPD** The failures `prepare.sh` relays are a translated message per sync failure kind (a folder that is not ours, a failed copy), in
  host-neutral wording ("start a new session"), and a message when an `AGENTS.md` in the Core blocks the link.
- **NEW** `scripts/prepare.sh [--cwd <dir>] [--part tools|project|host]`: the tools copy, the CLAUDE.local.md and AGENTS.md links
  (also in a worktree outside the main folder), the layout note and the old git hooks note, without waiting for the SessionStart
  hook; on Codex it also says that the corecrew hooks must be trusted (`/hooks`) until `session-start` has run once. A real file
  where a link should go is reported, never replaced. The task, ship and new-project skills run it at Start.
- **UPD** `session-start.sh` hands the tools sync and the project notes to `prepare.sh` (its Claude output is unchanged) and, on
  Codex, records the plugin version in `<settings folder>/state/hooks-seen-codex`. `install-hooks.sh` and `session-start.sh` take the
  tools folder from `lib.sh tools_dir`. New `lib.sh` helpers `host`, `tools_dir`, `hooks_marker_path`, `plugin_version`.
- **NEW** The guards understand Codex's `apply_patch`: `scripts/patch-paths.awk` (through `lib.sh patch_paths`) lists the
  files of a patch. `guard-code` blocks an internal file (`docs/`, `CLAUDE.md`, `AGENTS.md`, `.claude/`) as an Add, an Update
  or a Move destination; `guard-secrets` blocks `.env` and `~/.ssh` as a written file or a move source, lets a delete pass,
  and never scans patch bodies. A patch it cannot read (an `X` line: no `*** Begin Patch`, an unknown `***` line, a header after
  other text on its line) still has its readable paths judged, and its `***` lines are checked raw: `guard-code` refuses a
  component `docs`, `.claude`, `claude.md`, `claude.local.md` or `agents.md`, `guard-secrets` a secret-looking string; with no such line it passes.
  Header lines and paths are trimmed like Codex does (ASCII blanks, VT, FF and the Unicode spaces NBSP, U+3000, ...).
  More than 100 paths in one patch are refused by both guards ("corecrew: this patch names more than 100 files and cannot be checked. Split it into patches of at most 100 files."), because the hook
  timeout is 15 s and a timeout does not block.
- **NEW** Both guards refuse a patch handed to the shell (`guard-code` in every folder, `guard-secrets` inside a Core project), with "corecrew: run patches with the apply_patch tool,
  not through the Bash command line; that form cannot be checked." (exit 2, English and Russian). The rule (`lib.sh shell_patch_refused`)
  reads no shell syntax. A hit: the command text, with every `'`, `"`, `\` and newline deleted, holds `apply_patch`, `applypatch` or
  `apply-patch` in any letter case (also `--codex-run-as-apply-patch`); or `*** Begin Patch` is followed by an `Add File:`,
  `Update File:`, `Delete File:` or `Move to:` marker; or `$'` is followed by a `\x`, `\u`, `\U` or octal escape; or an unquoted word
  with `?`, `*` or `[` whose part after the last `/`, read as a glob, can match one of the three spellings (`../bin/apply_pat?h`,
  `../bin/appl*_patch`). No hit: pass.
  A hit passes only in the simple form: one read-only command (`grep`, `egrep`, `fgrep`, `rg`, `git log|show|diff|grep|status|blame`,
  `git commit` with only `-m -a -am --message -s --amend --no-edit`, `cat`, `head`, `tail`, `ls`, `wc`, `find`) piped only through
  `sort`, `uniq`, `cut`, `tr`, `nl`, `wc`, `head`, `tail`, `grep`, `rg`; quoted text is opaque (a single-quoted string, and a double-quoted
  one without `$`, backtick or `\`, counts as one word), so `grep -E 'apply_patch|applypatch' f` and `git commit -m "x (apply_patch); y"` pass;
  outside quotes no `$` at all (so `$IFS` word splitting cannot hide an option), no backtick, `\`, `;`, `&`, newline, `<`, `>`, parenthesis,
  brace or `!`; no program-running option (git `-c -C -p -O --pag* --ext* --output* --open-files-in-pager*` and any `--o...` that abbreviates
  `--output` or `--open-files-in-pager`, but `--oneline` passes; rg `--pre* --hostname-bin -z`, find `-exec -delete`, sort `--co*`); and an option word that holds the spelling only as `-e`, `--regexp=`, `--grep=`, `--author=`, `--committer=`, `-S`, `-G`,
  `-m`, `--message=`, `-g`, `--glob=`, `-name`, `-iname`, `-path`, `-ipath` with `=`. Passes: `grep -rn apply_patch .`,
  `git log --grep=apply_patch`, `git commit -m "Adds apply_patch guard"`, `cat docs/eval-apply_patch.md`, `find . -name apply_patch.rs`.
  Over-blocking by design: `echo apply_patch`, `cd x && grep apply_patch .`, `grep apply_patch f > out.txt`, `man apply_patch`,
  `command -v apply_patch`, `gh pr create --body "apply_patch"`, `FOO=apply_patch make`, `touch apply_patch.txt`, `grep apply_patch $FILE`. Earlier passes judged
  paths inside shell text, then used a folder gate and a wrapper list, then a tokenizer; each was bypassed (seven review passes in all, five of them against the tokenizer rule: quotes
  inside words, `-c` scripts, `eval`, assignment values, git `!` aliases, `$(...)`, size caps, `$'...'` escapes), so the rule no longer
  parses shell words. On the development machine a command of up to 1 MB took about 0.3 s as one long word (981 KB), about 1 s as 100 000 words (688 KB) and about 2 s as 300 000 quote pairs. This is a best-effort guard, not a security boundary: it catches plain and accidental shell patches and many
  disguised ones, it cannot see a name the shell builds at run time, and the `apply_patch` tool form is the checked path. Known ways past it: variables and `${...}` (`a=apply; ${a}_patch`),
  $(...) and backticks (also empty ones), brace expansion, `$'...'`/`$"..."` splitting (`$'apply'$'_patch'`), a quoted part glued to a glob (`'apply_pat'?h`), extglob (`shopt -s extglob`, then `apply_pat@(c)h`), a glob that expands to a file whose name is an option (`-...`), `IFS` changes, a script file or interpreter that runs `apply_patch`, and `write_stdin`. Over-blocking also includes a pure-wildcard word outside the simple form (`chmod +x scripts/*`, `rm -rf dist/*`), which is a hit by itself. A Delete of `.env` as a tool patch passes, like `rm`.
- **FIX** A TAB or CR inside a patch path is deleted before the path is judged, as Codex does (`do<TAB>cs/a.md` writes `docs/a.md`, `.e<TAB>nv` writes `.env`); before, both guards let such a path pass. Checked against the Codex CLI (`codex --codex-run-as-apply-patch`) in `tests/test_codex_patch_parity.sh`.
- **FIX** A settings file is read once per load in one linear pass; before, a file with one very long line took seconds (old reader on a 250 KB one-line file: 4.6 s for `core-dir`, 9.2 s for `settings` on the development machine; 1 MB: about 67 s; the new reader reads up to 64 KB in about 0.1 s) and a guard hook could pass its 15 s timeout, which does not block. A settings file over 64 KB is not read: one warning, the defaults are used.
- **FIX** An empty or relative `HOME` no longer decides where the plugin writes: `install-hooks.sh` and `session-start.sh` use `$HOME/.claude/plugins/data/corecrew-corekit` only when `CLAUDE_PLUGIN_DATA` is set or `HOME` is absolute. Otherwise `session-start` skips the tools sync and the hint marker (before: `mkdir /.claude` with an empty `HOME`, `<cwd>/rel/.claude/...` with `HOME=rel`), and `install-hooks.sh` says the data folder is unknown and exits 1 without writing.
- **FIX** An empty Core path gives plain messages: `session-start` no longer prints "Core not found at  —" (the HOME warning says why), `setup-core.sh` (also with `--dry-run`, before: "would create ./.git") and `lib.sh core-paths` refuse it, and `adopt.sh` says "no Core" instead of "already inside Core".
- **FIX** Both guards refuse an `apply_patch` call outright, with the message "corecrew: the patch cannot be judged: patch-paths.awk is missing or failed" (English and Russian), when the path reader (`patch-paths.awk`) is missing or awk failed (`lib.sh patch_paths` returns non-zero); before, `guard-code` let a cwd-relative `x.md` in `docs/` and `do<TAB>cs/a.md` pass through its raw `***` check, and `guard-secrets` checked the `***` lines raw, which missed `.e<TAB>nv`. A reader that ran and printed nothing (a patch that names no file, such as `*** Begin Patch` + `*** End Patch`) passes in both guards, as Codex writes nothing for it.
- **FIX** A relative `CORECREW_CONFIG` is ignored, like a relative `XDG_CONFIG_HOME`. With an empty or relative `HOME` there is no default Core (it was `/Projects/Core`): `lib.sh core-dir` prints a warning (en and ru in the session-start hook) and exits non-zero, and the hooks stay inert.
- **UPD** The `## Paths` text of the four skills checks the skill folder (a Codex cache folder, no `"`, `$` or backtick, no `..` component in it) before it runs `plugin-root`.
- **UPD** The messages for a patch that cannot be judged show the offending `***` line in quotes and say what to do (use the `apply_patch` tool with lines like `*** Add File: <full path>`); the Russian text says «не удаётся прочитать»; the shell message says "Bash command line".
- **UPD** `hooks.json` names `apply_patch` in the `guard-code` and `guard-secrets` matchers (re-trust the hooks in Codex `/hooks`).
- **UPD** Tests run `one-suite` and `stop-remind` on Codex-shaped payloads (`tests/fixtures/codex/`, built from the Codex
  source, not captured) and check that every exit 2 writes a non-empty stderr, which Codex requires for a block.
- **NEW** A Codex manifest, `.codex-plugin/plugin.json` (Codex reads it instead of `.claude-plugin/plugin.json`; the
  name, version, description and license must match; there is no root `plugin.json`, which would make Codex skip the hooks).
- **NEW** `agents/openai.yaml` with `allow_implicit_invocation: false` keeps `task`, `new-standard` and `ship` out of
  Codex's skills list, the equivalent of `disable-model-invocation` that Codex ignores.
- **NEW** `lib.sh plugin-root` prints the absolute plugin folder and exits 1 when the script is not in the corecrew plugin (the manifest must be named `corecrew`).
- **UPD** The skills name the plugin folder once, in a `## Paths` section, and use `<skill>`, `<plugin>` and `<scripts>`
  filled in after `lib.sh plugin-root`, instead of `${CLAUDE_SKILL_DIR}` in every command (Codex does not expand it).
- **NEW** A settings file, `~/.config/corecrew/settings` (or the path in `CORECREW_CONFIG`), holds `core_dir`,
  `attribution`, `model_profile` and `ui_language` as `key: value` lines; it is the settings source where there
  is no plugin options screen. Order per key: `CORE_DIR` env (`core_dir` only), plugin option, file, default.
- **NEW** `lib.sh settings [key[=value] ...]` prints the resolved settings and `lib.sh setting-path` the file path;
  the task skill calls them (ship points to task); the skills call `lib.sh core-dir` and relay its stderr.
- **FIX** A relative `core_dir` (for example `Core`) is no longer turned into `<current folder>/Core`: it is
  ignored with a warning and the next source is used. A wrong `attribution` or `model_profile` is ignored the same way. The warning (en and ru) names the
  setting and its source, says where to fix it and which value is used instead; several warnings are one per line. An unknown
  `ui_language` stays silent and falls back to `en`. The file accepts blanks before the colon and a UTF-8 BOM; one that
  cannot be read is named in a warning.
- **UPD** The hooks read `ui_language`, and the skills `attribution` and `model_profile`, through the same resolver;
  the session-start hook names an ignored setting at each session start (not on resume, clear or compact).

## 0.7.2 — 2026-11-06
- **FIX** The `new-project` resume stage now lives in a `## Progress` section of the brief (`Stage: <stage>`)
  instead of a `stage:` front matter field, which the wiki rules do not allow.
- **UPD** `wiki-check` reports front matter fields beyond the six; `wiki-migrate` moves a brief's one-line
  stage into `## Progress` (kept and warned when it is multi-line, the body has `## Progress` or ends in an open
  code fence) and warns about other extra fields.

## 0.7.1 — 2026-11-06
- **FIX** The Core pre-push hook asks GitHub up to three times, 2 s apart, whether the Core repository is
  private, so one network timeout no longer blocks a push. A "not private" answer still blocks at once.
- **UPD** The Core README template names the code folder `../<Name>/` and lists the `AGENTS.md` link, the
  generated `docs/INDEX.md`, the Obsidian vaults and the optional `session-rules.md`. An existing
  Core README is never changed.

## 0.7.0 — 2026-11-06
- **NEW** The wiki index is generated: `docs/INDEX.md` is built from the front matter of the pages
  (`wiki-index.sh`), so nobody edits it by hand; `wiki-check.sh` reports it when it is out of date.
- **NEW** Every project's `docs/` is one Obsidian vault: scaffold adds `wiki.base` (a table of all pages)
  and `.obsidian/`.
- **UPD** Front matter: `type` replaces `title`; page references are wikilinks (`[[page#Heading]]`), not
  `docs/page.md § Heading`. Specs and plans live in `docs/specs/` and `docs/plans/` (before:
  `docs/superpowers/`).
- **NEW** `wiki-check.sh` has new checks for the new format (front matter fields, wikilink targets, the
  generated INDEX).
- **NEW** New `AGENTS.md` link in the code folder next to `CLAUDE.local.md`, made by scaffold and adopt and
  repaired at session start. Note for coreopinion/Codex users: `AGENTS.md` now exposes the private
  `CLAUDE.md` to Codex in that folder, so `second-opinion` runs can send its content to OpenAI.
- **NEW** New `scripts/wiki-migrate.sh` converts a 0.6 wiki to the new format (front matter, wikilinks,
  `docs/superpowers/` to `docs/specs/` and `docs/plans/`, INDEX); `adopt` runs it too.
- **NEW** Upgrade: the first `/corecrew:task` on a 0.6 project offers the migration: it shows a
  `wiki-migrate.sh --dry-run` first and converts the wiki only on your ok, as its own commit.
  The old lines in the project's `CLAUDE.md` (`docs/superpowers`, map lines) are reported for a
  hand edit; the script never changes that file. By hand:
  `bash <plugin>/scripts/wiki-migrate.sh <Core>/<project> --dry-run`, then again without it.

## 0.6.6 — 2026-11-05
- **FIX** The one-suite hook no longer lets several test runs through when many waiters (8 in the stress
  test) find the same stale turn at the same instant. The takeover now runs under a short lock
  (`flock` when installed, else a `mkdir` lock), judges the turn again once it holds the lock, and
  never spins (the wait for the lock is bounded). This replaces the "known limit" named in 0.6.3.
## 0.6.5 — 2026-11-05
- **NEW** New skill `/corecrew:ship [patch|minor|major|<version>]`: releases the current branch through the
  `release` path of `/corecrew:task`, checks that the tests left the global git config unchanged,
  then, after your explicit yes, fast-forwards `main` to the branch and pushes it. Never forces.

## 0.6.4 — 2026-11-05
- **UPD** An icon for the plugin (and for coremodel and coreopinion): the directory listing wants one, and
  `claude plugin validate` no longer warns. Sources in `docs/icons/`.

## 0.6.3 — 2026-11-05
- **UPD** The one-suite hook names its two known limits in its header (several waiters finding one stale turn
  in the same instant; a 3 s grace against a slowly answered permission prompt). No behaviour change.
- **UPD** README and tests: repo paths named in the READMEs must exist; Vite recipe verified (see stacks.md).

## 0.6.2 — 2026-11-05
- **FIX** The read-only checkers' rule, after a second opinion from GPT: any `cd` ends relative writes
  (`(cd /tmp); rm x` and `cd /tmp | rm x` run rm where the command started, so the folder is not
  tracked; write logs to an absolute temp path); `git push`, `git config --global`/`--system`/`--file`,
  `--git-dir`/`--work-tree` and `git worktree add` are refused even with `-C` into a temp folder;
  `cp`/`mv` into a folder also judge `<folder>/<file name>`, which may be a link into the project;
  `sed` with a `w` command or `-f`, and grouped curl options (`-sSLo FILE`, `-D`, `-c`) are judged.

## 0.6.1 — 2026-11-05
- **FIX** The read-only checkers' rule, after an independent review: it follows `cd` (a relative write
  after a cd to an unknown folder is refused), looks into `$(...)` and backticks, and also refuses
  `find -delete`/`-exec`, `xargs rm`, `sort -o`, downloads and unpacking into the current folder,
  `ln`, more git changes (`branch <name>`, `config <key> <value>`, `remote add`, `fetch`,
  `--output`), and any command it cannot read whole or when the check itself fails. Reads it wrongly
  refused now pass: `git tag -l`, `git stash list`, `git worktree list`, `perl -Ilib`, `chmod -R u+w /tmp/x`.
- **UPD** The six agents' descriptions are 120 characters at most and say /corecrew:task calls them: they
  are listed to the model in every session, project or not (about 500 characters less each turn).
- **UPD** Trigger evals in `plugins/corecrew/evals/` (`claude plugin eval`): new-project starts for a new
  app in Russian or English and stays silent for a feature or a Jira project. The old scenario
  `evals/evals.json` is gone.
- **UPD** Tests: the wiki fixtures keep their CLAUDE.md as `CLAUDE.md.in`, so the repo tracks no internal
  file but its own CLAUDE.md.

## 0.6.0 — 2026-11-05
- **UPD** The plugin lives in `plugins/corecrew/` of the repo (the marketplace now points there). An install
  copies only the plugin, not the repo's docs, tests and the two other plugins. The name, the
  settings and the plugin data folder stay the same: an update needs nothing from you.
- **NEW** The read-only checkers (designer, localizer, security, verifier) can change nothing but the temp
  folders: a hook refuses their Bash writes, removals, in-place edits and git changes, wherever they
  run. Before, only their instructions said so.

## 0.5.3 — 2026-11-05
- **UPD** The session-start hook also runs when a session is forked, so a fork gets the project context too.
- **FIX** A quick test suite re-run at once (fix one line, run again) no longer waits about 10 s: the
  one-suite hook's grace is 3 s and it checks every second.
- **UPD** `tests/run.sh` names a test file that skipped (coremodel without the `claude` CLI) after
  ALL TESTS PASSED instead of hiding it.
- **UPD** Cleanup: a dead fallback in the stop hook; banners on two shipped plans; migration-0.3 lists all
  coremodel settings. Second refactor pass.

## 0.5.2 — 2026-11-05
- **FIX** Both guards judge the command line handed to `bash -c`, `sh -c`, `zsh -c`, `dash`, `ksh` and
  `eval`: `bash -c "cat .env"` and `bash -c "echo x > CLAUDE.md"` are blocked like the plain commands.
  Interpreters (`python -c`, `node -e`), `find -exec`, `git show REV:.env`, `dd` and `curl -F @file`
  are still not seen; the README now says so.
- **FIX** The one-time "Core not set up / not found" hint is shown to the person (a `systemMessage`), not
  only handed to the model; before, it was marked as shown even when nobody read it.
- **UPD** README: the Claude Code version it needs (2.1.271 for corecrew, 2.1.287 for coremodel) and a short
  "What the hooks do" section. The `task` description uses `[task]` instead of `<task>`.
- **UPD** Docs: finished plans and the old effort-picker documents carry a "historical" banner.

## 0.5.1 — 2026-11-05
- **FIX** guard-secrets: a secret name written with quotes or a backslash (`.e'n'v`, `.\env`, `~/.s""sh/id_rsa`)
  is judged after quote removal; globs that can match `.env`, `.env.*` or `.ssh` (`.e*`, `.en?`,
  `.[e]nv`, `~/.s*/id_rsa`) are blocked; `*`, `.*` and `*.env` still pass.
- **FIX** Both guards: wrapper options that take a value are skipped, so `timeout 5 cat .env`,
  `nice -n 5 cat .env`, `sudo -u root cat .env`, `env -u X cat .env` and `timeout 5 tee docs/a` are
  seen. `timeout`, `stdbuf`, `setsid`, `caffeinate`, `ionice` count as wrappers.
- **FIX** `zip a.zip src -x .env` is no longer blocked (`-x`/`-i` take patterns).
- **FIX** With HOME unset, `~/.ssh` is still protected (HOME comes from the account).
- **FIX** A `core_dir` that is a symlink: the code folders next to the link are recognised.
- **FIX** guard-code blocks a file written directly under `.claude/worktrees/`.
- **FIX** one-suite sees `echo $((1<<3)); swift test` as a test run.
- **UPD** Docs: CLAUDE.md layout, README (evals, release/adopt, session-rules), migration-0.3 names
  `coremodel`, old specs carry a "superseded / now true" note.
## 0.5.0 — 2026-11-04
- **NEW** New projects keep their code beside the Core, in `<Projects>/<Name>` (Projects is the folder
  that holds the Core, for example `~/Projects/MyApp`). Private files stay in `<Core>/<name>/`.
  Launch Claude Code in the code folder.
- **NEW** Session start makes and repairs `CLAUDE.local.md` in the code folder, a gitignored link to
  `<Core>/<name>/CLAUDE.md`, so the private instructions load there. A real file or a link that
  points elsewhere is never overwritten; the session start says what to fix.
- **UPD** Project rules move into `CLAUDE.md`: there is no `.claude/rules/` template any more.
- **UPD** `/corecrew:task adopt` keeps the repo where it is. It adds `.worktreeinclude`, folds tracked
  `.claude/rules/` into `CLAUDE.md`, warns about nested `CLAUDE.md` files, and moves only
  old-layout `<Core>/<name>/code` folders (to `<Projects>/<name>`), folding their
  `<Core>/<name>/.claude/rules/` into `CLAUDE.md` too.
- **UPD** `guard-code` guards the code folder beside the Core, as it did `<Core>/<name>/code`.
  `docs/superpowers/` stays private even when `docs/` is listed as public.
- **UPD** Core schema 2: a schema 1 Core gets one layout note at session start; the setup command changes
  only the schema line of `.coredev`.
- **UPD** Existing projects (code in `<Core>/<name>/code`): `/corecrew:task` stops in them and asks you to
  run `/corecrew:task adopt <Core>/<name>/code` first, which moves the code folder to
  `<Projects>/<name>`. `save` and the hooks still work there until then.

## 0.4.0 — 2026-11-04
- **UPD** `AGENTS.md` (the agent-instructions file Codex, Cursor and other tools read) is now an internal
  file, like `CLAUDE.md`: `guard-code` blocks writing it at any depth under `<Core>/<project>/code/`
  (file tools and Bash), the git pre-commit and pre-push checks block committing it
  (`blocked-patterns`), and the new-project `.gitignore` template lists it. Its place is
  `<Core>/<project>/AGENTS.md`.
- **UPD** `/corecrew:task adopt` moves a root `AGENTS.md` to `<Core>/<name>/` with `CLAUDE.md`, and adds
  the `AGENTS.md` ignore line. An `AGENTS.md` that is a symlink is refused, as `CLAUDE.md` is.
- **UPD** Existing projects: a code repo that already tracks `AGENTS.md` can no longer commit changes to
  it. Move it by hand: copy it to `<Core>/<project>/AGENTS.md`, then in `code/` run
  `git rm AGENTS.md`, add the line `AGENTS.md` to `.gitignore`, and commit.

## 0.3.1 — 2026-11-04
- **UPD** Plugin lists show the names as CoreCrew and CoreEffort (`displayName` in the manifests),
  not "Corecrew" and "Coreeffort". Commands keep their lowercase names.

## 0.3.0 — 2026-11-04
- **UPD** The plugin is now `corecrew` (brand CoreCrew); the marketplace and repo stay `corekit`.
  Commands are `/corecrew:...`, agents `corecrew:<role>`, hook messages start with `corecrew:`.
  The marketplace `renames` map moves `coredev` and `corekit` installs to `corecrew`.
  Steps: [docs/migration-0.3.md](docs/migration-0.3.md).
- **UPD** The plugin data folder is now `corecrew-corekit`. Git hook shims of 0.2.x (`# coredev hook shim`)
  count as old: the session start names them, and `install-hooks.sh` replaces them.
- **UPD** `<Core>/.coredev` keeps its name, so existing Cores need no change.
- **UPD** The second plugin `effort-picker` is now `coreeffort` (0.2.0); its command is `/coreeffort`.

## 0.2.1 — 2026-11-04
- **NEW** New plugin setting `ui_language` (`en` default, `ru`): the language of every message the
  hooks show. All hook texts live in one table, `hooks/messages.sh`; a new language is one more
  column there. Commands, paths and file names in the messages stay as they are.

## 0.2.0 — 2026-11-03
- **UPD** Hooks read settings from the plugin options. When `core_dir` is not the default and the
  options are not set (for example under `--plugin-dir`), the hooks stay silent: set
  `core_dir` in `/plugin` → Installed → coredev → Configure options.
- **FIX** The release attribution check matches only trailer lines (`Co-Authored-By:`,
  `Generated with` at a line start), the same lines `save --no-attribution` drops.
- **UPD** The plugin is now `coredev` (the marketplace and repo stay `corekit`). The marketplace
  `renames` map migrates old installs; run `/plugin install coredev@corekit` once.
  Commands are `/coredev:...`.
- **NEW** Plugin settings (`userConfig`): `core_dir`, `attribution` (`allow`/`forbid`),
  `model_profile` (`economy`/`balanced`/`strong`).
- **UPD** `feature-dev` (from `claude-plugins-official`, or from claude.ai) is needed by `/coredev:task`
  but is not declared as a hard dependency: a hard dependency stopped `coredev` from loading
  when `feature-dev` came from claude.ai sync or another marketplace. Install it with
  `/plugin install feature-dev@claude-plugins-official`; `task` checks for it at start.
- **FIX** Settings: a value that is still the literal text `${user_config.…}` (plugin not configured)
  counts as unset, so scripts fall back to `CLAUDE_PLUGIN_OPTION_*` and then the defaults.
- **UPD** Added `tests/test_manifest.sh`.
- **UPD** Git hooks installed in repos are small shims that run the plugin's scripts from a stable
  copy in the plugin data folder (`sync-tools.sh`); the copy is refreshed on version change, so
  hooks no longer go stale after an update. The copy is also refreshed when the scripts' content
  changes without a version bump, and a folder that is not a coredev tools copy is never replaced. `install-hooks.sh` fails with exit 1 when its hook
  sources are missing, and no longer copies `blocked-patterns` into `.git/hooks`.
- **UPD** The Stop hook ships with the plugin (`hooks/hooks.json`, runs `hooks/stop-remind.sh`) and
  stays silent outside a Core project. New projects no longer get a `hooks` block in
  `code/.claude/settings.local.json`; existing projects must remove theirs (migration step 4).
- **UPD** `install.sh` and its test are removed: install with `/plugin install coredev@corekit`.
  The README says the plugin needs Claude Code 2.1.271 or newer.
- **UPD** The project `CLAUDE.md` template names `save` and `undo-step` as plugin tools that Claude
  runs, instead of `Core/bin/`.
- **NEW** Added `/coredev:new-standard`: an interview, a research subagent and `scripts/check-standard.sh`
  help the user write their own standards into `<Core>/standards/`; the plugin ships none.
  `reference/knowledge.md` defines the knowledge files (`docs/knowledge/`, `<Core>/knowledge/`).
- **UPD** Added `docs/migration-0.2.md`: the seven steps for an existing 0.1.x user.
- **UPD** `.env.example`, `.env.sample` and `.env.template` are allowed everywhere: by `guard-secrets`, by
  the code repo's pre-commit and pre-push hooks, and by the new-project `.gitignore`.
- **UPD** `/coredev:task adopt` adds the missing coredev ignore lines (`CLAUDE.md`, `.claude/`, `.env`, ...)
  to the repo's `.gitignore` in its "Move internal Claude files to Core" commit, so a local
  `.claude/settings.local.json` or a `.claude/worktrees/` worktree never blocks `save`.
- **NEW** Added `/coredev:task <task>`: the orchestrator runs a task along one of four paths (`fix`,
  `full`, `question`, `batch`) and ends with a report with proof and one commit.
- **NEW** `/coredev:task release <version>` runs seven checks (tests, wiki, version, changelog) and commits the release; it tags and pushes nothing.
- **NEW** `/coredev:task adopt <folder>` (`scripts/adopt.sh`) moves an existing project into the Core
  layout, keeps its git history and adds the missing wiki pages.
- **NEW** Six agents: `engineer`, `tester`, `security`, `verifier`, `localizer`, `designer`.
- **NEW** Five hooks: `session-start` (refreshes the tools, shows the project context), `one-suite`
  (one test run at a time), `guard-code` (no internal files in `code/`), `guard-secrets`
  (no `.env`, no `~/.ssh`) and `stop-remind` (the save reminder).
- **NEW** Wiki rules (`reference/wiki.md`) and `scripts/wiki-check.sh`; `new-project` and adopt create a
  wiki that passes the check.
- **NEW** Knowledge: lessons per project (`docs/knowledge/`) and for all projects (`<Core>/knowledge/`),
  read by the agents before they work.
- **UPD** Install and update with the `claude plugin` commands on Mac and Windows (README); Windows
  needs Git for Windows.
- **UPD** Added the end-to-end fixture `tests/fixtures/make-test-coredev.sh` (a tiny project with a
  planted bug) and `tests/test_fixture.sh`.

## 0.1.1 — 2026-11-03
- **FIX** `save` reinstalls hooks when the code pre-push hook or `blocked-patterns` is missing
  (without the patterns file every commit was blocked and `save` never recovered).
- **FIX** `install.sh` no longer replaces a same-named skill it did not install; installed folders
  get a `.corekit` marker, `--force` replaces anyway. A symlinked skill folder is left alone,
  and it refuses to install into the repo's own `skills/` (that deleted the source).
- **UPD** Stop hook reminds once per set of uncommitted changes and tells Claude not to save while
  it waits for the user's answer. It notices edits in untracked files with non-ASCII names
  and in repos without commits, and stays fast with thousands of untracked files.
- **FIX** `scaffold.sh` joins a multi-line `--purpose` into one line (PROJECTS.md entry was split).
- **UPD** Test suite passes on macOS (bash 3.2, BSD utilities); new `tests/test_portability.sh`
  blocks bash 4 and GNU-only constructs. Added CLAUDE.md for contributors.
- **UPD** Upgrade note: existing docs repos keep their old `Core/bin/` copies; copy the new `save`
  and `stop-remind.sh` from `skills/new-project/core-bin/` there to get the fixes.
  (Historical: that folder is gone; since 0.2 the tools live in the plugin's `scripts/` and `hooks/` and
  nothing is copied into the docs repo.)

## 0.1.0 — 2026-11-03
- **NEW** First public release: `new-project` skill (interview, stack and architecture analysis,
  scaffold, private docs repo, protective git hooks, `save` / `undo-step`), per-user settings,
  Claude Code plugin and marketplace manifests.
