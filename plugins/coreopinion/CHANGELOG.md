# Changelog

## 0.2.3 — 2026-11-05

- Files you name were refused as secrets whenever they lay in one folder (a single file in a
  subfolder was enough): `git ls-files -- <files> <excludes>` lists nothing then, and with glob
  excludes it even lets a secret through (git 2.54, macOS). Named files now go through the skill's
  own `scripts/allowed-files.sh`, which picks them from the full allowed list.
- `ask-gpt.sh` runs and removes only a `mktemp -d` folder right in the temp folder; a wrong path
  (the project, say) is refused and left alone. Before, it would have been deleted.

## 0.2.2 — 2026-11-05

- The permission profile names `credentials`, `kubeconfig`, `secret`, `token` and service-account
  files in any letter case, as the send filter does (macOS matched them anyway; Linux is case-sensitive).
- An interrupted run ends at once; the temp folder is still removed.
- Trigger evals in `evals/`: the skill starts for "ask GPT" and "second opinion from ChatGPT" and
  stays silent for a plain review.

## 0.2.1 — 2026-11-05

- The Codex permission profile now blocks every secret the send filter drops: `prod.env`,
  `app.env.local` and service-account JSON files were readable by GPT inside the project, though
  the README said otherwise. Checked with `codex sandbox`; the test runs it where Codex is installed.
- One question instead of two: the Codex run lives in the skill's own script
  (`scripts/ask-gpt.sh`), which the skill pre-approves, so your yes to the file list is the only
  question; no allow rule in your settings is needed. A sandbox exclusion, if you use Claude Code's
  sandbox, now names the script.
- Outside a git repository the skill sends only the user's own question or text, with an empty
  folder for Codex, instead of an unreachable flag note.

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
