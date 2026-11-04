# Changelog

## 0.2.0 — 2026-11-05

- Confirmation: before anything is sent, the skill shows the list of files (and the paths left out
  as secrets) and waits for the user's yes.
- What Codex can read, stated truthfully: `--sandbox read-only` blocks writes and network but not
  reads (checked with `codex sandbox`), so the plugin now runs a project-only permission profile
  (project folder and minimal system paths; secret patterns blocked inside the project),
  `--ignore-user-config` (no user MCP servers or plugins) and `web_search="disabled"`. README and
  skill no longer say "GPT can read the project" as if that were the whole story.
- The exclusion pathspec now also covers `.npmrc`, `.netrc`, `.pypirc`, `.git-credentials`,
  `*.tfvars`, `*.tfstate`, `*.jks`, `*.keystore`, `*.p8`, `*secret*`, `*token*`, `kubeconfig`,
  `*.kdbx`, `.aws/*` and service-account JSON, and is applied to untracked files and files the
  user names.
- The project path is read from a file (`-C "$(cat "$T/dir")"`), so a path with `"`, `$(` or a
  backtick runs nothing.
- The temp folder is removed by a `trap` however the call ends; a repository with no commits is
  reviewed against the empty tree, and a git error is no longer read as "nothing to review".

## 0.1.1 — 2026-11-04

- Secrets: the skill lists changed paths first and reads a diff only through one exclusion
  pathspec (`.env*`, keys, certificates, `id_rsa*`, `id_ed25519*`, `*credentials*`), never a
  bare `git diff HEAD`, so a secret file no longer reaches Claude or GPT.
- A `429` or rate-limit error is quoted as it is; "plan limit used up" only when the error says so.

## 0.1.0 — 2026-11-04

- First version: the `second-opinion` skill asks OpenAI's GPT through `codex exec` in a read-only
  sandbox (effort `medium`, `high` on request) and shows its answer labelled as GPT's, followed by
  Claude's own assessment. Changes are applied only after the user's yes, by Claude itself.
