# Changelog

## 0.1.1 — 2026-11-04

- Secrets: the skill lists changed paths first and reads a diff only through one exclusion
  pathspec (`.env*`, keys, certificates, `id_rsa*`, `id_ed25519*`, `*credentials*`), never a
  bare `git diff HEAD`, so a secret file no longer reaches Claude or GPT.
- A `429` or rate-limit error is quoted as it is; "plan limit used up" only when the error says so.

## 0.1.0 — 2026-11-04

- First version: the `second-opinion` skill asks OpenAI's GPT through `codex exec` in a read-only
  sandbox (effort `medium`, `high` on request) and shows its answer labelled as GPT's, followed by
  Claude's own assessment. Changes are applied only after the user's yes, by Claude itself.
