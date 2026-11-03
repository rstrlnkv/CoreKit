# Changelog

## 0.1.1 — 2026-11-03
- `save` reinstalls a missing code pre-push hook (it checked only two of the three hooks).
- `install.sh` no longer replaces a same-named skill it did not install; installed folders
  get a `.corekit` marker, `--force` replaces anyway.
- Stop hook reminds once per set of uncommitted changes and tells Claude not to save while
  it waits for the user's answer.
- `scaffold.sh` joins a multi-line `--purpose` into one line (PROJECTS.md entry was split).
- Test suite passes on macOS (bash 3.2, BSD utilities); new `tests/test_portability.sh`
  blocks bash 4 and GNU-only constructs. Added CLAUDE.md for contributors.
- Upgrade note: existing docs repos keep their old `Core/bin/` copies; copy the new `save`
  and `stop-remind.sh` from `skills/new-project/core-bin/` there to get the fixes.

## 0.1.0 — 2026-11-03
- First public release: `new-project` skill (interview, stack and architecture analysis,
  scaffold, private docs repo, protective git hooks, `save` / `undo-step`), per-user settings,
  Claude Code plugin and marketplace manifests.
