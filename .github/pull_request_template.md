## What and why

<!-- What changes, and the problem it solves. Link the issue if there is one. -->

## Checks

- [ ] `bash tests/run.sh` prints ALL TESTS PASSED (a behaviour change starts with a failing test).
- [ ] `claude plugin validate .` and `claude plugin validate plugins/<plugin>` pass for every plugin I changed.
- [ ] Scripts run on macOS bash 3.2 with BSD tools (no `sed -i`, `mapfile`, `grep -P`, `jq`; see tests/test_portability.sh).
- [ ] `shellcheck --severity=warning` reports nothing for the shell files I changed (CI runs it on every shell file of
      the plugins, tests/ and scripts/; settings in .shellcheckrc and tests/.shellcheckrc).

## Release rule

- [ ] Every plugin whose behaviour changes has a line under `## [Unreleased]` in its CHANGELOG
      (corecrew: the root CHANGELOG.md; coremodel and coreopinion: their own).
- [ ] I did not bump versions or add tags. A release turns `[Unreleased]` into `[X.Y.Z] - YYYY-MM-DD` and bumps
      every manifest of that plugin (`.claude-plugin/plugin.json`, and `.codex-plugin/plugin.json` where it has one)
      in the same commit; the tag `<plugin>-vX.Y.Z` comes after the push.
