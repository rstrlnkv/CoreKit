# Changelog

## 0.1.0 — 2026-11-04

- First version: the `second-opinion` skill asks OpenAI's GPT through `codex exec` in a read-only
  sandbox (effort `medium`, `high` on request) and shows its answer labelled as GPT's, followed by
  Claude's own assessment. Changes are applied only after the user's yes, by Claude itself.
