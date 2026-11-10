# Changelog

All notable changes to `coreopinion` are listed here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-11-10

### Changed
- The trigger evals moved out of the plugin to `evals/coreopinion/`, so an install no longer
  carries them. Run them with `bash scripts/eval.sh coreopinion`.
- The plugin icon is 90 kB smaller, with the same pixels.
- `ask-gpt.sh` accepts only a folder made by `ask-gpt.sh --new` (`coreopinion.*`); a hand-made
  `tmp.*` folder is refused and left alone instead of run and removed.

### Fixed
- The read-only review profile no longer lets commands GPT runs create, change or delete files in
  `/tmp` and `/var/tmp`; reading them still works.
- `ask-gpt.sh` says a refused folder "is not a folder made by ask-gpt.sh --new" instead of calling
  a hand-made `mktemp -d` folder "not a mktemp -d folder"; it is still refused and left alone.
- second-opinion: after a timeout the skill points at the removal command at the end of the
  section instead of one that was no longer above.

## [0.3.0] - 2026-11-08

### Added

- An Uninstall section in the README.

### Changed

- The skill description names English phrases and "in any language"; German and Spanish trigger
  evals added.
- After a failed run the script prints 80 log lines instead of 20.
- A one-sentence description; the icon moved to `assets/icon.png` and is named in the manifest.

### Fixed

- Codex no longer offers the skill (`agents/openai.yaml`), and the run script refuses inside a
  Codex session.
- The skill reads the run's output instead of files the script had already removed.
- The run script refused its temp folder when TMPDIR pointed away from where `mktemp -d` put it
  (macOS, the Claude Code sandbox); it now accepts a mktemp folder in `$TMPDIR`, the system temp
  folder or `/tmp`.
- The skill's pre-approved commands match the quoted commands it runs, so the checks before your
  yes ask nothing.
- Checking for Codex and making the temp folder are done by the run script (`--check`, `--new`),
  which takes the prompt on stdin: no hand-written files outside the project and no refused
  `mktemp` command.
- In Codex the skill stops at its first step, and the run script refuses before it touches
  anything, with no "Operation not permitted" noise.
- The skill and README no longer say the run asks nothing: the run after your yes is a new turn,
  and Claude Code may ask once to run `ask-gpt.sh`.

### Security

- One list of secret names (`skills/second-opinion/scripts/secret-patterns.txt`) builds both the
  file filter and the Codex permission profile. The old lists had drifted and let SSH keys other
  than `id_rsa`/`id_ed25519`, `.kube/`, `.pgpass`, `.htpasswd` and Docker config reach GPT; files
  inside folders with a secret name are now left out too.
- The review profile uses the documented `:workspace_roots` and `"deny"`.

## [0.2.5] - 2026-11-05

### Added

- An icon file for the plugin listing (two speech bubbles). No manifest named it yet.

## [0.2.4] - 2026-11-05

### Fixed

- The description no longer says "read-only sandbox" (Codex's `--sandbox read-only` can read the
  whole disk, which this plugin avoids): it says a narrow read-only permission profile.

## [0.2.3] - 2026-11-05

### Fixed

- Files you name were refused as secrets whenever they lay in one folder. Named files now go
  through the skill's own `scripts/allowed-files.sh`, which picks them from the full allowed list.

### Security

- `ask-gpt.sh` runs in and removes only a `mktemp -d` folder right in the temp folder; a wrong path
  (the project, say) is refused and left alone. Before, it would have been deleted.

## [0.2.2] - 2026-11-05

### Changed

- Trigger evals in `evals/`: the skill starts for "ask GPT" and "second opinion from ChatGPT" and
  stays silent for a plain review.

### Fixed

- An interrupted run ends at once; the temp folder is still removed.

### Security

- The permission profile names `credentials`, `kubeconfig`, `secret`, `token` and service-account
  files in any letter case, as the send filter does (Linux is case-sensitive).

## [0.2.1] - 2026-11-05

### Changed

- One question instead of two: the Codex run lives in the skill's own script (`scripts/ask-gpt.sh`),
  which the skill pre-approves, so your yes to the file list is the only question.
- Outside a git repository the skill sends only your own question or text, with an empty folder for Codex.

### Security

- The Codex permission profile blocks every secret the send filter drops: `prod.env`,
  `app.env.local` and service-account JSON files were readable by GPT inside the project.

## [0.2.0] - 2026-11-05

### Added

- Confirmation: before anything is sent, the skill shows the list of files (and the paths left out
  as secrets) and waits for your yes.

### Changed

- What Codex can read is stated truthfully: `--sandbox read-only` blocks writes and network but not
  reads, so the plugin runs a project-only permission profile, `--ignore-user-config` (no user MCP
  servers or plugins) and `web_search="disabled"`.

### Fixed

- The temp folder is removed however the call ends; a repository with no commits is reviewed
  against the empty tree, and a git error is no longer read as "nothing to review".

### Security

- The exclusion list also covers `.npmrc`, `.netrc`, `.pypirc`, `.git-credentials`, `*.tfvars`,
  `*.tfstate`, `*.jks`, `*.keystore`, `*.p8`, `*secret*`, `*token*`, `kubeconfig`, `*.kdbx`,
  `.aws/*` and service-account JSON, and applies to untracked files and files you name.
- The project path is read from a file, so a path with `"`, `$(` or a backtick runs nothing.

## [0.1.1] - 2026-11-04

### Fixed

- A `429` or rate-limit error is quoted as it is; "plan limit used up" only when the error says so.

### Security

- The skill lists changed paths first and reads a diff only through one exclusion pathspec
  (`.env*`, keys, certificates, `*credentials*`), never a bare `git diff HEAD`, so a secret file no
  longer reaches Claude or GPT.

## [0.1.0] - 2026-11-04

### Added

- First version: the `second-opinion` skill asks OpenAI's GPT through `codex exec` in a read-only
  sandbox and shows its answer labelled as GPT's, followed by Claude's own assessment. Changes are
  applied only after your yes, by Claude itself.
